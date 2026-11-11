import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_log.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/repositories/parked_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/session.dart';
import '../../sales/refund_screen.dart';
import '../../sales/saved_sales_screen.dart';
import '../checkout_service.dart';

/// Day-to-day till actions on the Sell screen (receipt reprint, saved, refund, lock).
class SellShortcutsBar extends ConsumerWidget {
  const SellShortcutsBar({super.key});

  Future<void> _reprintLast(BuildContext context, WidgetRef ref) async {
    final sale = ref.read(localSalesProvider.notifier).lastReceiptSale;
    if (sale == null) {
      showMessage(context, 'No receipt to reprint yet', error: true);
      return;
    }
    try {
      await ref.read(checkoutServiceProvider).printReceipt(sale, copy: true);
      if (context.mounted) showMessage(context, 'Reprinted ${sale.receiptNumber}');
    } catch (e) {
      AppLog.warn('Reprint failed: $e');
      if (context.mounted) showMessage(context, 'Could not print receipt: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parked = ref.watch(parkedSalesProvider).length;
    final hasReceipt = ref.watch(localSalesProvider.select((s) => s.any((x) => x.status != 'voided')));

    Widget chip({required IconData icon, required String label, required VoidCallback? onPressed, int badge = 0}) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          avatar: badge > 0
              ? Badge(label: Text('$badge'), child: Icon(icon, size: 18))
              : Icon(icon, size: 18),
          label: Text(label),
          onPressed: onPressed,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          chip(
            icon: Icons.receipt_outlined,
            label: 'Receipt',
            onPressed: hasReceipt ? () => _reprintLast(context, ref) : null,
          ),
          chip(
            icon: Icons.bookmarks_outlined,
            label: 'Saved',
            badge: parked,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedSalesScreen())),
          ),
          chip(
            icon: Icons.undo,
            label: 'Refund',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RefundScreen())),
          ),
          chip(
            icon: Icons.lock_outline,
            label: 'Lock',
            onPressed: () => ref.read(sessionProvider.notifier).lock(),
          ),
        ],
      ),
    );
  }
}
