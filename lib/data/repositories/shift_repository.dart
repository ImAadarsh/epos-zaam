import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/money.dart';
import '../models/outbox.dart';
import '../models/sale.dart';
import '../models/shift.dart';
import 'bootstrap_repository.dart';
import 'initial_data.dart';
import 'outbox_repository.dart';
import 'sales_repository.dart';
import 'session.dart';

/// A cash movement or refund made on this device during the current shift,
/// kept so the X-read works offline.
class ShiftEvent {
  const ShiftEvent({required this.type, required this.amountPence, this.method, this.reason, required this.at});

  final String type; // paid_in | paid_out | drop | no_sale | refund
  final int amountPence;
  final String? method;
  final String? reason;
  final DateTime at;

  Map<String, dynamic> toJson() => {'type': type, 'amountPence': amountPence, 'method': method, 'reason': reason, 'at': at.toIso8601String()};

  factory ShiftEvent.fromJson(Map<String, dynamic> j) => ShiftEvent(
        type: '${j['type']}',
        amountPence: (j['amountPence'] as num?)?.toInt() ?? 0,
        method: j['method'] as String?,
        reason: j['reason'] as String?,
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
      );
}

class ShiftController extends Notifier<ShiftState?> {
  List<ShiftEvent> _events = [];

  @override
  ShiftState? build() {
    final j = ref.read(initialDataProvider).shift;
    Future.microtask(_loadEvents);
    if (j == null || j['clientId'] == null) return null;
    final s = ShiftState.fromJson(j);
    return s.isOpen ? s : null;
  }

  LocalDb get _db => ref.read(localDbProvider);

  Future<void> _loadEvents() async {
    final j = await _db.getKv('shift_events');
    _events = ((j?['events'] as List?) ?? []).map((e) => ShiftEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> _saveEvents() => _db.putKv('shift_events', {'events': _events.map((e) => e.toJson()).toList()});

  Future<void> _persist() async {
    if (state == null) {
      await _db.deleteKv('shift');
    } else {
      await _db.putKv('shift', state!.toJson());
    }
  }

  /// Suggested float for the next open (set when "Enter float after closing register" is on).
  Future<int?> suggestedFloat() async => ((await _db.getKv('next_float'))?['pence'] as num?)?.toInt();

  Future<ShiftState> open(int floatPence) async {
    final session = ref.read(sessionProvider);
    final registerId = session.registerId!;
    final shift = ShiftState(
      clientId: newId(),
      registerId: registerId,
      openedAt: DateTime.now(),
      openingFloatPence: floatPence,
      openedBy: session.staffId,
    );
    state = shift;
    _events = [];
    await _saveEvents();
    await _persist();
    await ref.read(outboxProvider.notifier).enqueue(
      OutboxType.shiftOpen,
      {'registerId': registerId, 'openingFloat': fromPence(floatPence), 'clientId': shift.clientId, 'openedAt': shift.openedAt.toUtc().toIso8601String()},
      summary: 'Float ${formatPence(floatPence)}',
      amountPence: floatPence,
    );
    AppLog.info('Register opened with float ${formatPence(floatPence)}');
    return shift;
  }

  Future<void> onServerId(String clientId, String serverId) async {
    if (state?.clientId == clientId) {
      state = state!.copyWith(serverId: serverId);
      await _persist();
    }
  }

  /// Adopts a register opened on another device (or after a reset) when nothing is pending locally.
  Future<void> reconcile() async {
    final session = ref.read(sessionProvider);
    if (!session.isLoggedIn || session.registerId == null) return;
    final outbox = ref.read(outboxProvider);
    if (outbox.entries.any((e) => e.type == OutboxType.shiftOpen || e.type == OutboxType.shiftClose)) return;
    try {
      final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/shifts/current', query: {'registerId': session.registerId}) as Map);
      final remote = res['shift'] is Map ? Map<String, dynamic>.from(res['shift'] as Map) : null;
      if (remote == null) {
        if (state?.serverId != null) {
          state = null;
          await _persist();
        }
        return;
      }
      final serverId = '${remote['id']}';
      if (state?.serverId == serverId) return;
      final clientId = (remote['clientId'] as String?) ?? 'server-$serverId';
      state = ShiftState(
        clientId: clientId,
        serverId: serverId,
        registerId: session.registerId!,
        openedAt: DateTime.tryParse('${remote['openedAt']}')?.toLocal() ?? DateTime.now(),
        openingFloatPence: toPence(remote['openingFloat'] as num?),
        openedBy: remote['openedBy']?.toString(),
      );
      await ref.read(outboxProvider.notifier).rememberShiftId(clientId, serverId);
      await _persist();
    } catch (e) {
      AppLog.warn('Shift reconcile failed: $e');
    }
  }

  Future<void> cashMovement(String type, int amountPence, String? reason) async {
    final shift = state;
    if (shift == null) return;
    _events.add(ShiftEvent(type: type, amountPence: amountPence, reason: reason, at: DateTime.now()));
    await _saveEvents();
    await ref.read(outboxProvider.notifier).enqueue(
      OutboxType.cashMovement,
      {
        'shiftId': shift.serverId,
        'shiftClientId': shift.clientId,
        'type': type,
        'amount': fromPence(amountPence),
        'reason': reason,
        'clientId': newId(),
      },
      summary: type.replaceAll('_', ' '),
      amountPence: amountPence,
    );
  }

  Future<void> recordRefund(String method, int amountPence) async {
    _events.add(ShiftEvent(type: 'refund', amountPence: amountPence, method: method, at: DateTime.now()));
    await _saveEvents();
  }

  /// X-read: server figures when online and synced, otherwise computed from this device.
  Future<ShiftReport?> report() async {
    final shift = state;
    if (shift == null) return null;
    final online = ref.read(onlineProvider);
    if (online) {
      await ref.read(outboxProvider.notifier).flush();
      final serverId = shift.serverId ?? ref.read(outboxProvider.notifier).serverShiftId(shift.clientId);
      if (serverId != null) {
        try {
          final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/shifts/$serverId/report') as Map);
          return ShiftReport.fromServer(res);
        } catch (e) {
          AppLog.warn('Server X-read failed, using device figures: $e');
        }
      }
    }
    return _localReport(shift);
  }

  ShiftReport _localReport(ShiftState shift, {int? countedPence}) {
    final sales = ref.read(localSalesProvider).where((s) => s.shiftClientId == shift.clientId).toList();
    final live = sales.where((s) => s.status != 'voided').toList();
    final voided = sales.where((s) => s.status == 'voided').toList();
    final payments = <String, PaymentBreakdown>{};
    for (final s in live) {
      for (final p in s.payments.where((p) => !p.isRefund)) {
        final prev = payments[p.method.name];
        payments[p.method.name] = PaymentBreakdown(
          method: p.method.name,
          count: (prev?.count ?? 0) + 1,
          takenPence: (prev?.takenPence ?? 0) + p.amountPence,
          refundedPence: prev?.refundedPence ?? 0,
        );
      }
    }
    var refundTotal = 0;
    var refundCount = 0;
    for (final e in _events.where((e) => e.type == 'refund')) {
      refundTotal += e.amountPence;
      refundCount++;
      final key = e.method ?? 'cash';
      final prev = payments[key];
      payments[key] = PaymentBreakdown(
        method: key,
        count: (prev?.count ?? 0) + 1,
        takenPence: prev?.takenPence ?? 0,
        refundedPence: (prev?.refundedPence ?? 0) - e.amountPence,
      );
    }
    int sumEvents(String type) => _events.where((e) => e.type == type).fold(0, (a, e) => a + e.amountPence);
    final cash = payments['cash'];
    final expected = shift.openingFloatPence + (cash?.netPence ?? 0) + sumEvents('paid_in') - sumEvents('paid_out') - sumEvents('drop');

    final categories = <String, NamedAmount>{};
    final staff = <String, NamedAmount>{};
    for (final s in live) {
      for (final l in s.lines) {
        final c = l.category ?? 'Uncategorised';
        final prev = categories[c];
        categories[c] = NamedAmount(c, (prev?.count ?? 0) + l.quantity, (prev?.amountPence ?? 0) + l.totalPence);
      }
      final name = s.staffName ?? 'Unknown';
      final prev = staff[name];
      staff[name] = NamedAmount(name, (prev?.count ?? 0) + 1, (prev?.amountPence ?? 0) + s.totalPence);
    }

    return ShiftReport(
      type: shift.isOpen ? 'X' : 'Z',
      openedAt: shift.openedAt,
      generatedAt: DateTime.now(),
      openingFloatPence: shift.openingFloatPence,
      salesCount: live.length,
      grossPence: live.fold(0, (a, s) => a + s.subtotalPence),
      discountsPence: live.fold(0, (a, s) => a + s.discountPence),
      taxPence: live.fold(0, (a, s) => a + s.taxPence),
      netPence: live.fold(0, (a, s) => a + s.totalPence),
      tipsPence: live.fold(0, (a, s) => a + s.tipPence),
      refundCount: refundCount,
      refundPence: refundTotal,
      voidCount: voided.length,
      voidPence: voided.fold(0, (a, s) => a + s.totalPence),
      payments: payments.values.toList(),
      paidInPence: sumEvents('paid_in'),
      paidOutPence: sumEvents('paid_out'),
      dropsPence: sumEvents('drop'),
      noSales: _events.where((e) => e.type == 'no_sale').length,
      categories: categories.values.toList()..sort((a, b) => b.amountPence.compareTo(a.amountPence)),
      staff: staff.values.toList(),
      expectedCashPence: expected,
      countedCashPence: countedPence,
      variancePence: countedPence == null ? null : countedPence - expected,
      source: 'device',
    );
  }

  /// Z-read: closes the register with the counted cash and queues the close for the server.
  Future<ShiftReport?> close({required int countedPence, Map<String, int>? denominations, String? notes, int? nextFloatPence}) async {
    final shift = state;
    if (shift == null) return null;
    final x = await report();
    final expected = x?.expectedCashPence ?? 0;
    final z = x == null
        ? null
        : ShiftReport(
            type: 'Z',
            openedAt: x.openedAt,
            closedAt: DateTime.now(),
            generatedAt: DateTime.now(),
            openingFloatPence: x.openingFloatPence,
            salesCount: x.salesCount,
            grossPence: x.grossPence,
            discountsPence: x.discountsPence,
            taxPence: x.taxPence,
            netPence: x.netPence,
            tipsPence: x.tipsPence,
            refundCount: x.refundCount,
            refundPence: x.refundPence,
            voidCount: x.voidCount,
            voidPence: x.voidPence,
            payments: x.payments,
            paidInPence: x.paidInPence,
            paidOutPence: x.paidOutPence,
            dropsPence: x.dropsPence,
            noSales: x.noSales,
            categories: x.categories,
            staff: x.staff,
            expectedCashPence: expected,
            countedCashPence: countedPence,
            variancePence: countedPence - expected,
            source: x.source,
          );
    await ref.read(outboxProvider.notifier).enqueue(
      OutboxType.shiftClose,
      {
        'shiftId': shift.serverId,
        'shiftClientId': shift.clientId,
        'countedCash': fromPence(countedPence),
        'denominations': denominations?.map((k, v) => MapEntry(k, v)),
        'notes': notes,
        'nextFloat': nextFloatPence == null ? null : fromPence(nextFloatPence),
        'closedAt': DateTime.now().toUtc().toIso8601String(),
      },
      summary: 'Counted ${formatPence(countedPence)}',
      amountPence: countedPence,
    );
    if (nextFloatPence != null) {
      await _db.putKv('next_float', {'pence': nextFloatPence});
    } else {
      await _db.deleteKv('next_float');
    }
    state = null;
    _events = [];
    await _saveEvents();
    await _persist();
    AppLog.info('Register closed. Counted ${formatPence(countedPence)}, expected ${formatPence(expected)}');
    return z;
  }

  /// Staff name for "opened by" lines.
  String? openedByName() => ref.read(bootstrapProvider).staffMember(state?.openedBy)?.name;

  Future<void> clearLocal() async {
    state = null;
    _events = [];
    await _saveEvents();
    await _persist();
  }
}

final shiftProvider = NotifierProvider<ShiftController, ShiftState?>(ShiftController.new);

/// Payment methods helper for reports.
String paymentLabel(String method) => paymentMethodFrom(method).label;
