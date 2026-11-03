import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/local_db.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/money.dart';
import '../models/catalog.dart';
import 'bootstrap_repository.dart';
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
      final parentSku = p.catalogItemSku?.trim().toLowerCase();
      if (p.sku.toLowerCase() == key ||
          (parentSku != null && parentSku.isNotEmpty && parentSku == key) ||
          p.barcodes.any((b) => b.toLowerCase() == key)) {
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
      final parentSku = p.catalogItemSku?.trim();
      if (parentSku != null && parentSku.isNotEmpty) claim(parentSku);
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
///
/// The offline store is keyed by organisation + API base URL so a till that
/// previously synced another org (or prod vs DEV) never shows foreign tiles.
///
/// `kWarehouseCatalogScope` bumps whenever the server catalogue visibility rule
/// changes (e.g. register-warehouse filtering) so stale offline tiles are
/// discarded and a full sync is forced once.
const int kWarehouseCatalogScope = 1;

class CatalogController extends Notifier<CatalogState> {
  @override
  CatalogState build() {
    // Drop foreign/offline tiles as soon as org, API host, or session changes.
    // Callers (login / SyncService) still run a full sync afterwards.
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      final orgChanged = prev?.user?.orgId != next.user?.orgId;
      final urlChanged = prev?.baseUrl != next.baseUrl;
      final signedOut = (prev?.isLoggedIn ?? false) && !next.isLoggedIn;
      if (orgChanged || urlChanged || signedOut) {
        Future.microtask(clear);
      }
    });
    Future.microtask(loadLocal);
    return const CatalogState();
  }

  LocalDb get _db => ref.read(localDbProvider);

  Future<Map<String, dynamic>> _readMeta() async => await _db.getKv('catalog_meta') ?? {};

  /// True when the on-disk catalogue belongs to the signed-in org + API host.
  Future<bool> cacheMatchesSession() async {
    final session = ref.read(sessionProvider);
    if (!session.isLoggedIn || session.user == null) return false;
    final meta = await _readMeta();
    return '${meta['orgId']}' == session.user!.orgId && '${meta['baseUrl']}' == session.baseUrl;
  }

  /// Stock is scoped to the register's warehouse. A cached catalogue from another
  /// register (or from before a register was chosen) must not be delta-synced —
  /// otherwise zero stock from an empty warehouse sticks forever.
  Future<bool> cacheMatchesRegister() async {
    final session = ref.read(sessionProvider);
    if (session.registerId == null) return true;
    final meta = await _readMeta();
    if (meta['registerId'] == null) return false;
    return '${meta['registerId']}' == session.registerId;
  }

  /// True when the on-disk catalogue was synced under the current warehouse-scope rule.
  Future<bool> cacheMatchesCatalogScope() async {
    final meta = await _readMeta();
    final raw = meta['warehouseCatalogScope'];
    final scope = raw is int ? raw : int.tryParse('$raw') ?? 0;
    return scope == kWarehouseCatalogScope;
  }

  Future<void> loadLocal() async {
    final session = ref.read(sessionProvider);
    final meta = await _readMeta();
    final scopedOk = session.isLoggedIn &&
        session.user != null &&
        '${meta['orgId']}' == session.user!.orgId &&
        '${meta['baseUrl']}' == session.baseUrl;
    final scopeRaw = meta['warehouseCatalogScope'];
    final catalogScope =
        scopeRaw is int ? scopeRaw : int.tryParse('$scopeRaw') ?? 0;
    final catalogScopeOk = catalogScope == kWarehouseCatalogScope;

    if (session.isLoggedIn && (!scopedOk || !catalogScopeOk)) {
      AppLog.warn(
        !scopedOk
            ? 'Discarding offline catalogue '
                '(cache org=${meta['orgId']} url=${meta['baseUrl']} ≠ '
                'session org=${session.user?.orgId} url=${session.baseUrl})'
            : 'Discarding offline catalogue (warehouseCatalogScope $catalogScope ≠ $kWarehouseCatalogScope)',
      );
      await clear();
      return;
    }

    final rows = await _db.all(LocalDb.products);
    final groups = await _db.all(LocalDb.modifierGroups);
    state = state.copyWith(
      products: {for (final r in rows) '${r['variantId']}': Product.fromJson(r)},
      modifierGroups: groups.map(ModifierGroup.fromJson).toList(),
      loaded: true,
      serverTime: meta['serverTime'] as String?,
      stockServerTime: meta['stockServerTime'] as String?,
      lastSync: meta['lastSync'] != null ? DateTime.tryParse('${meta['lastSync']}') : null,
    );
    AppLog.info('Loaded ${rows.length} cached products for org ${meta['orgId']}');
  }

  Future<void> _saveMeta({
    required String orgId,
    required String baseUrl,
    String? registerId,
    String? warehouseId,
  }) =>
      _db.putKv('catalog_meta', {
        'orgId': orgId,
        'baseUrl': baseUrl,
        'registerId': registerId ?? ref.read(sessionProvider).registerId,
        'warehouseId': warehouseId,
        'warehouseCatalogScope': kWarehouseCatalogScope,
        'serverTime': state.serverTime,
        'stockServerTime': state.stockServerTime,
        'lastSync': state.lastSync?.toIso8601String(),
      });

  /// Full sync when nothing is cached / org scope mismatch, otherwise deltas.
  Future<void> sync({bool full = false}) async {
    final session = ref.read(sessionProvider);
    if (!session.isLoggedIn || session.user == null || state.syncing) return;
    final scopeOk = await cacheMatchesSession();
    final registerOk = await cacheMatchesRegister();
    final catalogScopeOk = await cacheMatchesCatalogScope();
    if (!scopeOk && state.products.isNotEmpty) {
      AppLog.warn('Forcing full catalogue sync after org/API scope mismatch');
      await clear();
    }
    if ((!registerOk || !catalogScopeOk) && !full) {
      AppLog.warn(
        !catalogScopeOk
            ? 'Forcing full catalogue sync after warehouse-scope rule change'
            : 'Forcing full catalogue sync after register/warehouse change',
      );
    }
    final since =
        full || !scopeOk || !registerOk || !catalogScopeOk || state.products.isEmpty ? null : state.serverTime;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/catalog', query: {
        'registerId': session.registerId,
        'since': since,
      }) as Map);
      final responseOrg = res['organizationId'] == null ? null : '${res['organizationId']}';
      if (responseOrg != null && responseOrg != session.user!.orgId) {
        throw ApiException(
          'Catalogue organisation mismatch (API $responseOrg ≠ session ${session.user!.orgId})',
        );
      }
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
      final responseWarehouseId = res['warehouseId'] == null ? null : '${res['warehouseId']}';
      state = state.copyWith(
        products: next,
        modifierGroups: groups,
        syncing: false,
        loaded: true,
        lastSync: DateTime.now(),
        serverTime: res['serverTime'] as String?,
        stockServerTime: since == null ? res['serverTime'] as String? : state.stockServerTime,
      );
      await _saveMeta(
        orgId: session.user!.orgId,
        baseUrl: session.baseUrl,
        registerId: session.registerId,
        warehouseId: responseWarehouseId,
      );
      AppLog.info(
        'Catalogue sync (${since == null ? 'full' : 'delta'}) org=${session.user!.orgId}'
        ' register=${session.registerId} warehouse=$responseWarehouseId: ${incoming.length} rows'
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
    if (!session.isLoggedIn || session.user == null || state.products.isEmpty) return;
    if (!await cacheMatchesSession() ||
        !await cacheMatchesRegister() ||
        !await cacheMatchesCatalogScope()) {
      await sync(full: true);
      return;
    }
    try {
      final meta = await _readMeta();
      final cachedWarehouseId = meta['warehouseId'] == null ? null : '${meta['warehouseId']}';
      // Probe with a delta first; if the register's warehouse changed server-side,
      // fall through to a full stock replace for this warehouse.
      var res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/stock', query: {
        'registerId': session.registerId,
        'since': state.stockServerTime,
      }) as Map);
      final responseWarehouseId = res['warehouseId'] == null ? null : '${res['warehouseId']}';
      final warehouseChanged =
          responseWarehouseId != null && cachedWarehouseId != null && responseWarehouseId != cachedWarehouseId;
      final fullStock = warehouseChanged || state.stockServerTime == null;
      if (fullStock) {
        res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/stock', query: {
          'registerId': session.registerId,
        }) as Map);
      }
      final levels = (res['levels'] as List?) ?? [];
      if (fullStock || levels.isNotEmpty) {
        final next = Map.of(state.products);
        final changed = <String, Map<String, dynamic>>{};
        final qtyById = <String, int>{};
        for (final l in levels) {
          final m = Map<String, dynamic>.from(l as Map);
          qtyById['${m['variantId']}'] = (m['quantity'] as num?)?.toInt() ?? 0;
        }
        if (fullStock) {
          // Replace every tracked quantity for this warehouse (missing → 0).
          for (final entry in next.entries) {
            final p = entry.value;
            if (p.stock == null && !qtyById.containsKey(p.variantId)) continue;
            final updated = p.copyWith(stock: qtyById[p.variantId] ?? 0);
            next[entry.key] = updated;
            changed[entry.key] = updated.toJson();
          }
        } else {
          for (final e in qtyById.entries) {
            final p = next[e.key];
            if (p == null) continue;
            final updated = p.copyWith(stock: e.value);
            next[e.key] = updated;
            changed[e.key] = updated.toJson();
          }
        }
        if (changed.isNotEmpty) await _db.putMany(LocalDb.products, changed);
        state = state.copyWith(products: next, stockServerTime: res['serverTime'] as String?);
      } else {
        state = state.copyWith(stockServerTime: res['serverTime'] as String?);
      }
      await _saveMeta(
        orgId: session.user!.orgId,
        baseUrl: session.baseUrl,
        registerId: session.registerId,
        warehouseId: res['warehouseId'] == null ? cachedWarehouseId : '${res['warehouseId']}',
      );
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

  /// Prefer real classification ids; skip synthetic `product:type:Name` fallbacks (API resolves names).
  static String? realClassificationId(String? id) {
    if (id == null || id.isEmpty) return null;
    if (id.startsWith('product:')) return null;
    return id;
  }

  /// Creates a catalogue product via `POST /api/pos/catalog-items` (catalog_items only, post-023).
  /// Optional [imageBytes] multipart field `image` → API writes under `/uploads/product-media/…`.
  Future<Map<String, dynamic>> createCatalogItem({
    required String name,
    String? sku,
    String? categoryId,
    String? category,
    String? subCategoryId,
    String? subCategory,
    String? brandId,
    String? brand,
    String? packSizeId,
    String? packSize,
    String? currency,
    String? taxCodeId,
    String? uomId,
    String? uom,
    String status = 'active',
    String? description,
    String? remarks,
    String? supplierSku,
    int? leadTimeDays,
    String? hsCode,
    String? countryOfOrigin,
    List<int>? imageBytes,
    String? imageFilename,
  }) async {
    final fields = <String, dynamic>{
      'name': name,
      'sku': sku,
      'categoryId': realClassificationId(categoryId),
      'category': category,
      'subCategoryId': realClassificationId(subCategoryId),
      'subCategory': subCategory,
      'brandId': realClassificationId(brandId),
      'brand': brand,
      'packSizeId': realClassificationId(packSizeId),
      'packSize': packSize,
      'currency': currency,
      'taxCodeId': taxCodeId,
      'uomId': realClassificationId(uomId),
      'uom': uom,
      'status': status,
      'description': description,
      'remarks': remarks,
      'supplierSku': supplierSku,
      'leadTimeDays': leadTimeDays,
      'hsCode': hsCode,
      'countryOfOrigin': countryOfOrigin,
    };
    final api = ref.read(apiClientProvider);
    final Map res;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      final form = FormData.fromMap({
        ..._multipartFields(fields),
        'image': MultipartFile.fromBytes(
          imageBytes,
          filename: (imageFilename?.trim().isNotEmpty == true) ? imageFilename!.trim() : 'product.jpg',
        ),
      });
      res = Map<String, dynamic>.from(await api.postMultipart('/api/pos/catalog-items', data: form) as Map);
    } else {
      res = Map<String, dynamic>.from(await api.post('/api/pos/catalog-items', data: fields) as Map);
    }
    return Map<String, dynamic>.from(res['catalogItem'] as Map? ?? res);
  }

  static Map<String, dynamic> _multipartFields(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    for (final e in fields.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is String && v.isEmpty) continue;
      if (v is Map) {
        out[e.key] = jsonEncode(v);
      } else if (v is num || v is bool) {
        out[e.key] = v;
      } else {
        out[e.key] = '$v';
      }
    }
    return out;
  }

  /// Search parent catalogue products (`GET /api/pos/catalog-items`).
  Future<List<CatalogItemRef>> searchCatalogItems({String? q, int limit = 40}) async {
    final session = ref.read(sessionProvider);
    final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get(
          '/api/pos/catalog-items',
          query: {
            'q': q,
            'limit': limit,
            'registerId': session.registerId,
          },
        ) as Map);
    final rows = (res['data'] as List? ?? const []);
    return [
      for (final raw in rows) CatalogItemRef.fromApi(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  /// Active racks for a warehouse (`GET /api/pos/racks`).
  Future<List<StockLocationOption>> listRacks({required String warehouseId, String? q, int limit = 200}) async {
    final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get(
          '/api/pos/racks',
          query: {
            'warehouseId': warehouseId,
            if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
            'limit': limit,
          },
        ) as Map);
    final rows = (res['data'] as List? ?? const []);
    return [
      for (final raw in rows) StockLocationOption.fromApi(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  /// Active bins for a warehouse, optionally filtered by rack (`GET /api/pos/bins`).
  Future<List<StockLocationOption>> listBins({
    required String warehouseId,
    String? rackId,
    String? q,
    int limit = 200,
  }) async {
    final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get(
          '/api/pos/bins',
          query: {
            'warehouseId': warehouseId,
            if (rackId != null && rackId.isNotEmpty) 'rackId': rackId,
            if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
            'limit': limit,
          },
        ) as Map);
    final rows = (res['data'] as List? ?? const []);
    return [
      for (final raw in rows) StockLocationOption.fromApi(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  /// Creates a sellable variant via `POST /api/pos/variants` and upserts it into the local Sell grid.
  Future<Product> createVariant({
    required String catalogItemId,
    required String variantSku,
    String? name,
    String? option1Name,
    String? option1Value,
    String? option2Name,
    String? option2Value,
    String? option3Name,
    String? option3Value,
    String? barcode,
    bool autoGenerateBarcode = true,
    int? costPricePence,
    required int sellPricePence,
    String? currency,
    String status = 'active',
    String? warehouseId,
    int quantity = 0,
    num? reorderLevel,
    num? reorderQuantity,
    String? binId,
    String? binCode,
    String? rackId,
    String? rackCode,
    num? weightValue,
    String? weightUnit,
    num? lengthValue,
    num? widthValue,
    num? heightValue,
    String? dimensionUnit,
    Map<String, dynamic>? attributes,
    List<int>? imageBytes,
    String? imageFilename,
  }) async {
    final session = ref.read(sessionProvider);
    final barcodeTrimmed = barcode?.trim();
    final fields = <String, dynamic>{
      'catalogItemId': catalogItemId,
      'variantSku': variantSku,
      'name': name,
      'option1Name': option1Name,
      'option1Value': option1Value,
      'option2Name': option2Name,
      'option2Value': option2Value,
      'option3Name': option3Name,
      'option3Value': option3Value,
      'barcode': barcodeTrimmed,
      'autoGenerateBarcode': (barcodeTrimmed == null || barcodeTrimmed.isEmpty) && autoGenerateBarcode,
      if (costPricePence != null) 'costPrice': fromPence(costPricePence),
      'sellPrice': fromPence(sellPricePence),
      'currency': currency,
      'status': status,
      'warehouseId': warehouseId,
      'registerId': session.registerId,
      'quantity': quantity,
      'reorderLevel': reorderLevel,
      'reorderQuantity': reorderQuantity,
      'binId': binId,
      'binCode': binCode,
      'rackId': rackId,
      'rackCode': rackCode,
      'weightValue': weightValue,
      'weightUnit': weightUnit,
      'lengthValue': lengthValue,
      'widthValue': widthValue,
      'heightValue': heightValue,
      'dimensionUnit': dimensionUnit,
      if (attributes != null && attributes.isNotEmpty) 'attributes': attributes,
    };
    final api = ref.read(apiClientProvider);
    final Map res;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      final formMap = <String, dynamic>{
        ..._multipartFields(fields),
        'image': MultipartFile.fromBytes(
          imageBytes,
          filename: (imageFilename?.trim().isNotEmpty == true) ? imageFilename!.trim() : 'variant.jpg',
        ),
      };
      res = Map<String, dynamic>.from(await api.postMultipart('/api/pos/variants', data: FormData.fromMap(formMap)) as Map);
    } else {
      res = Map<String, dynamic>.from(await api.post('/api/pos/variants', data: fields) as Map);
    }
    final productJson = Map<String, dynamic>.from(res['product'] as Map);
    var product = Product.fromApi(productJson);
    // Prefer the qty we just wrote when the create response/sync briefly omits it.
    if (product.stock == null || (quantity > 0 && (product.stock ?? 0) == 0)) {
      product = product.copyWith(stock: quantity);
    }
    state = state.copyWith(products: {...state.products, product.variantId: product}, loaded: true);
    await _db.put(LocalDb.products, product.variantId, product.toJson());
    await sync(full: false);
    await syncStock();
    final after = state.products[product.variantId];
    // If delta sync wiped stock to 0 for the register warehouse before DB catch-up, restore.
    if (after != null && quantity > 0 && (after.stock ?? 0) == 0) {
      final registerWh = ref.read(currentRegisterProvider)?.warehouseId;
      if (warehouseId == null || warehouseId == registerWh) {
        await applyLocalStock(after.variantId, quantity);
        return state.products[after.variantId] ?? after.copyWith(stock: quantity);
      }
    }
    return after ?? product;
  }

  /// Legacy combined create (`POST /api/pos/products`) — prefer [createCatalogItem] + [createVariant].
  Future<Product> createProduct({
    required String name,
    required int sellPricePence,
    required int quantity,
    String? sku,
    String? barcode,
    String? categoryId,
    String? category,
    String? subCategoryId,
    String? subCategory,
    String? brandId,
    String? brand,
    String? packSizeId,
    String? packSize,
    int? costPricePence,
    String? currency,
    String? taxCodeId,
    String? uomId,
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
            'categoryId': realClassificationId(categoryId),
            'category': category,
            'subCategoryId': realClassificationId(subCategoryId),
            'subCategory': subCategory,
            'brandId': realClassificationId(brandId),
            'brand': brand,
            'packSizeId': realClassificationId(packSizeId),
            'packSize': packSize,
            if (costPricePence != null) 'costPrice': fromPence(costPricePence),
            'currency': currency,
            'taxCodeId': taxCodeId,
            'uomId': realClassificationId(uomId),
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

  static const defaultUoms = ['each', 'pack', 'box', 'case', 'kg', 'g', 'litre', 'ml', 'SET', 'PCS'];

  /// Distinct free-text classification values already on downloaded products (offline-safe).
  Map<String, List<String>> classificationsFromProducts() {
    final out = <String, Set<String>>{
      'category': {},
      'sub_category': {},
      'brand': {},
      'uom': {},
      'pack_size': {},
    };
    for (final p in state.products.values) {
      final cat = p.category?.trim();
      if (cat != null && cat.isNotEmpty && cat != CatalogState.uncategorisedLabel) out['category']!.add(cat);
      final sub = p.subCategory?.trim();
      if (sub != null && sub.isNotEmpty) out['sub_category']!.add(sub);
      final brand = p.brand?.trim();
      if (brand != null && brand.isNotEmpty) out['brand']!.add(brand);
    }
    return {
      for (final e in out.entries) e.key: (e.value.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))),
    };
  }

  /// Org-scoped classification master data for Add Product dropdowns (`GET /api/pos/classifications`).
  /// Each entry is `{id, name}` — pickers save **id**; display uses name.
  /// Merges local product values + default UOMs so empty master tables never strand a cashier.
  Future<({Map<String, List<({String id, String name})>> options, String? hint, bool fromProducts})> listClassifications({
    String? type,
    String? parentId,
  }) async {
    final out = <String, List<({String id, String name})>>{
      'category': [],
      'sub_category': [],
      'brand': [],
      'uom': [],
      'pack_size': [],
    };
    String? hint;
    var fromProducts = false;

    void addOpt(String t, String id, String name) {
      if (name.isEmpty || !out.containsKey(t)) return;
      if (out[t]!.any((o) => o.id == id || o.name.toLowerCase() == name.toLowerCase())) return;
      out[t]!.add((id: id, name: name));
    }

    try {
      final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get(
            '/api/pos/classifications',
            query: {
              'type': ?type,
              'parentId': ?parentId,
            },
          ) as Map);
      final rows = (res['data'] as List? ?? const []);
      final meta = res['meta'] is Map ? Map<String, dynamic>.from(res['meta'] as Map) : const <String, dynamic>{};
      hint = meta['hint']?.toString();
      fromProducts = meta['fromProducts'] == true;
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final t = '${row['type'] ?? ''}';
        final name = '${row['name'] ?? ''}'.trim();
        final id = '${row['id'] ?? ''}'.trim();
        if (name.isEmpty || id.isEmpty) continue;
        addOpt(t, id, name);
      }
    } catch (_) {
      hint =
          'Could not load classifications online. Using products already on this till. In ERP: Catalog → Classifications → Import from products.';
      fromProducts = true;
    }

    final local = classificationsFromProducts();
    for (final e in local.entries) {
      for (final name in e.value) {
        addOpt(e.key, 'product:${e.key}:$name', name);
      }
    }
    for (final u in defaultUoms) {
      addOpt('uom', 'product:uom:$u', u);
    }
    for (final list in out.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    if (hint == null && out['category']!.isEmpty && out['brand']!.isEmpty) {
      hint =
          'No categories yet. In ERP open Catalog → Classifications (Manage Classifications), add values or Import from products, then tap Refresh on Add Product.';
    }
    return (options: out, hint: hint, fromProducts: fromProducts);
  }

  /// Server-side lookup for codes not in the local cache (e.g. a barcode added moments ago).
  Future<Product?> lookupRemote(String code) async {
    try {
      final session = ref.read(sessionProvider);
      final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/lookup', query: {
        'code': code,
        'registerId': session.registerId,
      }) as Map);
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
