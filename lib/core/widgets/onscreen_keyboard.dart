import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen on-screen QWERTY for touch tills (Pay Out reason, etc.).
/// Returns trimmed text, or null if cancelled.
Future<String?> promptTextWithKeyboard(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? initial,
  String? hint,
  String confirmLabel = 'Done',
  bool allowEmpty = false,
  int maxLength = 120,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _OnScreenKeyboardDialog(
      title: title,
      subtitle: subtitle,
      initial: initial ?? '',
      hint: hint,
      confirmLabel: confirmLabel,
      allowEmpty: allowEmpty,
      maxLength: maxLength,
    ),
  );
}

class _OnScreenKeyboardDialog extends StatefulWidget {
  const _OnScreenKeyboardDialog({
    required this.title,
    this.subtitle,
    required this.initial,
    this.hint,
    required this.confirmLabel,
    required this.allowEmpty,
    required this.maxLength,
  });

  final String title;
  final String? subtitle;
  final String initial;
  final String? hint;
  final String confirmLabel;
  final bool allowEmpty;
  final int maxLength;

  @override
  State<_OnScreenKeyboardDialog> createState() => _OnScreenKeyboardDialogState();
}

class _OnScreenKeyboardDialogState extends State<_OnScreenKeyboardDialog> {
  late String _text = widget.initial;
  bool _caps = false;
  bool _shift = false;

  bool get _canSubmit => widget.allowEmpty || _text.trim().isNotEmpty;

  void _append(String ch) {
    if (_text.length >= widget.maxLength) return;
    setState(() {
      _text += ch;
      if (_shift) {
        _shift = false;
        _caps = false;
      }
    });
  }

  void _backspace() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.substring(0, _text.length - 1));
  }

  void _clear() => setState(() => _text = '');

  void _space() => _append(' ');

  void _toggleCaps() => setState(() {
        _caps = !_caps;
        _shift = false;
      });

  void _toggleShift() => setState(() {
        _shift = !_shift;
        if (_shift) _caps = true;
      });

  String _case(String lower) {
    final upper = _caps || _shift;
    return upper ? lower.toUpperCase() : lower;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(context, _text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // Use the full till width — tills are touch-first and need every key large.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      backgroundColor: const Color(0xFF1A222D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: size.width,
        height: size.height * 0.96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(widget.subtitle!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1116),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A3340)),
                ),
                child: Text(
                  _text.isEmpty ? (widget.hint ?? 'Type here…') : _text,
                  style: TextStyle(
                    color: _text.isEmpty ? Colors.white38 : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _KeyboardPad(
                  letterCase: _case,
                  caps: _caps,
                  shift: _shift,
                  onKey: _append,
                  onBackspace: _backspace,
                  onClear: _clear,
                  onSpace: _space,
                  onCaps: _toggleCaps,
                  onShift: _toggleShift,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1F8A4C),
                    disabledBackgroundColor: const Color(0xFF2A3340),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _canSubmit ? _submit : null,
                  child: Text(
                    widget.confirmLabel.toUpperCase(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyboardPad extends StatelessWidget {
  const _KeyboardPad({
    required this.letterCase,
    required this.caps,
    required this.shift,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onSpace,
    required this.onCaps,
    required this.onShift,
  });

  final String Function(String) letterCase;
  final bool caps;
  final bool shift;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSpace;
  final VoidCallback onCaps;
  final VoidCallback onShift;

  static const _row1 = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _row2 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _row3 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _row4 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

  @override
  Widget build(BuildContext context) {
    Widget key(
      String label, {
      VoidCallback? onTap,
      int flex = 1,
      Color? color,
      double fontSize = 18,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: color ?? const Color(0xFF2A3544),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap?.call();
              },
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: fontSize),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget letterRow(List<String> letters) {
      return Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in letters) key(letterCase(l), onTap: () => onKey(letterCase(l))),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final n in _row1) key(n, onTap: () => onKey(n)),
              key('BKP', onTap: onBackspace, flex: 2, color: const Color(0xFF3A4A5C), fontSize: 14),
            ],
          ),
        ),
        letterRow(_row2),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              key(caps ? 'CAPS' : 'caps', onTap: onCaps, flex: 2, color: caps ? const Color(0xFF1F8A4C) : const Color(0xFF3A4A5C), fontSize: 13),
              for (final l in _row3) key(letterCase(l), onTap: () => onKey(letterCase(l))),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              key(shift ? 'SHIFT' : 'Shift', onTap: onShift, flex: 2, color: shift ? const Color(0xFF1F8A4C) : const Color(0xFF3A4A5C), fontSize: 13),
              for (final l in _row4) key(letterCase(l), onTap: () => onKey(letterCase(l))),
              key('CLEAR', onTap: onClear, flex: 2, color: const Color(0xFFC43C5A), fontSize: 13),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              key('.', onTap: () => onKey('.')),
              key(',', onTap: () => onKey(',')),
              key('-', onTap: () => onKey('-')),
              key('SPACE', onTap: onSpace, flex: 6, color: const Color(0xFF3A4A5C), fontSize: 14),
              key("'", onTap: () => onKey("'")),
              key('/', onTap: () => onKey('/')),
            ],
          ),
        ),
      ],
    );
  }
}
