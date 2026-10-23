import 'package:flutter_test/flutter_test.dart';
import 'package:zaam_epos/core/utils/money.dart';
import 'package:zaam_epos/data/models/cart.dart';
import 'package:zaam_epos/data/models/catalog.dart';
import 'package:zaam_epos/data/models/settings.dart';

Product _product(String id, int pence, {double tax = 0.2}) => Product(
      variantId: id,
      catalogItemId: 'item-$id',
      sku: 'SKU-$id',
      name: 'Product $id',
      pricePence: pence,
      taxRate: tax,
    );

void main() {
  test('money formatting and parsing', () {
    expect(formatPence(1234), '£12.34');
    expect(parsePence('£12.34'), 1234);
    expect(toPence(9.99), 999);
  });

  test('VAT rates stored as percent (20) are treated as 20%', () {
    final cart = Cart(lines: [CartLine(id: 'a', product: _product('1', 1200, tax: 20), quantity: 1)]);
    final t = computeTotals(cart);
    expect(t.totalPence, 1200);
    expect(t.taxPence, 200);
  });

  test('VAT-inclusive totals extract VAT from the line value', () {
    final cart = Cart(lines: [CartLine(id: 'a', product: _product('1', 1200), quantity: 1)]);
    final t = computeTotals(cart);
    expect(t.totalPence, 1200);
    expect(t.taxPence, 200);
  });

  test('VAT off reports no tax and keeps an inclusive total', () {
    final cart = Cart(applyVat: false, lines: [CartLine(id: 'a', product: _product('1', 1200), quantity: 1)]);
    final t = computeTotals(cart);
    expect(t.totalPence, 1200);
    expect(t.taxPence, 0);
  });

  test('till VAT rate is added on top of the price', () {
    final cart = Cart(
      applyVat: true,
      vatRate: 0.2,
      lines: [CartLine(id: 'a', product: _product('1', 1000), quantity: 1)],
    );
    final t = computeTotals(cart);
    expect(t.taxPence, 200);
    expect(t.totalPence, 1200);
  });

  test('exclusive prices add the selected VAT on top', () {
    final cart = Cart(
      applyVat: true,
      vatRate: 0.18,
      lines: [CartLine(id: 'a', product: _product('1', 1000, tax: 0.2), quantity: 1)],
    );
    final t = computeTotals(cart, pricesIncludeTax: false);
    expect(t.taxPence, 180);
    expect(t.totalPence, 1180);
  });

  test('cart discount is spread across lines and never exceeds the total', () {
    final cart = Cart(
      lines: [
        CartLine(id: 'a', product: _product('1', 1000), quantity: 1),
        CartLine(id: 'b', product: _product('2', 3000), quantity: 1),
      ],
      cartDiscount: const Discount(type: DiscountType.percent, value: 10),
    );
    final t = computeTotals(cart);
    expect(t.cartDiscountPence, 400);
    expect(t.totalPence, 3600);
    expect(t.lines.fold<int>(0, (s, l) => s + l.discountPence), 400);
  });

  test('auto-print receipts defaults on and survives JSON round-trip', () {
    const fresh = PosSettings();
    expect(fresh.autoPrintReceipts, isTrue);
    final restored = PosSettings.fromJson({});
    expect(restored.autoPrintReceipts, isTrue);
    final off = fresh.copyWith(autoPrintReceipts: false);
    expect(PosSettings.fromJson(off.toJson()).autoPrintReceipts, isFalse);
    // Legacy saved settings without the key keep the default (on).
    expect(PosSettings.fromJson({'receiptPrompt': true}).autoPrintReceipts, isTrue);
  });

}
