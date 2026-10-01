import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/shift_repository.dart';
import 'shift_report_view.dart';

/// UK notes and coins, in pence.
const _denominations = [5000, 2000, 1000, 500, 200, 100, 50, 20, 10, 5, 2, 1];

String _denomLabel(int p) => p >= 100 ? '£${p ~/ 100}' : '${p}p';

/// Blind cash count by denomination, then close the register (Z-read).
class CloseRegisterScreen extends ConsumerStatefulWidget {
  const CloseRegisterScreen({super.key});

  @override
  ConsumerState<CloseRegisterScreen> createState() => _CloseRegisterScreenState();
}

class _CloseRegisterScreenState extends ConsumerState<CloseRegisterScreen> {
  final Map<int, TextEditingController> _counts = {for (final d in _denominations) d: TextEditingController()};
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  int get _total => _counts.entries.fold(0, (s, e) => s + e.key * (int.tryParse(e.value.text) ?? 0));

  Future<void> _close() async {
    final settings = ref.read(settingsProvider);
    final ok = await confirm(context, title: 'Close register?', message: 'Counted cash: ${formatPence(_total)}. This ends the session and produces the Z-read.', confirmLabel: 'Close register');
    if (!ok || !mounted) return;
    int? nextFloat;
    if (settings.floatAfterClose) {
      nextFloat = await promptAmount(context, title: 'Float left in drawer', message: 'Cash left in the drawer for the next session.', confirmLabel: 'Save float');
      if (!mounted) return;
    }
    setState(() => _busy = true);
    try {
      final z = await ref.read(shiftProvider.notifier).close(
            countedPence: _total,
            denominations: {for (final e in _counts.entries) if ((int.tryParse(e.value.text) ?? 0) > 0) _denomLabel(e.key): int.parse(e.value.text)},
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            nextFloatPence: nextFloat,
          );
      if (!mounted) return;
      if (z != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ShiftReportScreen(report: z)));
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Close failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cols = context.isCompact ? 2 : 4;
    return Scaffold(
      appBar: AppBar(title: const Text('Close Register')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Count the cash in the drawer', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Enter how many of each note and coin you have.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.4,
                  children: [
                    for (final d in _denominations)
                      TextField(
                        controller: _counts[d],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                        decoration: InputDecoration(
                          labelText: _denomLabel(d),
                          suffixText: (int.tryParse(_counts[d]!.text) ?? 0) > 0 ? formatPence(d * int.parse(_counts[d]!.text)) : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              ],
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Counted'),
                    Text(formatPence(_total), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                  const Spacer(),
                  FilledButton.icon(onPressed: _busy ? null : _close, icon: const Icon(Icons.lock), label: const Text('Close register')),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
