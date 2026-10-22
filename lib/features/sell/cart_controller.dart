import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/ids.dart';
import '../../data/models/cart.dart';
import '../../data/models/catalog.dart';
import '../../data/models/customer.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/initial_data.dart';
import '../../data/repositories/settings_repository.dart';

/// The sale being built. Persisted on every change so a crash or restart
/// never loses a customer's basket.
class CartController extends Notifier<Cart> {
  @override
  Cart build() {
    final j = ref.read(initialDataProvider).cart;
    if (j == null) return _fromSettings();
    try {
      return Cart.fromJson(j);
    } catch (_) {
      return _fromSettings();
    }
  }

  Cart _fromSettings() {
    final s = ref.read(settingsProvider);
    return Cart(
      applyVat: s.vatEnabled,
      vatRate: s.vatRate,
      vatTaxCodeId: s.vatTaxCodeId.isEmpty ? null : s.vatTaxCodeId,
    );
  }

  void _set(Cart cart) {
    state = cart;
    ref.read(localDbProvider).putKv('cart', cart.toJson());
  }

  /// Latest stock for [variantId] from the catalogue, or null when not tracked.
  int? _stockOf(String variantId) => ref.read(catalogProvider).products[variantId]?.stock;

  int quantityInCart(String variantId, {String? exceptLineId}) => state.lines
      .where((l) => l.product.variantId == variantId && l.id != exceptLineId)
      .fold(0, (s, l) => s + l.quantity);

  /// Null when [extra] more units of [product] fit within stock, otherwise the reason.
  String? stockProblem(Product product, int extra, {String? exceptLineId}) {
    if (extra <= 0 || ref.read(settingsProvider).sellBeyondStock) return null;
    final stock = _stockOf(product.variantId) ?? product.stock;
    if (stock == null) return null;
    final inCart = quantityInCart(product.variantId, exceptLineId: exceptLineId);
    if (inCart + extra <= stock) return null;
    if (stock <= 0) return '${product.displayName} is out of stock.';
    final left = stock - inCart;
    return left <= 0
        ? 'Only $stock of ${product.displayName} in stock, all already in this sale.'
        : 'Only $stock of ${product.displayName} in stock ($left more can be added).';
  }

  /// Adds a product; plain lines of the same variant merge into one.
  /// Returns an error message instead of adding when stock would be exceeded.
  String? add(Product product, {int quantity = 1, List<Modifier> modifiers = const [], String? note}) {
    final problem = stockProblem(product, quantity);
    if (problem != null) return problem;
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
    return null;
  }

  void updateLine(CartLine line) => _set(state.copyWith(lines: [for (final l in state.lines) l.id == line.id ? line : l]));

  /// Returns an error message (and leaves the line unchanged) when stock would be exceeded.
  String? setQuantity(String lineId, int quantity) {
    if (quantity <= 0) {
      removeLine(lineId);
      return null;
    }
    final line = state.lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return null;
    if (quantity > line.quantity) {
      final problem = stockProblem(line.product, quantity, exceptLineId: lineId);
      if (problem != null) return problem;
    }
    _set(state.copyWith(lines: [for (final l in state.lines) l.id == lineId ? l.copyWith(quantity: quantity) : l]));
    return null;
  }

  String? increment(String lineId, int by) {
    final line = state.lines.where((l) => l.id == lineId).firstOrNull;
    return line == null ? null : setQuantity(lineId, line.quantity + by);
  }

  /// Removing the last item starts a fresh order, so its customer never carries over.
  void removeLine(String lineId) {
    final lines = state.lines.where((l) => l.id != lineId).toList();
    _set(lines.isEmpty && state.parkedId == null ? _fromSettings() : state.copyWith(lines: lines));
  }

  void setCartDiscount(Discount? discount) =>
      _set(discount == null ? state.copyWith(clearCartDiscount: true) : state.copyWith(cartDiscount: discount));

  void setCustomer(Customer? customer) => _set(customer == null ? state.copyWith(clearCustomer: true) : state.copyWith(customer: customer));

  void setNote(String note) => _set(state.copyWith(note: note));

  void setSaleType(SaleType type) => _set(state.copyWith(saleType: type));

  void setTable(String? tableRef) =>
      _set(tableRef == null || tableRef.isEmpty ? state.copyWith(clearTableRef: true) : state.copyWith(tableRef: tableRef));

  void markAllergenAsked() => _set(state.copyWith(allergenAsked: true));

  void restore(Cart cart) => _set(cart);

  void setVat({required bool enabled, double? rate, String? taxCodeId}) {
    if (!enabled) {
      _set(state.copyWith(applyVat: false, clearVatRate: true, clearVatTaxCodeId: true));
      return;
    }
    _set(state.copyWith(
      applyVat: true,
      vatRate: rate,
      clearVatRate: rate == null,
      vatTaxCodeId: taxCodeId,
      clearVatTaxCodeId: taxCodeId == null || taxCodeId.isEmpty,
    ));
  }

  void clear() => _set(_fromSettings());

  CartTotals get totals => computeTotals(state, pricesIncludeTax: ref.read(settingsProvider).pricesIncludeTax);
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

final cartTotalsProvider = Provider<CartTotals>((ref) {
  final cart = ref.watch(cartProvider);
  final inclusive = ref.watch(settingsProvider.select((s) => s.pricesIncludeTax));
  return computeTotals(cart, pricesIncludeTax: inclusive);
});
