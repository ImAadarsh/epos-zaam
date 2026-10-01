import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../data/models/settings.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../utils/app_log.dart';
import 'escpos.dart';
import 'pdf_receipt.dart';
import 'receipt.dart';
import 'socket_io.dart' if (dart.library.js_interop) 'socket_web.dart';

class PrinterException implements Exception {
  PrinterException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Routes receipts to the configured printer.
///
/// * system — OS print dialog / AirPrint / PDF (every platform, incl. web)
/// * network — raw ESC/POS over TCP 9100 (native platforms)
/// * bluetooth — needs a native plugin per platform; reported as not configured
class PrinterService {
  PrinterService(this._settings);

  final PosSettings Function() _settings;

  bool get networkSupported => rawSocketSupported;

  Future<void> print(ReceiptDoc doc, {String jobName = 'Receipt'}) async {
    final s = _settings();
    switch (s.printerType) {
      case PrinterType.none:
        return;
      case PrinterType.system:
        final bytes = await renderReceiptPdf(doc, paperWidth: s.paperWidth);
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: jobName);
      case PrinterType.network:
        if (s.printerHost.trim().isEmpty) throw PrinterException('Set the printer IP address in Settings → Printer.');
        try {
          await sendRaw(s.printerHost.trim(), s.printerPort, EscPosEncoder.render(doc, paperWidth: s.paperWidth));
        } on UnsupportedError catch (e) {
          throw PrinterException(e.message ?? 'Network printing is not supported here.');
        } catch (e) {
          throw PrinterException('Printer ${s.printerHost}:${s.printerPort} did not respond ($e).');
        }
      case PrinterType.bluetooth:
        throw PrinterException('Bluetooth printers need the native printer plugin, which is not bundled yet. Use a network or system printer.');
    }
    AppLog.info('Printed $jobName via ${s.printerType.name}');
  }

  /// Kicks the cash drawer (drawer is wired to the receipt printer's RJ11 port).
  Future<void> openDrawer() async {
    final s = _settings();
    if (s.printerType != PrinterType.network || s.printerHost.trim().isEmpty) {
      throw PrinterException('A cash drawer needs a network ESC/POS printer configured in Settings → Printer.');
    }
    await sendRaw(s.printerHost.trim(), s.printerPort, EscPosEncoder.drawerOnly());
  }

  Future<void> testPrint() => print(
        const ReceiptDoc(rows: [
          ReceiptRow('Zaam EPOS', '', ReceiptStyle.large),
          ReceiptRow('Printer test', '', ReceiptStyle.centerBold),
          ReceiptRow('', '', ReceiptStyle.divider),
          ReceiptRow('Left', 'Right'),
          ReceiptRow('Price', '£12.34'),
          ReceiptRow('', '', ReceiptStyle.divider),
        ], barcode: 'TEST-0001'),
        jobName: 'Test print',
      );
}

final printerServiceProvider = Provider<PrinterService>((ref) => PrinterService(() => ref.read(settingsProvider)));
