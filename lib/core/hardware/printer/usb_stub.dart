import 'dart:typed_data';

/// Info about a paired USB ESC/POS printer.
class UsbPrinterInfo {
  const UsbPrinterInfo({
    required this.vendorId,
    required this.productId,
    this.productName = '',
    this.manufacturerName = '',
  });

  final int vendorId;
  final int productId;
  final String productName;
  final String manufacturerName;

  String get label {
    final name = productName.isNotEmpty
        ? productName
        : 'USB ${vendorId.toRadixString(16).padLeft(4, '0')}:${productId.toRadixString(16).padLeft(4, '0')}';
    return manufacturerName.isNotEmpty ? '$manufacturerName $name' : name;
  }
}

const bool usbSupported = false;

bool get usbConnected => false;

UsbPrinterInfo? get currentUsbPrinter => null;

Future<UsbPrinterInfo> requestPrinter() async {
  throw UnsupportedError('USB printing is only available in Chrome (WebUSB).');
}

Future<UsbPrinterInfo?> reconnectPrinter({int? vendorId, int? productId}) async => null;

Future<void> sendUsb(Uint8List bytes) async {
  throw UnsupportedError('USB printing is only available in Chrome (WebUSB).');
}

Future<void> disconnectUsb() async {}
