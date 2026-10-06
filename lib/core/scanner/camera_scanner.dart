import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'camera_release_stub.dart' if (dart.library.js_interop) 'camera_release_web.dart';

bool get cameraScanSupported =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.macOS;

/// Retail product barcodes plus QR (tables, customers, receipts).
const _scanFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.itf14,
  BarcodeFormat.qrCode,
];

/// Opens the camera and returns the first barcode / QR code read, or null.
Future<String?> scanWithCamera(BuildContext context, {String title = 'Scan barcode'}) async {
  if (!cameraScanSupported) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Camera scanning is not available on this device. Use a USB/Bluetooth scanner or type the code.')),
    );
    return null;
  }
  final result = await Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _CameraScanPage(title: title)));
  releaseAllCameras();
  return result;
}

/// EAN-8/EAN-13/UPC-A check digit; other formats pass through.
bool _checksumOk(Barcode b) {
  final v = b.rawValue ?? '';
  final isEanUpc = b.format == BarcodeFormat.ean13 || b.format == BarcodeFormat.ean8 || b.format == BarcodeFormat.upcA;
  if (!isEanUpc || !RegExp(r'^\d{8}$|^\d{12,13}$').hasMatch(v)) return true;
  final digits = v.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    final fromRight = digits.length - i;
    sum += digits[i] * (fromRight.isOdd ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == check;
}

class _CameraScanPage extends StatefulWidget {
  const _CameraScanPage({required this.title});
  final String title;

  @override
  State<_CameraScanPage> createState() => _CameraScanPageState();
}

class _CameraScanPageState extends State<_CameraScanPage> {
  final _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: _scanFormats,
  );
  Future<void>? _starting;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _starting = _controller.start().catchError((_) {});
  }

  @override
  void dispose() {
    final controller = _controller;
    final starting = _starting;
    // Wait for a start still in progress, otherwise its stream outlives the page.
    unawaited(() async {
      await starting;
      try {
        await controller.stop();
      } catch (_) {}
      await controller.dispose();
      releaseAllCameras();
    }());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final barcode = capture.barcodes.where((b) => (b.rawValue ?? '').trim().isNotEmpty && _checksumOk(b)).firstOrNull;
    if (barcode == null) return;
    _done = true;
    Navigator.of(context).pop(barcode.rawValue!.trim());
  }

  Future<void> _typeCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'e.g. 5012345678900'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Use code')),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || code == null || code.isEmpty || _done) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(tooltip: 'Type code', icon: const Icon(Icons.keyboard_outlined), onPressed: _typeCode),
          if (!kIsWeb) IconButton(tooltip: 'Torch', icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _controller.toggleTorch()),
          IconButton(tooltip: 'Switch camera', icon: const Icon(Icons.cameraswitch_outlined), onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Camera unavailable: ${error.errorCode.name}.\nCheck camera permission in system settings.',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 300,
                height: 160,
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD4A017), width: 3), borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Text(
              'Hold the barcode flat, 10–20 cm from the camera, filling the box. Avoid glare.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
