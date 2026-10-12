import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/permissions.dart';
import '../../core/widgets/manager_override.dart';
import '../../core/sync/connectivity.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/session.dart';
import '../auth/register_select_screen.dart';
import '../unsynced/unsynced_screen.dart';

/// Online/sync state and the signed-in staff member, shown in every app bar.
class ShellStatusActions extends ConsumerWidget {
  const ShellStatusActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider);
    final outbox = ref.watch(outboxProvider);
    final staff = ref.watch(currentStaffProvider);
    final register = ref.watch(currentRegisterProvider);
    final compact = MediaQuery.sizeOf(context).width < 600;

    final Color color;
    final String label;
    final IconData icon;
    if (!online) {
      color = ZaamColors.amber;
      label = outbox.pendingCount > 0 ? 'Offline · ${outbox.pendingCount}' : 'Offline';
      icon = Icons.cloud_off;
    } else if (outbox.failedCount > 0) {
      color = ZaamColors.red;
      label = '${outbox.failedCount} failed';
      icon = Icons.sync_problem;
    } else if (outbox.pendingCount > 0 || outbox.flushing) {
      color = ZaamColors.amber;
      label = 'Syncing ${outbox.pendingCount}';
      icon = Icons.sync;
    } else {
      color = ZaamColors.green;
      label = 'Synced';
      icon = Icons.cloud_done;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (register != null) ...[
          Tooltip(
            message: 'Register: ${register.name} · tap to switch, add or remove registers',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                if (await requirePermission(context, ref, Perm.changeRegister) && context.mounted) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterSelectScreen(changing: true)));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.point_of_sale, size: 18),
                  if (!compact) ...[const SizedBox(width: 6), Text(register.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))],
                  const Icon(Icons.arrow_drop_down, size: 18),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Tooltip(
          message: 'Tap to view unsynced changes. Long-press to sync now.',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnsyncedScreen())),
            onLongPress: () => ref.read(syncServiceProvider).syncNow(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18, color: color),
                if (!compact) ...[const SizedBox(width: 6), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))],
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: staff == null ? 'Lock' : '${staff.name} (${staff.posRole.name}) · tap to lock / switch user',
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => ref.read(sessionProvider.notifier).lock(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 16, child: Text(staff?.initials ?? '?', style: const TextStyle(fontSize: 12))),
                if (!compact && staff != null) ...[const SizedBox(width: 6), Text(staff.name.split(' ').first), const Icon(Icons.lock_outline, size: 16)],
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
