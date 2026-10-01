import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/session.dart';
import '../config/app_config.dart';

/// Whether the Zaam API is reachable, probed via `GET /health`.
class ConnectivityController extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.watch(sessionProvider.select((s) => s.baseUrl));
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.connectivityInterval, (_) => check());
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(check);
    return true;
  }

  Future<bool> check() async {
    final ok = await ref.read(apiClientProvider).ping();
    if (ok != state) state = ok;
    return ok;
  }

  /// Called when a request fails with a network error, so the UI flips to offline at once.
  void markOffline() {
    if (state) state = false;
  }
}

final onlineProvider = NotifierProvider<ConnectivityController, bool>(ConnectivityController.new);
