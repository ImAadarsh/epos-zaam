import 'package:flutter_test/flutter_test.dart';
import 'package:zaam_epos/data/models/sale.dart';

void main() {
  test('misc Direct Sale line sends null variantId to API', () {
    const line = SaleLine(
      variantId: '',
      sku: 'MISC',
      name: 'Miscellaneous sale',
      quantity: 1,
      unitPence: 800,
      totalPence: 800,
      note: 'Direct Sale',
      category: 'Direct Sale',
    );
    final api = line.toApi();
    expect(api['variantId'], isNull);
    expect(api['sku'], 'MISC');
    expect(api['lineTotal'], 8.0);
    expect(api['notes'], 'Direct Sale');
  });

  test('cents keypad: 2 then 00 is £2.00', () {
    var digits = '';
    void append(String d) {
      final next = '$digits$d';
      digits = next.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (digits.isEmpty && (d == '0' || d == '00')) digits = '0';
    }

    append('2');
    expect(int.tryParse(digits) ?? 0, 2);
    append('00');
    expect(int.tryParse(digits) ?? 0, 200);
    expect(((int.tryParse(digits) ?? 0) / 100).toStringAsFixed(2), '2.00');
  });
}
