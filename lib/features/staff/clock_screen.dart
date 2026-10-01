import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/security/pin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/pin_entry.dart';
import '../../data/models/org.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/clock_repository.dart';

/// Staff Clock In/Out with search. Staff confirm with their own PIN when they have one.
class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key, this.requirePin = false});

  /// From the lock screen nobody is signed in, so a PIN is always needed.
  final bool requirePin;

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  String _q = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(clockProvider.notifier).refresh());
  }

  Future<void> _toggle(StaffMember s) async {
    final me = ref.read(currentStaffProvider);
    final needPin = s.pinHash != null && (widget.requirePin || me?.id != s.id);
    if (needPin) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${s.name}: enter your PIN'),
          content: SizedBox(
            width: 340,
            child: PinEntry(onSubmit: (pin) async {
              final m = matchPin([s], pin);
              if (m == null) return false;
              if (ctx.mounted) Navigator.pop(ctx, true);
              return true;
            }),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))],
        ),
      );
      if (ok != true) return;
    } else if (widget.requirePin && s.pinHash == null) {
      if (mounted) showMessage(context, '${s.name} has no PIN yet. A manager can set one in Settings → Staff PINs.', error: true);
      return;
    }
    final wasIn = ref.read(clockProvider).containsKey(s.id);
    await ref.read(clockProvider.notifier).toggle(s.id);
    if (mounted) showMessage(context, '${s.name} clocked ${wasIn ? 'out' : 'in'} at ${DateFormat('HH:mm').format(DateTime.now())}');
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(bootstrapProvider).staff.where((s) => _q.isEmpty || s.name.toLowerCase().contains(_q.toLowerCase())).toList();
    final clock = ref.watch(clockProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Clock In/Out'), actions: [IconButton(onPressed: () => ref.read(clockProvider.notifier).refresh(), icon: const Icon(Icons.refresh))]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(decoration: const InputDecoration(hintText: 'Search staff', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v.trim())),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: staff.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final s = staff[i];
                  final since = clock[s.id];
                  return ListTile(
                    leading: CircleAvatar(child: Text(s.initials)),
                    title: Text(s.name),
                    subtitle: Text(since == null ? 'Clocked out' : 'Clocked in since ${DateFormat('HH:mm').format(since)}',
                        style: TextStyle(color: since == null ? null : ZaamColors.green)),
                    trailing: FilledButton.tonal(onPressed: () => _toggle(s), child: Text(since == null ? 'Clock in' : 'Clock out')),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
