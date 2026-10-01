import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/security/permissions.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/models/outbox.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../sell/checkout_service.dart';
import 'refund_screen.dart';
import 'sale_loader.dart';

class SaleDetailScreen extends ConsumerStatefulWidget {
  const SaleDetailScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  SaleRecord? _sale;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await loadSale(ref, widget.code);
      if (mounted) setState(() => _sale = s);
      if (s == null && mounted) setState(() => _error = 'Sale not found');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _void() async {
    final sale = _sale!;
    if (!await requirePermission(context, ref, Perm.voidSale) || !mounted) return;
    final reason = await promptText(context, title: 'Void ${sale.receiptNumber}?', hint: 'Reason', confirmLabel: 'Void sale');
    if (reason == null) return;
    final code = sale.sync == SyncState.synced ? (sale.orderNumber ?? sale.serverId ?? sale.clientId) : sale.clientId;
    await ref.read(outboxProvider.notifier).enqueue(OutboxType.voidSale, {'saleCode': code, 'reason': reason}, summary: 'Void ${sale.receiptNumber}', amountPence: sale.totalPence);
    await ref.read(localSalesProvider.notifier).markVoided(sale.clientId);
    if (!mounted) return;
    showMessage(context, 'Sale voided. Stock returned; return any cash or refund the card on the terminal.');
    setState(() => _sale = sale.copyWith(status: 'voided'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sale = _sale;
    return Scaffold(
      appBar: AppBar(title: Text(sale?.receiptNumber ?? 'Sale'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : sale == null
              ? Center(child: Text(_error ?? 'Sale not found'))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(formatPence(sale.totalPence), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700))),
                                Chip(label: Text(sale.sync != SyncState.synced ? 'Not synced' : sale.status.replaceAll('_', ' '))),
                              ]),
                              const SizedBox(height: 4),
                              Text(DateFormat('EEEE d MMM yyyy, HH:mm').format(sale.soldAt)),
                              Text([
                                if (sale.registerName != null) sale.registerName!,
                                if (sale.staffName != null) 'Served by ${sale.staffName}',
                                if (sale.customerName != null) 'Customer ${sale.customerName}',
                                if (sale.tableRef != null) 'Table ${sale.tableRef}',
                              ].join(' · ')),
                              if (sale.orderNumber != null) Text('Order ${sale.orderNumber}', style: theme.textTheme.bodySmall),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Column(children: [
                            for (final l in sale.lines)
                              ListTile(
                                title: Text('${l.quantity} × ${l.name}'),
                                subtitle: Text([
                                  if (l.modifiers.isNotEmpty) l.modifiers.join(', '),
                                  if (l.discountPence > 0) 'discount ${formatPence(l.discountPence)}',
                                  if (l.refundedQuantity > 0) 'refunded ${l.refundedQuantity}',
                                  if (l.note != null && l.note!.isNotEmpty) l.note!,
                                ].join(' · ')),
                                trailing: Text(formatPence(l.totalPence), style: theme.textTheme.titleMedium),
                              ),
                            const Divider(),
                            ListTile(dense: true, title: const Text('Subtotal'), trailing: Text(formatPence(sale.subtotalPence))),
                            if (sale.discountPence > 0) ListTile(dense: true, title: const Text('Discounts'), trailing: Text('-${formatPence(sale.discountPence)}')),
                            ListTile(dense: true, title: const Text('VAT'), trailing: Text(formatPence(sale.taxPence))),
                            if (sale.refundedPence > 0) ListTile(dense: true, title: const Text('Refunded'), trailing: Text('-${formatPence(sale.refundedPence)}')),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Column(children: [
                            for (final p in sale.payments)
                              ListTile(
                                leading: Icon(p.isRefund ? Icons.undo : Icons.payments_outlined),
                                title: Text(p.isRefund ? 'Refund · ${p.label}' : p.label),
                                subtitle: p.reference == null ? null : Text(p.reference!),
                                trailing: Text(formatPenceSigned(p.amountPence)),
                              ),
                            if (sale.changePence > 0) ListTile(dense: true, title: const Text('Change given'), trailing: Text(formatPence(sale.changePence))),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              try {
                                await ref.read(checkoutServiceProvider).printReceipt(sale, copy: true);
                              } catch (e) {
                                if (context.mounted) showMessage(context, 'Print failed: $e', error: true);
                              }
                            },
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Reprint'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final email = await promptText(context, title: 'Email receipt', initial: sale.customerEmail, keyboardType: TextInputType.emailAddress, confirmLabel: 'Send');
                              if (email == null || !email.contains('@')) return;
                              await ref.read(checkoutServiceProvider).emailReceipt(sale, email);
                              if (context.mounted) showMessage(context, 'Receipt queued for $email');
                            },
                            icon: const Icon(Icons.email_outlined),
                            label: const Text('Email'),
                          ),
                          if (sale.status != 'voided' && sale.refundablePence > 0)
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RefundScreen(initialCode: sale.orderNumber ?? sale.receiptNumber)));
                                _load();
                              },
                              icon: const Icon(Icons.undo),
                              label: const Text('Refund'),
                            ),
                          if (sale.status == 'completed' && sale.refundedPence == 0)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                              onPressed: _void,
                              icon: const Icon(Icons.block),
                              label: const Text('Void sale'),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ),
    );
  }
}
