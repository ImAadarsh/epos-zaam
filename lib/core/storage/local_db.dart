import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import 'db_factory_io.dart' if (dart.library.js_interop) 'db_factory_web.dart';

/// Offline-first local store (sembast: file-backed on native, IndexedDB on web).
///
/// Every store keeps JSON maps keyed by string ids so models round-trip
/// through `toJson` / `fromJson`.
class LocalDb {
  LocalDb(this.db);

  static const String name = 'zaam_epos';

  final Database db;

  static final products = stringMapStoreFactory.store('products');
  static final modifierGroups = stringMapStoreFactory.store('modifier_groups');
  static final outbox = stringMapStoreFactory.store('outbox');
  static final sales = stringMapStoreFactory.store('sales');
  static final parked = stringMapStoreFactory.store('parked_sales');
  static final kv = stringMapStoreFactory.store('kv');

  static Future<LocalDb> open() async => LocalDb(await openPlatformDatabase(name));

  /// Values read from sembast are immutable; this returns a mutable deep copy.
  static Map<String, dynamic> clone(Object? value) =>
      value == null ? <String, dynamic>{} : jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  Future<Map<String, dynamic>?> getKv(String key) async {
    final v = await kv.record(key).get(db);
    return v == null ? null : clone(v);
  }

  Future<void> putKv(String key, Map<String, dynamic> value) => kv.record(key).put(db, _json(value));

  Future<void> deleteKv(String key) => kv.record(key).delete(db);

  Future<List<Map<String, dynamic>>> all(StoreRef<String, Map<String, Object?>> store, {Finder? finder}) async {
    final records = await store.find(db, finder: finder);
    return records.map((r) => clone(r.value)).toList();
  }

  Future<void> put(StoreRef<String, Map<String, Object?>> store, String key, Map<String, dynamic> value) =>
      store.record(key).put(db, _json(value));

  Future<void> putMany(StoreRef<String, Map<String, Object?>> store, Map<String, Map<String, dynamic>> values) async {
    await db.transaction((txn) async {
      for (final e in values.entries) {
        await store.record(e.key).put(txn, _json(e.value));
      }
    });
  }

  Future<void> replaceAll(StoreRef<String, Map<String, Object?>> store, Map<String, Map<String, dynamic>> values) async {
    await db.transaction((txn) async {
      await store.delete(txn);
      for (final e in values.entries) {
        await store.record(e.key).put(txn, _json(e.value));
      }
    });
  }

  Future<void> delete(StoreRef<String, Map<String, Object?>> store, String key) => store.record(key).delete(db);

  Future<void> deleteMany(StoreRef<String, Map<String, Object?>> store, Iterable<String> keys) =>
      store.records(keys).delete(db);

  /// Wipes every store (used by "Reset App").
  Future<void> clearAll() async {
    await db.transaction((txn) async {
      for (final s in [products, modifierGroups, outbox, sales, parked, kv]) {
        await s.delete(txn);
      }
    });
  }

  /// sembast only accepts JSON-compatible values; this strips anything else.
  static Map<String, Object?> _json(Map<String, dynamic> value) =>
      (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();
}

/// Overridden in `main()` once the database is open.
final localDbProvider = Provider<LocalDb>((ref) => throw UnimplementedError('LocalDb not initialised'));
