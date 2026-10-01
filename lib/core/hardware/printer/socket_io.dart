import 'dart:io';
import 'dart:typed_data';

const bool rawSocketSupported = true;

/// Sends raw bytes to a LAN printer (port 9100 "JetDirect"/raw).
Future<void> sendRaw(String host, int port, Uint8List bytes) async {
  final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
  try {
    socket.add(bytes);
    await socket.flush();
  } finally {
    await socket.close();
    socket.destroy();
  }
}
