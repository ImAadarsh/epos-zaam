import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/hardware/printer/printer_service.dart';
import '../../core/scanner/scan_bus.dart';
import '../../core/scanner/socket_scanner.dart';
import '../../core/sync/sync_service.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/settings.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/models/org.dart';
import '../sell/widgets/vat_dialog.dart';
import 'staff_pins_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final session = ref.watch(sessionProvider);
    final register = ref.watch(currentRegisterProvider);
    final theme = Theme.of(context);
    final socket = ref.watch(socketScannerProvider);
    void set(PosSettings Function(PosSettings) f) => ctrl.update(f);

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(t.toUpperCase(), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        );
    Widget toggle(String title, bool value, ValueChanged<bool> onChanged, {String? subtitle}) =>
        SwitchListTile(title: Text(title), subtitle: subtitle == null ? null : Text(subtitle), value: value, onChanged: onChanged);
    Widget card(List<Widget> children) => Card(child: Column(children: children));

    Future<void> editText(String title, String initial, ValueChanged<String> onSave, {TextInputType? type, bool secret = false}) async {
      final v = await promptText(context, title: title, initial: secret ? '' : initial, hint: secret && initial.isNotEmpty ? '•••• (saved, enter to replace)' : null, keyboardType: type, allowEmpty: true);
      if (v != null && (!secret || v.isNotEmpty)) onSave(v);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
            children: [
              header('Payment types'),
              card([
                toggle('Cash', s.cashEnabled, (v) => set((x) => x.copyWith(cashEnabled: v))),
                toggle('Show prompt for cash', s.cashPrompt, (v) => set((x) => x.copyWith(cashPrompt: v)), subtitle: 'Confirm the amount and change before recording cash'),
                const Divider(),
                toggle('Card', s.cardEnabled, (v) => set((x) => x.copyWith(cardEnabled: v))),
                toggle('Show prompt for card', s.cardPrompt, (v) => set((x) => x.copyWith(cardPrompt: v)), subtitle: 'Confirm before sending the amount to an integrated reader'),
                const Divider(),
                toggle('Other payments', s.otherEnabled, (v) => set((x) => x.copyWith(otherEnabled: v)), subtitle: 'Vouchers, on account, bank transfer'),
                toggle('Tips on card payments', s.tipsEnabled, (v) => set((x) => x.copyWith(tipsEnabled: v))),
              ]),
              header('Card provider'),
              card([
                RadioGroup<CardProviderType>(
                  groupValue: s.cardProvider,
                  onChanged: (v) => set((x) => x.copyWith(cardProvider: v)),
                  child: Column(children: [
                    for (final p in CardProviderType.values) RadioListTile<CardProviderType>(value: p, title: Text(p.label)),
                  ]),
                ),
                if (s.cardProvider == CardProviderType.sumupSolo) ...[
                  const Divider(),
                  ListTile(
                    title: const Text('SumUp API key'),
                    subtitle: Text(s.sumupApiKey.isEmpty ? 'Not set' : 'Saved on this device only'),
                    trailing: const Icon(Icons.key),
                    onTap: () => editText('SumUp API key (sup_sk_…)', s.sumupApiKey, (v) => set((x) => x.copyWith(sumupApiKey: v)), secret: true),
                  ),
                  ListTile(
                    title: const Text('Merchant code'),
                    subtitle: Text(s.sumupMerchantCode.isEmpty ? 'Not set' : s.sumupMerchantCode),
                    onTap: () => editText('SumUp merchant code', s.sumupMerchantCode, (v) => set((x) => x.copyWith(sumupMerchantCode: v))),
                  ),
                  ListTile(
                    title: const Text('Reader ID'),
                    subtitle: Text(s.sumupReaderId.isEmpty ? 'Pair the Solo in the SumUp dashboard, then paste its reader ID' : s.sumupReaderId),
                    onTap: () => editText('SumUp reader ID', s.sumupReaderId, (v) => set((x) => x.copyWith(sumupReaderId: v))),
                  ),
                ],
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Other providers'),
                  subtitle: Text('iZettle, Adyen, Payment Express and Paymentsense can be used today as a standalone terminal. Integrated drivers are planned.'),
                ),
              ]),
              header('General'),
              card([
                toggle('Eat in / take away', s.eatInTakeAway, (v) => set((x) => x.copyWith(eatInTakeAway: v))),
                toggle('Enter float after closing register', s.floatAfterClose, (v) => set((x) => x.copyWith(floatAfterClose: v))),
                toggle('Allergen popup', s.allergenPopup, (v) => set((x) => x.copyWith(allergenPopup: v)), subtitle: 'Ask about allergies on the first item of each sale'),
                toggle('Sell beyond stock', s.sellBeyondStock, (v) => set((x) => x.copyWith(sellBeyondStock: v)),
                    subtitle: 'Off: a sale can never hold more units than this register has in stock'),
                if (s.sellBeyondStock) toggle('Out-of-stock prompt', s.outOfStockPrompt, (v) => set((x) => x.copyWith(outOfStockPrompt: v))),
                toggle('QR scanner after order', s.qrAfterOrder, (v) => set((x) => x.copyWith(qrAfterOrder: v))),
                toggle('Table QR button', s.tableQrButton, (v) => set((x) => x.copyWith(tableQrButton: v))),
                toggle('Table timers', s.tableTimers, (v) => set((x) => x.copyWith(tableTimers: v)), subtitle: 'Show how long saved sales have been open'),
                toggle(
                  'VAT',
                  s.vatEnabled,
                  (v) => editSettingsVat(context, ref, enable: v),
                  subtitle: !s.vatEnabled
                      ? 'Off — sales charge no VAT'
                      : s.vatRate == null
                          ? 'On — each product uses its own rate'
                          : 'On — ${formatVatPercent(s.vatRate!)} on every item',
                ),
                if (s.vatEnabled)
                  ListTile(
                    title: const Text('VAT rate'),
                    subtitle: Text(
                      s.vatRate == null
                          ? 'Each product uses its own rate. Tap to use 20% or an organisation tax code.'
                          : '${formatVatPercent(s.vatRate!)} · tap to pick 20% or an organisation tax code',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => editSettingsVat(context, ref, enable: true),
                  ),
                toggle('Prices include VAT', s.pricesIncludeTax, (v) => set((x) => x.copyWith(pricesIncludeTax: v)),
                    subtitle: 'On: shelf prices already include VAT (UK retail). Off: VAT is added on top.'),
                ListTile(
                  title: const Text('Cashier discount limit'),
                  subtitle: Text('${s.maxCashierDiscountPercent}% · higher discounts need a manager PIN'),
                  onTap: () => editText('Max cashier discount %', '${s.maxCashierDiscountPercent}', (v) {
                    final n = int.tryParse(v);
                    if (n != null) set((x) => x.copyWith(maxCashierDiscountPercent: n.clamp(0, 100)));
                  }, type: TextInputType.number),
                ),
                ListTile(
                  title: const Text('Auto-lock'),
                  subtitle: Text(s.autoLockSeconds == 0 ? 'Off' : 'After ${s.autoLockSeconds ~/ 60} min idle'),
                  onTap: () async {
                    final v = await pickOption<int>(context, title: 'Auto-lock after', options: const [(0, 'Off'), (60, '1 minute'), (300, '5 minutes'), (900, '15 minutes')]);
                    if (v != null) set((x) => x.copyWith(autoLockSeconds: v));
                  },
                ),
              ]),
              header('Receipts'),
              card([
                toggle('Prompt for email / print receipt', s.receiptPrompt, (v) => set((x) => x.copyWith(receiptPrompt: v))),
                if (!s.receiptPrompt)
                  ListTile(
                    title: const Text('When not prompting'),
                    subtitle: Text(switch (s.receiptDefault) { ReceiptDefault.print => 'Always print', ReceiptDefault.email => 'Email if customer has an email', _ => 'No receipt' }),
                    onTap: () async {
                      final v = await pickOption<ReceiptDefault>(context, title: 'Default receipt', options: const [
                        (ReceiptDefault.print, 'Always print'),
                        (ReceiptDefault.email, 'Email if customer has an email'),
                        (ReceiptDefault.none, 'No receipt'),
                      ]);
                      if (v != null) set((x) => x.copyWith(receiptDefault: v));
                    },
                  ),
                ListTile(
                  title: const Text('Receipt footer'),
                  subtitle: Text(s.receiptFooter.isEmpty ? 'None' : s.receiptFooter),
                  onTap: () => editText('Receipt footer', s.receiptFooter, (v) => set((x) => x.copyWith(receiptFooter: v))),
                ),
              ]),
              header('Printer & cash drawer'),
              card([
                RadioGroup<PrinterType>(
                  groupValue: s.printerType,
                  onChanged: (v) => set((x) => x.copyWith(printerType: v)),
                  child: Column(children: [
                    for (final p in PrinterType.values) RadioListTile<PrinterType>(value: p, title: Text(p.label)),
                  ]),
                ),
                if (s.printerType == PrinterType.network) ...[
                  ListTile(
                    title: const Text('Printer IP address'),
                    subtitle: Text(s.printerHost.isEmpty ? 'e.g. 192.168.1.50' : '${s.printerHost}:${s.printerPort}'),
                    onTap: () => editText('Printer IP (host or host:port)', s.printerHost.isEmpty ? '' : '${s.printerHost}:${s.printerPort}', (v) {
                      final parts = v.split(':');
                      set((x) => x.copyWith(printerHost: parts.first.trim(), printerPort: parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100));
                    }),
                  ),
                  toggle('Open drawer on cash sales', s.openDrawerOnCash, (v) => set((x) => x.copyWith(openDrawerOnCash: v))),
                  if (!ref.read(printerServiceProvider).networkSupported)
                    const ListTile(leading: Icon(Icons.warning_amber), title: Text('Browsers cannot reach network printers. Use USB ESC/POS (Chrome) or the system print dialog on web.')),
                ],
                if (s.printerType == PrinterType.usb) ...[
                  ListTile(
                    leading: Icon(ref.read(printerServiceProvider).usbIsConnected ? Icons.usb : Icons.usb_off),
                    title: Text(ref.read(printerServiceProvider).usbIsConnected ? 'Connected' : 'Not connected'),
                    subtitle: Text(() {
                      final p = ref.read(printerServiceProvider);
                      if (p.usbPrinter != null) return p.usbPrinter!.label;
                      if (s.usbVendorId != 0) {
                        return 'Last paired ${s.usbVendorId.toRadixString(16).padLeft(4, '0')}:${s.usbProductId.toRadixString(16).padLeft(4, '0')} — tap Connect to use';
                      }
                      return 'Chrome + HTTPS (or localhost). Pair once; Print after sales uses this printer.';
                    }()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('Connect USB printer'),
                    subtitle: const Text('Browser will ask you to pick the device'),
                    onTap: () async {
                      try {
                        final info = await ref.read(printerServiceProvider).connectUsbPrinter();
                        if (context.mounted) showMessage(context, 'Connected: ${info.label}');
                      } catch (e) {
                        if (context.mounted) showMessage(context, '$e', error: true);
                      }
                    },
                  ),
                  if (ref.read(printerServiceProvider).usbIsConnected || s.usbVendorId != 0)
                    ListTile(
                      leading: const Icon(Icons.link_off),
                      title: const Text('Disconnect'),
                      onTap: () async {
                        await ref.read(printerServiceProvider).disconnectUsbPrinter();
                        if (context.mounted) showMessage(context, 'USB printer disconnected');
                      },
                    ),
                  toggle('Open drawer on cash sales', s.openDrawerOnCash, (v) => set((x) => x.copyWith(openDrawerOnCash: v))),
                  if (!ref.read(printerServiceProvider).usbPrintingSupported)
                    const ListTile(leading: Icon(Icons.warning_amber), title: Text('WebUSB needs Chrome over HTTPS or localhost.')),
                ],
                ListTile(
                  title: const Text('Paper width'),
                  subtitle: Text('${s.paperWidth} mm'),
                  onTap: () async {
                    final v = await pickOption<int>(context, title: 'Paper width', options: const [(80, '80 mm'), (58, '58 mm')]);
                    if (v != null) set((x) => x.copyWith(paperWidth: v));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: const Text('Test print'),
                  onTap: () async {
                    try {
                      await ref.read(printerServiceProvider).testPrint();
                      if (context.mounted) showMessage(context, 'Test page sent');
                    } catch (e) {
                      if (context.mounted) showMessage(context, '$e', error: true);
                    }
                  },
                ),
              ]),
              header('Barcode scanner'),
              card([
                const ListTile(
                  leading: Icon(Icons.qr_code_scanner),
                  title: Text('Socket Mobile S700 / USB scanners (Basic mode)'),
                  subtitle: Text('Pair the scanner in this device\'s Bluetooth settings (it appears as a keyboard). '
                      'Scans go straight into the till, on the web app and installed app alike. No setup needed here.'),
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Setup guide'),
                  subtitle: const Text('Basic mode vs Application mode, step by step'),
                  onTap: () => showDialog<void>(context: context, builder: (_) => const _ScannerGuideDialog()),
                ),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Test scanner'),
                  subtitle: const Text('Scan any barcode to check it reaches the till'),
                  onTap: () => showDialog<void>(context: context, builder: (_) => const _ScanTestDialog()),
                ),
                if (socketCaptureAvailable) ...[
                  const Divider(),
                  toggle('Socket Mobile Application mode', s.socketCaptureEnabled, (v) => set((x) => x.copyWith(socketCaptureEnabled: v)),
                      subtitle: 'Uses CaptureJS + Socket Mobile Companion (Windows/Android) or the Rumba browser (iOS). '
                          'Keeps the on-screen keyboard and works whatever field has focus.'),
                  if (s.socketCaptureEnabled) ...[
                    ListTile(
                      title: const Text('App ID'),
                      subtitle: Text(s.socketAppId.isEmpty ? 'Not set' : s.socketAppId),
                      onTap: () => editText('App ID (e.g. web:epos.zaamaitech.co.uk)', s.socketAppId, (v) => set((x) => x.copyWith(socketAppId: v.trim()))),
                    ),
                    ListTile(
                      title: const Text('Developer ID'),
                      subtitle: Text(s.socketDeveloperId.isEmpty ? 'Not set' : s.socketDeveloperId),
                      onTap: () => editText('Developer ID', s.socketDeveloperId, (v) => set((x) => x.copyWith(socketDeveloperId: v.trim()))),
                    ),
                    ListTile(
                      title: const Text('AppKey'),
                      subtitle: Text(s.socketAppKey.isEmpty ? 'Not set' : 'Saved'),
                      onTap: () => editText('AppKey', s.socketAppKey, (v) => set((x) => x.copyWith(socketAppKey: v.trim())), secret: true),
                    ),
                    ListTile(
                      leading: Icon(
                        socket.state == SocketScannerState.connected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                        color: socket.state == SocketScannerState.connected
                            ? Colors.green
                            : (socket.state == SocketScannerState.error || socket.state == SocketScannerState.noService ? theme.colorScheme.error : null),
                      ),
                      title: Text(socket.label),
                      subtitle: socket.lastScan == null ? (socket.detail.isEmpty || socket.state == SocketScannerState.error ? null : Text(socket.detail)) : Text('Last scan: ${socket.lastScan}'),
                      trailing: TextButton(onPressed: () => ref.read(socketScannerProvider.notifier).retry(), child: const Text('Reconnect')),
                    ),
                  ],
                ],
              ]),
              header('Appearance'),
              card([
                ListTile(
                  title: const Text('Theme'),
                  subtitle: Text(switch (s.themeMode) { 'light' => 'Light', 'dark' => 'Dark', _ => 'Match device' }),
                  onTap: () async {
                    final v = await pickOption<String>(context, title: 'Theme', options: const [('system', 'Match device'), ('light', 'Light'), ('dark', 'Dark')]);
                    if (v != null) set((x) => x.copyWith(themeMode: v));
                  },
                ),
                toggle('Show product images', s.showProductImages, (v) => set((x) => x.copyWith(showProductImages: v))),
                ListTile(
                  title: const Text('Product grid columns'),
                  subtitle: Text(s.gridColumns == 0 ? 'Automatic' : '${s.gridColumns}'),
                  onTap: () async {
                    final v = await pickOption<int>(context, title: 'Columns', options: const [(0, 'Automatic'), (2, '2'), (3, '3'), (4, '4'), (5, '5'), (6, '6')]);
                    if (v != null) set((x) => x.copyWith(gridColumns: v));
                  },
                ),
              ]),
              header('Staff'),
              card([
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('Staff PINs & roles'),
                  subtitle: const Text('Set PINs used to unlock the till and approve refunds'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StaffPinsScreen())),
                ),
              ]),
              header('Server & device'),
              card([
                ListTile(title: const Text('Server'), subtitle: Text(session.baseUrl)),
                ListTile(title: const Text('Signed in as'), subtitle: Text(session.user?.email ?? '-')),
                ListTile(title: const Text('Register'), subtitle: Text(register == null ? '-' : '${register.name} (${register.code})')),
                ListTile(title: const Text('Device ID'), subtitle: Text(session.deviceId)),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('Re-download all products'),
                  onTap: () async {
                    await ref.read(syncServiceProvider).syncNow(fullCatalog: true);
                    if (context.mounted) showMessage(context, 'Products refreshed');
                  },
                ),
                ListTile(title: const Text('App version'), subtitle: Text(AppConfig.appVersion)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows each scan as it arrives, from any scanner source.
class _ScanTestDialog extends ConsumerStatefulWidget {
  const _ScanTestDialog();

  @override
  ConsumerState<_ScanTestDialog> createState() => _ScanTestDialogState();
}

class _ScanTestDialogState extends ConsumerState<_ScanTestDialog> {
  final _scans = <ScanEvent>[];
  late final StreamSubscription<ScanEvent> _sub;
  int _keys = 0;
  String _lastKeys = '';

  @override
  void initState() {
    super.initState();
    _sub = ref.read(scanBusProvider).stream.listen((e) => setState(() => _scans.insert(0, e)));
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _sub.cancel();
    super.dispose();
  }

  /// Counts raw keystrokes so a scanner that types nothing (not in Basic mode) is obvious.
  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && mounted) {
      final ch = e.character ?? (e.logicalKey == LogicalKeyboardKey.enter ? '⏎' : '');
      setState(() {
        _keys++;
        _lastKeys = (_lastKeys + ch).characters.takeLast(24).toString();
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Test scanner'),
      content: SizedBox(
        width: 380,
        height: 300,
        child: _scans.isEmpty
            ? Center(
                child: Text(
                  _keys == 0
                      ? 'Scan a barcode now…\n\nNo keystrokes received yet. If scanning shows nothing here, the scanner is not '
                          'in Basic (keyboard) mode: a scanner paired through the Socket Mobile Companion app is in '
                          'Application mode and types nothing into browsers. See Settings → Barcode scanner → Setup guide.'
                      : 'Keystrokes received: $_keys (last: $_lastKeys)\nbut no complete scan yet. Check the scanner ends '
                          'each scan with Enter, or scan again.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                children: [
                  for (final e in _scans)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(e.code, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(switch (e.source) {
                        ScanSource.socketMobile => 'Socket Mobile (Application mode)',
                        ScanSource.keyboardWedge => 'Scanner (Basic / HID mode)',
                        ScanSource.camera => 'Camera',
                        ScanSource.manual => 'Typed',
                      }),
                    ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}

class _ScannerGuideDialog extends StatelessWidget {
  const _ScannerGuideDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget h(String t) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(t, style: theme.textTheme.titleSmall));
    Widget p(String t) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t));
    return AlertDialog(
      title: const Text('Socket Mobile scanner setup'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            h('A. Basic mode (recommended, works in any browser, no keys needed)'),
            p('1. If the scanner was paired in the Socket Mobile Companion app, remove it there and in this device\'s Bluetooth settings.'),
            p('2. Put the scanner in Basic (HID keyboard) mode: in Companion choose the scanner → change mode to Basic / HID, '
                'or scan the "Basic mode (HID)" command barcode from the Socket Mobile quick-start guide for your model.'),
            p('3. Pair it in this device\'s Bluetooth settings (Windows: Settings → Bluetooth & devices → Add device). It shows as a keyboard.'),
            p('4. Settings → Barcode scanner → Test scanner, then scan. Each code appears with "Basic / HID mode".'),
            p('Tip: open Notepad and scan. If text appears there, the till will receive it too.'),
            h('B. Application mode (optional, Windows/Android with Companion, iOS with Rumba)'),
            p('1. Register at the Socket Mobile developer portal and create an AppKey for App ID web:epos.zaamaitech.co.uk.'),
            p('2. Keep Socket Mobile Companion running and pair the scanner in it.'),
            p('3. Turn on "Socket Mobile Application mode" here and enter the App ID, Developer ID and AppKey. The status line must show "Connected".'),
            p('Without the Developer ID and AppKey, Application mode stays off, and a scanner paired in Companion sends nothing to the browser.'),
            p('macOS: Companion/CaptureJS is not available; use Basic mode.'),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
