import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/local_db.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/ids.dart';
import '../models/outbox.dart';
import 'sales_repository.dart';
import 'session.dart';
import 'shift_repository.dart';

class OutboxState {
  const OutboxState({this.entries = const [], this.flushing = false, this.lastFlush, this.loaded = false});

  final List<OutboxEntry> entries;
  final bool flushing;
  final DateTime? lastFlush;
  final bool loaded;

  int get pendingCount => entries.length;
  int get failedCount => entries.where((e) => e.status == OutboxStatus.failed).length;
  int get unsyncedSales => entries.where((e) => e.type == OutboxType.sale).length;

  OutboxState copyWith({List<OutboxEntry>? entries, bool? flushing, DateTime? lastFlush, bool? loaded}) => OutboxState(
        entries: entries ?? this.entries,
        flushing: flushing ?? this.flushing,
        lastFlush: lastFlush ?? this.lastFlush,
        loaded: loaded ?? this.loaded,
      );
}

/// Durable FIFO queue of changes made on the till. Everything the till does
/// is written here first, so selling never depends on the network.
class OutboxController extends Notifier<OutboxState> {
  int _seq = 0;
  Map<String, String> _shiftIds = {};

  @override
  OutboxState build() {
    Future.microtask(_load);
    return const OutboxState();
  }

  LocalDb get _db => ref.read(localDbProvider);

  Future<void> _load() async {
    final rows = await _db.all(LocalDb.outbox);
    final entries = rows.map(OutboxEntry.fromJson).toList()..sort((a, b) => a.seq.compareTo(b.seq));
    _seq = entries.isEmpty ? 0 : entries.last.seq;
    final ids = await _db.getKv('shift_ids') ?? {};
    _shiftIds = ids.map((k, v) => MapEntry(k, '$v'));
    state = state.copyWith(entries: entries, loaded: true);
  }

  Future<OutboxEntry> enqueue(OutboxType type, Map<String, dynamic> payload, {String? summary, int? amountPence}) async {
    final entry = OutboxEntry(
      id: newId(),
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
      summary: summary,
      amountPence: amountPence,
      seq: ++_seq,
    );
    await _db.put(LocalDb.outbox, entry.id, entry.toJson());
    state = state.copyWith(entries: [...state.entries, entry]);
    Future.microtask(flush);
    return entry;
  }

  /// Server id for a shift opened on this device (known once its open was synced).
  String? serverShiftId(String? shiftClientId) => shiftClientId == null ? null : _shiftIds[shiftClientId];

  Future<void> rememberShiftId(String clientId, String serverId) async {
    _shiftIds[clientId] = serverId;
    await _db.putKv('shift_ids', _shiftIds);
  }

  /// "Fix Sales": retry everything that previously failed.
  Future<void> retryFailed() async {
    final next = <OutboxEntry>[];
    for (final e in state.entries) {
      final reset = e.status == OutboxStatus.failed ? e.copyWith(status: OutboxStatus.pending, attempts: 0, clearError: true) : e;
      next.add(reset);
      if (reset != e) await _db.put(LocalDb.outbox, reset.id, reset.toJson());
    }
    state = state.copyWith(entries: next);
    await flush();
  }

  Future<void> discard(String id) async {
    await _db.delete(LocalDb.outbox, id);
    state = state.copyWith(entries: state.entries.where((e) => e.id != id).toList());
  }

  Future<void> flush() async {
    if (state.flushing || !state.loaded) return;
    if (!ref.read(sessionProvider).isLoggedIn) return;
    final pending = state.entries.where((e) => e.status == OutboxStatus.pending).toList();
    if (pending.isEmpty) return;
    state = state.copyWith(flushing: true);
    try {
      for (final entry in pending) {
        try {
          await _send(entry);
          await _db.delete(LocalDb.outbox, entry.id);
          state = state.copyWith(entries: state.entries.where((e) => e.id != entry.id).toList());
        } on ApiException catch (e) {
          if (e.isNetwork) {
            ref.read(onlineProvider.notifier).markOffline();
            break;
          }
          final attempts = entry.attempts + 1;
          final failed = e.isPermanent || attempts >= 5;
          await _update(entry.copyWith(attempts: attempts, status: failed ? OutboxStatus.failed : OutboxStatus.pending, lastError: e.message));
          AppLog.warn('Outbox ${entry.type.name} ${entry.summary ?? ''} failed: ${e.message}');
          if (!failed) break;
        } catch (e) {
          await _update(entry.copyWith(attempts: entry.attempts + 1, status: OutboxStatus.failed, lastError: e.toString()));
          AppLog.error('Outbox ${entry.type.name} crashed', e);
        }
      }
    } finally {
      state = state.copyWith(flushing: false, lastFlush: DateTime.now());
    }
  }

  Future<void> _update(OutboxEntry entry) async {
    await _db.put(LocalDb.outbox, entry.id, entry.toJson());
    state = state.copyWith(entries: state.entries.map((e) => e.id == entry.id ? entry : e).toList());
  }

  String _requireShift(Map<String, dynamic> p) {
    final id = p['shiftId']?.toString() ?? serverShiftId(p['shiftClientId'] as String?);
    if (id == null) throw ApiException('Register open has not synced yet', statusCode: 409);
    return id;
  }

  Future<void> _send(OutboxEntry entry) async {
    final api = ref.read(apiClientProvider);
    final p = Map<String, dynamic>.from(entry.payload);
    switch (entry.type) {
      case OutboxType.shiftOpen:
        final res = Map<String, dynamic>.from(await api.post('/api/pos/shifts/open', data: p) as Map);
        final clientId = '${p['clientId']}';
        final serverId = '${res['id']}';
        await rememberShiftId(clientId, serverId);
        await ref.read(shiftProvider.notifier).onServerId(clientId, serverId);
      case OutboxType.sale:
        p['shiftId'] ??= serverShiftId(p['shiftClientId'] as String?);
        final res = Map<String, dynamic>.from(await api.post('/api/pos/sales', data: p) as Map);
        final sale = Map<String, dynamic>.from((res['sale'] as Map?) ?? {});
        await ref.read(localSalesProvider.notifier).markSynced('${p['clientId']}', sale['id']?.toString(), sale['orderNumber'] as String?);
      case OutboxType.refund:
        final code = Uri.encodeComponent('${p.remove('saleCode')}');
        p['shiftId'] ??= serverShiftId(p['shiftClientId'] as String?);
        await api.post('/api/pos/sales/$code/refund', data: p);
      case OutboxType.voidSale:
        final code = Uri.encodeComponent('${p.remove('saleCode')}');
        await api.post('/api/pos/sales/$code/void', data: p);
      case OutboxType.cashMovement:
        final shiftId = _requireShift(p);
        await api.post('/api/pos/shifts/$shiftId/cash-movements', data: p);
      case OutboxType.shiftClose:
        final shiftId = _requireShift(p);
        await api.post('/api/pos/shifts/$shiftId/close', data: p);
      case OutboxType.clock:
        await api.post('/api/pos/clock', data: p);
      case OutboxType.availability:
        await api.put('/api/pos/availability', data: p);
      case OutboxType.emailReceipt:
        final code = Uri.encodeComponent('${p.remove('saleCode')}');
        await api.post('/api/pos/sales/$code/email-receipt', data: p);
    }
  }

  Future<void> clear() async {
    await _db.replaceAll(LocalDb.outbox, {});
    state = const OutboxState(loaded: true);
  }
}

final outboxProvider = NotifierProvider<OutboxController, OutboxState>(OutboxController.new);
