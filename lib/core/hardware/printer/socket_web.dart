import 'dart:typed_data';

const bool rawSocketSupported = false;

Future<void> sendRaw(String host, int port, Uint8List bytes) async {
  throw UnsupportedError('Browsers cannot open raw printer sockets. Use "System print dialog" on the web.');
}
