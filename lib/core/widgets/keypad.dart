import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Large numeric keypad for PIN entry, cash tendered, floats and quantities.
/// Also accepts a physical keyboard (digits, Backspace, Enter).
class Keypad extends StatelessWidget {
  const Keypad({super.key, required this.onDigit, required this.onBackspace, this.onEnter, this.showDoubleZero = false, this.enterLabel, this.maxWidth = 360});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onEnter;
  final bool showDoubleZero;
  final String? enterLabel;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon, bool primary = false}) {
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: primary ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              height: 64,
              child: Center(
                child: icon != null
                    ? Icon(icon, color: primary ? scheme.onPrimary : null)
                    : Text(label, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: primary ? scheme.onPrimary : null)),
              ),
            ),
          ),
        ),
      );
    }

    Widget row(List<Widget> children) => Row(children: children.map((c) => Expanded(child: c)).toList());

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final ch = event.character;
        if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
          onDigit(ch);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          onBackspace();
          return KeyEventResult.handled;
        }
        if ((event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) && onEnter != null) {
          onEnter!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row([key('1', onTap: () => onDigit('1')), key('2', onTap: () => onDigit('2')), key('3', onTap: () => onDigit('3'))]),
            row([key('4', onTap: () => onDigit('4')), key('5', onTap: () => onDigit('5')), key('6', onTap: () => onDigit('6'))]),
            row([key('7', onTap: () => onDigit('7')), key('8', onTap: () => onDigit('8')), key('9', onTap: () => onDigit('9'))]),
            row([
              showDoubleZero ? key('00', onTap: () => onDigit('00')) : key('', icon: Icons.backspace_outlined, onTap: onBackspace),
              key('0', onTap: () => onDigit('0')),
              if (onEnter != null)
                key(enterLabel ?? 'OK', icon: enterLabel == null ? Icons.check : null, onTap: onEnter, primary: true)
              else
                key('', icon: Icons.backspace_outlined, onTap: onBackspace),
            ]),
            if (showDoubleZero && onEnter != null) row([key('', icon: Icons.backspace_outlined, onTap: onBackspace)]),
          ],
        ),
      ),
    );
  }
}
