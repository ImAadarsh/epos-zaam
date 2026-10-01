import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/ids.dart';
import '../models/outbox.dart';
import 'outbox_repository.dart';
import 'session.dart';

/// Staff member id → time they clocked in (only for those currently clocked in).
class ClockController extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    Future.microtask(_load);
    return const {};
  }

  LocalDb get _db => ref.read(localDbProvider);

  Future<void> _load() async {
    final j = await _db.getKv('clock') ?? {};
    state = j.map((k, v) => MapEntry(k, DateTime.tryParse('$v') ?? DateTime.now()));
  }

  Future<void> _save() => _db.putKv('clock', state.map((k, v) => MapEntry(k, v.toIso8601String())));

  Future<void> refresh() async {
    try {
      final rows = (await ref.read(apiClientProvider).get('/api/pos/clock') as List).map((e) => Map<String, dynamic>.from(e as Map));
      final open = <String, DateTime>{};
      for (final r in rows) {
        if (r['clockOut'] == null) open['${r['userId']}'] = DateTime.tryParse('${r['clockIn']}')?.toLocal() ?? DateTime.now();
      }
      final pending = ref.read(outboxProvider).entries.where((e) => e.type == OutboxType.clock);
      if (pending.isEmpty) {
        state = open;
        await _save();
      }
    } catch (e) {
      AppLog.warn('Clock refresh failed: $e');
    }
  }

  Future<void> toggle(String userId) async {
    final clockingIn = !state.containsKey(userId);
    final now = DateTime.now();
    state = clockingIn ? {...state, userId: now} : (Map.of(state)..remove(userId));
    await _save();
    await ref.read(outboxProvider.notifier).enqueue(
      OutboxType.clock,
      {
        'userId': userId,
        'action': clockingIn ? 'in' : 'out',
        'registerId': ref.read(sessionProvider).registerId,
        'clientId': newId(),
        'at': now.toUtc().toIso8601String(),
      },
      summary: clockingIn ? 'Clock in' : 'Clock out',
    );
  }
}

final clockProvider = NotifierProvider<ClockController, Map<String, DateTime>>(ClockController.new);
