import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display/customer_display.dart';
import '../../core/scanner/camera_scanner.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/sale.dart';
import '../../data/models/settings.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'checkout_service.dart';

/// Shown after payment succeeds. Auto-prints when [PosSettings.autoPrintReceipts] is on.
class SaleCompleteScreen extends ConsumerStatefulWidget {
  const SaleCompleteScreen({super.key, required this.sale});
  final SaleRecord sale;

  @override
  ConsumerState<SaleCompleteScreen> createState() => _SaleCompleteScreenState();
}

class _SaleCompleteScreenState extends ConsumerState<SaleCompleteScreen> {
  String? _receiptDone;
  bool _printedOk = false;
  bool _autoPrintStarted = false;

  static const _autoPrintFailMsg =
      'Sale saved. Printer not connected / print failed — use Print to retry';

  @override
  void initState() {
    super.initState();
    Future.microtask(_afterSale);
  }

  Future<void> _afterSale() async {
    final s = ref.read(settingsProvider);
    // Auto-print once on success (default on). Sale is already saved — never roll back on print failure.
    if (s.autoPrintReceipts) {
      await _print(auto: true);
    } else if (!s.receiptPrompt) {
      switch (s.receiptDefault) {
        case ReceiptDefault.print:
          await _print(auto: true);
        case ReceiptDefault.email:
          if (widget.sale.customerEmail != null) await _email(widget.sale.customerEmail!);
        case ReceiptDefault.ask:
        case ReceiptDefault.none:
          break;
      }
    }
    if (s.qrAfterOrder && mounted && cameraScanSupported) await _scanQr();
  }

  Future<void> _print({bool auto = false}) async {
    if (auto) {
      if (_autoPrintStarted) return;
      _autoPrintStarted = true;
    }
    final settings = ref.read(settingsProvider);
    if (settings.printerType == PrinterType.none) {
      if (!mounted) return;
      if (auto) {
        setState(() => _receiptDone = _autoPrintFailMsg);
        showMessage(context, _autoPrintFailMsg, error: true);
      } else {
        showMessage(context, 'No printer configured. Open Settings → Printer.', error: true);
      }
      return;
    }
    try {
      await ref.read(checkoutServiceProvider).printReceipt(widget.sale);
      if (mounted) {
        setState(() {
          _printedOk = true;
          _receiptDone = 'Receipt printed';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = auto ? _autoPrintFailMsg : 'Print failed: $e';
      setState(() => _receiptDone = auto ? _autoPrintFailMsg : _receiptDone);
      showMessage(context, msg, error: true);
    }
  }

  Future<void> _email([String? to]) async {
    final email = to ?? await promptText(context, title: 'Email receipt', initial: widget.sale.customerEmail, hint: 'customer@example.com', keyboardType: TextInputType.emailAddress, confirmLabel: 'Send');
    if (email == null || !email.contains('@')) return;
    await ref.read(checkoutServiceProvider).emailReceipt(widget.sale, email);
    if (mounted) setState(() => _receiptDone = 'Receipt will be emailed to $email');
  }

  /// "QR scanner after order": scan the customer's QR (e.g. email or loyalty code) to send the receipt.
  Future<void> _scanQr() async {
    final code = await scanWithCamera(context, title: 'Scan customer QR');
    if (code == null || !mounted) return;
    final value = code.startsWith('mailto:') ? code.substring(7) : code;
    if (value.contains('@')) {
      await _email(value);
    } else {
      showMessage(context, 'Scanned: $value');
    }
  }

  void _newSale() {
    ref.read(customerDisplayProvider).show(DisplayState(storeName: ref.read(bootstrapProvider).org?.name ?? ''));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sale = widget.sale;
    final settings = ref.watch(settingsProvider);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _newSale,
        const SingleActivator(LogicalKeyboardKey.keyP): () => _print(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.check_circle, size: 72, color: ZaamColors.green),
                      const SizedBox(height: 8),
                      Text('Sale complete', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                      Text('${sale.receiptNumber} · ${formatPence(sale.totalPence)}', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 24),
                      if (sale.changePence > 0)
                        Card(
                          color: ZaamColors.gold.withValues(alpha: 0.15),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(children: [
                              Text('Change due', style: theme.textTheme.titleMedium),
                              Text(formatPence(sale.changePence), style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800)),
                            ]),
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (_receiptDone != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _receiptDone!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _printedOk ? theme.colorScheme.primary : theme.colorScheme.error),
                          ),
                        ),
                      // Print stays available for reprints even after auto-print.
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: settings.printerType == PrinterType.none ? null : () => _print(),
                            icon: const Icon(Icons.print_outlined),
                            label: Text(_printedOk ? 'Reprint' : 'Print'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: OutlinedButton.icon(onPressed: () => _email(), icon: const Icon(Icons.email_outlined), label: const Text('Email'))),
                      ]),
                      const SizedBox(height: 10),
                      if (settings.qrAfterOrder && cameraScanSupported) ...[
                        OutlinedButton.icon(onPressed: _scanQr, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan customer QR')),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(height: 64, child: FilledButton.icon(onPressed: _newSale, icon: const Icon(Icons.add_shopping_cart), label: const Text('New sale'))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
