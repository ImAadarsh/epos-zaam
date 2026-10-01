import 'package:flutter_test/flutter_test.dart';
import 'package:zaam_epos/core/security/pin.dart';
import 'package:zaam_epos/core/utils/money.dart';
import 'package:zaam_epos/data/models/cart.dart';
import 'package:zaam_epos/data/models/catalog.dart';
import 'package:zaam_epos/data/models/org.dart';

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

  test('VAT-inclusive totals extract VAT from the line value', () {
    final cart = Cart(lines: [CartLine(id: 'a', product: _product('1', 1200), quantity: 1)]);
    final t = computeTotals(cart);
    expect(t.totalPence, 1200);
    expect(t.taxPence, 200);
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

  test('offline PIN check matches the server hash scheme', () {
    const salt = 'abc123';
    final staff = [StaffMember(id: '7', name: 'Sam Cashier', pinSalt: salt, pinHash: hashPin(salt, '1234'))];
    expect(matchPin(staff, '1234')?.id, '7');
    expect(matchPin(staff, '9999'), isNull);
  });
}
