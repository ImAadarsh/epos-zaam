import 'package:audioplayers/audioplayers.dart';

AudioPlayer? _player;

Future<void> prepareClick() async {
  _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  await _player!.setSource(AssetSource('sounds/click.wav'));
  await _player!.setVolume(0.55);
}

Future<void> playClick() async {
  final p = _player;
  if (p == null) return;
  await p.seek(Duration.zero);
  await p.resume();
}
