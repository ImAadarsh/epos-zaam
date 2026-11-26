import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hardware/printer/printer_service.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/settings.dart';
import '../../data/repositories/settings_repository.dart';

/// Direct Sale popup for cash drawer — same pattern as the Printer dialog.
Future<void> showCashDrawerDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1A222D),
        title: const Text(
          'Cash drawer',
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
              child: const _CashDrawerPanel(),
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

class _CashDrawerPanel extends ConsumerWidget {
  const _CashDrawerPanel();

  bool _canKick(PosSettings s) =>
      s.printerType == PrinterType.usb || s.printerType == PrinterType.network;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final canKick = _canKick(s);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Open drawer on cash sales'),
          subtitle: Text(
            canKick
                ? 'Drawer opens when cash is taken'
                : 'Needs Printer → USB ESC/POS (Chrome) — System print dialog cannot kick the drawer',
          ),
          value: s.openDrawerOnCash,
          onChanged: (v) => ctrl.update((x) => x.copyWith(openDrawerOnCash: v)),
        ),
        if (!canKick)
          const ListTile(
            leading: Icon(Icons.warning_amber, color: Color(0xFFFFB020)),
            title: Text('Drawer will not open with this printer mode'),
            subtitle: Text(
              'Open Printer, choose “USB ESC/POS printer (Chrome)”, tap Connect, then Test open drawer here.',
            ),
          ),
        ListTile(
          leading: const Icon(Icons.inbox_outlined),
          title: const Text('Test open drawer'),
          subtitle: Text(
            canKick
                ? 'Send a kick now — drawer should open'
                : 'Set Printer to USB or Network ESC/POS first',
          ),
          enabled: canKick,
          onTap: !canKick
              ? null
              : () async {
                  try {
                    await ref.read(printerServiceProvider).openDrawer();
                    if (context.mounted) showMessage(context, 'Drawer kick sent — drawer should open');
                  } catch (e) {
                    if (context.mounted) showMessage(context, '$e', error: true);
                  }
                },
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('How to connect'),
          subtitle: Text(
            'Please connect the drawer to the printer DK (RJ11) port.',
          ),
        ),
      ],
    );
  }
}
