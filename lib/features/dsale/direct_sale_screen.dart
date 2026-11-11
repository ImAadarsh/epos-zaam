import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/audio/till_click.dart';
import '../../core/security/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../register/open_register_card.dart';
import '../shell/app_shell.dart';
import '../shell/status_bar.dart';
import 'dsale_service.dart';

void _click() => TillClick.play();

final _saleTime = DateFormat('HH:mm');

/// Immersive EPOS Direct Sale till: cents keypad → Sale / Print / Payout / Hourly.
/// Parallel to Sell — does not replace product scanning.
class DirectSaleScreen extends ConsumerStatefulWidget {
  const DirectSaleScreen({super.key});

  @override
  ConsumerState<DirectSaleScreen> createState() => _DirectSaleScreenState();
}

class _DirectSaleScreenState extends ConsumerState<DirectSaleScreen> {
  /// Digits typed as the smallest currency unit (pence). `2` → 2p → £0.02; `2` then `00` → £2.00.
  String _digits = '';
  bool _busy = false;
  String? _flash;
  bool _flashError = false;

  int get _pence => int.tryParse(_digits) ?? 0;

  String get _display => (_pence / 100).toStringAsFixed(2);

  void _flashMsg(String msg, {bool error = false}) {
    setState(() {
      _flash = msg;
      _flashError = error;
    });
  }

  void _digit(String d) {
    _click();
    if (d == '.') return; // Classic cents entry ignores the decimal key.
    setState(() {
      final next = '$_digits$d';
      if (next.length > 9) return;
      // Keep leading zeros only while building fractional pounds (e.g. first "0" of "00").
      _digits = next.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (_digits.isEmpty && d == '0') _digits = '0';
      if (_digits.isEmpty && d == '00') _digits = '0';
    });
  }

  void _back() {
    _click();
    setState(() {
      if (_digits.isEmpty) return;
      _digits = _digits.substring(0, _digits.length - 1);
    });
  }

  void _clear() {
    _click();
    setState(() => _digits = '');
  }

  Future<void> _run(Future<DSaleResult> Function() action, {bool clearOnOk = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await action();
      if (!mounted) return;
      _flashMsg(r.message, error: r.error || !r.ok);
      if (r.ok && clearOnOk) setState(() => _digits = '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sale() async {
    _click();
    if (_pence <= 0) {
      _flashMsg('Enter the sale total first', error: true);
      return;
    }
    await _run(() => ref.read(dSaleServiceProvider).completeSale(_pence));
  }

  Future<void> _print() async {
    _click();
    await _run(() => ref.read(dSaleServiceProvider).reprintLast(), clearOnOk: false);
  }

  Future<void> _payout() async {
    _click();
    if (_pence <= 0) {
      _flashMsg('Enter the payout amount first', error: true);
      return;
    }
    if (!await requirePermission(context, ref, Perm.cashMovement) || !mounted) return;
    final ok = await confirm(
      context,
      title: 'Direct Sale payout',
      message: 'Take ${formatPence(_pence)} out of the drawer?',
      confirmLabel: 'Confirm payout',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() => ref.read(dSaleServiceProvider).payout(_pence));
  }

  Future<void> _hourly() async {
    _click();
    final report = await ref.read(dSaleServiceProvider).hourlyReport();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _HourlyReportDialog(
        report: report,
        onPrint: () async {
          Navigator.pop(ctx);
          await _run(() => ref.read(dSaleServiceProvider).printHourlyReport(report), clearOnOk: false);
        },
      ),
    );
  }

  Future<void> _onSaleTap(SaleRecord sale) async {
    _click();
    if (_busy) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A222D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  sale.receiptNumber,
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatPence(sale.totalPence)} · ${_saleTime.format(sale.soldAt)}'
                  '${isDirectSaleRecord(sale) ? ' · Direct Sale' : ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Colors.white),
                  title: const Text('Edit amount', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Void this sale and record a new Direct Sale', style: TextStyle(color: Colors.white54)),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: ZaamColors.red),
                  title: Text('Delete / void', style: TextStyle(color: ZaamColors.red, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Cancel this sale (manager PIN if required)', style: TextStyle(color: Colors.white54)),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 'delete') {
      await _deleteSale(sale);
    } else if (choice == 'edit') {
      await _editSale(sale);
    }
  }

  Future<void> _deleteSale(SaleRecord sale) async {
    if (!await requirePermission(context, ref, Perm.voidSale) || !mounted) return;
    final reason = await promptText(
      context,
      title: 'Void ${sale.receiptNumber}?',
      hint: 'Reason',
      confirmLabel: 'Void sale',
    );
    if (reason == null || !mounted) return;
    await _run(
      () => ref.read(dSaleServiceProvider).voidSale(sale, reason: reason.isEmpty ? 'Voided via Direct Sale' : reason),
      clearOnOk: false,
    );
  }

  Future<void> _editSale(SaleRecord sale) async {
    if (!await requirePermission(context, ref, Perm.voidSale) || !mounted) return;
    final newPence = await showDialog<int>(
      context: context,
      builder: (ctx) => _EditAmountDialog(initialPence: sale.totalPence, receiptNumber: sale.receiptNumber),
    );
    if (newPence == null || !mounted) return;
    await _run(() => ref.read(dSaleServiceProvider).editSale(sale, newPence));
  }

  void _backToModules() {
    _click();
    ref.read(shellTabProvider.notifier).go(0);
  }

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(shiftProvider);
    // Rebuild when local sales change so the left list + last-receipt label stay live.
    ref.watch(localSalesProvider);
    final recent = ref.read(dSaleServiceProvider).recentSales(limit: 10);
    final lastPrintable = recent.isNotEmpty ? recent.first : null;
    final theme = Theme.of(context);

    final appBar = AppBar(
      leading: IconButton(
        tooltip: 'Back to Ethos modules',
        icon: const Icon(Icons.arrow_back),
        onPressed: _backToModules,
      ),
      title: const Text('Direct Sale'),
      actions: const [ShellStatusActions()],
      backgroundColor: const Color(0xFF161B22),
      foregroundColor: Colors.white,
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
    );

    if (shift == null) {
      return Scaffold(appBar: appBar, body: const OpenRegisterCard());
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      appBar: appBar,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final amountHeader = _AmountHeader(
              display: _display,
              pence: _pence,
              flash: _flash,
              flashError: _flashError,
              lastLabel: lastPrintable == null
                  ? 'No sales yet on this till'
                  : 'Last: ${lastPrintable.receiptNumber} · ${formatPence(lastPrintable.totalPence)}',
              busy: _busy,
            );
            final salesList = _RecentSalesList(
              sales: recent,
              enabled: !_busy,
              onTap: _onSaleTap,
            );
            final pad = _Numpad(
              onDigit: _digit,
              onBack: _back,
              onClear: _clear,
              onOk: _sale,
              enabled: !_busy,
            );
            final actions = _ActionColumn(
              onSale: _busy ? null : _sale,
              onPrint: _busy ? null : _print,
              onPayout: _busy ? null : _payout,
              onHourly: _busy ? null : _hourly,
            );

            if (wide) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          amountHeader,
                          const SizedBox(height: 10),
                          Expanded(child: salesList),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: [
                          Expanded(child: pad),
                          const SizedBox(height: 10),
                          SizedBox(height: 108, child: actions),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                children: [
                  amountHeader,
                  const SizedBox(height: 8),
                  SizedBox(height: 160, child: salesList),
                  const SizedBox(height: 8),
                  Expanded(child: pad),
                  const SizedBox(height: 8),
                  SizedBox(height: 96, child: actions),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({
    required this.display,
    required this.pence,
    required this.flash,
    required this.flashError,
    required this.lastLabel,
    required this.busy,
  });

  final String display;
  final int pence;
  final String? flash;
  final bool flashError;
  final String lastLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A222D), Color(0xFF12171E)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3340)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DIRECT SALE',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: ZaamColors.gold,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Enter total in pence — e.g. 2 then 00 for £2.00',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '£$display',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: pence > 0 ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(lastLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white38)),
          if (flash != null) ...[
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: flashError ? ZaamColors.red.withValues(alpha: 0.18) : ZaamColors.green.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: flashError ? ZaamColors.red.withValues(alpha: 0.5) : ZaamColors.green.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  if (busy) ...[
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                    const SizedBox(width: 10),
                  ] else ...[
                    Icon(flashError ? Icons.error_outline : Icons.check_circle_outline, size: 18, color: flashError ? ZaamColors.red : ZaamColors.green),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      flash!,
                      style: TextStyle(color: flashError ? const Color(0xFFFFC9C9) : const Color(0xFFC8F5D8), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentSalesList extends StatelessWidget {
  const _RecentSalesList({required this.sales, required this.enabled, required this.onTap});

  final List<SaleRecord> sales;
  final bool enabled;
  final ValueChanged<SaleRecord> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12171E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3340)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Text(
                  'LAST ${sales.isEmpty ? 10 : sales.length} SALES',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white70,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                Text('Tap to edit / void', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white38)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2A3340)),
          Expanded(
            child: sales.isEmpty
                ? const Center(
                    child: Text('No sales on this till yet', style: TextStyle(color: Colors.white38)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: sales.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1E2630)),
                    itemBuilder: (context, i) {
                      final s = sales[i];
                      final direct = isDirectSaleRecord(s);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: enabled ? () => onTap(s) : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: direct ? ZaamColors.gold : const Color(0xFF5A6A7C),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.receiptNumber,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      Text(
                                        '${_saleTime.format(s.soldAt)}${direct ? ' · Direct' : ''}${s.staffName != null ? ' · ${s.staffName}' : ''}',
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatPence(s.totalPence),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Numpad extends StatelessWidget {
  const _Numpad({
    required this.onDigit,
    required this.onBack,
    required this.onClear,
    required this.onOk,
    required this.enabled,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final VoidCallback onOk;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(
      String label, {
      VoidCallback? onTap,
      Color? color,
      Color? fg,
      int flex = 1,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Material(
            color: color ?? const Color(0xFF243041),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? onTap : null,
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: fg ?? Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget row(List<Widget> kids) => Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids));

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
        final ch = event.character;
        if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
          onDigit(ch);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          onBack();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          onOk();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          row([
            key('1', onTap: () => onDigit('1')),
            key('2', onTap: () => onDigit('2')),
            key('3', onTap: () => onDigit('3')),
            key('CLEAR', onTap: onClear, color: const Color(0xFF3A4A5C)),
          ]),
          row([
            key('4', onTap: () => onDigit('4')),
            key('5', onTap: () => onDigit('5')),
            key('6', onTap: () => onDigit('6')),
            key('BACK', onTap: onBack, color: const Color(0xFF3A4A5C)),
          ]),
          row([
            key('7', onTap: () => onDigit('7')),
            key('8', onTap: () => onDigit('8')),
            key('9', onTap: () => onDigit('9')),
            key('OK', onTap: onOk, color: const Color(0xFF1F8A4C)),
          ]),
          row([
            key('0', onTap: () => onDigit('0')),
            key('00', onTap: () => onDigit('00'), flex: 2),
            const Expanded(child: SizedBox()),
          ]),
        ],
      ),
    );
  }
}

class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.onSale,
    required this.onPrint,
    required this.onPayout,
    required this.onHourly,
  });

  final VoidCallback? onSale;
  final VoidCallback? onPrint;
  final VoidCallback? onPayout;
  final VoidCallback? onHourly;

  @override
  Widget build(BuildContext context) {
    Widget action({
      required String label,
      required String sub,
      required Color color,
      required VoidCallback? onTap,
      required IconData icon,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 26),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3)),
                          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        action(label: 'SALE', sub: 'No auto-print', color: const Color(0xFF1F8A4C), onTap: onSale, icon: Icons.shopping_bag_outlined),
        action(label: 'PRINT', sub: 'Last receipt', color: const Color(0xFF2F6FED), onTap: onPrint, icon: Icons.print_outlined),
        action(label: 'PAYOUT', sub: 'Print slip', color: const Color(0xFFC43C5A), onTap: onPayout, icon: Icons.outbox_outlined),
        action(label: 'HOURLY', sub: 'Early report', color: const Color(0xFFB8860B), onTap: onHourly, icon: Icons.schedule_outlined),
      ],
    );
  }
}

class _EditAmountDialog extends StatefulWidget {
  const _EditAmountDialog({required this.initialPence, required this.receiptNumber});

  final int initialPence;
  final String receiptNumber;

  @override
  State<_EditAmountDialog> createState() => _EditAmountDialogState();
}

class _EditAmountDialogState extends State<_EditAmountDialog> {
  late String _digits;

  @override
  void initState() {
    super.initState();
    _digits = widget.initialPence > 0 ? '${widget.initialPence}' : '';
  }

  int get _pence => int.tryParse(_digits) ?? 0;
  String get _display => (_pence / 100).toStringAsFixed(2);

  void _digit(String d) {
    _click();
    setState(() {
      final next = '$_digits$d';
      if (next.length > 9) return;
      _digits = next.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (_digits.isEmpty && (d == '0' || d == '00')) _digits = '0';
    });
  }

  void _back() {
    _click();
    setState(() {
      if (_digits.isEmpty) return;
      _digits = _digits.substring(0, _digits.length - 1);
    });
  }

  void _clear() {
    _click();
    setState(() => _digits = '');
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, Color? color, int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: color ?? const Color(0xFF243041),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF1A222D),
      title: Text('Edit ${widget.receiptNumber}', style: const TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '£$_display',
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [key('1', onTap: () => _digit('1')), key('2', onTap: () => _digit('2')), key('3', onTap: () => _digit('3')), key('C', onTap: _clear, color: const Color(0xFF3A4A5C))]),
            Row(children: [key('4', onTap: () => _digit('4')), key('5', onTap: () => _digit('5')), key('6', onTap: () => _digit('6')), key('⌫', onTap: _back, color: const Color(0xFF3A4A5C))]),
            Row(children: [key('7', onTap: () => _digit('7')), key('8', onTap: () => _digit('8')), key('9', onTap: () => _digit('9')), key('00', onTap: () => _digit('00'))]),
            Row(children: [key('0', onTap: () => _digit('0'), flex: 3), const Expanded(child: SizedBox())]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _pence <= 0 ? null : () => Navigator.pop(context, _pence),
          child: const Text('Save amount'),
        ),
      ],
    );
  }
}

class _HourlyReportDialog extends StatelessWidget {
  const _HourlyReportDialog({required this.report, required this.onPrint});

  final HourlySalesReport report;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Hourly Report'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sales by hour · ${report.source == 'server' ? 'server' : 'this till'}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (report.hours.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No sales recorded yet today')),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowHeight: 36,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 40,
                    columns: const [
                      DataColumn(label: Text('Hours')),
                      DataColumn(label: Text('Sales'), numeric: true),
                      DataColumn(label: Text('Sales %'), numeric: true),
                    ],
                    rows: [
                      for (final h in report.hours)
                        DataRow(cells: [
                          DataCell(Text(h.label)),
                          DataCell(Text(formatPence(h.amountPence))),
                          DataCell(Text(h.percent.toStringAsFixed(2))),
                        ]),
                    ],
                  ),
                ),
              ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total of the Day', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  '${formatPence(report.totalPence)}  ·  100.00%',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Exit')),
        FilledButton.icon(onPressed: report.hours.isEmpty ? null : onPrint, icon: const Icon(Icons.print_outlined, size: 18), label: const Text('Print')),
      ],
    );
  }
}
