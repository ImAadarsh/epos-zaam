import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/security/permissions.dart';
import '../../core/sync/connectivity.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/models/outbox.dart';
import '../../data/repositories/outbox_repository.dart';

/// Check Unsynced Sales: everything queued on this device, with Fix Sales (retry).
class UnsyncedScreen extends ConsumerWidget {
  const UnsyncedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outbox = ref.watch(outboxProvider);
    final online = ref.watch(onlineProvider);
    final theme = Theme.of(context);
    final fmt = DateFormat('dd MMM HH:mm:ss');

    return Scaffold(
      appBar: AppBar(title: const Text('Unsynced Sales')),
      body: Column(children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: ListTile(
            leading: Icon(online ? Icons.cloud_done : Icons.cloud_off, color: online ? ZaamColors.green : ZaamColors.amber, size: 32),
            title: Text(outbox.pendingCount == 0 ? 'All changes are synced' : '${outbox.pendingCount} change(s) waiting · ${outbox.unsyncedSales} sale(s)'),
            subtitle: Text([
              online ? 'Connected to Zaam' : 'Offline: changes will sync automatically when back online',
              if (outbox.lastFlush != null) 'last attempt ${DateFormat('HH:mm:ss').format(outbox.lastFlush!)}',
            ].join(' · ')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: outbox.flushing ? null : () => ref.read(syncServiceProvider).syncNow(),
                icon: outbox.flushing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                label: const Text('Sync now'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: outbox.failedCount == 0
                    ? null
                    : () async {
                        await ref.read(outboxProvider.notifier).retryFailed();
                        if (context.mounted) showMessage(context, 'Retrying ${outbox.failedCount} failed change(s)');
                      },
                icon: const Icon(Icons.build_outlined),
                label: Text('Fix Sales${outbox.failedCount > 0 ? ' (${outbox.failedCount})' : ''}'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: outbox.entries.isEmpty
              ? const Center(child: Icon(Icons.done_all, size: 64, color: ZaamColors.green))
              : ListView.separated(
                  itemCount: outbox.entries.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    final e = outbox.entries[i];
                    final failed = e.status == OutboxStatus.failed;
                    return ListTile(
                      leading: Icon(failed ? Icons.error_outline : Icons.schedule, color: failed ? ZaamColors.red : ZaamColors.amber),
                      title: Text('${e.type.label}${e.summary != null ? ' · ${e.summary}' : ''}'),
                      subtitle: Text([
                        fmt.format(e.createdAt),
                        if (e.attempts > 0) '${e.attempts} attempt(s)',
                        if (e.lastError != null) e.lastError!,
                      ].join(' · '), style: failed ? TextStyle(color: theme.colorScheme.error) : null),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (e.amountPence != null) Text(formatPence(e.amountPence!)),
                        if (failed)
                          IconButton(
                            tooltip: 'Discard',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (!await requirePermission(context, ref, Perm.resetApp) || !context.mounted) return;
                              final ok = await confirm(context,
                                  title: 'Discard this change?',
                                  message: 'It will never reach Zaam ERP. Only do this if it was entered in the ERP some other way.',
                                  confirmLabel: 'Discard',
                                  destructive: true);
                              if (ok) await ref.read(outboxProvider.notifier).discard(e.id);
                            },
                          ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
