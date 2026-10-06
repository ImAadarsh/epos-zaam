import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ScanSource { keyboardWedge, socketMobile, camera, manual }

class ScanEvent {
  const ScanEvent(this.code, this.source);
  final String code;
  final ScanSource source;
}

/// Broadcasts barcode scans from USB/Bluetooth HID scanners and the camera.
///
/// HID "keyboard wedge" scanners (USB, or Bluetooth such as Socket Mobile S700
/// in Basic mode) type the code very quickly, usually ending with Enter.
/// Keys arriving less than [_maxGap] apart are buffered (Bluetooth adds jitter);
/// a burst counts as a scan when its average key gap is at most [_maxAvgGap]
/// (faster than any person types) and it ends with Enter, or, for scanners set
/// up without a suffix, goes quiet for [_flushAfter] with at least
/// [_minLengthNoSuffix] characters. When a text field has focus the keys are
/// left for the field (the field handles its own submit).
class ScanBus {
  ScanBus() {
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static const _maxGap = Duration(milliseconds: 120);
  static const _maxAvgGapMs = 45;
  static const _minLength = 4;
  static const _minLengthNoSuffix = 6;
  static const _flushAfter = Duration(milliseconds: 200);

  final _controller = StreamController<ScanEvent>.broadcast();
  final _buffer = StringBuffer();
  DateTime _first = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _flush;

  Stream<ScanEvent> get stream => _controller.stream;

  void emit(String code, ScanSource source) {
    final c = code.trim();
    if (c.isNotEmpty) _controller.add(ScanEvent(c, source));
  }

  bool _textFieldFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool get _machineSpeed {
    final n = _buffer.length;
    if (n < 2) return true;
    return _last.difference(_first).inMilliseconds / (n - 1) <= _maxAvgGapMs;
  }

  void _flushNoSuffix() {
    final code = _buffer.toString();
    if (code.length >= _minLengthNoSuffix && _machineSpeed && !_textFieldFocused()) emit(code, ScanSource.keyboardWedge);
    _buffer.clear();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final now = DateTime.now();
    if (now.difference(_last) > _maxGap) _buffer.clear();
    _last = now;
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _flush?.cancel();
      final code = _buffer.toString();
      final fast = _machineSpeed;
      _buffer.clear();
      if (code.length >= _minLength && fast && !_textFieldFocused()) {
        emit(code, ScanSource.keyboardWedge);
        return true;
      }
      return false;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32) {
      if (_buffer.isEmpty) _first = now;
      _buffer.write(ch);
      _flush?.cancel();
      _flush = Timer(_flushAfter, _flushNoSuffix);
    }
    return false;
  }

  void dispose() {
    _flush?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _controller.close();
  }
}

final scanBusProvider = Provider<ScanBus>((ref) {
  final bus = ScanBus();
  ref.onDispose(bus.dispose);
  return bus;
});
