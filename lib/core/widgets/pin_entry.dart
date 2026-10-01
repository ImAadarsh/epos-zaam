import 'package:flutter/material.dart';

import 'keypad.dart';

/// Masked PIN dots plus keypad. Calls [onSubmit] when [length] digits are entered
/// or Enter is pressed (for 4–8 digit PINs).
class PinEntry extends StatefulWidget {
  const PinEntry({super.key, required this.onSubmit, this.maxLength = 8, this.autoSubmitLength, this.error});

  final Future<bool> Function(String pin) onSubmit;
  final int maxLength;

  /// Submit automatically once this many digits are typed.
  final int? autoSubmitLength;
  final String? error;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  String _pin = '';
  bool _busy = false;
  bool _shake = false;

  Future<void> _submit() async {
    if (_pin.length < 4 || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.onSubmit(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _shake = !ok;
    });
  }

  void _digit(String d) {
    if (_pin.length >= widget.maxLength) return;
    setState(() {
      _pin += d;
      _shake = false;
    });
    if (widget.autoSubmitLength != null && _pin.length == widget.autoSubmitLength) _submit();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? (_shake ? scheme.error : scheme.primary) : Colors.transparent,
                    border: Border.all(color: _shake ? scheme.error : scheme.outline, width: 2),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 28,
          child: Center(
            child: _shake
                ? Text(widget.error ?? 'PIN not recognised', style: TextStyle(color: scheme.error))
                : _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
          ),
        ),
        Keypad(
          onDigit: _digit,
          onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
          onEnter: _submit,
        ),
      ],
    );
  }
}
