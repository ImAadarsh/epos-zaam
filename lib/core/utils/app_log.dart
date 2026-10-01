import 'package:flutter/foundation.dart';

/// Small in-memory ring buffer of log lines, attached to "Send Debug Data".
class AppLog {
  static final List<String> _lines = [];
  static const int _max = 400;

  static void info(String message) => _add('I', message);
  static void warn(String message) => _add('W', message);
  static void error(String message, [Object? error]) => _add('E', error == null ? message : '$message: $error');

  static void _add(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} [$level] $message';
    _lines.add(line);
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
    if (kDebugMode) debugPrint(line);
  }

  static List<String> get lines => List.unmodifiable(_lines);
}
