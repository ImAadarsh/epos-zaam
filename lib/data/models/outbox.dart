/// Kinds of change the till queues while offline, replayed in order.
enum OutboxType { shiftOpen, sale, refund, voidSale, cashMovement, shiftClose, clock, availability, emailReceipt }

extension OutboxTypeX on OutboxType {
  String get label => switch (this) {
        OutboxType.shiftOpen => 'Open register',
        OutboxType.sale => 'Sale',
        OutboxType.refund => 'Refund',
        OutboxType.voidSale => 'Void',
        OutboxType.cashMovement => 'Cash movement',
        OutboxType.shiftClose => 'Close register',
        OutboxType.clock => 'Clock in/out',
        OutboxType.availability => 'Availability',
        OutboxType.emailReceipt => 'Email receipt',
      };
}

enum OutboxStatus { pending, failed }

class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.status = OutboxStatus.pending,
    this.lastError,
    this.summary,
    this.amountPence,
    this.seq = 0,
  });

  final String id;
  final OutboxType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final OutboxStatus status;
  final String? lastError;
  final String? summary;
  final int? amountPence;

  /// Monotonic order so entries replay in the order they happened.
  final int seq;

  OutboxEntry copyWith({int? attempts, OutboxStatus? status, String? lastError, bool clearError = false, Map<String, dynamic>? payload}) => OutboxEntry(
        id: id,
        type: type,
        payload: payload ?? this.payload,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        status: status ?? this.status,
        lastError: clearError ? null : (lastError ?? this.lastError),
        summary: summary,
        amountPence: amountPence,
        seq: seq,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        'status': status.name,
        'lastError': lastError,
        'summary': summary,
        'amountPence': amountPence,
        'seq': seq,
      };

  factory OutboxEntry.fromJson(Map<String, dynamic> j) => OutboxEntry(
        id: '${j['id']}',
        type: OutboxType.values.firstWhere((t) => t.name == j['type'], orElse: () => OutboxType.sale),
        payload: Map<String, dynamic>.from((j['payload'] as Map?) ?? {}),
        createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        status: j['status'] == 'failed' ? OutboxStatus.failed : OutboxStatus.pending,
        lastError: j['lastError'] as String?,
        summary: j['summary'] as String?,
        amountPence: (j['amountPence'] as num?)?.toInt(),
        seq: (j['seq'] as num?)?.toInt() ?? 0,
      );
}
