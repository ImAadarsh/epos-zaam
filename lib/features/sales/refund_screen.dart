import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hardware/printer/printer_service.dart';
import '../../core/hardware/printer/receipt.dart';
import '../../core/network/api_exception.dart';
import '../../core/scanner/camera_scanner.dart';
import '../../core/scanner/scan_bus.dart';
import '../../core/security/permissions.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/shift_repository.dart';
import 'sale_loader.dart';

/// Refund Transaction: scan or type the receipt barcode, pick items and quantities,
/// choose how to refund and whether to put stock back.
class RefundScreen extends ConsumerStatefulWidget {
  const RefundScreen({super.key, this.initialCode});
  final String? initialCode;

  @override
  ConsumerState<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends ConsumerState<RefundScreen> {
  final _code = TextEditingController();
  StreamSubscription<ScanEvent>? _scanSub;
  SaleRecord? _sale;
  final Map<int, int> _qty = {};
  bool _restock = true;
  PaymentMethod _method = PaymentMethod.cash;
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanSub = ref.read(scanBusProvider).stream.listen((e) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _find(e.code);
    });
    if (widget.initialCode != null) Future.microtask(() => _find(widget.initialCode!));
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _find(String code) async {
    if (code.trim().isEmpty) return;
    _code.text = code.trim();
    setState(() {
      _loading = true;
      _error = null;
      _sale = null;
      _qty.clear();
    });
    try {
      final s = await loadSale(ref, code);
      if (!mounted) return;
      if (s == null) {
        setState(() => _error = 'No sale found for "$code"');
      } else {
        final original = s.payments.where((p) => !p.isRefund).map((p) => p.method).firstOrNull;
        setState(() {
          _sale = s;
          _method = original ?? PaymentMethod.cash;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _lineRefund(SaleLine l, int qty) => l.quantity == 0 ? 0 : (l.totalPence * qty / l.quantity).round();

  int get _amount {
    final s = _sale;
    if (s == null) return 0;
    var total = 0;
    _qty.forEach((i, q) => total += _lineRefund(s.lines[i], q));
    return total.clamp(0, s.refundablePence);
  }

  Future<void> _refund() async {
    final sale = _sale!;
    final amount = _amount;
    if (amount <= 0) return;
    if (!await requirePermission(context, ref, Perm.refund) || !mounted) return;
    final reason = await promptText(context, title: 'Refund ${formatPence(amount)} to ${_method.label}?', hint: 'Reason (e.g. faulty, changed mind)', confirmLabel: 'Refund');
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final shift = ref.read(shiftProvider);
      final lines = [
        for (final e in _qty.entries)
          if (e.value > 0) (line: sale.lines[e.key], quantity: e.value, amountPence: _lineRefund(sale.lines[e.key], e.value)),
      ];
      await ref.read(localSalesProvider.notifier).refund(
            sale: sale,
            lines: lines,
            amountPence: amount,
            method: _method,
            restock: _restock,
            reason: reason,
            shiftId: shift?.serverId,
            shiftClientId: shift?.clientId,
          );
      await ref.read(shiftProvider.notifier).recordRefund(_method.name, amount);
      try {
        await ref.read(printerServiceProvider).print(
              buildRefundReceipt(sale, amountPence: amount, method: _method.label, lines: [for (final l in lines) (l.line.name, l.quantity, l.amountPence)], org: ref.read(bootstrapProvider).org),
              jobName: 'Refund ${sale.receiptNumber}',
            );
      } catch (_) {}
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, size: 48),
          title: Text('Refunded ${formatPence(amount)}'),
          content: Text(_method == PaymentMethod.card
              ? 'Now refund ${formatPence(amount)} to the customer\'s card on the card terminal.'
              : _method == PaymentMethod.cash
                  ? 'Give ${formatPence(amount)} cash back to the customer.'
                  : 'Refund recorded as ${_method.label}.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sale = _sale;
    return Scaffold(
      appBar: AppBar(title: const Text('Refund Transaction')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Scan the barcode on the receipt, or type the receipt number.', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    autofocus: widget.initialCode == null,
                    decoration: const InputDecoration(hintText: 'Receipt number', prefixIcon: Icon(Icons.receipt_long)),
                    onSubmitted: _find,
                  ),
                ),
                const SizedBox(width: 8),
                if (cameraScanSupported)
                  IconButton.filledTonal(
                    iconSize: 28,
                    onPressed: () async {
                      final c = await scanWithCamera(context, title: 'Scan receipt');
                      if (c != null) _find(c);
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => _find(_code.text), child: const Text('Find')),
              ]),
              if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
              if (sale != null) ...[
                const SizedBox(height: 16),
                Text('${sale.receiptNumber} · ${formatPence(sale.totalPence)}${sale.refundedPence > 0 ? ' · ${formatPence(sale.refundedPence)} already refunded' : ''}',
                    style: theme.textTheme.titleMedium),
                if (sale.status == 'voided') Text('This sale was voided and cannot be refunded.', style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 8),
                Card(
                  child: Column(children: [
                    for (var i = 0; i < sale.lines.length; i++)
                      Builder(builder: (_) {
                        final l = sale.lines[i];
                        final max = l.refundableQuantity;
                        final q = _qty[i] ?? 0;
                        return ListTile(
                          title: Text(l.name),
                          subtitle: Text('Sold ${l.quantity}${l.refundedQuantity > 0 ? ', refunded ${l.refundedQuantity}' : ''} · ${formatPence(l.totalPence)}'),
                          trailing: max <= 0
                              ? const Text('Refunded')
                              : Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(onPressed: q > 0 ? () => setState(() => _qty[i] = q - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
                                  SizedBox(width: 32, child: Text('$q', textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
                                  IconButton(onPressed: q < max ? () => setState(() => _qty[i] = q + 1) : null, icon: const Icon(Icons.add_circle_outline)),
                                ]),
                        );
                      }),
                    ListTile(
                      title: const Text('Select all remaining'),
                      trailing: TextButton(
                        onPressed: () => setState(() {
                          for (var i = 0; i < sale.lines.length; i++) {
                            _qty[i] = sale.lines[i].refundableQuantity;
                          }
                        }),
                        child: const Text('All'),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                SwitchListTile(value: _restock, onChanged: (v) => setState(() => _restock = v), title: const Text('Return items to stock'), subtitle: const Text('Turn off for faulty or damaged items')),
                const SizedBox(height: 8),
                Text('Refund to', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<PaymentMethod>(
                  segments: const [
                    ButtonSegment(value: PaymentMethod.cash, label: Text('Cash'), icon: Icon(Icons.payments_outlined)),
                    ButtonSegment(value: PaymentMethod.card, label: Text('Card'), icon: Icon(Icons.credit_card)),
                    ButtonSegment(value: PaymentMethod.voucher, label: Text('Voucher'), icon: Icon(Icons.card_giftcard)),
                  ],
                  selected: {_method == PaymentMethod.cash || _method == PaymentMethod.card || _method == PaymentMethod.voucher ? _method : PaymentMethod.cash},
                  onSelectionChanged: (s) => setState(() => _method = s.first),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 60,
                  child: FilledButton(
                    onPressed: _busy || _amount <= 0 || sale.status == 'voided' ? null : _refund,
                    child: Text('Refund ${formatPence(_amount)}'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
