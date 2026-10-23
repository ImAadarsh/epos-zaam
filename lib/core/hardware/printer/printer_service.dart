import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../data/models/settings.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../utils/app_log.dart';
import 'escpos.dart';
import 'pdf_receipt.dart';
import 'receipt.dart';
import 'socket_io.dart' if (dart.library.js_interop) 'socket_web.dart';
import 'usb_stub.dart' if (dart.library.js_interop) 'usb_web.dart';

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
/// * usb — WebUSB ESC/POS in Chrome (PWA)
/// * bluetooth — needs a native plugin per platform; reported as not configured
class PrinterService {
  PrinterService(this._settings, {this.onUsbPaired});

  final PosSettings Function() _settings;

  /// Called after a successful WebUSB pair so the till can persist VID/PID.
  final void Function(UsbPrinterInfo info)? onUsbPaired;

  bool get networkSupported => rawSocketSupported;
  bool get usbPrintingSupported => usbSupported;
  bool get usbIsConnected => usbConnected;
  UsbPrinterInfo? get usbPrinter => currentUsbPrinter;

  Future<UsbPrinterInfo> connectUsbPrinter() async {
    if (!usbSupported) {
      throw PrinterException('USB printing needs Chrome over HTTPS (or localhost).');
    }
    try {
      final info = await requestPrinter();
      onUsbPaired?.call(info);
      return info;
    } on UnsupportedError catch (e) {
      throw PrinterException(e.message ?? 'USB printing is not supported here.');
    } catch (e) {
      throw PrinterException(_usbConnectError(e));
    }
  }

  static String _usbConnectError(Object e) {
    final s = e.toString();
    if (s.contains('Access denied') || s.contains('SecurityError')) {
      return 'Windows is blocking the USB printer (Access denied). '
          'Close any print queue / POS app using it, then in Device Manager find the printer '
          '(often under "USB Printing Support"), and use Zadig to install the WinUSB driver for that device. '
          'Unplug/replug, reopen Chrome, and tap Connect again.';
    }
    return 'Could not connect USB printer ($e).';
  }

  /// Re-opens a previously permitted WebUSB device (no picker).
  Future<UsbPrinterInfo?> reconnectUsbPrinter() async {
    if (!usbSupported) return null;
    final s = _settings();
    try {
      return await reconnectPrinter(vendorId: s.usbVendorId, productId: s.usbProductId);
    } catch (e) {
      AppLog.warn('USB reconnect: $e');
      return null;
    }
  }

  Future<void> disconnectUsbPrinter() => disconnectUsb();

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
      case PrinterType.usb:
        await _ensureUsb();
        try {
          await sendUsb(EscPosEncoder.render(doc, paperWidth: s.paperWidth));
        } on UnsupportedError catch (e) {
          throw PrinterException(e.message ?? 'USB printing is not supported here.');
        } catch (e) {
          throw PrinterException('USB printer did not respond ($e).');
        }
      case PrinterType.bluetooth:
        throw PrinterException('Bluetooth printers need the native printer plugin, which is not bundled yet. Use a network, USB, or system printer.');
    }
    AppLog.info('Printed $jobName via ${s.printerType.name}');
  }

  /// Kicks the cash drawer (drawer is wired to the receipt printer's kick port).
  Future<void> openDrawer() async {
    final s = _settings();
    switch (s.printerType) {
      case PrinterType.network:
        if (s.printerHost.trim().isEmpty) {
          throw PrinterException('A cash drawer needs a network ESC/POS printer configured in Settings → Printer.');
        }
        await sendRaw(s.printerHost.trim(), s.printerPort, EscPosEncoder.drawerOnly());
      case PrinterType.usb:
        await _ensureUsb();
        await sendUsb(EscPosEncoder.drawerOnly());
      default:
        throw PrinterException('A cash drawer needs a USB or network ESC/POS printer in Settings → Printer.');
    }
  }

  Future<void> _ensureUsb() async {
    if (!usbSupported) {
      throw PrinterException('USB printing needs Chrome over HTTPS (or localhost).');
    }
    if (usbConnected) return;
    final info = await reconnectUsbPrinter();
    if (info == null) {
      throw PrinterException('No USB printer connected. Open Settings → Printer and tap Connect USB printer.');
    }
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

final printerServiceProvider = Provider<PrinterService>((ref) {
  return PrinterService(
    () => ref.read(settingsProvider),
    onUsbPaired: (info) {
      ref.read(settingsProvider.notifier).update(
            (s) => s.copyWith(usbVendorId: info.vendorId, usbProductId: info.productId),
          );
    },
  );
});
