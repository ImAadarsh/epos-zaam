import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/ids.dart';
import '../models/cart.dart';

class ParkedSale {
  const ParkedSale({required this.id, required this.cart, required this.parkedAt, this.label, this.staffName, required this.totalPence});

  final String id;
  final Cart cart;
  final DateTime parkedAt;
  final String? label;
  final String? staffName;
  final int totalPence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'cart': cart.toJson(),
        'parkedAt': parkedAt.toIso8601String(),
        'label': label,
        'staffName': staffName,
        'totalPence': totalPence,
      };

  factory ParkedSale.fromJson(Map<String, dynamic> j) => ParkedSale(
        id: '${j['id']}',
        cart: Cart.fromJson(Map<String, dynamic>.from(j['cart'] as Map)),
        parkedAt: DateTime.tryParse('${j['parkedAt']}') ?? DateTime.now(),
        label: j['label'] as String?,
        staffName: j['staffName'] as String?,
        totalPence: (j['totalPence'] as num?)?.toInt() ?? 0,
      );
}

/// Saved (parked) sales on this device — e.g. open tables or customers still shopping.
class ParkedSalesController extends Notifier<List<ParkedSale>> {
  @override
  List<ParkedSale> build() {
    Future.microtask(_load);
    return const [];
  }

  LocalDb get _db => ref.read(localDbProvider);

  Future<void> _load() async {
    final rows = await _db.all(LocalDb.parked);
    state = rows.map(ParkedSale.fromJson).toList()..sort((a, b) => b.parkedAt.compareTo(a.parkedAt));
  }

  Future<ParkedSale> park(Cart cart, {String? label, String? staffName, required int totalPence}) async {
    final id = cart.parkedId ?? newId();
    final sale = ParkedSale(
      id: id,
      cart: cart.copyWith(parkedId: id, startedAt: cart.startedAt ?? DateTime.now()),
      parkedAt: DateTime.now(),
      label: label ?? cart.tableRef ?? cart.customer?.name,
      staffName: staffName,
      totalPence: totalPence,
    );
    await _db.put(LocalDb.parked, id, sale.toJson());
    state = [sale, ...state.where((s) => s.id != id)];
    return sale;
  }

  Future<void> remove(String id) async {
    await _db.delete(LocalDb.parked, id);
    state = state.where((s) => s.id != id).toList();
  }

  Future<void> clear() async {
    await _db.replaceAll(LocalDb.parked, {});
    state = const [];
  }
}

final parkedSalesProvider = NotifierProvider<ParkedSalesController, List<ParkedSale>>(ParkedSalesController.new);
