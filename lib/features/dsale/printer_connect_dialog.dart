import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hardware/printer/printer_service.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/settings.dart';
import '../../data/repositories/settings_repository.dart';

/// Direct Sale–only modal: mirrors Settings → Printer connect/configure flow
/// without navigating away. Does not replace or alter the Settings screen.
Future<void> showPrinterConnectDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1A222D),
        title: const Text(
          'Printer',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Theme(
              data: ThemeData(
                brightness: Brightness.dark,
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFF5B9CFF),
                  surface: Color(0xFF1A222D),
                  onSurface: Colors.white,
                ),
                listTileTheme: const ListTileThemeData(
                  iconColor: Colors.white70,
                  textColor: Colors.white,
                  subtitleTextStyle: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                radioTheme: RadioThemeData(
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return const Color(0xFF5B9CFF);
                    return Colors.white54;
                  }),
                ),
                switchTheme: SwitchThemeData(
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return const Color(0xFF5B9CFF);
                    return Colors.white70;
                  }),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return const Color(0xFF5B9CFF).withValues(alpha: 0.45);
                    return Colors.white24;
                  }),
                ),
                dividerColor: Colors.white12,
              ),
              child: const _PrinterConnectPanel(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done', style: TextStyle(color: Colors.white70)),
          ),
        ],
      );
    },
  );
}

/// Same connect controls as Settings → Printer (type, USB pair, IP, test print).
class _PrinterConnectPanel extends ConsumerStatefulWidget {
  const _PrinterConnectPanel();

  @override
  ConsumerState<_PrinterConnectPanel> createState() => _PrinterConnectPanelState();
}

class _PrinterConnectPanelState extends ConsumerState<_PrinterConnectPanel> {
  bool _reconnecting = false;

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_tryRestoreUsb);
  }

  Future<void> _tryRestoreUsb() async {
    final s = ref.read(settingsProvider);
    final printer = ref.read(printerServiceProvider);
    if (s.printerType != PrinterType.usb || s.usbVendorId == 0 || printer.usbIsConnected) return;
    setState(() => _reconnecting = true);
    await printer.reconnectUsbPrinter();
    if (mounted) setState(() => _reconnecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final printer = ref.read(printerServiceProvider);
    void set(PosSettings Function(PosSettings) f) => ctrl.update(f);

    Future<void> editText(String title, String initial, ValueChanged<String> onSave) async {
      final v = await promptText(context, title: title, initial: initial, allowEmpty: true);
      if (v != null) onSave(v);
    }

    String statusLine() {
      switch (s.printerType) {
        case PrinterType.none:
          return 'Printing is off';
        case PrinterType.usb:
          if (printer.usbIsConnected) {
            return printer.usbPrinter?.label ?? 'USB printer connected';
          }
          if (_reconnecting) return 'Reconnecting to saved USB printer…';
          if (s.usbVendorId != 0) {
            return 'Saved USB ${s.usbVendorId.toRadixString(16).padLeft(4, '0')}:${s.usbProductId.toRadixString(16).padLeft(4, '0')} — tap Connect if needed';
          }
          return 'No USB printer paired yet';
        case PrinterType.network:
          return s.printerHost.trim().isEmpty
              ? 'No network printer IP set'
              : 'Network ${s.printerHost.trim()}:${s.printerPort}';
        case PrinterType.system:
          return 'System print dialog';
        case PrinterType.bluetooth:
          return 'Bluetooth (not available on web)';
      }
    }

    final liveConnected = switch (s.printerType) {
      PrinterType.usb => printer.usbIsConnected,
      PrinterType.network => s.printerHost.trim().isNotEmpty,
      PrinterType.system || PrinterType.bluetooth => true,
      PrinterType.none => false,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(
            liveConnected ? Icons.print : Icons.print_disabled_outlined,
            color: liveConnected ? const Color(0xFF3DDC97) : Colors.white54,
          ),
          title: Text(liveConnected ? 'Ready' : 'Not connected', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(statusLine()),
        ),
        const Divider(height: 1),
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
          SwitchListTile(
            title: const Text('Open drawer on cash sales'),
            value: s.openDrawerOnCash,
            onChanged: (v) => set((x) => x.copyWith(openDrawerOnCash: v)),
          ),
          if (!printer.networkSupported)
            const ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('Browsers cannot reach network printers. Use USB ESC/POS (Chrome) or the system print dialog on web.'),
            ),
        ],
        if (s.printerType == PrinterType.usb) ...[
          ListTile(
            leading: Icon(printer.usbIsConnected ? Icons.usb : Icons.usb_off),
            title: Text(printer.usbIsConnected ? 'Connected' : (_reconnecting ? 'Reconnecting…' : 'Not connected')),
            subtitle: Text(() {
              if (printer.usbPrinter != null) return printer.usbPrinter!.label;
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
                _refresh();
                if (context.mounted) showMessage(context, 'Connected: ${info.label}');
              } catch (e) {
                if (context.mounted) showMessage(context, '$e', error: true);
              }
            },
          ),
          if (printer.usbIsConnected || s.usbVendorId != 0)
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Disconnect'),
              onTap: () async {
                await ref.read(printerServiceProvider).disconnectUsbPrinter();
                _refresh();
                if (context.mounted) showMessage(context, 'USB printer disconnected');
              },
            ),
          SwitchListTile(
            title: const Text('Open drawer on cash sales'),
            value: s.openDrawerOnCash,
            onChanged: (v) => set((x) => x.copyWith(openDrawerOnCash: v)),
          ),
          if (!printer.usbPrintingSupported)
            const ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('WebUSB needs Chrome over HTTPS or localhost.'),
            ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Windows “Access denied”?'),
            subtitle: Text(
              'The OS printer driver often locks the USB port. Close other apps using the printer, '
              'then install WinUSB for that device with Zadig (zadig.akeo.ie), unplug/replug, and Connect again.',
            ),
          ),
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
        if (s.printerType == PrinterType.usb || s.printerType == PrinterType.network)
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: const Text('Test open drawer'),
            subtitle: const Text('Please connect the drawer to the printer DK (RJ11) port.'),
            onTap: () async {
              try {
                await ref.read(printerServiceProvider).openDrawer();
                if (context.mounted) showMessage(context, 'Drawer kick sent — drawer should open');
              } catch (e) {
                if (context.mounted) showMessage(context, '$e', error: true);
              }
            },
          ),
      ],
    );
  }
}
