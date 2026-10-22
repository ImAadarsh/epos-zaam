import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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

// Minimal WebUSB bindings — package:web 1.1.x exposes navigator.usb as JSObject only.

@JS()
@anonymous
extension type _USBDeviceFilter._(JSObject _) implements JSObject {
  external factory _USBDeviceFilter({int classCode});
}

@JS()
@anonymous
extension type _USBDeviceRequestOptions._(JSObject _) implements JSObject {
  external factory _USBDeviceRequestOptions({JSArray<_USBDeviceFilter> filters});
}

extension type _USB._(JSObject _) implements JSObject {
  external JSPromise<JSArray<_USBDevice>> getDevices();
  external JSPromise<_USBDevice> requestDevice(_USBDeviceRequestOptions options);
}

extension type _USBDevice._(JSObject _) implements JSObject {
  external int get vendorId;
  external int get productId;
  external String get productName;
  external String get manufacturerName;
  external bool get opened;
  external _USBConfiguration? get configuration;
  external JSArray<_USBConfiguration>? get configurations;
  external JSPromise<JSAny?> open();
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> selectConfiguration(int configurationValue);
  external JSPromise<JSAny?> claimInterface(int interfaceNumber);
  external JSPromise<JSAny?> releaseInterface(int interfaceNumber);
  external JSPromise<_USBOutTransferResult> transferOut(int endpointNumber, JSUint8Array data);
}

extension type _USBConfiguration._(JSObject _) implements JSObject {
  external int get configurationValue;
  external JSArray<_USBInterface> get interfaces;
}

extension type _USBInterface._(JSObject _) implements JSObject {
  external int get interfaceNumber;
  external bool get claimed;
  external _USBAlternateInterface get alternate;
  external JSArray<_USBAlternateInterface> get alternates;
}

extension type _USBAlternateInterface._(JSObject _) implements JSObject {
  external int get alternateSetting;
  external int get interfaceClass;
  external JSArray<_USBEndpoint> get endpoints;
}

extension type _USBEndpoint._(JSObject _) implements JSObject {
  external int get endpointNumber;
  external String get direction; // "in" | "out"
  external String get type; // "bulk" | "interrupt" | "isochronous"
  external int get packetSize;
}

extension type _USBOutTransferResult._(JSObject _) implements JSObject {
  external String get status;
  external int get bytesWritten;
}

_USB? get _usb {
  final nav = web.window.navigator as JSObject;
  if (!nav.has('usb')) return null;
  final raw = nav['usb'];
  if (raw == null || raw.isUndefinedOrNull) return null;
  return _USB._(raw as JSObject);
}

bool get usbSupported => _usb != null;

_USBDevice? _device;
int? _outEndpoint;
int? _interfaceNumber;

bool get usbConnected => _device != null && _outEndpoint != null;

UsbPrinterInfo? get currentUsbPrinter {
  final d = _device;
  if (d == null) return null;
  return UsbPrinterInfo(
    vendorId: d.vendorId,
    productId: d.productId,
    productName: d.productName,
    manufacturerName: d.manufacturerName,
  );
}

UsbPrinterInfo _info(_USBDevice d) => UsbPrinterInfo(
      vendorId: d.vendorId,
      productId: d.productId,
      productName: d.productName,
      manufacturerName: d.manufacturerName,
    );

Future<void> _claim(_USBDevice device) async {
  if (!device.opened) {
    await device.open().toDart;
  }
  final configs = device.configurations;
  if (configs == null || configs.length == 0) {
    throw StateError('USB printer has no configurations.');
  }

  // Prefer printer class (0x07), else first interface with a bulk OUT endpoint.
  _USBInterface? chosenIface;
  _USBAlternateInterface? chosenAlt;
  _USBEndpoint? chosenEp;
  int? configValue;

  for (var ci = 0; ci < configs.length; ci++) {
    final config = configs[ci];
    final ifaces = config.interfaces;
    for (var ii = 0; ii < ifaces.length; ii++) {
      final iface = ifaces[ii];
      final alts = iface.alternates;
      for (var ai = 0; ai < alts.length; ai++) {
        final alt = alts[ai];
        final eps = alt.endpoints;
        for (var ei = 0; ei < eps.length; ei++) {
          final ep = eps[ei];
          if (ep.direction != 'out' || ep.type != 'bulk') continue;
          final isPrinter = alt.interfaceClass == 0x07;
          if (chosenEp == null || isPrinter) {
            chosenIface = iface;
            chosenAlt = alt;
            chosenEp = ep;
            configValue = config.configurationValue;
            if (isPrinter) break;
          }
        }
        if (chosenEp != null && chosenAlt?.interfaceClass == 0x07) break;
      }
      if (chosenEp != null && chosenAlt?.interfaceClass == 0x07) break;
    }
    if (chosenEp != null && chosenAlt?.interfaceClass == 0x07) break;
  }

  if (chosenIface == null || chosenEp == null || configValue == null) {
    throw StateError('No bulk OUT endpoint found on this USB device. Is it an ESC/POS printer?');
  }

  if (device.configuration?.configurationValue != configValue) {
    await device.selectConfiguration(configValue).toDart;
  }
  if (!chosenIface.claimed) {
    await device.claimInterface(chosenIface.interfaceNumber).toDart;
  }

  _device = device;
  _interfaceNumber = chosenIface.interfaceNumber;
  _outEndpoint = chosenEp.endpointNumber;
}

Future<UsbPrinterInfo> requestPrinter() async {
  final usb = _usb;
  if (usb == null) {
    throw UnsupportedError('WebUSB is not available. Use Chrome over HTTPS (or localhost).');
  }
  // Empty filter matches all devices (Chrome). Also surface USB printer-class devices.
  final options = _USBDeviceRequestOptions(
    filters: <_USBDeviceFilter>[
      _USBDeviceFilter(classCode: 0x07),
      _USBDeviceFilter(),
    ].toJS,
  );
  final device = await usb.requestDevice(options).toDart;
  await _claim(device);
  return _info(device);
}

Future<UsbPrinterInfo?> reconnectPrinter({int? vendorId, int? productId}) async {
  final usb = _usb;
  if (usb == null) return null;
  if (usbConnected) return currentUsbPrinter;

  final devices = (await usb.getDevices().toDart).toDart;
  if (devices.isEmpty) return null;

  _USBDevice? match;
  if (vendorId != null && vendorId != 0 && productId != null && productId != 0) {
    for (final d in devices) {
      if (d.vendorId == vendorId && d.productId == productId) {
        match = d;
        break;
      }
    }
  }
  match ??= devices.first;

  await _claim(match);
  return _info(match);
}

Future<void> sendUsb(Uint8List bytes) async {
  var device = _device;
  final endpoint = _outEndpoint;
  if (device == null || endpoint == null) {
    throw StateError('No USB printer connected. Open Settings → Printer and tap Connect USB printer.');
  }
  if (!device.opened) {
    await _claim(device);
    device = _device!;
  }

  const chunk = 4096;
  var offset = 0;
  while (offset < bytes.length) {
    final end = (offset + chunk > bytes.length) ? bytes.length : offset + chunk;
    final slice = bytes.sublist(offset, end);
    final result = await device.transferOut(endpoint, slice.toJS).toDart;
    if (result.status != 'ok') {
      throw StateError('USB transfer failed (${result.status}).');
    }
    offset = end;
  }
}

Future<void> disconnectUsb() async {
  final device = _device;
  final iface = _interfaceNumber;
  _device = null;
  _outEndpoint = null;
  _interfaceNumber = null;
  if (device == null) return;
  try {
    if (iface != null && device.opened) {
      await device.releaseInterface(iface).toDart;
    }
  } catch (_) {}
  try {
    if (device.opened) await device.close().toDart;
  } catch (_) {}
}
