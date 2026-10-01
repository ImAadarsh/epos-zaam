import '../../core/utils/money.dart';

/// The register session between "open register" and the Z-read.
class ShiftState {
  const ShiftState({
    required this.clientId,
    this.serverId,
    required this.registerId,
    required this.openedAt,
    required this.openingFloatPence,
    this.openedBy,
    this.status = 'open',
  });

  final String clientId;
  final String? serverId;
  final String registerId;
  final DateTime openedAt;
  final int openingFloatPence;
  final String? openedBy;
  final String status;

  bool get isOpen => status == 'open';

  ShiftState copyWith({String? serverId, String? status}) => ShiftState(
        clientId: clientId,
        serverId: serverId ?? this.serverId,
        registerId: registerId,
        openedAt: openedAt,
        openingFloatPence: openingFloatPence,
        openedBy: openedBy,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'serverId': serverId,
        'registerId': registerId,
        'openedAt': openedAt.toIso8601String(),
        'openingFloatPence': openingFloatPence,
        'openedBy': openedBy,
        'status': status,
      };

  factory ShiftState.fromJson(Map<String, dynamic> j) => ShiftState(
        clientId: '${j['clientId']}',
        serverId: j['serverId']?.toString(),
        registerId: '${j['registerId']}',
        openedAt: DateTime.tryParse('${j['openedAt']}')?.toLocal() ?? DateTime.now(),
        openingFloatPence: (j['openingFloatPence'] as num?)?.toInt() ?? 0,
        openedBy: j['openedBy']?.toString(),
        status: '${j['status'] ?? 'open'}',
      );
}

class PaymentBreakdown {
  const PaymentBreakdown({required this.method, this.provider, required this.count, required this.takenPence, required this.refundedPence});
  final String method;
  final String? provider;
  final int count;
  final int takenPence;
  final int refundedPence;
  int get netPence => takenPence + refundedPence;
}

class NamedAmount {
  const NamedAmount(this.name, this.count, this.amountPence);
  final String name;
  final int count;
  final int amountPence;
}

/// X-read (register open) or Z-read (register closed) figures.
class ShiftReport {
  const ShiftReport({
    required this.type,
    required this.openedAt,
    this.closedAt,
    required this.generatedAt,
    required this.openingFloatPence,
    required this.salesCount,
    required this.grossPence,
    required this.discountsPence,
    required this.taxPence,
    required this.netPence,
    this.tipsPence = 0,
    required this.refundCount,
    required this.refundPence,
    required this.voidCount,
    required this.voidPence,
    required this.payments,
    this.paidInPence = 0,
    this.paidOutPence = 0,
    this.dropsPence = 0,
    this.noSales = 0,
    this.categories = const [],
    this.staff = const [],
    required this.expectedCashPence,
    this.countedCashPence,
    this.variancePence,
    this.source = 'server',
  });

  final String type;
  final DateTime openedAt;
  final DateTime? closedAt;
  final DateTime generatedAt;
  final int openingFloatPence;
  final int salesCount;
  final int grossPence;
  final int discountsPence;
  final int taxPence;
  final int netPence;
  final int tipsPence;
  final int refundCount;
  final int refundPence;
  final int voidCount;
  final int voidPence;
  final List<PaymentBreakdown> payments;
  final int paidInPence;
  final int paidOutPence;
  final int dropsPence;
  final int noSales;
  final List<NamedAmount> categories;
  final List<NamedAmount> staff;
  final int expectedCashPence;
  final int? countedCashPence;
  final int? variancePence;

  /// `server` or `device` (computed offline from this device's sales).
  final String source;

  int get averageSalePence => salesCount == 0 ? 0 : (netPence / salesCount).round();

  factory ShiftReport.fromServer(Map<String, dynamic> j) {
    final cm = j['cashMovements'] is Map ? Map<String, dynamic>.from(j['cashMovements'] as Map) : <String, dynamic>{};
    final refunds = j['refunds'] is Map ? Map<String, dynamic>.from(j['refunds'] as Map) : <String, dynamic>{};
    final voids = j['voids'] is Map ? Map<String, dynamic>.from(j['voids'] as Map) : <String, dynamic>{};
    return ShiftReport(
      type: '${j['type'] ?? 'X'}',
      openedAt: DateTime.tryParse('${j['openedAt']}')?.toLocal() ?? DateTime.now(),
      closedAt: j['closedAt'] != null ? DateTime.tryParse('${j['closedAt']}')?.toLocal() : null,
      generatedAt: DateTime.tryParse('${j['generatedAt']}')?.toLocal() ?? DateTime.now(),
      openingFloatPence: toPence(j['openingFloat'] as num?),
      salesCount: (j['salesCount'] as num?)?.toInt() ?? 0,
      grossPence: toPence(j['grossSales'] as num?),
      discountsPence: toPence(j['discounts'] as num?),
      taxPence: toPence(j['tax'] as num?),
      netPence: toPence(j['netSales'] as num?),
      tipsPence: toPence(j['tips'] as num?),
      refundCount: (refunds['count'] as num?)?.toInt() ?? 0,
      refundPence: toPence(refunds['amount'] as num?),
      voidCount: (voids['count'] as num?)?.toInt() ?? 0,
      voidPence: toPence(voids['amount'] as num?),
      payments: ((j['payments'] as List?) ?? []).map((p) {
        final m = Map<String, dynamic>.from(p as Map);
        return PaymentBreakdown(
          method: '${m['method']}',
          provider: m['provider'] as String?,
          count: (m['count'] as num?)?.toInt() ?? 0,
          takenPence: toPence(m['taken'] as num?),
          refundedPence: toPence(m['refunded'] as num?),
        );
      }).toList(),
      paidInPence: toPence(cm['paidIn'] as num?),
      paidOutPence: toPence(cm['paidOut'] as num?),
      dropsPence: toPence(cm['drops'] as num?),
      noSales: (cm['noSales'] as num?)?.toInt() ?? 0,
      categories: ((j['categories'] as List?) ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .map((c) => NamedAmount('${c['category']}', (c['quantity'] as num?)?.toInt() ?? 0, toPence(c['amount'] as num?)))
          .toList(),
      staff: ((j['staff'] as List?) ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .map((c) => NamedAmount('${c['name']}', (c['count'] as num?)?.toInt() ?? 0, toPence(c['amount'] as num?)))
          .toList(),
      expectedCashPence: toPence(j['expectedCash'] as num?),
      countedCashPence: j['countedCash'] == null ? null : toPence(j['countedCash'] as num),
      variancePence: j['cashVariance'] == null ? null : toPence(j['cashVariance'] as num),
    );
  }
}
