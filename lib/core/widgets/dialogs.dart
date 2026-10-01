import 'package:flutter/material.dart';

import '../utils/money.dart';
import 'keypad.dart';

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    duration: Duration(seconds: error ? 5 : 3),
  ));
}

Future<bool> confirm(BuildContext context, {required String title, String? message, String confirmLabel = 'Confirm', bool destructive = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String confirmLabel = 'Save',
  TextInputType? keyboardType,
  int maxLines = 1,
  bool allowEmpty = false,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v.trim()) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isEmpty && !allowEmpty) return;
            Navigator.pop(ctx, v);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Keypad amount entry in pence (typing 1250 shows £12.50).
Future<int?> promptAmount(BuildContext context, {required String title, int? initialPence, String confirmLabel = 'OK', String? message, bool allowZero = true}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _AmountDialog(title: title, initialPence: initialPence, confirmLabel: confirmLabel, message: message, allowZero: allowZero),
  );
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, this.initialPence, required this.confirmLabel, this.message, required this.allowZero});
  final String title;
  final int? initialPence;
  final String confirmLabel;
  final String? message;
  final bool allowZero;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late String _digits = widget.initialPence == null || widget.initialPence == 0 ? '' : '${widget.initialPence}';

  int get _pence => int.tryParse(_digits) ?? 0;

  void _submit() {
    if (!widget.allowZero && _pence == 0) return;
    Navigator.pop(context, _pence);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.message != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(widget.message!)),
            Text(formatPence(_pence), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Keypad(
              showDoubleZero: true,
              onDigit: (d) => setState(() => _digits = (_digits + d).length > 8 ? _digits : _digits + d),
              onBackspace: () => setState(() => _digits = _digits.isEmpty ? '' : _digits.substring(0, _digits.length - 1)),
              onEnter: _submit,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

Future<T?> pickOption<T>(BuildContext context, {required String title, required List<(T, String)> options}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final (value, label) in options)
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, value), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), child: Text(label)),
      ],
    ),
  );
}
