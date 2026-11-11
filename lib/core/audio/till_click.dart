import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Audible keypad "tip" for till buttons. [SystemSoundType.click] is silent on
/// Flutter web / Chrome, so we play a short bundled WAV via audioplayers.
class TillClick {
  TillClick._();

  static final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  static bool _ready = false;

  static Future<void> _ensure() async {
    if (_ready) return;
    try {
      await _player.setSource(AssetSource('sounds/click.wav'));
      await _player.setVolume(0.55);
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
          await _player.seek(Duration.zero);
          await _player.resume();
          return;
        }
      } catch (_) {}
      SystemSound.play(SystemSoundType.click);
    }();
  }
}
