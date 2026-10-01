import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ScanSource { keyboardWedge, camera, manual }

class ScanEvent {
  const ScanEvent(this.code, this.source);
  final String code;
  final ScanSource source;
}

/// Broadcasts barcode scans from USB/Bluetooth HID scanners and the camera.
///
/// HID "keyboard wedge" scanners type the code very quickly and finish with
/// Enter. Keys arriving less than [_maxGap] apart are buffered; Enter after at
/// least [_minLength] fast characters counts as a scan. When a text field has
/// focus the keys are left for the field (the field handles its own submit).
class ScanBus {
  ScanBus() {
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static const _maxGap = Duration(milliseconds: 60);
  static const _minLength = 4;

  final _controller = StreamController<ScanEvent>.broadcast();
  final _buffer = StringBuffer();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

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

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final now = DateTime.now();
    if (now.difference(_last) > _maxGap) _buffer.clear();
    _last = now;
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString();
      _buffer.clear();
      if (code.length >= _minLength && !_textFieldFocused()) {
        emit(code, ScanSource.keyboardWedge);
        return true;
      }
      return false;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32) _buffer.write(ch);
    return false;
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _controller.close();
  }
}

final scanBusProvider = Provider<ScanBus>((ref) {
  final bus = ScanBus();
  ref.onDispose(bus.dispose);
  return bus;
});
