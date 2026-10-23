import 'package:flutter_test/flutter_test.dart';
import 'package:zaam_epos/core/utils/money.dart';
import 'package:zaam_epos/data/models/cart.dart';
import 'package:zaam_epos/data/models/catalog.dart';

Product _product(String id, int pence) => Product(
      variantId: id,
      catalogItemId: 'item-$id',
      sku: 'SKU-$id',
      name: 'Product $id',
      pricePence: pence,
      taxRate: 0.2,
    );

void main() {
  test('sale-only override keeps catalogue product price', () {
    final product = _product('1', 800);
    final line = CartLine(id: 'a', product: product, quantity: 2, priceOverridePence: 960);
    expect(line.unitPence, 960);
    expect(line.product.pricePence, 800);
    expect(line.grossPence, 1920);
  });

  test('permanent local apply updates product and clears override', () {
    final old = _product('1', 800);
    final updated = old.copyWith(pricePence: 960, clearPromoPrice: true);
    final line = CartLine(id: 'a', product: old, quantity: 1, priceOverridePence: 900)
        .copyWith(product: updated, clearPriceOverride: true);
    expect(line.priceOverridePence, isNull);
    expect(line.unitPence, 960);
    expect(line.product.pricePence, 960);
    expect(formatPence(line.unitPence), '£9.60');
  });
}
