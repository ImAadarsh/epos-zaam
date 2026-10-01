import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/hardware/printer/printer_service.dart';
import '../../core/security/permissions.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/models/shift.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../shell/status_bar.dart';
import 'close_register_screen.dart';
import 'open_register_card.dart';
import 'shift_report_view.dart';

/// Register tab: session summary, X-read, cash in/out, no sale, close register.
class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({super.key, this.standalone = false});

  final bool standalone;

  Future<void> _xRead(BuildContext context, WidgetRef ref) async {
    final r = await showDialog<ShiftReport?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        ref.read(shiftProvider.notifier).report().then((v) {
          if (ctx.mounted) Navigator.pop(ctx, v);
        });
        return const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Building X-read…')]));
      },
    );
    if (r != null && context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShiftReportScreen(report: r)));
  }

  Future<void> _movement(BuildContext context, WidgetRef ref, String type, String title) async {
    if (!await requirePermission(context, ref, Perm.cashMovement) || !context.mounted) return;
    final amount = await promptAmount(context, title: title, allowZero: false);
    if (amount == null || !context.mounted) return;
    final reason = await promptText(context, title: 'Reason', hint: type == 'paid_out' ? 'e.g. milk, window cleaner' : 'e.g. change top-up', allowEmpty: true, confirmLabel: 'Record');
    if (reason == null) return;
    await ref.read(shiftProvider.notifier).cashMovement(type, amount, reason.isEmpty ? null : reason);
    try {
      await ref.read(printerServiceProvider).openDrawer();
    } catch (_) {}
    if (context.mounted) showMessage(context, '$title ${formatPence(amount)} recorded');
  }

  Future<void> _noSale(BuildContext context, WidgetRef ref) async {
    if (!await requirePermission(context, ref, Perm.noSale) || !context.mounted) return;
    await ref.read(shiftProvider.notifier).cashMovement('no_sale', 0, null);
    try {
      await ref.read(printerServiceProvider).openDrawer();
      if (context.mounted) showMessage(context, 'Drawer opened (no sale logged)');
    } catch (e) {
      if (context.mounted) showMessage(context, 'No sale logged. $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(shiftProvider);
    final register = ref.watch(currentRegisterProvider);
    final theme = Theme.of(context);
    final appBar = AppBar(
      automaticallyImplyLeading: standalone,
      title: Text(standalone ? 'Close Register' : 'Register'),
      actions: [if (!standalone) const ShellStatusActions()],
    );
    if (shift == null) return Scaffold(appBar: appBar, body: const OpenRegisterCard());

    final sales = ref.watch(localSalesProvider).where((s) => s.shiftClientId == shift.clientId && s.status != 'voided').toList();
    final takings = sales.fold(0, (a, s) => a + s.totalPence - s.refundedPence);
    final opener = ref.read(shiftProvider.notifier).openedByName();

    Widget action(IconData icon, String label, String sub, VoidCallback onTap, {bool primary = false}) => Card(
          color: primary ? theme.colorScheme.primaryContainer : null,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            leading: Icon(icon, size: 32, color: primary ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.primary),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );

    return Scaffold(
      appBar: appBar,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(register?.name ?? 'Register', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Open since ${DateFormat('EEE d MMM, HH:mm').format(shift.openedAt)}${opener != null ? ' by $opener' : ''}'),
                        Text('Float ${formatPence(shift.openingFloatPence)}${shift.serverId == null ? ' · not synced yet' : ''}', style: theme.textTheme.bodySmall),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(formatPence(takings), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${sales.length} sales on this till', style: theme.textTheme.bodySmall),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              action(Icons.lock_clock, 'Start Close Register', 'Count the drawer and print the Z-read', () async {
                if (!await requirePermission(context, ref, Perm.closeRegister) || !context.mounted) return;
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CloseRegisterScreen()));
              }, primary: true),
              const SizedBox(height: 8),
              action(Icons.summarize_outlined, 'View X-Read', 'Takings so far without closing', () => _xRead(context, ref)),
              const SizedBox(height: 8),
              action(Icons.add_card, 'Pay in', 'Add cash to the drawer', () => _movement(context, ref, 'paid_in', 'Pay in')),
              const SizedBox(height: 8),
              action(Icons.outbox_outlined, 'Pay out', 'Take cash out for an expense', () => _movement(context, ref, 'paid_out', 'Pay out')),
              const SizedBox(height: 8),
              action(Icons.savings_outlined, 'Cash drop', 'Move cash to the safe', () => _movement(context, ref, 'drop', 'Cash drop')),
              const SizedBox(height: 8),
              action(Icons.inbox_outlined, 'No sale', 'Open the drawer without a sale', () => _noSale(context, ref)),
            ],
          ),
        ),
      ),
    );
  }
}
