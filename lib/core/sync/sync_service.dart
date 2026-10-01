import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/clock_repository.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../config/app_config.dart';
import '../utils/app_log.dart';
import 'connectivity.dart';

/// Background sync while signed in: replays the outbox, pulls stock deltas and
/// catalogue changes, and catches up immediately when the connection returns.
class SyncService {
  SyncService(this.ref);

  final Ref ref;
  final List<Timer> _timers = [];
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _timers
      ..add(Timer.periodic(AppConfig.outboxFlushInterval, (_) => _ifOnline(flushOutbox)))
      ..add(Timer.periodic(AppConfig.stockSyncInterval, (_) => _ifOnline(() => ref.read(catalogProvider.notifier).syncStock())))
      ..add(Timer.periodic(AppConfig.catalogSyncInterval, (_) => _ifOnline(() => ref.read(catalogProvider.notifier).sync())));
    ref.listen<bool>(onlineProvider, (prev, online) {
      if (online && prev == false) {
        AppLog.info('Back online, syncing');
        syncNow();
      }
    });
    syncNow();
  }

  Future<void> _ifOnline(Future<void> Function() fn) async {
    if (!ref.read(onlineProvider) || !ref.read(sessionProvider).isLoggedIn) return;
    try {
      await fn();
    } catch (e) {
      AppLog.warn('Background sync: $e');
    }
  }

  Future<void> flushOutbox() => ref.read(outboxProvider.notifier).flush();

  /// Full refresh: pending changes first, then reference data and stock.
  Future<void> syncNow({bool fullCatalog = false}) async {
    if (!ref.read(sessionProvider).isLoggedIn) return;
    final online = await ref.read(onlineProvider.notifier).check();
    if (!online) return;
    await _ifOnline(flushOutbox);
    await _ifOnline(() async {
      await ref.read(bootstrapProvider.notifier).refresh();
      final register = ref.read(currentRegisterProvider);
      if (register != null) await ref.read(settingsProvider.notifier).applyRegisterDefaults(register.id, register.settings);
    });
    await _ifOnline(() => ref.read(catalogProvider.notifier).sync(full: fullCatalog));
    await _ifOnline(() => ref.read(shiftProvider.notifier).reconcile());
    await _ifOnline(() => ref.read(clockProvider.notifier).refresh());
  }

  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _started = false;
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final s = SyncService(ref);
  ref.onDispose(s.stop);
  return s;
});
