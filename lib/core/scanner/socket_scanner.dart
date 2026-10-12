import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../utils/app_log.dart';
import 'scan_bus.dart';
import 'socket_capture_stub.dart' if (dart.library.js_interop) 'socket_capture_web.dart';

export 'socket_capture_stub.dart' if (dart.library.js_interop) 'socket_capture_web.dart' show socketCaptureAvailable;

enum SocketScannerState { off, loading, waiting, connected, disconnected, noService, error }

class SocketScannerStatus {
  const SocketScannerStatus(this.state, [this.detail = '', this.lastScan]);
  final SocketScannerState state;
  final String detail;
  final String? lastScan;

  String get label => switch (state) {
        SocketScannerState.off => detail.isEmpty ? 'Off (Basic/HID mode works without this)' : 'Not connected: $detail',
        SocketScannerState.loading => 'Starting…',
        SocketScannerState.waiting => 'Ready. Turn the scanner on to connect',
        SocketScannerState.connected => 'Connected${detail.isEmpty ? '' : ': $detail'}',
        SocketScannerState.disconnected => 'Scanner disconnected${detail.isEmpty ? '' : ': $detail'}',
        SocketScannerState.noService => 'Socket Mobile Companion is not running on this device',
        SocketScannerState.error => detail.isEmpty ? 'Error' : detail,
      };
}

/// Socket Mobile scanners in Application mode: decoded data goes straight into [ScanBus],
/// regardless of which field has focus. Follows the CaptureJS settings.
class SocketScannerController extends Notifier<SocketScannerStatus> {
  String? _activeKey;

  @override
  SocketScannerStatus build() {
    ref.onDispose(socketCaptureStop);
    ref.listen(settingsProvider, (_, _) => _apply(), fireImmediately: false);
    Future.microtask(_apply);
    return const SocketScannerStatus(SocketScannerState.off);
  }

  void _apply() {
    final s = ref.read(settingsProvider);
    final ready = s.socketCaptureEnabled && s.socketAppId.trim().isNotEmpty && s.socketDeveloperId.trim().isNotEmpty && s.socketAppKey.trim().isNotEmpty;
    final key = ready ? '${s.socketAppId}|${s.socketDeveloperId}|${s.socketAppKey}' : null;
    if (key == _activeKey) return;
    _activeKey = key;
    socketCaptureStop();
    if (key == null) {
      state = SocketScannerStatus(
        SocketScannerState.off,
        s.socketCaptureEnabled ? 'enter the Developer ID and AppKey from the Socket Mobile developer portal (see Setup guide)' : '',
      );
      return;
    }
    socketCaptureStart(
      appId: s.socketAppId.trim(),
      developerId: s.socketDeveloperId.trim(),
      appKey: s.socketAppKey.trim(),
      onScan: (code, symbology) {
        AppLog.info('Socket Mobile scan ($symbology)');
        state = SocketScannerStatus(state.state, state.detail, code);
        ref.read(scanBusProvider).emit(code, ScanSource.socketMobile);
      },
      onStatus: (raw, detail) {
        final st = switch (raw) {
          'loading' => SocketScannerState.loading,
          'waiting' => SocketScannerState.waiting,
          'connected' => SocketScannerState.connected,
          'disconnected' => SocketScannerState.disconnected,
          'no-service' => SocketScannerState.noService,
          _ => SocketScannerState.error,
        };
        if (st == SocketScannerState.error) AppLog.warn('Socket Mobile: $detail');
        state = SocketScannerStatus(st, detail, state.lastScan);
      },
    );
  }

  /// Reconnects with the current settings (e.g. after starting Companion).
  void retry() {
    _activeKey = null;
    _apply();
  }
}

final socketScannerProvider = NotifierProvider<SocketScannerController, SocketScannerStatus>(SocketScannerController.new);
