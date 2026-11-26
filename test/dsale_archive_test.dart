import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:zaam_epos/core/storage/local_db.dart';
import 'package:zaam_epos/features/dsale/dsale_archive.dart';
import 'package:zaam_epos/features/dsale/dsale_service.dart';

Future<ProviderContainer> _container(Database db) async {
  final c = ProviderContainer(overrides: [localDbProvider.overrideWithValue(LocalDb(db))]);
  addTearDown(c.dispose);
  // Let the initial async load finish.
  c.read(dSaleArchiveProvider);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return c;
}

void main() {
  test('archive keeps items + quantities, restore removes it, state persists', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('archive_test');
    final c = await _container(db);
    final n = c.read(dSaleArchiveProvider.notifier);

    expect(c.read(dSaleArchiveProvider), isEmpty);

    final sale = await n.archive(const [
      DSaleMiscLine(unitPence: 250, quantity: 2),
      DSaleMiscLine(unitPence: 100),
    ]);
    expect(c.read(dSaleArchiveProvider), hasLength(1));
    expect(sale.totalPence, 600);
    expect(sale.itemCount, 3);

    // A fresh container over the same database (page reload) sees the archive.
    final c2 = await _container(db);
    final loaded = c2.read(dSaleArchiveProvider);
    expect(loaded, hasLength(1));
    expect(loaded.first.lines.map((l) => (l.unitPence, l.quantity)).toList(), [(250, 2), (100, 1)]);
    expect(loaded.first.totalPence, 600);

    // Restoring (remove) empties the list, and that persists too.
    await c2.read(dSaleArchiveProvider.notifier).remove(loaded.first.id);
    expect(c2.read(dSaleArchiveProvider), isEmpty);
    final c3 = await _container(db);
    expect(c3.read(dSaleArchiveProvider), isEmpty);
  });

  test('multiple archives are listed newest first', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('archive_test_2');
    final c = await _container(db);
    final n = c.read(dSaleArchiveProvider.notifier);
    final a = await n.archive(const [DSaleMiscLine(unitPence: 100)]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final b = await n.archive(const [DSaleMiscLine(unitPence: 200)]);
    expect(c.read(dSaleArchiveProvider).map((s) => s.id).toList(), [b.id, a.id]);

    final c2 = await _container(db);
    expect(c2.read(dSaleArchiveProvider).map((s) => s.id).toList(), [b.id, a.id]);
  });
}
