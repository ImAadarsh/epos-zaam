import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Short, human-friendly device tag derived from the device id (e.g. `7F3A`).
String deviceTag(String deviceId) => deviceId.replaceAll('-', '').substring(0, 4).toUpperCase();
