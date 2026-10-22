import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/pin.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/pin_entry.dart';
import '../../data/models/org.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../staff/clock_screen.dart';

/// Staff unlock the till with their PIN (checked by the server; PINs used here before also work offline).
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final boot = await ref.read(bootstrapProvider.notifier).refresh();
        await ref.read(pinVerifierProvider).prune(boot.staff);
        await ref.read(settingsProvider.notifier).applyOrgVat(boot.taxCodes);
      } catch (_) {}
    });
  }

  Future<bool> _submit(String pin) async {
    final r = await ref.read(pinVerifierProvider).verify(pin);
    final match = r.staff;
    if (match == null) {
      if (r.message != null && mounted) showMessage(context, r.message!, error: true);
      return false;
    }
    await ref.read(sessionProvider.notifier).unlock(match.id, staffToken: r.staffToken);
    return true;
  }

  Future<void> _signOut() async {
    final pending = ref.read(outboxProvider).pendingCount;
    final ok = await confirm(
      context,
      title: 'Sign this device out?',
      message: pending > 0
          ? '$pending change(s) have not synced yet. They stay on this device and sync after you sign back in with the same organisation.'
          : 'An ERP login will be needed to use this till again.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (ok) await ref.read(sessionProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(bootstrapProvider);
    final session = ref.watch(sessionProvider);
    final register = ref.watch(currentRegisterProvider);
    final withPins = boot.staff.where((s) => s.hasPin).toList();
    final user = session.user!;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const ZaamLogo(height: 44),
                  const SizedBox(height: 8),
                  Text(register?.name ?? 'Register', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 28),
                  if (withPins.isNotEmpty) ...[
                    Text('Enter your PIN', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    PinEntry(onSubmit: _submit),
                  ] else ...[
                    Icon(Icons.pin_outlined, size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('No staff PINs yet', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('Continue as the signed-in account, then add PINs under Options → Settings → Staff PINs.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => ref.read(sessionProvider.notifier).unlock(user.id),
                        icon: const Icon(Icons.login),
                        label: Text('Continue as ${user.name}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClockScreen(requirePin: true))),
                        icon: const Icon(Icons.schedule),
                        label: const Text('Clock in / out'),
                      ),
                      TextButton.icon(onPressed: _signOut, icon: const Icon(Icons.logout), label: const Text('Sign out device')),
                    ],
                  ),
                  if (withPins.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StaffHint(staff: withPins),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffHint extends StatelessWidget {
  const _StaffHint({required this.staff});
  final List<StaffMember> staff;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final s in staff.take(12))
          Tooltip(message: s.name, child: CircleAvatar(radius: 16, child: Text(s.initials, style: const TextStyle(fontSize: 12)))),
      ],
    );
  }
}
