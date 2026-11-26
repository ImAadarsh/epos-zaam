import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/ids.dart';
import 'dsale_service.dart';

/// A Direct Sale cart set aside (not paid) so another customer can be served.
class ArchivedDSale {
  const ArchivedDSale({required this.id, required this.lines, required this.archivedAt});

  final String id;
  final List<DSaleMiscLine> lines;
  final DateTime archivedAt;

  int get totalPence => lines.fold(0, (a, l) => a + l.totalPence);
  int get itemCount => lines.fold(0, (a, l) => a + l.quantity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'archivedAt': archivedAt.toIso8601String(),
        'lines': [
          for (final l in lines) {'unitPence': l.unitPence, 'quantity': l.quantity},
        ],
      };

  factory ArchivedDSale.fromJson(Map<String, dynamic> j) => ArchivedDSale(
        id: '${j['id']}',
        archivedAt: DateTime.tryParse('${j['archivedAt']}') ?? DateTime.now(),
        lines: [
          for (final l in (j['lines'] as List? ?? const []))
            DSaleMiscLine(
              unitPence: ((l as Map)['unitPence'] as num?)?.toInt() ?? 0,
              quantity: (l['quantity'] as num?)?.toInt() ?? 1,
            ),
        ],
      );
}

/// Archived Direct Sales on this device. Persisted so they survive a reload.
class DSaleArchiveController extends Notifier<List<ArchivedDSale>> {
  static const _key = 'dsale_archived';

  @override
  List<ArchivedDSale> build() {
    Future.microtask(_load);
    return const [];
  }

  LocalDb get _db => ref.read(localDbProvider);

  Future<void> _load() async {
    final j = await _db.getKv(_key);
    final loaded = ((j?['sales'] as List?) ?? const [])
        .map((e) => ArchivedDSale.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((s) => s.lines.isNotEmpty)
        .toList();
    // Merge with anything archived while loading.
    final ids = state.map((s) => s.id).toSet();
    state = [...state, ...loaded.where((s) => !ids.contains(s.id))]
      ..sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
  }

  Future<void> _save() => _db.putKv(_key, {'sales': state.map((s) => s.toJson()).toList()});

  /// Set a cart aside. Returns the archived record.
  Future<ArchivedDSale> archive(List<DSaleMiscLine> lines) async {
    final sale = ArchivedDSale(id: newId(), lines: List.unmodifiable(lines), archivedAt: DateTime.now());
    state = [sale, ...state];
    await _save();
    return sale;
  }

  /// Remove an archived sale (after it is restored to the till or discarded).
  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _save();
  }
}

final dSaleArchiveProvider = NotifierProvider<DSaleArchiveController, List<ArchivedDSale>>(DSaleArchiveController.new);
