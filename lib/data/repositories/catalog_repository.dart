import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/local_db.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/money.dart';
import '../models/catalog.dart';
import 'session.dart';

class CatalogState {
  const CatalogState({
    this.products = const {},
    this.modifierGroups = const [],
    this.codeIndex = const {},
    this.loaded = false,
    this.syncing = false,
    this.lastSync,
    this.serverTime,
    this.stockServerTime,
    this.error,
  });

  /// Keyed by variant id.
  final Map<String, Product> products;
  final List<ModifierGroup> modifierGroups;

  /// Barcode / SKU (lower-cased) → variant id, for instant scan lookups.
  final Map<String, String> codeIndex;
  final bool loaded;
  final bool syncing;
  final DateTime? lastSync;
  final String? serverTime;
  final String? stockServerTime;
  final String? error;

  List<Product> get sellable => products.values.where((p) => p.active).toList();

  /// Stable category labels for the sell screen. Blank/whitespace → "Uncategorised"
  /// so those products remain filterable instead of disappearing from the chip bar.
  static const uncategorisedLabel = 'Uncategorised';

  String categoryLabelOf(Product p) {
    final raw = p.category?.trim() ?? '';
    return raw.isEmpty ? uncategorisedLabel : raw;
  }

  List<String> get categories {
    final set = <String>{};
    var hasBlank = false;
    for (final p in products.values) {
      if (!p.active) continue;
      final raw = p.category?.trim() ?? '';
      if (raw.isEmpty) {
        hasBlank = true;
      } else {
        set.add(raw);
      }
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (hasBlank) list.add(uncategorisedLabel);
    return list;
  }

  Product? byCode(String code) {
    final matches = allByCode(code);
    if (matches.isEmpty) return null;
    return preferBarcodeMatch(matches);
  }

  /// Every active local product that exactly matches [code] as barcode or SKU.
  /// Used when a hard-deleted re-import left a stale twin in IndexedDB.
  List<Product> allByCode(String code) {
    final key = code.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final hits = <Product>[];
    for (final p in products.values) {
      if (!p.active) continue;
      if (p.sku.toLowerCase() == key || p.barcodes.any((b) => b.toLowerCase() == key)) {
        hits.add(p);
      }
    }
    return hits;
  }

  List<Product> variantsOf(String catalogItemId) =>
      products.values.where((p) => p.catalogItemId == catalogItemId && p.active).toList();

  List<ModifierGroup> groupsFor(Product p) {
    final ids = p.modifierGroupIds.toSet();
    return modifierGroups.where((g) => ids.contains(g.id) || g.catalogItemIds.contains(p.catalogItemId)).toList();
  }

  CatalogState copyWith({
    Map<String, Product>? products,
    List<ModifierGroup>? modifierGroups,
    bool? loaded,
    bool? syncing,
    DateTime? lastSync,
    String? serverTime,
    String? stockServerTime,
    String? error,
    bool clearError = false,
  }) {
    final prods = products ?? this.products;
    return CatalogState(
      products: prods,
      modifierGroups: modifierGroups ?? this.modifierGroups,
      codeIndex: products == null ? codeIndex : _index(prods),
      loaded: loaded ?? this.loaded,
      syncing: syncing ?? this.syncing,
      lastSync: lastSync ?? this.lastSync,
      serverTime: serverTime ?? this.serverTime,
      stockServerTime: stockServerTime ?? this.stockServerTime,
      error: clearError ? null : (error ?? this.error),
    );
  }

  static Map<String, String> _index(Map<String, Product> products) {
    final idx = <String, String>{};
    final best = <String, Product>{};
    for (final p in products.values) {
      if (!p.active) continue;
      void claim(String raw) {
        final key = raw.toLowerCase();
        final prev = best[key];
        if (prev == null || compareBarcodeCandidates(p, prev) < 0) {
          best[key] = p;
          idx[key] = p.variantId;
        }
      }

      claim(p.sku);
      for (final b in p.barcodes) {
        claim(b);
      }
    }
    return idx;
  }
}

/// True for retail-length numeric barcodes (EAN-8/13, UPC-A, etc.).
bool looksLikeBarcode(String q) => RegExp(r'^\d{8,14}$').hasMatch(q.trim());

/// Prefer in-stock → available → newer [Product.updatedAt] → higher variant id.
int compareBarcodeCandidates(Product a, Product b) {
  int rank(Product p) {
    final stock = p.stock;
    final inStock = stock == null || stock > 0;
    return (inStock ? 4 : 0) + (p.available ? 2 : 0) + (p.active ? 1 : 0);
  }

  final byRank = rank(b).compareTo(rank(a));
  if (byRank != 0) return byRank;
  final aAt = DateTime.tryParse(a.updatedAt ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bAt = DateTime.tryParse(b.updatedAt ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  final byTime = bAt.compareTo(aAt);
  if (byTime != 0) return byTime;
  return b.variantId.compareTo(a.variantId);
}

Product preferBarcodeMatch(List<Product> matches) {
  final ranked = [...matches]..sort(compareBarcodeCandidates);
  return ranked.first;
}

/// Drop stale local twins that still claim a barcode owned by a better row
/// (typical after a hard re-import where delta sync never tombstoned the old id).
Map<String, Product> purgeStaleBarcodeDuplicates(Map<String, Product> products) {
  final byCode = <String, List<Product>>{};
  for (final p in products.values) {
    for (final b in p.barcodes) {
      byCode.putIfAbsent(b.toLowerCase(), () => []).add(p);
    }
  }
  final remove = <String>{};
  for (final list in byCode.values) {
    if (list.length < 2) continue;
    final ranked = [...list]..sort(compareBarcodeCandidates);
    for (final loser in ranked.skip(1)) {
      remove.add(loser.variantId);
    }
  }
  if (remove.isEmpty) return products;
  return {for (final e in products.entries) if (!remove.contains(e.key)) e.key: e.value};
}

/// Product/modifier cache with full + incremental sync from `/api/pos/catalog`
/// and stock refresh from `/api/pos/stock`.
class CatalogController extends Notifier<CatalogState> {
  @override
  CatalogState build() {
    Future.microtask(loadLocal);
    return const CatalogState();
  }

  LocalDb get _db => ref.read(localDbProvider);

  Future<void> loadLocal() async {
    final rows = await _db.all(LocalDb.products);
    final groups = await _db.all(LocalDb.modifierGroups);
    final meta = await _db.getKv('catalog_meta') ?? {};
    state = state.copyWith(
      products: {for (final r in rows) '${r['variantId']}': Product.fromJson(r)},
      modifierGroups: groups.map(ModifierGroup.fromJson).toList(),
      loaded: true,
      serverTime: meta['serverTime'] as String?,
      stockServerTime: meta['stockServerTime'] as String?,
      lastSync: meta['lastSync'] != null ? DateTime.tryParse('${meta['lastSync']}') : null,
    );
    AppLog.info('Loaded ${rows.length} cached products');
  }

  Future<void> _saveMeta() => _db.putKv('catalog_meta', {
        'serverTime': state.serverTime,
        'stockServerTime': state.stockServerTime,
        'lastSync': state.lastSync?.toIso8601String(),
      });

  /// Full sync when nothing is cached, otherwise only changes since the last sync.
  Future<void> sync({bool full = false}) async {
    final session = ref.read(sessionProvider);
    if (!session.isLoggedIn || state.syncing) return;
    final since = full || state.products.isEmpty ? null : state.serverTime;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/catalog', query: {
        'registerId': session.registerId,
        'since': since,
      }) as Map);
      final incoming = ((res['products'] as List?) ?? []).map((e) => Product.fromApi(Map<String, dynamic>.from(e as Map))).toList();
      final groups = ((res['modifierGroups'] as List?) ?? []).map((e) => ModifierGroup.fromJson(Map<String, dynamic>.from(e as Map))).toList();

      var next = <String, Product>{};
      if (since == null) {
        next = {for (final p in incoming) p.variantId: p};
      } else {
        next = Map.of(state.products);
        final deleted = <String>[];
        final changed = <String, Map<String, dynamic>>{};
        for (final e in (res['products'] as List? ?? [])) {
          final m = Map<String, dynamic>.from(e as Map);
          final p = Product.fromApi(m);
          if (m['deleted'] == true) {
            next.remove(p.variantId);
            deleted.add(p.variantId);
          } else {
            next[p.variantId] = p;
            changed[p.variantId] = p.toJson();
          }
        }
        if (changed.isNotEmpty) await _db.putMany(LocalDb.products, changed);
        if (deleted.isNotEmpty) await _db.deleteMany(LocalDb.products, deleted);
      }

      final beforePurge = next.length;
      next = purgeStaleBarcodeDuplicates(next);
      final purged = beforePurge - next.length;
      if (since == null || purged > 0) {
        await _db.replaceAll(LocalDb.products, {for (final p in next.values) p.variantId: p.toJson()});
      }

      await _db.replaceAll(LocalDb.modifierGroups, {for (final g in groups) g.id: g.toJson()});
      state = state.copyWith(
        products: next,
        modifierGroups: groups,
        syncing: false,
        loaded: true,
        lastSync: DateTime.now(),
        serverTime: res['serverTime'] as String?,
        stockServerTime: since == null ? res['serverTime'] as String? : state.stockServerTime,
      );
      await _saveMeta();
      AppLog.info(
        'Catalogue sync (${since == null ? 'full' : 'delta'}): ${incoming.length} rows'
        '${purged > 0 ? ', purged $purged stale barcode twin(s)' : ''}',
      );
    } catch (e) {
      if (e is ApiException && e.isNetwork) ref.read(onlineProvider.notifier).markOffline();
      state = state.copyWith(syncing: false, error: errorMessage(e));
      AppLog.warn('Catalogue sync failed: $e');
    }
  }

  /// Pulls stock levels changed since the last stock sync.
  Future<void> syncStock() async {
    final session = ref.read(sessionProvider);
    if (!session.isLoggedIn || state.products.isEmpty) return;
    try {
      final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/stock', query: {
        'registerId': session.registerId,
        'since': state.stockServerTime,
      }) as Map);
      final levels = (res['levels'] as List?) ?? [];
      if (levels.isNotEmpty) {
        final next = Map.of(state.products);
        final changed = <String, Map<String, dynamic>>{};
        for (final l in levels) {
          final m = Map<String, dynamic>.from(l as Map);
          final id = '${m['variantId']}';
          final p = next[id];
          if (p == null) continue;
          final updated = p.copyWith(stock: (m['quantity'] as num?)?.toInt() ?? 0);
          next[id] = updated;
          changed[id] = updated.toJson();
        }
        await _db.putMany(LocalDb.products, changed);
        state = state.copyWith(products: next, stockServerTime: res['serverTime'] as String?);
      } else {
        state = state.copyWith(stockServerTime: res['serverTime'] as String?);
      }
      await _saveMeta();
    } catch (e) {
      if (e is ApiException && e.isNetwork) ref.read(onlineProvider.notifier).markOffline();
      AppLog.warn('Stock sync failed: $e');
    }
  }

  /// Optimistic local stock change after a sale/refund, until the next stock sync.
  Future<void> adjustStock(Map<String, int> deltas) async {
    final next = Map.of(state.products);
    final changed = <String, Map<String, dynamic>>{};
    deltas.forEach((id, delta) {
      final p = next[id];
      if (p == null || p.stock == null) return;
      final updated = p.copyWith(stock: p.stock! + delta);
      next[id] = updated;
      changed[id] = updated.toJson();
    });
    if (changed.isEmpty) return;
    state = state.copyWith(products: next);
    await _db.putMany(LocalDb.products, changed);
  }

  Future<void> setProductAvailability(String variantId, bool available) async {
    final p = state.products[variantId];
    if (p == null) return;
    final updated = p.copyWith(available: available);
    state = state.copyWith(products: {...state.products, variantId: updated});
    await _db.put(LocalDb.products, variantId, updated.toJson());
  }

  /// Updates the local cache after a permanent catalogue price change.
  Future<Product?> applyLocalPrice(String variantId, int pricePence) async {
    final p = state.products[variantId];
    if (p == null) return null;
    final updated = p.copyWith(pricePence: pricePence, clearPromoPrice: true, updatedAt: DateTime.now().toIso8601String());
    state = state.copyWith(products: {...state.products, variantId: updated});
    await _db.put(LocalDb.products, variantId, updated.toJson());
    return updated;
  }

  /// Permanently sets the sell price via `PATCH /api/pos/products/:variantId/price`, then updates the local cache.
  /// Throws [ApiException] on failure — caller must not change the cart until this succeeds.
  Future<Product> setPermanentSellPrice(String variantId, int pricePence) async {
    final session = ref.read(sessionProvider);
    final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).patch(
          '/api/pos/products/$variantId/price',
          data: {
            'price': fromPence(pricePence),
            'registerId': session.registerId,
          },
        ) as Map);
    final serverPence = res['price'] != null ? toPence(res['price'] as num?) : pricePence;
    final updated = await applyLocalPrice(variantId, serverPence);
    if (updated == null) throw ApiException('Product left the local catalogue');
    return updated;
  }

  /// Updates the local cache after a permanent catalogue stock change (also refreshes grid badges).
  Future<Product?> applyLocalStock(String variantId, int stock) async {
    final p = state.products[variantId];
    if (p == null) return null;
    final updated = p.copyWith(stock: stock, updatedAt: DateTime.now().toIso8601String());
    state = state.copyWith(products: {...state.products, variantId: updated});
    await _db.put(LocalDb.products, variantId, updated.toJson());
    return updated;
  }

  /// Permanently sets available stock via `PATCH /api/pos/products/:variantId/stock`, then updates the local cache.
  Future<Product> setPermanentStock(String variantId, int quantity) async {
    final session = ref.read(sessionProvider);
    final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).patch(
          '/api/pos/products/$variantId/stock',
          data: {
            'quantity': quantity,
            'registerId': session.registerId,
          },
        ) as Map);
    final serverQty = (res['quantity'] as num?)?.toInt() ?? quantity;
    final updated = await applyLocalStock(variantId, serverQty);
    if (updated == null) throw ApiException('Product left the local catalogue');
    return updated;
  }

  /// Creates a catalogue product via `POST /api/pos/products` and upserts it into the local Sell grid.
  /// Payload mirrors ERP `/api/catalog/items` create fields that POS auth supports.
  Future<Product> createProduct({
    required String name,
    required int sellPricePence,
    required int quantity,
    String? sku,
    String? barcode,
    String? category,
    String? subCategory,
    String? brand,
    String? packSize,
    int? costPricePence,
    String? currency,
    String? taxCodeId,
    String? uom,
    String status = 'active',
    String? warehouseId,
    String? description,
    String? remarks,
    num? reorderLevel,
    num? reorderQuantity,
    String? binCode,
    String? lotNumber,
    String? expiryDate,
    String? supplierName,
    String? supplierSku,
    int? leadTimeDays,
    Map<String, dynamic>? attributes,
  }) async {
    final session = ref.read(sessionProvider);
    final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).post(
          '/api/pos/products',
          data: {
            'name': name,
            'sellPrice': fromPence(sellPricePence),
            'quantity': quantity,
            'sku': sku,
            'barcode': barcode,
            'category': category,
            'subCategory': subCategory,
            'brand': brand,
            'packSize': packSize,
            if (costPricePence != null) 'costPrice': fromPence(costPricePence),
            'currency': currency,
            'taxCodeId': taxCodeId,
            'uom': uom,
            'status': status,
            'warehouseId': warehouseId,
            'registerId': session.registerId,
            'description': description,
            'remarks': remarks,
            'reorderLevel': reorderLevel,
            'reorderQuantity': reorderQuantity,
            'binCode': binCode,
            'lotNumber': lotNumber,
            'expiryDate': expiryDate,
            'supplierName': supplierName,
            'supplierSku': supplierSku,
            'leadTimeDays': leadTimeDays,
            if (attributes != null && attributes.isNotEmpty) 'attributes': attributes,
          },
        ) as Map);
    final productJson = Map<String, dynamic>.from(res['product'] as Map);
    final product = Product.fromApi(productJson);
    state = state.copyWith(products: {...state.products, product.variantId: product}, loaded: true);
    await _db.put(LocalDb.products, product.variantId, product.toJson());
    // Pull a delta so price-list / stock badges stay aligned with the server.
    await sync(full: false);
    await syncStock();
    return state.products[product.variantId] ?? product;
  }

  Future<void> setModifierAvailability(String modifierId, bool available) async {
    final groups = state.modifierGroups
        .map((g) => g.copyWith(modifiers: g.modifiers.map((m) => m.id == modifierId ? m.copyWith(available: available) : m).toList()))
        .toList();
    state = state.copyWith(modifierGroups: groups);
    await _db.replaceAll(LocalDb.modifierGroups, {for (final g in groups) g.id: g.toJson()});
  }

  /// Server-side lookup for codes not in the local cache (e.g. a barcode added moments ago).
  Future<Product?> lookupRemote(String code) async {
    try {
      final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/lookup', query: {'code': code}) as Map);
      final id = '${res['variantId']}';
      if (!state.products.containsKey(id)) await sync();
      return state.products[id];
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    state = const CatalogState(loaded: true);
    await _db.replaceAll(LocalDb.products, {});
    await _db.replaceAll(LocalDb.modifierGroups, {});
    await _db.deleteKv('catalog_meta');
  }
}

final catalogProvider = NotifierProvider<CatalogController, CatalogState>(CatalogController.new);
