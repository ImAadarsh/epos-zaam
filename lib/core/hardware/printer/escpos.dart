import 'dart:convert';
import 'dart:typed_data';

import 'receipt.dart';

/// Minimal ESC/POS encoder covering what receipts need on common 58/80mm
/// thermal printers (Epson TM, Star in ESC/POS mode, Xprinter, Munbyn, ...).
class EscPosEncoder {
  EscPosEncoder({this.paperWidth = 80}) : columns = paperWidth >= 80 ? 48 : 32;

  final int paperWidth;
  final int columns;
  final _b = BytesBuilder();

  static const _esc = 0x1B;
  static const _gs = 0x1D;

  void init() => _b.add([_esc, 0x40, _esc, 0x74, 0x10]); // reset, code page WPC1252

  void align(int a) => _b.add([_esc, 0x61, a]); // 0 left, 1 centre, 2 right
  void bold(bool on) => _b.add([_esc, 0x45, on ? 1 : 0]);
  void size(int w, int h) => _b.add([_gs, 0x21, ((w - 1) << 4) | (h - 1)]);
  void feed([int lines = 1]) => _b.add([_esc, 0x64, lines]);
  void cut() => _b.add([_gs, 0x56, 0x42, 0x00]);
  void openDrawer() => _b.add([_esc, 0x70, 0x00, 0x19, 0xFA]);

  void text(String s) {
    _b.add(_encode(s));
    _b.addByte(0x0A);
  }

  List<int> _encode(String s) {
    final out = <int>[];
    for (final r in s.runes) {
      if (r == 0x00A3) {
        out.add(0xA3); // £ in WPC1252
      } else if (r < 0x80) {
        out.add(r);
      } else if (r == 0x2013 || r == 0x2014) {
        out.add(0x2D);
      } else if (r == 0x2022) {
        out.add(0x2A);
      } else {
        out.add(r <= 0xFF ? r : 0x3F);
      }
    }
    return out;
  }

  void twoColumn(String left, String right, {int width = 1}) {
    final cols = columns ~/ width;
    if (right.isEmpty) {
      text(left);
      return;
    }
    final space = cols - right.length - 1;
    if (left.length > space) {
      text(left);
      text(right.padLeft(cols));
    } else {
      text('${left.padRight(space)} $right');
    }
  }

  void barcode128(String data) {
    final bytes = ascii.encode(data.replaceAll(RegExp(r'[^\x20-\x7E]'), ''));
    _b.add([_gs, 0x68, 60, _gs, 0x77, 2, _gs, 0x48, 2]);
    _b.add([_gs, 0x6B, 73, bytes.length + 2, 0x7B, 0x42, ...bytes]);
    _b.addByte(0x0A);
  }

  void qr(String data) {
    final bytes = utf8.encode(data);
    final len = bytes.length + 3;
    _b.add([_gs, 0x28, 0x6B, 4, 0, 0x31, 0x41, 0x32, 0x00]);
    _b.add([_gs, 0x28, 0x6B, 3, 0, 0x31, 0x43, 6]);
    _b.add([_gs, 0x28, 0x6B, 3, 0, 0x31, 0x45, 0x31]);
    _b.add([_gs, 0x28, 0x6B, len & 0xFF, len >> 8, 0x31, 0x50, 0x30, ...bytes]);
    _b.add([_gs, 0x28, 0x6B, 3, 0, 0x31, 0x51, 0x30]);
  }

  Uint8List bytes() => _b.toBytes();

  /// Renders a whole receipt, including the barcode and drawer kick.
  static Uint8List render(ReceiptDoc doc, {int paperWidth = 80, bool cutPaper = true}) {
    final e = EscPosEncoder(paperWidth: paperWidth)..init();
    if (doc.openDrawer) e.openDrawer();
    for (final row in doc.rows) {
      switch (row.style) {
        case ReceiptStyle.large:
          e.align(row.right.isEmpty ? 1 : 0);
          e.bold(true);
          e.size(2, 2);
          e.twoColumn(row.left, row.right, width: 2);
          e.size(1, 1);
          e.bold(false);
          e.align(0);
        case ReceiptStyle.center:
          e.align(1);
          e.text(row.left);
          e.align(0);
        case ReceiptStyle.centerBold:
          e.align(1);
          e.bold(true);
          e.text(row.left);
          e.bold(false);
          e.align(0);
        case ReceiptStyle.bold:
          e.bold(true);
          e.twoColumn(row.left, row.right);
          e.bold(false);
        case ReceiptStyle.divider:
          e.text('-' * e.columns);
        case ReceiptStyle.gap:
          e.feed(1);
        case ReceiptStyle.normal:
        case ReceiptStyle.small:
          e.twoColumn(row.left, row.right);
      }
    }
    if (doc.barcode != null) {
      e.feed(1);
      e.align(1);
      e.barcode128(doc.barcode!);
      e.align(0);
    }
    if (doc.qr != null) {
      e.align(1);
      e.qr(doc.qr!);
      e.align(0);
    }
    e.feed(4);
    if (cutPaper) e.cut();
    return e.bytes();
  }

  /// Just the drawer kick (for "No sale").
  static Uint8List drawerOnly() => (EscPosEncoder()
        ..init()
        ..openDrawer())
      .bytes();
}
