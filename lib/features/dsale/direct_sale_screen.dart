import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/till_click.dart';
import '../../core/hardware/printer/printer_service.dart';
import '../../core/security/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../core/widgets/onscreen_keyboard.dart';
import '../../data/models/settings.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../register/open_register_card.dart';
import '../shell/app_shell.dart';
import '../shell/status_bar.dart';
import '../sell/widgets/cash_notes.dart';
import 'cash_drawer_dialog.dart';
import 'dsale_archive.dart';
import 'dsale_service.dart';
import 'printer_connect_dialog.dart';

void _click() => TillClick.play();

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
  /// Misc lines built with OK before SALE takes payment (qty defaults to 1).
  final List<DSaleMiscLine> _cart = [];
  bool _busy = false;
  String? _flash;
  bool _flashError = false;
  /// Bumps when USB reconnect / dialog closes so AppBar printer chip refreshes.
  int _printerTick = 0;

  int get _pence => int.tryParse(_digits) ?? 0;
  int get _cartTotalPence => _cart.fold(0, (a, l) => a + l.totalPence);

  @override
  void initState() {
    super.initState();
    // WebUSB drops the live handle on reload; re-open the saved device so the
    // header / dialog show the previously paired printer again.
    Future.microtask(_restorePrinterSession);
  }

  Future<void> _restorePrinterSession() async {
    final s = ref.read(settingsProvider);
    if (s.printerType != PrinterType.usb || s.usbVendorId == 0) return;
    final printer = ref.read(printerServiceProvider);
    if (printer.usbIsConnected) return;
    await printer.reconnectUsbPrinter();
    if (mounted) setState(() => _printerTick++);
  }

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
    if (_busy) {
      _flashMsg('Still finishing the last action — wait a moment', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      if (!session.isLoggedIn) {
        await ref.read(sessionProvider.notifier).forceLogout(reason: 'Not signed in during Direct Sale');
        if (mounted) _flashMsg('Session ended — sign in again', error: true);
        return;
      }
      final r = await action().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _flashMsg(r.message, error: r.error || !r.ok);
      if (r.ok && clearOnOk) setState(() => _digits = '');
    } on TimeoutException {
      if (mounted) _flashMsg('Sale timed out — check connection, then try again', error: true);
    } catch (e) {
      if (mounted) _flashMsg('Could not finish: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// OK on the keypad: add the typed amount as a Misc line (does not take payment).
  void _addMiscLine() {
    _click();
    if (_pence <= 0) {
      _flashMsg('Enter an amount, then press ADD (+)', error: true);
      return;
    }
    setState(() {
      _cart.add(DSaleMiscLine(unitPence: _pence, quantity: 1));
      _digits = '';
      _flash = 'Added Misc ${formatPence(_cart.last.unitPence)} · total ${formatPence(_cartTotalPence)}';
      _flashError = false;
    });
  }

  void _bumpQty(int index, int delta) {
    _click();
    if (index < 0 || index >= _cart.length) return;
    setState(() {
      final next = (_cart[index].quantity + delta).clamp(1, 99);
      _cart[index] = _cart[index].copyWith(quantity: next);
    });
  }

  void _removeCartLine(int index) {
    _click();
    if (index < 0 || index >= _cart.length) return;
    setState(() => _cart.removeAt(index));
  }

  void _clearCart() {
    _click();
    setState(() {
      _cart.clear();
      _digits = '';
      _flash = 'Misc lines cleared';
      _flashError = false;
    });
  }

  /// ARCHIVE SALE: set the current Misc cart aside (unpaid) so it can be reloaded later.
  Future<void> _archiveSale() async {
    _click();
    final lines = List<DSaleMiscLine>.from(_cart);
    if (lines.isEmpty && _pence > 0) {
      lines.add(DSaleMiscLine(unitPence: _pence, quantity: 1));
    }
    if (lines.isEmpty) {
      _flashMsg('Nothing to archive — add amounts with ADD (+) first', error: true);
      return;
    }
    final total = lines.fold<int>(0, (a, l) => a + l.totalPence);
    await ref.read(dSaleArchiveProvider.notifier).archive(lines);
    if (!mounted) return;
    setState(() {
      _cart.clear();
      _digits = '';
      _flash = 'Sale archived · ${formatPence(total)}';
      _flashError = false;
    });
  }

  /// Reload an archived sale onto the till. A cart already in progress is archived (not lost).
  Future<void> _restoreArchived(ArchivedDSale sale) async {
    _click();
    final notifier = ref.read(dSaleArchiveProvider.notifier);
    final current = List<DSaleMiscLine>.from(_cart);
    await notifier.remove(sale.id);
    if (current.isNotEmpty) await notifier.archive(current);
    if (!mounted) return;
    setState(() {
      _cart
        ..clear()
        ..addAll(sale.lines);
      _digits = '';
      _flash = current.isEmpty
          ? 'Archived sale reloaded · ${formatPence(sale.totalPence)}'
          : 'Archived sale reloaded · previous cart archived';
      _flashError = false;
    });
  }

  Future<void> _discardArchived(ArchivedDSale sale) async {
    _click();
    final ok = await confirm(
      context,
      title: 'Discard archived sale?',
      message: 'Delete the archived ${formatPence(sale.totalPence)} sale (${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'})? This cannot be undone.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(dSaleArchiveProvider.notifier).remove(sale.id);
  }

  /// SALE: take payment for all Misc lines on the cart (or the keypad amount if cart empty).
  Future<void> _sale() async {
    _click();
    final lines = List<DSaleMiscLine>.from(_cart);
    if (lines.isEmpty && _pence > 0) {
      lines.add(DSaleMiscLine(unitPence: _pence, quantity: 1));
    }
    if (lines.isEmpty) {
      _flashMsg('Add amounts with ADD (+), then press SALE', error: true);
      return;
    }
    final due = lines.fold<int>(0, (a, l) => a + l.totalPence);
    final tendered = await showCashTenderDialog(context, amountDuePence: due, playClick: true);
    if (!mounted || tendered == null) return;
    await _run(() async {
      final r = await ref.read(dSaleServiceProvider).completeSale(due, tenderedPence: tendered, lines: lines);
      if (r.ok && mounted) setState(() => _cart.clear());
      return r;
    });
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
    final amount = _pence;
    final reason = await promptTextWithKeyboard(
      context,
      title: 'Payout reason / info',
      subtitle: 'Take ${formatPence(amount)} out of the drawer — add a short note',
      hint: 'e.g. milk, lottery, supplier',
      allowEmpty: true,
      confirmLabel: 'Confirm payout',
    );
    if (reason == null || !mounted) return;
    final ok = await confirm(
      context,
      title: 'Direct Sale payout',
      message: reason.isEmpty
          ? 'Take ${formatPence(amount)} out of the drawer?'
          : 'Take ${formatPence(amount)} out of the drawer?\n\nReason: $reason',
      confirmLabel: 'Confirm payout',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() => ref.read(dSaleServiceProvider).payout(amount, reason: reason.isEmpty ? null : reason));
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

  void _backToModules() {
    _click();
    ref.read(shellTabProvider.notifier).go(0);
  }

  bool _printerReady(PosSettings s, PrinterService printer) {
    switch (s.printerType) {
      case PrinterType.none:
        return false;
      case PrinterType.usb:
        return printer.usbIsConnected || s.usbVendorId != 0;
      case PrinterType.network:
        return s.printerHost.trim().isNotEmpty;
      case PrinterType.system:
      case PrinterType.bluetooth:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(shiftProvider);
    // Rebuild when local sales change so the last-receipt label stays live.
    ref.watch(localSalesProvider);
    final settings = ref.watch(settingsProvider);
    final archived = ref.watch(dSaleArchiveProvider);
    // Keep analyzer/lints happy: tick is only used to force rebuild after reconnect.
    final _ = _printerTick;
    final recent = ref.read(dSaleServiceProvider).recentSales(limit: 1);
    final lastPrintable = recent.isNotEmpty ? recent.first : null;
    final theme = Theme.of(context);
    final printer = ref.read(printerServiceProvider);
    final printerReady = _printerReady(settings, printer);

    final appBar = AppBar(
      leading: IconButton(
        tooltip: 'Back to Ethos modules',
        icon: const Icon(Icons.arrow_back),
        onPressed: _backToModules,
      ),
      title: const Text('Direct Sale'),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: printerReady
                ? 'Printer connected — tap to manage'
                : 'Printer not connected — tap to connect',
            child: TextButton.icon(
              onPressed: () async {
                _click();
                await showPrinterConnectDialog(context);
                if (mounted) setState(() => _printerTick++);
              },
              icon: Icon(
                printerReady ? Icons.print : Icons.print_outlined,
                color: printerReady ? ZaamColors.green : Colors.white70,
                size: 22,
              ),
              label: Text(
                printerReady ? 'Printer' : 'No printer',
                style: TextStyle(
                  color: printerReady ? ZaamColors.green : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 40),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: settings.openDrawerOnCash
                ? 'Cash drawer enabled — tap to manage / test'
                : 'Cash drawer off — tap to enable (opens via printer)',
            child: TextButton.icon(
              onPressed: () async {
                _click();
                await showCashDrawerDialog(context);
                if (mounted) setState(() => _printerTick++);
              },
              icon: Icon(
                settings.openDrawerOnCash ? Icons.inbox : Icons.inbox_outlined,
                color: settings.openDrawerOnCash && printerReady ? ZaamColors.green : Colors.white70,
                size: 22,
              ),
              label: Text(
                settings.openDrawerOnCash ? 'Drawer' : 'Drawer off',
                style: TextStyle(
                  color: settings.openDrawerOnCash && printerReady ? ZaamColors.green : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 40),
              ),
            ),
          ),
        ),
        const ShellStatusActions(),
      ],
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
              cartTotalPence: _cartTotalPence,
              cartCount: _cart.length,
              flash: _flash,
              flashError: _flashError,
              lastLabel: lastPrintable == null
                  ? 'No sales yet on this till'
                  : 'Last: ${lastPrintable.receiptNumber} · ${formatPence(lastPrintable.totalPence)}',
              busy: _busy,
            );
            final cartPanel = _MiscCartPanel(
              lines: _cart,
              enabled: !_busy,
              onBumpQty: _bumpQty,
              onRemove: _removeCartLine,
              onClear: _cart.isEmpty ? null : _clearCart,
            );
            final pad = _Numpad(
              onDigit: _digit,
              onBack: _back,
              onClear: _clear,
              onOk: _addMiscLine,
              onArchive: _archiveSale,
              enabled: !_busy,
            );
            final archivePanel = archived.isEmpty
                ? null
                : _ArchivePanel(sales: archived, enabled: !_busy, onRestore: _restoreArchived, onDiscard: _discardArchived);
            final actions = _ActionColumn(
              onSale: _busy ? null : _sale,
              onPrint: _busy ? null : _print,
              onPayout: _busy ? null : _payout,
              onHourly: _busy ? null : _hourly,
              saleSub: _cart.isEmpty ? 'ADD (+) first' : 'Total ${formatPence(_cartTotalPence)}',
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
                          // Full left column for Misc — Last 5 Sales panel removed.
                          Expanded(child: cartPanel),
                          // Only visible once at least one sale is archived.
                          if (archivePanel != null) ...[
                            const SizedBox(height: 10),
                            SizedBox(height: 140, child: archivePanel),
                          ],
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
                  Expanded(flex: 2, child: cartPanel),
                  if (archivePanel != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(height: 110, child: archivePanel),
                  ],
                  const SizedBox(height: 8),
                  Expanded(flex: 3, child: pad),
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
    required this.cartTotalPence,
    required this.cartCount,
    required this.flash,
    required this.flashError,
    required this.lastLabel,
    required this.busy,
  });

  final String display;
  final int pence;
  final int cartTotalPence;
  final int cartCount;
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
            'Type amount → ADD (+ ) for Misc · SALE to take payment',
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
          Row(
            children: [
              Expanded(
                child: Text(lastLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white38)),
              ),
              if (cartCount > 0)
                Text(
                  'Cart ${formatPence(cartTotalPence)} · $cartCount',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ZaamColors.gold, fontWeight: FontWeight.w700),
                ),
            ],
          ),
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

/// Pending Misc amounts before SALE (numbers + qty only — no product names).
class _MiscCartPanel extends StatelessWidget {
  const _MiscCartPanel({
    required this.lines,
    required this.enabled,
    required this.onBumpQty,
    required this.onRemove,
    this.onClear,
  });

  final List<DSaleMiscLine> lines;
  final bool enabled;
  final void Function(int index, int delta) onBumpQty;
  final ValueChanged<int> onRemove;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final total = lines.fold(0, (a, l) => a + l.totalPence);
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
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  'MISC ITEMS',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: ZaamColors.gold,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                if (lines.isNotEmpty)
                  Text(
                    formatPence(total),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                if (onClear != null)
                  IconButton(
                    tooltip: 'Clear all',
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? onClear : null,
                    icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 20),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2A3340)),
          Expanded(
            child: lines.isEmpty
                ? const Center(
                    child: Text('ADD (+) puts Misc amounts here', style: TextStyle(color: Colors.white38)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1E2630)),
                    itemBuilder: (context, i) {
                      final line = lines[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatPence(line.unitPence),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: enabled ? () => onBumpQty(i, -1) : null,
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.white54, size: 22),
                            ),
                            Text(
                              '${line.quantity}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: enabled ? () => onBumpQty(i, 1) : null,
                              icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 22),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatPence(line.totalPence),
                              style: const TextStyle(color: ZaamColors.gold, fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: enabled ? () => onRemove(i) : null,
                              icon: Icon(Icons.close, color: ZaamColors.red.withValues(alpha: 0.85), size: 18),
                            ),
                          ],
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

/// Archived (unpaid) sales. Shown on the left only while at least one exists.
class _ArchivePanel extends StatelessWidget {
  const _ArchivePanel({required this.sales, required this.enabled, required this.onRestore, required this.onDiscard});

  final List<ArchivedDSale> sales;
  final bool enabled;
  final ValueChanged<ArchivedDSale> onRestore;
  final ValueChanged<ArchivedDSale> onDiscard;

  static const _purple = Color(0xFFB79CFF);

  String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12171E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7A4FD1).withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 16, color: _purple),
                const SizedBox(width: 6),
                Text(
                  'ARCHIVED SALES',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: _purple, letterSpacing: 1.1, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text('${sales.length}', style: const TextStyle(color: _purple, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2A3340)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: sales.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1E2630)),
              itemBuilder: (context, i) {
                final s = sales[i];
                return InkWell(
                  onTap: enabled ? () => onRestore(s) : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                    child: Row(
                      children: [
                        Text(_time(s.archivedAt), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${s.itemCount} item${s.itemCount == 1 ? '' : 's'}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                        Text(formatPence(s.totalPence), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(width: 6),
                        const Icon(Icons.restore, size: 18, color: _purple),
                        IconButton(
                          tooltip: 'Discard',
                          visualDensity: VisualDensity.compact,
                          onPressed: enabled ? () => onDiscard(s) : null,
                          icon: Icon(Icons.close, color: ZaamColors.red.withValues(alpha: 0.85), size: 18),
                        ),
                      ],
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
    required this.onArchive,
    required this.enabled,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final VoidCallback onOk;
  final VoidCallback onArchive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(
      String label, {
      VoidCallback? onTap,
      Color? color,
      Color? fg,
      int flex = 1,
      IconData? icon,
      bool small = false,
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
                child: icon == null
                    ? Text(
                        label,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: fg ?? Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      )
                    : small
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, color: fg ?? Colors.white, size: 24),
                              const SizedBox(height: 4),
                              const Text(
                                'HOLD',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.3),
                              ),
                              Text('SALE', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700, fontSize: 11)),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, color: fg ?? Colors.white, size: 26),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      color: fg ?? Colors.white,
                                      fontWeight: FontWeight.w800,
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
            // Explicit ADD (+ icon) — adds Misc to the cart; SALE still takes payment.
            key('ADD', onTap: onOk, color: const Color(0xFF1F8A4C), icon: Icons.add),
          ]),
          row([
            key('0', onTap: () => onDigit('0')),
            key('00', onTap: () => onDigit('00'), flex: 2),
            key('HOLD', onTap: onArchive, color: const Color(0xFF7A4FD1), icon: Icons.inventory_2_outlined, small: true),
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
    this.saleSub = 'No auto-print',
  });

  final VoidCallback? onSale;
  final VoidCallback? onPrint;
  final VoidCallback? onPayout;
  final VoidCallback? onHourly;
  final String saleSub;

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
        action(label: 'SALE', sub: saleSub, color: const Color(0xFF1F8A4C), onTap: onSale, icon: Icons.shopping_bag_outlined),
        action(label: 'PRINT', sub: 'Last receipt', color: const Color(0xFF2F6FED), onTap: onPrint, icon: Icons.print_outlined),
        action(label: 'PAYOUT', sub: 'Reason + slip', color: const Color(0xFFC43C5A), onTap: onPayout, icon: Icons.outbox_outlined),
        action(label: 'HOURLY', sub: 'Early report', color: const Color(0xFFB8860B), onTap: onHourly, icon: Icons.schedule_outlined),
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
