import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scanner/camera_scanner.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/cart.dart';
import '../../../data/models/org.dart';
import '../../../data/repositories/bootstrap_repository.dart';
import '../../../data/repositories/parked_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../customers/customer_picker.dart';
import '../../sales/saved_sales_screen.dart';
import '../cart_controller.dart';
import '../sell_actions.dart';
import 'vat_dialog.dart';

/// The basket: lines, totals and the actions around a sale.
class CartPanel extends ConsumerWidget {
  const CartPanel({super.key, required this.onPay, this.scrollController});

  final VoidCallback onPay;
  final ScrollController? scrollController;

  Future<void> _park(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final label = await promptText(context, title: 'Save sale', hint: 'Name or table (optional)', initial: cart.tableRef ?? cart.customer?.name, confirmLabel: 'Save', allowEmpty: true);
    if (label == null) return;
    await ref.read(parkedSalesProvider.notifier).park(
          cart,
          label: label.isEmpty ? null : label,
          staffName: ref.read(currentStaffProvider)?.name,
          totalPence: ref.read(cartTotalsProvider).totalPence,
        );
    ref.read(cartProvider.notifier).clear();
    if (context.mounted) showMessage(context, 'Sale saved. Find it in Saved Sales.');
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    if (await confirm(context, title: 'Clear this sale?', message: 'All items, the customer and any discount will be removed.', confirmLabel: 'Clear', destructive: true)) {
      ref.read(cartProvider.notifier).clear();
    }
  }

  Future<void> _table(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider);
    final choice = await pickOption<String>(context, title: 'Table', options: [
      if (cameraScanSupported) ('scan', 'Scan table QR code'),
      ('type', 'Enter table number'),
      if (cart.tableRef != null) ('clear', 'Remove table'),
    ]);
    if (!context.mounted || choice == null) return;
    final ctrl = ref.read(cartProvider.notifier);
    if (choice == 'clear') {
      ctrl.setTable(null);
    } else if (choice == 'scan') {
      final code = await scanWithCamera(context, title: 'Scan table QR');
      if (code != null) ctrl.setTable(code.toUpperCase().startsWith('TABLE:') ? code.substring(6) : code);
    } else {
      final t = await promptText(context, title: 'Table number', initial: cart.tableRef, confirmLabel: 'Set');
      if (t != null) ctrl.setTable(t);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final totals = ref.watch(cartTotalsProvider);
    final settings = ref.watch(settingsProvider);
    final parkedCount = ref.watch(parkedSalesProvider).length;
    final theme = Theme.of(context);
    final ctrl = ref.read(cartProvider.notifier);

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(cart.isEmpty ? 'Current sale' : 'Current sale · ${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Saved sales',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedSalesScreen())),
                  icon: Badge(isLabelVisible: parkedCount > 0, label: Text('$parkedCount'), child: const Icon(Icons.bookmarks_outlined)),
                ),
                IconButton(tooltip: 'Clear sale', onPressed: cart.hasContent ? () => _clear(context, ref) : null, icon: const Icon(Icons.delete_sweep_outlined)),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                InputChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(cart.customer?.name ?? 'Add customer'),
                  onPressed: () async {
                    final c = await showCustomerPicker(context);
                    if (c != null) ctrl.setCustomer(c);
                  },
                  onDeleted: cart.customer == null ? null : () => ctrl.setCustomer(null),
                ),
                if (settings.eatInTakeAway) ...[
                  const SizedBox(width: 8),
                  SegmentedButton<SaleType>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: SaleType.eatIn, label: Text('Eat in')),
                      ButtonSegment(value: SaleType.takeAway, label: Text('Take away')),
                    ],
                    selected: {cart.saleType == SaleType.instore ? SaleType.takeAway : cart.saleType},
                    onSelectionChanged: (s) => ctrl.setSaleType(s.first),
                  ),
                ],
                if (settings.tableQrButton) ...[
                  const SizedBox(width: 8),
                  ActionChip(avatar: const Icon(Icons.table_restaurant_outlined, size: 18), label: Text(cart.tableRef == null ? 'Table' : 'Table ${cart.tableRef}'), onPressed: () => _table(context, ref)),
                ],
                const SizedBox(width: 8),
                FilterChip(
                  avatar: Icon(cart.applyVat ? Icons.percent : Icons.money_off, size: 18),
                  label: Text(
                    !cart.applyVat
                        ? 'VAT off'
                        : cart.vatRate == null
                            ? 'VAT on'
                            : 'VAT ${formatVatPercent(cart.vatRate!)}',
                  ),
                  selected: cart.applyVat,
                  onSelected: (on) {
                    if (on) {
                      editSaleVat(context, ref, enable: true);
                    } else {
                      ref.read(cartProvider.notifier).setVat(enabled: false);
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.sell_outlined, size: 18),
                  label: Text(cart.cartDiscount == null ? 'Discount' : 'Discount ${cart.cartDiscount!.label(formatPence)}'),
                  selected: cart.cartDiscount != null,
                  onSelected: cart.isEmpty ? null : (_) => editCartDiscount(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Divider(),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.qr_code_scanner, size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 8),
                      Text('Tap a product or scan a barcode', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ]),
                  )
                : ListView.separated(
                    controller: scrollController,
                    itemCount: totals.lines.length,
                    separatorBuilder: (_, _) => const Divider(indent: 12, endIndent: 12),
                    itemBuilder: (_, i) {
                      final lt = totals.lines[totals.lines.length - 1 - i];
                      return _CartLineTile(totals: lt, onTap: () => editCartLine(context, ref, lt.line));
                    },
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: [
                _TotalRow('Subtotal', formatPence(totals.subtotalPence)),
                InkWell(
                  onTap: cart.isEmpty ? null : () => editCartDiscount(context, ref),
                  child: totals.discountPence > 0
                      ? _TotalRow('Discount', '-${formatPence(totals.discountPence)}', color: theme.colorScheme.error)
                      : _TotalRow('Discount', 'Add', muted: true),
                ),
                InkWell(
                  onTap: () => editSaleVat(context, ref, enable: true),
                  child: _TotalRow(
                    !cart.applyVat
                        ? 'VAT off'
                        : settings.pricesIncludeTax
                            ? (cart.vatRate == null ? 'VAT included' : 'VAT included (${formatVatPercent(cart.vatRate!)})')
                            : (cart.vatRate == null ? 'VAT' : 'VAT (${formatVatPercent(cart.vatRate!)})'),
                    formatPence(totals.taxPence),
                    muted: true,
                  ),
                ),
                if (cart.note != null && cart.note!.isNotEmpty)
                  Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('Note: ${cart.note}', style: theme.textTheme.bodySmall))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: cart.isEmpty ? null : () => editCartDiscount(context, ref),
                    icon: const Icon(Icons.sell_outlined, size: 20),
                    label: Text(cart.cartDiscount == null ? 'Discount' : cart.cartDiscount!.label(formatPence)),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      final n = await promptText(context, title: 'Sale note', initial: cart.note, maxLines: 3, allowEmpty: true);
                      if (n != null) ctrl.setNote(n);
                    },
                    icon: const Icon(Icons.sticky_note_2_outlined, size: 20),
                    label: const Text('Note'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(onPressed: cart.isEmpty ? null : () => _park(context, ref), icon: const Icon(Icons.bookmark_add_outlined, size: 20), label: const Text('Save')),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  onPressed: cart.isEmpty ? null : onPay,
                  child: Row(
                    children: [
                      const Text('Pay'),
                      const Spacer(),
                      Text(formatPence(totals.totalPence), style: theme.textTheme.headlineSmall?.copyWith(color: cart.isEmpty ? null : theme.colorScheme.onPrimary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.color, this.muted = false});
  final String label;
  final String value;
  final Color? color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: color ?? (muted ? Theme.of(context).colorScheme.onSurfaceVariant : null));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(value, style: style)]),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.totals, required this.onTap});
  final LineTotals totals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = totals.line;
    final theme = Theme.of(context);
    final ctrl = ref.read(cartProvider.notifier);
    final details = [
      if (line.modifiers.isNotEmpty) line.modifiers.map((m) => m.name).join(', '),
      if (line.quantity > 1) '${line.quantity} × ${formatPence(line.unitPence)}',
      if (line.priceOverridePence != null) 'price changed',
      if (line.discount != null) 'discount ${line.discount!.label(formatPence)}',
      if (line.note != null && line.note!.isNotEmpty) line.note!,
    ];
    return Dismissible(
      key: ValueKey(line.id),
      direction: DismissDirection.endToStart,
      background: Container(color: theme.colorScheme.error, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) => ctrl.removeLine(line.id),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
          child: Row(
            children: [
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => ctrl.increment(line.id, -1), icon: const Icon(Icons.remove_circle_outline)),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => editLineQuantity(context, ref, line),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 36),
                    child: Text('${line.quantity}', textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final error = ctrl.increment(line.id, 1);
                  if (error != null) showMessage(context, error, error: true);
                },
                icon: const Icon(Icons.add_circle_outline),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.product.displayName, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                    if (details.isNotEmpty) Text(details.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatPence(totals.totalPence), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if (totals.discountPence > 0)
                    Text(formatPence(totals.grossPence), style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
