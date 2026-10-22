import 'catalog.dart';
import 'customer.dart';

enum DiscountType { percent, amount }

class Discount {
  const Discount({required this.type, required this.value, this.reason});

  final DiscountType type;

  /// Percent (0–100) or pence, depending on [type].
  final num value;
  final String? reason;

  int amountOn(int basePence) {
    if (basePence <= 0) return 0;
    final raw = type == DiscountType.percent ? (basePence * value / 100).round() : value.round();
    return raw.clamp(0, basePence);
  }

  String label(String Function(int) money) => type == DiscountType.percent ? '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%' : money(value.round());

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value, 'reason': reason};

  factory Discount.fromJson(Map<String, dynamic> j) => Discount(
        type: j['type'] == 'amount' ? DiscountType.amount : DiscountType.percent,
        value: (j['value'] as num?) ?? 0,
        reason: j['reason'] as String?,
      );
}

class CartLine {
  const CartLine({
    required this.id,
    required this.product,
    this.quantity = 1,
    this.modifiers = const [],
    this.priceOverridePence,
    this.discount,
    this.note,
  });

  final String id;
  final Product product;
  final int quantity;
  final List<Modifier> modifiers;
  final int? priceOverridePence;
  final Discount? discount;
  final String? note;

  int get unitPence => (priceOverridePence ?? product.effectivePricePence) + modifiers.fold(0, (s, m) => s + m.priceDeltaPence);

  int get grossPence => unitPence * quantity;

  int get itemDiscountPence => discount?.amountOn(grossPence) ?? 0;

  /// Lines merge when the same variant is added with no customisation.
  bool get isPlain => modifiers.isEmpty && priceOverridePence == null && discount == null && (note == null || note!.isEmpty);

  CartLine copyWith({
    int? quantity,
    List<Modifier>? modifiers,
    int? priceOverridePence,
    bool clearPriceOverride = false,
    Discount? discount,
    bool clearDiscount = false,
    String? note,
  }) =>
      CartLine(
        id: id,
        product: product,
        quantity: quantity ?? this.quantity,
        modifiers: modifiers ?? this.modifiers,
        priceOverridePence: clearPriceOverride ? null : (priceOverridePence ?? this.priceOverridePence),
        discount: clearDiscount ? null : (discount ?? this.discount),
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'product': product.toJson(),
        'quantity': quantity,
        'modifiers': modifiers.map((m) => m.toJson()).toList(),
        'priceOverridePence': priceOverridePence,
        'discount': discount?.toJson(),
        'note': note,
      };

  factory CartLine.fromJson(Map<String, dynamic> j) => CartLine(
        id: '${j['id']}',
        product: Product.fromJson(Map<String, dynamic>.from(j['product'] as Map)),
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        modifiers: ((j['modifiers'] as List?) ?? []).map((m) => Modifier.fromJson(Map<String, dynamic>.from(m as Map))).toList(),
        priceOverridePence: (j['priceOverridePence'] as num?)?.toInt(),
        discount: j['discount'] is Map ? Discount.fromJson(Map<String, dynamic>.from(j['discount'] as Map)) : null,
        note: j['note'] as String?,
      );
}

enum SaleType { instore, eatIn, takeAway }

extension SaleTypeX on SaleType {
  String get api => switch (this) { SaleType.instore => 'instore', SaleType.eatIn => 'eat_in', SaleType.takeAway => 'take_away' };
  String get label => switch (this) { SaleType.instore => 'In store', SaleType.eatIn => 'Eat in', SaleType.takeAway => 'Take away' };
}

SaleType saleTypeFrom(String? v) => switch (v) { 'eat_in' => SaleType.eatIn, 'take_away' => SaleType.takeAway, _ => SaleType.instore };

class Cart {
  const Cart({
    this.lines = const [],
    this.cartDiscount,
    this.customer,
    this.note,
    this.saleType = SaleType.instore,
    this.tableRef,
    this.parkedId,
    this.startedAt,
    this.allergenAsked = false,
    this.applyVat = true,
    this.vatRate,
    this.vatTaxCodeId,
  });

  final List<CartLine> lines;
  final Discount? cartDiscount;
  final Customer? customer;
  final String? note;
  final SaleType saleType;
  final String? tableRef;

  /// Set when this cart was restored from a saved (parked) sale.
  final String? parkedId;
  final DateTime? startedAt;
  final bool allergenAsked;

  /// When false, every line is treated as 0% VAT.
  final bool applyVat;

  /// Till-wide VAT fraction for this sale (`0.05` = 5%). Null keeps each product's own rate.
  final double? vatRate;
  final String? vatTaxCodeId;

  double taxRateFor(CartLine line) {
    if (!applyVat) return 0;
    final raw = vatRate ?? line.product.taxRate;
    return raw > 1 ? raw / 100 : raw;
  }

  bool get isEmpty => lines.isEmpty;

  /// True when anything (items, customer, discount, table, note) is attached to the order.
  bool get hasContent =>
      lines.isNotEmpty || customer != null || cartDiscount != null || tableRef != null || (note?.isNotEmpty ?? false) || parkedId != null;
  int get itemCount => lines.fold(0, (s, l) => s + l.quantity);

  Cart copyWith({
    List<CartLine>? lines,
    Discount? cartDiscount,
    bool clearCartDiscount = false,
    Customer? customer,
    bool clearCustomer = false,
    String? note,
    SaleType? saleType,
    String? tableRef,
    bool clearTableRef = false,
    String? parkedId,
    DateTime? startedAt,
    bool? allergenAsked,
    bool? applyVat,
    double? vatRate,
    bool clearVatRate = false,
    String? vatTaxCodeId,
    bool clearVatTaxCodeId = false,
  }) =>
      Cart(
        lines: lines ?? this.lines,
        cartDiscount: clearCartDiscount ? null : (cartDiscount ?? this.cartDiscount),
        customer: clearCustomer ? null : (customer ?? this.customer),
        note: note ?? this.note,
        saleType: saleType ?? this.saleType,
        tableRef: clearTableRef ? null : (tableRef ?? this.tableRef),
        parkedId: parkedId ?? this.parkedId,
        startedAt: startedAt ?? this.startedAt,
        allergenAsked: allergenAsked ?? this.allergenAsked,
        applyVat: applyVat ?? this.applyVat,
        vatRate: clearVatRate ? null : (vatRate ?? this.vatRate),
        vatTaxCodeId: clearVatTaxCodeId ? null : (vatTaxCodeId ?? this.vatTaxCodeId),
      );

  Map<String, dynamic> toJson() => {
        'lines': lines.map((l) => l.toJson()).toList(),
        'cartDiscount': cartDiscount?.toJson(),
        'customer': customer?.toJson(),
        'note': note,
        'saleType': saleType.api,
        'tableRef': tableRef,
        'parkedId': parkedId,
        'startedAt': startedAt?.toIso8601String(),
        'applyVat': applyVat,
        'vatRate': vatRate,
        'vatTaxCodeId': vatTaxCodeId,
      };

  factory Cart.fromJson(Map<String, dynamic> j) => Cart(
        lines: ((j['lines'] as List?) ?? []).map((l) => CartLine.fromJson(Map<String, dynamic>.from(l as Map))).toList(),
        cartDiscount: j['cartDiscount'] is Map ? Discount.fromJson(Map<String, dynamic>.from(j['cartDiscount'] as Map)) : null,
        customer: j['customer'] is Map ? Customer.fromJson(Map<String, dynamic>.from(j['customer'] as Map)) : null,
        note: j['note'] as String?,
        saleType: saleTypeFrom(j['saleType'] as String?),
        tableRef: j['tableRef'] as String?,
        parkedId: j['parkedId'] as String?,
        startedAt: j['startedAt'] != null ? DateTime.tryParse('${j['startedAt']}') : null,
        allergenAsked: true,
        applyVat: j['applyVat'] != false,
        vatRate: (j['vatRate'] as num?)?.toDouble(),
        vatTaxCodeId: j['vatTaxCodeId'] as String?,
      );
}

class LineTotals {
  const LineTotals({required this.line, required this.grossPence, required this.discountPence, required this.taxPence, required this.totalPence});

  final CartLine line;
  final int grossPence;

  /// Item discount plus this line's share of the cart discount.
  final int discountPence;
  final int taxPence;
  final int totalPence;
}

class CartTotals {
  const CartTotals({
    required this.lines,
    required this.subtotalPence,
    required this.itemDiscountPence,
    required this.cartDiscountPence,
    required this.taxPence,
    required this.totalPence,
  });

  final List<LineTotals> lines;
  final int subtotalPence;
  final int itemDiscountPence;
  final int cartDiscountPence;
  final int taxPence;
  final int totalPence;

  int get discountPence => itemDiscountPence + cartDiscountPence;

  static const empty = CartTotals(lines: [], subtotalPence: 0, itemDiscountPence: 0, cartDiscountPence: 0, taxPence: 0, totalPence: 0);
}

/// Computes line and cart totals.
///
/// UK retail prices are normally VAT-inclusive ([pricesIncludeTax] = true):
/// VAT is extracted from the net line value. Otherwise VAT is added on top.
/// The cart discount is spread across lines in proportion to their value so
/// each line's VAT stays correct; rounding remainders go to the last line.
CartTotals computeTotals(Cart cart, {bool pricesIncludeTax = true}) {
  if (cart.lines.isEmpty) return CartTotals.empty;
  final subtotal = cart.lines.fold(0, (s, l) => s + l.grossPence);
  final itemDiscount = cart.lines.fold(0, (s, l) => s + l.itemDiscountPence);
  final afterItem = subtotal - itemDiscount;
  final cartDiscount = cart.cartDiscount?.amountOn(afterItem) ?? 0;

  final result = <LineTotals>[];
  var allocated = 0;
  var tax = 0;
  var total = 0;
  for (var i = 0; i < cart.lines.length; i++) {
    final line = cart.lines[i];
    final lineNet = line.grossPence - line.itemDiscountPence;
    int share;
    if (i == cart.lines.length - 1) {
      share = cartDiscount - allocated;
    } else {
      share = afterItem == 0 ? 0 : (cartDiscount * lineNet / afterItem).round();
      allocated += share;
    }
    final net = (lineNet - share).clamp(0, lineNet);
    final rate = cart.taxRateFor(line);
    final int lineTax;
    final int lineTotal;
    // A rate chosen on the till (20% or an organisation code) is added on top of the price.
    // Product rates stay inside the price only when the till is set to VAT-inclusive shelf prices.
    final addOnTop = cart.vatRate != null || !pricesIncludeTax;
    if (!addOnTop) {
      lineTax = rate <= 0 ? 0 : (net - net / (1 + rate)).round();
      lineTotal = net;
    } else {
      lineTax = (net * rate).round();
      lineTotal = net + lineTax;
    }
    tax += lineTax;
    total += lineTotal;
    result.add(LineTotals(line: line, grossPence: line.grossPence, discountPence: line.itemDiscountPence + share, taxPence: lineTax, totalPence: lineTotal));
  }
  return CartTotals(
    lines: result,
    subtotalPence: subtotal,
    itemDiscountPence: itemDiscount,
    cartDiscountPence: cartDiscount,
    taxPence: tax,
    totalPence: total,
  );
}
