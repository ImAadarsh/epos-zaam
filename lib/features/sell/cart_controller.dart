import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/ids.dart';
import '../../data/models/cart.dart';
import '../../data/models/catalog.dart';
import '../../data/models/customer.dart';
import '../../data/repositories/initial_data.dart';
import '../../data/repositories/settings_repository.dart';

/// The sale being built. Persisted on every change so a crash or restart
/// never loses a customer's basket.
class CartController extends Notifier<Cart> {
  @override
  Cart build() {
    final j = ref.read(initialDataProvider).cart;
    if (j == null) return const Cart();
    try {
      return Cart.fromJson(j);
    } catch (_) {
      return const Cart();
    }
  }

  void _set(Cart cart) {
    state = cart;
    ref.read(localDbProvider).putKv('cart', cart.toJson());
  }

  /// Adds a product; plain lines of the same variant merge into one.
  void add(Product product, {int quantity = 1, List<Modifier> modifiers = const [], String? note}) {
    final lines = [...state.lines];
    final plain = modifiers.isEmpty && (note == null || note.isEmpty);
    final idx = plain ? lines.indexWhere((l) => l.product.variantId == product.variantId && l.isPlain) : -1;
    if (idx >= 0) {
      lines[idx] = lines[idx].copyWith(quantity: lines[idx].quantity + quantity);
      final moved = lines.removeAt(idx);
      lines.add(moved);
    } else {
      lines.add(CartLine(id: newId(), product: product, quantity: quantity, modifiers: modifiers, note: note));
    }
    _set(state.copyWith(lines: lines, startedAt: state.startedAt ?? DateTime.now()));
  }

  void updateLine(CartLine line) => _set(state.copyWith(lines: [for (final l in state.lines) l.id == line.id ? line : l]));

  void setQuantity(String lineId, int quantity) {
    if (quantity <= 0) {
      removeLine(lineId);
      return;
    }
    _set(state.copyWith(lines: [for (final l in state.lines) l.id == lineId ? l.copyWith(quantity: quantity) : l]));
  }

  void increment(String lineId, int by) {
    final line = state.lines.where((l) => l.id == lineId).firstOrNull;
    if (line != null) setQuantity(lineId, line.quantity + by);
  }

  void removeLine(String lineId) => _set(state.copyWith(lines: state.lines.where((l) => l.id != lineId).toList()));

  void setCartDiscount(Discount? discount) =>
      _set(discount == null ? state.copyWith(clearCartDiscount: true) : state.copyWith(cartDiscount: discount));

  void setCustomer(Customer? customer) => _set(customer == null ? state.copyWith(clearCustomer: true) : state.copyWith(customer: customer));

  void setNote(String note) => _set(state.copyWith(note: note));

  void setSaleType(SaleType type) => _set(state.copyWith(saleType: type));

  void setTable(String? tableRef) =>
      _set(tableRef == null || tableRef.isEmpty ? state.copyWith(clearTableRef: true) : state.copyWith(tableRef: tableRef));

  void markAllergenAsked() => _set(state.copyWith(allergenAsked: true));

  void restore(Cart cart) => _set(cart);

  void clear() => _set(const Cart());

  CartTotals get totals => computeTotals(state, pricesIncludeTax: ref.read(settingsProvider).pricesIncludeTax);
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

final cartTotalsProvider = Provider<CartTotals>((ref) {
  final cart = ref.watch(cartProvider);
  final inclusive = ref.watch(settingsProvider.select((s) => s.pricesIncludeTax));
  return computeTotals(cart, pricesIncludeTax: inclusive);
});
