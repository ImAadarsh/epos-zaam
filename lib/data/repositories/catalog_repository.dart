import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/local_db.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/app_log.dart';
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

  List<String> get categories {
    final set = <String>{};
    for (final p in products.values) {
      if (p.active && p.category != null && p.category!.trim().isNotEmpty) set.add(p.category!.trim());
    }
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Product? byCode(String code) {
    final id = codeIndex[code.trim().toLowerCase()];
    return id == null ? null : products[id];
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
    for (final p in products.values) {
      idx[p.sku.toLowerCase()] = p.variantId;
      for (final b in p.barcodes) {
        idx[b.toLowerCase()] = p.variantId;
      }
    }
    return idx;
  }
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

      final Map<String, Product> next;
      if (since == null) {
        next = {for (final p in incoming) p.variantId: p};
        await _db.replaceAll(LocalDb.products, {for (final p in next.values) p.variantId: p.toJson()});
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
      AppLog.info('Catalogue sync (${since == null ? 'full' : 'delta'}): ${incoming.length} rows');
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
