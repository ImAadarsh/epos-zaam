import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../core/widgets/keypad.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/shift_repository.dart';

/// Start of day: count the float into the drawer and open the register.
class OpenRegisterCard extends ConsumerStatefulWidget {
  const OpenRegisterCard({super.key});

  @override
  ConsumerState<OpenRegisterCard> createState() => _OpenRegisterCardState();
}

class _OpenRegisterCardState extends ConsumerState<OpenRegisterCard> {
  String _digits = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(shiftProvider.notifier).suggestedFloat().then((p) {
      if (mounted && p != null && p > 0 && _digits.isEmpty) setState(() => _digits = '$p');
    });
  }

  int get _pence => int.tryParse(_digits) ?? 0;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      await ref.read(shiftProvider.notifier).open(_pence);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final register = ref.watch(currentRegisterProvider);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            children: [
              Icon(Icons.point_of_sale, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text('Open ${register?.name ?? 'register'}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Count the cash float in the drawer', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Text(formatPence(_pence), style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final p in const [5000, 10000, 15000, 20000]) ActionChip(label: Text(formatPence(p)), onPressed: () => setState(() => _digits = '$p')),
              ]),
              const SizedBox(height: 8),
              Keypad(
                showDoubleZero: true,
                onDigit: (d) => setState(() => _digits = (_digits + d).length > 8 ? _digits : _digits + d),
                onBackspace: () => setState(() => _digits = _digits.isEmpty ? '' : _digits.substring(0, _digits.length - 1)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(onPressed: _busy ? null : _open, icon: const Icon(Icons.lock_open), label: const Text('Open register')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
