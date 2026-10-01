import '../../core/utils/money.dart';

enum PaymentMethod { cash, card, voucher, account, other }

PaymentMethod paymentMethodFrom(String? v) => PaymentMethod.values.firstWhere((m) => m.name == v, orElse: () => PaymentMethod.other);

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.card => 'Card',
        PaymentMethod.voucher => 'Voucher',
        PaymentMethod.account => 'On account',
        PaymentMethod.other => 'Other',
      };
}

class SalePayment {
  const SalePayment({
    required this.method,
    required this.amountPence,
    this.provider,
    this.tipPence = 0,
    this.tenderedPence,
    this.reference,
    this.cardBrand,
    this.cardLast4,
    this.status = 'approved',
    this.isRefund = false,
  });

  final PaymentMethod method;

  /// Amount applied to the sale (cash tendered minus change).
  final int amountPence;
  final String? provider;
  final int tipPence;
  final int? tenderedPence;
  final String? reference;
  final String? cardBrand;
  final String? cardLast4;
  final String status;
  final bool isRefund;

  String get label {
    final base = method.label;
    if (cardLast4 != null && cardLast4!.isNotEmpty) return '$base •••• $cardLast4';
    return base;
  }

  Map<String, dynamic> toApi() => {
        'method': method.name,
        'provider': provider,
        'amount': fromPence(amountPence),
        'tipAmount': fromPence(tipPence),
        'tendered': tenderedPence == null ? null : fromPence(tenderedPence!),
        'reference': reference,
        'cardBrand': cardBrand,
        'cardLast4': cardLast4,
        'status': status,
      };

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'amountPence': amountPence,
        'provider': provider,
        'tipPence': tipPence,
        'tenderedPence': tenderedPence,
        'reference': reference,
        'cardBrand': cardBrand,
        'cardLast4': cardLast4,
        'status': status,
        'isRefund': isRefund,
      };

  factory SalePayment.fromJson(Map<String, dynamic> j) => SalePayment(
        method: paymentMethodFrom(j['method'] as String?),
        amountPence: (j['amountPence'] as num?)?.toInt() ?? toPence(j['amount'] as num?),
        provider: j['provider'] as String?,
        tipPence: (j['tipPence'] as num?)?.toInt() ?? toPence(j['tipAmount'] as num?),
        tenderedPence: (j['tenderedPence'] as num?)?.toInt() ?? (j['tendered'] == null ? null : toPence(j['tendered'] as num)),
        reference: j['reference'] as String?,
        cardBrand: j['cardBrand'] as String?,
        cardLast4: j['cardLast4'] as String?,
        status: '${j['status'] ?? 'approved'}',
        isRefund: j['isRefund'] == true,
      );
}

class SaleLine {
  const SaleLine({
    this.orderLineId,
    required this.variantId,
    required this.sku,
    required this.name,
    required this.quantity,
    required this.unitPence,
    this.discountPence = 0,
    this.taxRate = 0,
    this.taxPence = 0,
    required this.totalPence,
    this.costPence,
    this.modifiers = const [],
    this.note,
    this.refundedQuantity = 0,
    this.category,
  });

  final String? orderLineId;
  final String variantId;
  final String sku;
  final String name;
  final int quantity;
  final int unitPence;
  final int discountPence;
  final double taxRate;
  final int taxPence;
  final int totalPence;
  final int? costPence;
  final List<String> modifiers;
  final String? note;
  final int refundedQuantity;
  final String? category;

  int get refundableQuantity => quantity - refundedQuantity;

  SaleLine copyWith({int? refundedQuantity}) => SaleLine(
        orderLineId: orderLineId,
        variantId: variantId,
        sku: sku,
        name: name,
        quantity: quantity,
        unitPence: unitPence,
        discountPence: discountPence,
        taxRate: taxRate,
        taxPence: taxPence,
        totalPence: totalPence,
        costPence: costPence,
        modifiers: modifiers,
        note: note,
        refundedQuantity: refundedQuantity ?? this.refundedQuantity,
        category: category,
      );

  Map<String, dynamic> toApi() => {
        'variantId': variantId,
        'sku': sku.isEmpty ? variantId : sku,
        'name': name,
        'quantity': quantity,
        'unitPrice': fromPence(unitPence),
        'discountAmount': fromPence(discountPence),
        'taxRate': taxRate,
        'taxAmount': fromPence(taxPence),
        'lineTotal': fromPence(totalPence),
        'costPrice': costPence == null ? null : fromPence(costPence!),
        'modifiers': modifiers.map((m) => {'name': m}).toList(),
        'notes': note,
      };

  Map<String, dynamic> toJson() => {
        'orderLineId': orderLineId,
        'variantId': variantId,
        'sku': sku,
        'name': name,
        'quantity': quantity,
        'unitPence': unitPence,
        'discountPence': discountPence,
        'taxRate': taxRate,
        'taxPence': taxPence,
        'totalPence': totalPence,
        'costPence': costPence,
        'modifiers': modifiers,
        'note': note,
        'refundedQuantity': refundedQuantity,
        'category': category,
      };

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
        orderLineId: j['orderLineId']?.toString(),
        variantId: '${j['variantId']}',
        sku: '${j['sku'] ?? ''}',
        name: '${j['name'] ?? ''}',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        unitPence: (j['unitPence'] as num?)?.toInt() ?? 0,
        discountPence: (j['discountPence'] as num?)?.toInt() ?? 0,
        taxRate: ((j['taxRate'] as num?) ?? 0).toDouble(),
        taxPence: (j['taxPence'] as num?)?.toInt() ?? 0,
        totalPence: (j['totalPence'] as num?)?.toInt() ?? 0,
        costPence: (j['costPence'] as num?)?.toInt(),
        modifiers: ((j['modifiers'] as List?) ?? []).map((e) => '$e').toList(),
        note: j['note'] as String?,
        refundedQuantity: (j['refundedQuantity'] as num?)?.toInt() ?? 0,
        category: j['category'] as String?,
      );

  /// Parses a line from `GET /api/pos/sales/:code`.
  factory SaleLine.fromServer(Map<String, dynamic> j) => SaleLine(
        orderLineId: '${j['id']}',
        variantId: '${j['variantId']}',
        sku: '${j['sku'] ?? ''}',
        name: '${j['name'] ?? ''}',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        unitPence: toPence(j['unitPrice'] as num?),
        discountPence: toPence(j['discountAmount'] as num?),
        taxRate: ((j['taxRate'] as num?) ?? 0).toDouble(),
        taxPence: toPence(j['taxAmount'] as num?),
        totalPence: toPence(j['lineTotal'] as num?),
        note: j['notes'] as String?,
        refundedQuantity: (j['refundedQuantity'] as num?)?.toInt() ?? 0,
      );
}

enum SyncState { pending, synced, failed }

class SaleRecord {
  const SaleRecord({
    required this.clientId,
    required this.receiptNumber,
    this.orderNumber,
    this.serverId,
    this.registerId,
    this.registerName,
    this.shiftId,
    this.shiftClientId,
    this.staffUserId,
    this.staffName,
    this.deviceId,
    required this.soldAt,
    this.saleType = 'instore',
    this.tableRef,
    this.customerId,
    this.customerName,
    this.customerEmail,
    required this.subtotalPence,
    this.discountPence = 0,
    required this.taxPence,
    required this.totalPence,
    this.tipPence = 0,
    this.changePence = 0,
    this.refundedPence = 0,
    this.notes,
    required this.lines,
    required this.payments,
    this.status = 'completed',
    this.sync = SyncState.pending,
  });

  final String clientId;
  final String receiptNumber;
  final String? orderNumber;
  final String? serverId;
  final String? registerId;
  final String? registerName;
  final String? shiftId;
  final String? shiftClientId;
  final String? staffUserId;
  final String? staffName;
  final String? deviceId;
  final DateTime soldAt;
  final String saleType;
  final String? tableRef;
  final String? customerId;
  final String? customerName;
  final String? customerEmail;
  final int subtotalPence;
  final int discountPence;
  final int taxPence;
  final int totalPence;
  final int tipPence;
  final int changePence;
  final int refundedPence;
  final String? notes;
  final List<SaleLine> lines;
  final List<SalePayment> payments;
  final String status;
  final SyncState sync;

  /// The code printed as the receipt barcode and used for refund lookups.
  String get lookupCode => receiptNumber;

  int get refundablePence => totalPence - refundedPence;

  SaleRecord copyWith({String? status, SyncState? sync, String? serverId, String? orderNumber, int? refundedPence, List<SaleLine>? lines, String? customerEmail}) => SaleRecord(
        clientId: clientId,
        receiptNumber: receiptNumber,
        orderNumber: orderNumber ?? this.orderNumber,
        serverId: serverId ?? this.serverId,
        registerId: registerId,
        registerName: registerName,
        shiftId: shiftId,
        shiftClientId: shiftClientId,
        staffUserId: staffUserId,
        staffName: staffName,
        deviceId: deviceId,
        soldAt: soldAt,
        saleType: saleType,
        tableRef: tableRef,
        customerId: customerId,
        customerName: customerName,
        customerEmail: customerEmail ?? this.customerEmail,
        subtotalPence: subtotalPence,
        discountPence: discountPence,
        taxPence: taxPence,
        totalPence: totalPence,
        tipPence: tipPence,
        changePence: changePence,
        refundedPence: refundedPence ?? this.refundedPence,
        notes: notes,
        lines: lines ?? this.lines,
        payments: payments,
        status: status ?? this.status,
        sync: sync ?? this.sync,
      );

  Map<String, dynamic> toApi() => {
        'clientId': clientId,
        'receiptNumber': receiptNumber,
        'registerId': registerId,
        'shiftId': shiftId,
        'shiftClientId': shiftClientId,
        'staffUserId': staffUserId,
        'deviceId': deviceId,
        'soldAt': soldAt.toUtc().toIso8601String(),
        'saleType': saleType,
        'tableRef': tableRef,
        'customerId': customerId,
        'customerEmail': customerEmail,
        'currency': 'GBP',
        'subtotal': fromPence(subtotalPence),
        'discountAmount': fromPence(discountPence),
        'taxAmount': fromPence(taxPence),
        'total': fromPence(totalPence),
        'tipAmount': fromPence(tipPence),
        'changeGiven': fromPence(changePence),
        'notes': notes,
        'lines': lines.map((l) => l.toApi()).toList(),
        'payments': payments.map((p) => p.toApi()).toList(),
      };

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'receiptNumber': receiptNumber,
        'orderNumber': orderNumber,
        'serverId': serverId,
        'registerId': registerId,
        'registerName': registerName,
        'shiftId': shiftId,
        'shiftClientId': shiftClientId,
        'staffUserId': staffUserId,
        'staffName': staffName,
        'deviceId': deviceId,
        'soldAt': soldAt.toIso8601String(),
        'saleType': saleType,
        'tableRef': tableRef,
        'customerId': customerId,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'subtotalPence': subtotalPence,
        'discountPence': discountPence,
        'taxPence': taxPence,
        'totalPence': totalPence,
        'tipPence': tipPence,
        'changePence': changePence,
        'refundedPence': refundedPence,
        'notes': notes,
        'lines': lines.map((l) => l.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'status': status,
        'sync': sync.name,
      };

  factory SaleRecord.fromJson(Map<String, dynamic> j) => SaleRecord(
        clientId: '${j['clientId']}',
        receiptNumber: '${j['receiptNumber']}',
        orderNumber: j['orderNumber'] as String?,
        serverId: j['serverId']?.toString(),
        registerId: j['registerId']?.toString(),
        registerName: j['registerName'] as String?,
        shiftId: j['shiftId']?.toString(),
        shiftClientId: j['shiftClientId'] as String?,
        staffUserId: j['staffUserId']?.toString(),
        staffName: j['staffName'] as String?,
        deviceId: j['deviceId'] as String?,
        soldAt: DateTime.tryParse('${j['soldAt']}')?.toLocal() ?? DateTime.now(),
        saleType: '${j['saleType'] ?? 'instore'}',
        tableRef: j['tableRef'] as String?,
        customerId: j['customerId']?.toString(),
        customerName: j['customerName'] as String?,
        customerEmail: j['customerEmail'] as String?,
        subtotalPence: (j['subtotalPence'] as num?)?.toInt() ?? 0,
        discountPence: (j['discountPence'] as num?)?.toInt() ?? 0,
        taxPence: (j['taxPence'] as num?)?.toInt() ?? 0,
        totalPence: (j['totalPence'] as num?)?.toInt() ?? 0,
        tipPence: (j['tipPence'] as num?)?.toInt() ?? 0,
        changePence: (j['changePence'] as num?)?.toInt() ?? 0,
        refundedPence: (j['refundedPence'] as num?)?.toInt() ?? 0,
        notes: j['notes'] as String?,
        lines: ((j['lines'] as List?) ?? []).map((l) => SaleLine.fromJson(Map<String, dynamic>.from(l as Map))).toList(),
        payments: ((j['payments'] as List?) ?? []).map((p) => SalePayment.fromJson(Map<String, dynamic>.from(p as Map))).toList(),
        status: '${j['status'] ?? 'completed'}',
        sync: SyncState.values.firstWhere((s) => s.name == j['sync'], orElse: () => SyncState.pending),
      );

  /// Parses `GET /api/pos/sales/:code`.
  factory SaleRecord.fromServer(Map<String, dynamic> j) {
    final customer = j['customer'] is Map ? Map<String, dynamic>.from(j['customer'] as Map) : null;
    return SaleRecord(
      clientId: '${j['clientId'] ?? j['id']}',
      receiptNumber: '${j['receiptNumber'] ?? j['orderNumber']}',
      orderNumber: j['orderNumber'] as String?,
      serverId: j['id']?.toString(),
      registerId: j['registerId']?.toString(),
      registerName: j['registerName'] as String?,
      shiftId: j['shiftId']?.toString(),
      staffUserId: j['staffUserId']?.toString(),
      staffName: j['staffName'] as String?,
      soldAt: DateTime.tryParse('${j['soldAt']}')?.toLocal() ?? DateTime.now(),
      saleType: '${j['saleType'] ?? 'instore'}',
      tableRef: j['tableRef'] as String?,
      customerId: customer?['id']?.toString(),
      customerName: customer?['name'] as String?,
      customerEmail: (customer?['email'] ?? j['customerEmail']) as String?,
      subtotalPence: toPence(j['subtotal'] as num?),
      discountPence: toPence(j['discountAmount'] as num?),
      taxPence: toPence(j['taxAmount'] as num?),
      totalPence: toPence(j['total'] as num?),
      tipPence: toPence(j['tipAmount'] as num?),
      changePence: toPence(j['changeGiven'] as num?),
      refundedPence: toPence(j['refundedAmount'] as num?),
      notes: j['notes'] as String?,
      lines: ((j['lines'] as List?) ?? []).map((l) => SaleLine.fromServer(Map<String, dynamic>.from(l as Map))).toList(),
      payments: ((j['payments'] as List?) ?? []).map((p) => SalePayment.fromJson(Map<String, dynamic>.from(p as Map))).toList(),
      status: '${j['status'] ?? 'completed'}',
      sync: SyncState.synced,
    );
  }
}

/// Row in the Previous Sales list (`GET /api/pos/sales`).
class SaleSummary {
  const SaleSummary({
    required this.code,
    required this.receiptNumber,
    required this.soldAt,
    required this.totalPence,
    this.registerName,
    this.staffName,
    this.status = 'completed',
    this.paymentMethods = const [],
    this.itemCount = 0,
    this.sync = SyncState.synced,
  });

  final String code;
  final String receiptNumber;
  final DateTime soldAt;
  final int totalPence;
  final String? registerName;
  final String? staffName;
  final String status;
  final List<String> paymentMethods;
  final int itemCount;
  final SyncState sync;

  factory SaleSummary.fromServer(Map<String, dynamic> j) => SaleSummary(
        code: '${j['orderNumber']}',
        receiptNumber: '${j['receiptNumber'] ?? j['orderNumber']}',
        soldAt: DateTime.tryParse('${j['soldAt']}')?.toLocal() ?? DateTime.now(),
        totalPence: toPence(j['total'] as num?),
        registerName: j['registerName'] as String?,
        staffName: j['staffName'] as String?,
        status: '${j['status'] ?? 'completed'}',
        paymentMethods: ((j['paymentMethods'] as List?) ?? []).map((e) => '$e').toList(),
        itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
      );

  factory SaleSummary.fromLocal(SaleRecord s) => SaleSummary(
        code: s.clientId,
        receiptNumber: s.receiptNumber,
        soldAt: s.soldAt,
        totalPence: s.totalPence,
        registerName: s.registerName,
        staffName: s.staffName,
        status: s.status,
        paymentMethods: s.payments.map((p) => p.method.name).toSet().toList(),
        itemCount: s.lines.fold(0, (a, l) => a + l.quantity),
        sync: s.sync,
      );
}
