import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display/customer_display.dart';
import '../../core/hardware/payments/card_terminal.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/money.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/keypad.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'cart_controller.dart';
import 'checkout_service.dart';
import 'sale_complete_screen.dart';

/// Take payment: cash (with change), card via the configured provider, or
/// other tenders; any mix of them (split payments).
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final List<SalePayment> _payments = [];
  String _digits = '';
  bool _busy = false;

  int get _total => ref.read(cartTotalsProvider).totalPence;
  int get _paid => _payments.fold(0, (s, p) => s + p.amountPence);
  int get _remaining => (_total - _paid).clamp(0, 1 << 31);
  int get _entered => _digits.isEmpty ? _remaining : (int.tryParse(_digits) ?? 0);

  @override
  void initState() {
    super.initState();
    Future.microtask(_showOnDisplay);
  }

  void _showOnDisplay() {
    final totals = ref.read(cartTotalsProvider);
    final org = ref.read(bootstrapProvider).org;
    final base = DisplayState.fromCart(ref.read(cartProvider), totals, org?.name ?? '');
    ref.read(customerDisplayProvider).show(DisplayState(
          mode: 'paying',
          storeName: base.storeName,
          lines: base.lines,
          totalPence: base.totalPence,
          discountPence: base.discountPence,
          paidPence: _paid,
        ));
  }

  Future<void> _addPayment(SalePayment p) async {
    setState(() {
      _payments.add(p);
      _digits = '';
    });
    _showOnDisplay();
    if (_remaining == 0) await _finish();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final tip = _payments.fold(0, (s, p) => s + p.tipPence);
      final sale = await ref.read(checkoutServiceProvider).complete(payments: List.of(_payments), tipPence: tip);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SaleCompleteScreen(sale: sale)));
    } catch (e) {
      AppLog.error('Checkout failed', e);
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, 'Could not complete sale: $e', error: true);
      }
    }
  }

  Future<void> _cash([int? tendered]) async {
    final t = tendered ?? _entered;
    if (t <= 0) return;
    final settings = ref.read(settingsProvider);
    final applied = t < _remaining ? t : _remaining;
    if (settings.cashPrompt) {
      final change = t - applied;
      final ok = await confirm(context, title: 'Cash ${formatPence(t)}', message: change > 0 ? 'Change due: ${formatPence(change)}' : 'Take cash payment?', confirmLabel: 'Take cash');
      if (!ok) return;
    }
    await _addPayment(SalePayment(method: PaymentMethod.cash, amountPence: applied, tenderedPence: t));
  }

  Future<int?> _askTip(int amount) async {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add a tip?'),
        children: [
          for (final pct in const [0, 10, 12.5, 15])
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              onPressed: () => Navigator.pop(ctx, (amount * pct / 100).round()),
              child: Text(pct == 0 ? 'No tip' : '$pct% · ${formatPence((amount * pct / 100).round())}'),
            ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            onPressed: () async {
              final v = await promptAmount(ctx, title: 'Tip amount');
              if (ctx.mounted) Navigator.pop(ctx, v ?? 0);
            },
            child: const Text('Custom amount'),
          ),
        ],
      ),
    );
  }

  Future<void> _card() async {
    final amount = _entered > _remaining ? _remaining : _entered;
    if (amount <= 0) return;
    final settings = ref.read(settingsProvider);
    final terminal = ref.read(cardTerminalProvider);
    var tip = 0;
    if (settings.tipsEnabled) {
      final t = await _askTip(amount);
      if (t == null || !mounted) return;
      tip = t;
    }
    final charge = amount + tip;
    final reference = 'POS ${DateTime.now().millisecondsSinceEpoch}';

    if (terminal.manualConfirmation) {
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.credit_card, size: 40),
          title: Text('Charge ${formatPence(charge)} on the card terminal'),
          content: const Text('Key the amount into the card machine and wait for the customer to pay. Was the payment approved?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Declined / cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approved')),
          ],
        ),
      );
      if (approved == true) await _addPayment(SalePayment(method: PaymentMethod.card, amountPence: amount, tipPence: tip, provider: terminal.providerCode));
      return;
    }

    if (settings.cardPrompt) {
      final ok = await confirm(context, title: 'Card ${formatPence(charge)}', message: 'Send to ${terminal.name}?', confirmLabel: 'Send');
      if (!ok || !mounted) return;
    }
    final status = ValueNotifier<String>('Connecting to ${terminal.name}…');
    final future = terminal.charge(amountPence: charge, reference: reference, onStatus: (s) => status.value = s);
    if (!mounted) return;
    final result = await showDialog<CardResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        future.then((r) {
          if (ctx.mounted) Navigator.pop(ctx, r);
        });
        return AlertDialog(
          title: Text('${terminal.name} · ${formatPence(charge)}'),
          content: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, s, _) => Row(children: [const CircularProgressIndicator(), const SizedBox(width: 20), Expanded(child: Text(s))]),
          ),
          actions: [TextButton(onPressed: () => terminal.cancel(), child: const Text('Cancel on reader'))],
        );
      },
    );
    status.dispose();
    if (!mounted || result == null) return;
    if (result.approved) {
      await _addPayment(SalePayment(
        method: PaymentMethod.card,
        amountPence: amount,
        tipPence: tip,
        provider: result.provider ?? terminal.providerCode,
        reference: result.reference,
        cardBrand: result.cardBrand,
        cardLast4: result.last4,
      ));
    } else {
      showMessage(context, result.message ?? 'Card payment ${result.outcome.name}', error: true);
    }
  }

  Future<void> _other() async {
    final method = await pickOption<PaymentMethod>(context, title: 'Other payment', options: [
      (PaymentMethod.voucher, 'Gift voucher'),
      (PaymentMethod.account, 'On account'),
      (PaymentMethod.other, 'Other (bank transfer, cheque…)'),
    ]);
    if (method == null || !mounted) return;
    final amount = _entered > _remaining ? _remaining : _entered;
    final ref0 = await promptText(context, title: '${method.label} reference', hint: 'Voucher number or note (optional)', allowEmpty: true, confirmLabel: 'Take ${formatPence(amount)}');
    if (ref0 == null) return;
    await _addPayment(SalePayment(method: method, amountPence: amount, reference: ref0.isEmpty ? null : ref0));
  }

  Future<bool> _confirmLeave() async {
    if (_payments.isEmpty) return true;
    final cards = _payments.where((p) => p.method == PaymentMethod.card).length;
    return confirm(
      context,
      title: 'Cancel payment?',
      message: cards > 0 ? '$cards card payment(s) were already approved. Refund them on the card terminal if you cancel.' : 'Payments taken so far will be removed.',
      confirmLabel: 'Cancel payment',
      destructive: true,
    );
  }

  List<int> _quickCash(int remaining) {
    final notes = [500, 1000, 2000, 5000];
    final out = <int>{remaining};
    for (final n in notes) {
      final v = ((remaining + n - 1) ~/ n) * n;
      if (v > remaining) out.add(v);
    }
    return out.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final totals = ref.watch(cartTotalsProvider);
    final remaining = _remaining;

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Total', style: theme.textTheme.titleMedium),
        Text(formatPence(totals.totalPence), style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (var i = 0; i < _payments.length; i++)
          Card(
            child: ListTile(
              leading: Icon(switch (_payments[i].method) { PaymentMethod.cash => Icons.payments_outlined, PaymentMethod.card => Icons.credit_card, _ => Icons.receipt_outlined }),
              title: Text(_payments[i].label),
              subtitle: _payments[i].tenderedPence != null && _payments[i].tenderedPence! > _payments[i].amountPence
                  ? Text('Tendered ${formatPence(_payments[i].tenderedPence!)}')
                  : _payments[i].tipPence > 0
                      ? Text('Tip ${formatPence(_payments[i].tipPence)}')
                      : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(formatPence(_payments[i].amountPence), style: theme.textTheme.titleMedium),
                if (_payments[i].method != PaymentMethod.card)
                  IconButton(onPressed: _busy ? null : () => setState(() => _payments.removeAt(i)), icon: const Icon(Icons.close)),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Text('Remaining', style: theme.textTheme.titleMedium),
          const Spacer(),
          Text(formatPence(remaining), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
        ]),
      ],
    );

    final entry = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_digits.isEmpty ? 'Amount (remaining)' : 'Amount', style: theme.textTheme.bodyMedium),
        Text(formatPence(_entered), style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (settings.cashEnabled)
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final v in _quickCash(remaining))
              ActionChip(avatar: const Icon(Icons.payments_outlined, size: 18), label: Text(v == remaining ? 'Exact ${formatPence(v)}' : formatPence(v)), onPressed: _busy ? null : () => _cash(v)),
          ]),
        const SizedBox(height: 8),
        Keypad(
          showDoubleZero: true,
          onDigit: (d) => setState(() => _digits = (_digits + d).length > 8 ? _digits : _digits + d),
          onBackspace: () => setState(() => _digits = _digits.isEmpty ? '' : _digits.substring(0, _digits.length - 1)),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(children: [
            if (settings.cashEnabled)
              _MethodButton(icon: Icons.payments_outlined, label: 'Cash', onPressed: _busy || remaining == 0 ? null : () => _cash()),
            if (settings.cardEnabled)
              _MethodButton(icon: Icons.credit_card, label: 'Card', onPressed: _busy || remaining == 0 ? null : _card),
            if (settings.otherEnabled)
              _MethodButton(icon: Icons.more_horiz, label: 'Other', tonal: true, onPressed: _busy || remaining == 0 ? null : _other),
          ]),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
          ref.read(customerDisplayProvider).show(DisplayState.fromCart(ref.read(cartProvider), ref.read(cartTotalsProvider), ref.read(bootstrapProvider).org?.name ?? ''));
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment')),
        body: _busy && remaining == 0
            ? const Center(child: CircularProgressIndicator())
            : context.isCompact
                ? ListView(padding: const EdgeInsets.all(16), children: [summary, const SizedBox(height: 16), Center(child: entry)])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: summary)),
                      const VerticalDivider(width: 1),
                      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Center(child: entry))),
                    ],
                  ),
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({required this.icon, required this.label, required this.onPressed, this.tonal = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon), const SizedBox(width: 10), Text(label)]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: tonal ? FilledButton.tonal(onPressed: onPressed, child: child) : FilledButton(onPressed: onPressed, child: child),
      ),
    );
  }
}
