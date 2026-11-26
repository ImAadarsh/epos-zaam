import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// HTML5 Audio — avoids audioplayers' MissingPluginException on Flutter web.
web.HTMLAudioElement? _audio;

Future<void> prepareClick() async {
  final a = web.HTMLAudioElement();
  a.src = 'assets/assets/sounds/click.wav';
  a.preload = 'auto';
  a.volume = 0.55;
  // Prime decode without playing (some browsers need a user gesture later).
  try {
    a.load();
  } catch (_) {}
  _audio = a;
}

Future<void> playClick() async {
  final a = _audio;
  if (a == null) return;
  try {
    a.currentTime = 0;
    // HTMLAudioElement.play() returns a JSPromise — ignore autoplay rejections.
    await a.play().toDart;
  } catch (_) {}
}
