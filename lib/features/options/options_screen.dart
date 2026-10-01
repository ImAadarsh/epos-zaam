import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/security/permissions.dart';
import '../../core/storage/local_db.dart';
import '../../core/utils/app_log.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/parked_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/shift_repository.dart';
import '../auth/register_select_screen.dart';
import '../availability/availability_screen.dart';
import '../display/connect_display_screen.dart';
import '../register/register_screen.dart';
import '../sales/previous_sales_screen.dart';
import '../sales/refund_screen.dart';
import '../sales/saved_sales_screen.dart';
import '../settings/settings_screen.dart';
import '../shell/status_bar.dart';
import '../staff/clock_screen.dart';
import '../support/debug_screen.dart';
import '../support/faq_screen.dart';
import '../unsynced/unsynced_screen.dart';

/// "Options" menu, mirroring the Goodtill/SumUp POS options list.
class OptionsScreen extends ConsumerWidget {
  const OptionsScreen({super.key});

  void _push(BuildContext context, Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    if (!await requirePermission(context, ref, Perm.resetApp) || !context.mounted) return;
    final pending = ref.read(outboxProvider).pendingCount;
    final ok = await confirm(
      context,
      title: 'Reset app?',
      message: '${pending > 0 ? 'WARNING: $pending change(s) have not synced and will be lost.\n\n' : ''}'
          'This removes all data from this device (products, saved sales, settings, sign-in). Sales already synced stay in Zaam ERP.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    if (pending > 0) {
      final again = await confirm(context, title: 'Really lose $pending unsynced change(s)?', confirmLabel: 'Yes, reset', destructive: true);
      if (!again) return;
    }
    AppLog.warn('App reset by user');
    await ref.read(localDbProvider).clearAll();
    await ref.read(outboxProvider.notifier).clear();
    await ref.read(catalogProvider.notifier).clear();
    await ref.read(localSalesProvider.notifier).clear();
    await ref.read(parkedSalesProvider.notifier).clear();
    await ref.read(shiftProvider.notifier).clearLocal();
    await ref.read(bootstrapProvider.notifier).clear();
    await ref.read(sessionProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outbox = ref.watch(outboxProvider);
    final parked = ref.watch(parkedSalesProvider).length;
    final register = ref.watch(currentRegisterProvider);

    final items = <(IconData, String, String?, VoidCallback)>[
      (Icons.lock_clock, 'Close Register', 'Start close register, X-read and Z-read', () => _push(context, const RegisterScreen(standalone: true))),
      (Icons.schedule, 'Staff Clock In/Out', null, () => _push(context, const ClockScreen())),
      (Icons.settings_outlined, 'Settings', 'Payments, receipts, printer, staff PINs', () async {
        if (await requirePermission(context, ref, Perm.settings) && context.mounted) _push(context, const SettingsScreen());
      }),
      (Icons.bookmarks_outlined, 'Saved Sales', parked > 0 ? '$parked saved' : null, () => _push(context, const SavedSalesScreen())),
      (Icons.receipt_long_outlined, 'Previous Sales', null, () => _push(context, const PreviousSalesScreen())),
      (Icons.undo, 'Refund Transaction', 'Scan or type the receipt number', () => _push(context, const RefundScreen())),
      (Icons.inventory_2_outlined, 'Manage Availability', 'Mark products and modifiers unavailable', () async {
        if (await requirePermission(context, ref, Perm.manageAvailability) && context.mounted) _push(context, const AvailabilityScreen());
      }),
      (
        Icons.sync_problem_outlined,
        'Check Unsynced Sales',
        outbox.pendingCount == 0 ? 'Everything is synced' : '${outbox.pendingCount} waiting${outbox.failedCount > 0 ? ', ${outbox.failedCount} failed' : ''}',
        () => _push(context, const UnsyncedScreen()),
      ),
      (Icons.point_of_sale, 'Change Register', register == null ? null : 'Active: ${register.name}', () async {
        if (await requirePermission(context, ref, Perm.changeRegister) && context.mounted) _push(context, const RegisterSelectScreen(changing: true));
      }),
      (Icons.connected_tv, 'Connect Display', 'Customer-facing screen', () => _push(context, const ConnectDisplayScreen())),
      (Icons.bug_report_outlined, 'Send Debug Data', 'Send logs to Zaam support', () => _push(context, const DebugScreen())),
      (Icons.help_outline, 'FAQ', null, () => _push(context, const FaqScreen())),
      (Icons.lock_outline, 'Lock till', 'Switch staff member', () => ref.read(sessionProvider.notifier).lock()),
      (Icons.restart_alt, 'Reset App', 'Remove all data from this device', () => _reset(context, ref)),
    ];

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Options'), actions: const [ShellStatusActions()]),
      body: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1100 ? 3 : c.maxWidth >= 700 ? 2 : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 84, mainAxisSpacing: 10, crossAxisSpacing: 10),
          itemCount: items.length + 1,
          itemBuilder: (context, i) {
            if (i == items.length) {
              return Center(child: Text('Zaam EPOS v${AppConfig.appVersion}', style: Theme.of(context).textTheme.bodySmall));
            }
            final (icon, title, sub, onTap) = items[i];
            final danger = title == 'Reset App';
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                leading: Icon(icon, size: 30, color: danger ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
                title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? Theme.of(context).colorScheme.error : null)),
                subtitle: sub == null ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: onTap,
              ),
            );
          },
        );
      }),
    );
  }
}
