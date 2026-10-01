import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt.dart';

/// Renders a receipt on a roll-width PDF page (used for the system print dialog,
/// AirPrint, Windows/macOS printers and "save as PDF").
Future<Uint8List> renderReceiptPdf(ReceiptDoc doc, {int paperWidth = 80}) async {
  final pdf = pw.Document();
  final width = (paperWidth >= 80 ? 72 : 48) * PdfPageFormat.mm;
  final font = pw.Font.courier();
  final bold = pw.Font.courierBold();

  pw.Widget row(ReceiptRow r) {
    switch (r.style) {
      case ReceiptStyle.divider:
        return pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed));
      case ReceiptStyle.gap:
        return pw.SizedBox(height: 6);
      case ReceiptStyle.center:
      case ReceiptStyle.centerBold:
        return pw.Center(
          child: pw.Text(r.left, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: r.style == ReceiptStyle.centerBold ? bold : font, fontSize: 8)),
        );
      case ReceiptStyle.large:
        if (r.right.isEmpty) return pw.Center(child: pw.Text(r.left, style: pw.TextStyle(font: bold, fontSize: 13)));
        return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(r.left, style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.Text(r.right, style: pw.TextStyle(font: bold, fontSize: 11)),
        ]);
      case ReceiptStyle.normal:
      case ReceiptStyle.bold:
      case ReceiptStyle.small:
        final style = pw.TextStyle(font: r.style == ReceiptStyle.bold ? bold : font, fontSize: r.style == ReceiptStyle.small ? 7 : 8);
        return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Text(r.left, style: style)),
          if (r.right.isNotEmpty) pw.Text(r.right, style: style),
        ]);
    }
  }

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat(width, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        ...doc.rows.map(row),
        if (doc.barcode != null) ...[
          pw.SizedBox(height: 8),
          pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: doc.barcode!, width: width * 0.8, height: 36, textStyle: pw.TextStyle(font: font, fontSize: 7))),
        ],
        if (doc.qr != null) ...[
          pw.SizedBox(height: 8),
          pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: doc.qr!, width: 80, height: 80)),
        ],
      ],
    ),
  ));
  return pdf.save();
}
