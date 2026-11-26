import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'till_click_stub.dart' if (dart.library.js_interop) 'till_click_web.dart' as platform;

/// Audible keypad "tip" for till buttons. [SystemSoundType.click] is silent on
/// Flutter web / Chrome, so web uses an HTML Audio element; native uses a WAV.
class TillClick {
  TillClick._();

  static bool _ready = false;

  static Future<void> _ensure() async {
    if (_ready) return;
    try {
      await platform.prepareClick();
      _ready = true;
    } catch (_) {
      // Fall through to SystemSound on platforms without the asset / plugin.
    }
  }

  /// Fire-and-forget click. Safe to call from every numpad / action press.
  static void play() {
    HapticFeedback.selectionClick();
    () async {
      try {
        await _ensure();
        if (_ready) {
          await platform.playClick();
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[TillClick] $e');
        }
      }
      SystemSound.play(SystemSoundType.click);
    }();
  }
}
