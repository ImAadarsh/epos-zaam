import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../../../core/widgets/keypad.dart';
import '../../../data/models/cart.dart';
import '../../../data/models/org.dart';

/// Result of the discount dialog: a discount, or `clear` to remove the current one.
class DiscountResult {
  const DiscountResult(this.discount);
  final Discount? discount;
}

Future<DiscountResult?> showDiscountDialog(
  BuildContext context, {
  required String title,
  Discount? current,
  required int basePence,
  List<DiscountPreset> presets = const [],
}) {
  return showDialog<DiscountResult>(
    context: context,
    builder: (_) => _DiscountDialog(title: title, current: current, basePence: basePence, presets: presets),
  );
}

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({required this.title, this.current, required this.basePence, this.presets = const []});
  final String title;
  final Discount? current;
  final int basePence;
  final List<DiscountPreset> presets;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late DiscountType _type = widget.current?.type ?? DiscountType.percent;
  late String _digits = widget.current == null ? '' : '${widget.current!.value.round()}';
  late final _reason = TextEditingController(text: widget.current?.reason);

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  num get _value => int.tryParse(_digits) ?? 0;

  Discount get _discount => Discount(type: _type, value: _type == DiscountType.percent ? _value.clamp(0, 100) : _value, reason: _reason.text.trim().isEmpty ? null : _reason.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = _discount.amountOn(widget.basePence);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<DiscountType>(
                segments: const [
                  ButtonSegment(value: DiscountType.percent, label: Text('Percent %'), icon: Icon(Icons.percent)),
                  ButtonSegment(value: DiscountType.amount, label: Text('Amount £'), icon: Icon(Icons.currency_pound)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _digits = '';
                }),
              ),
              const SizedBox(height: 12),
              Text(_type == DiscountType.percent ? '${_value.clamp(0, 100)}%' : formatPence(_value.toInt()),
                  style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
              Text('Saves ${formatPence(amount)} of ${formatPence(widget.basePence)}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in widget.presets)
                  ActionChip(
                    label: Text(p.name.isEmpty ? (p.isAmount ? formatPence((p.value * 100).round()) : '${p.value.round()}%') : p.name),
                    onPressed: () => setState(() {
                      _type = p.isAmount ? DiscountType.amount : DiscountType.percent;
                      _digits = p.isAmount ? '${(p.value * 100).round()}' : '${p.value.round()}';
                      if (_reason.text.trim().isEmpty) _reason.text = p.name;
                    }),
                  ),
                if (widget.presets.isEmpty && _type == DiscountType.percent)
                  for (final p in const [5, 10, 20]) ActionChip(label: Text('$p%'), onPressed: () => setState(() => _digits = '$p')),
              ]),
              const SizedBox(height: 8),
              Keypad(
                showDoubleZero: _type == DiscountType.amount,
                onDigit: (d) => setState(() => _digits = (_digits + d).length > 7 ? _digits : _digits + d),
                onBackspace: () => setState(() => _digits = _digits.isEmpty ? '' : _digits.substring(0, _digits.length - 1)),
              ),
              const SizedBox(height: 8),
              TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. Staff, damaged box, loyalty')),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.current != null) TextButton(onPressed: () => Navigator.pop(context, const DiscountResult(null)), child: const Text('Remove discount')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _value <= 0 ? null : () => Navigator.pop(context, DiscountResult(_discount)), child: const Text('Apply')),
      ],
    );
  }
}
