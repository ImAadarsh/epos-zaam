import 'package:intl/intl.dart';

import '../../../data/models/org.dart';
import '../../../data/models/sale.dart';
import '../../../data/models/shift.dart';
import '../../utils/money.dart';

/// Printer-agnostic receipt: rows of text that ESC/POS and PDF renderers both lay out.
class ReceiptRow {
  const ReceiptRow(this.left, [this.right = '', this.style = ReceiptStyle.normal]);
  final String left;
  final String right;
  final ReceiptStyle style;
}

enum ReceiptStyle { normal, bold, large, small, center, centerBold, divider, gap }

class ReceiptDoc {
  const ReceiptDoc({required this.rows, this.barcode, this.qr, this.openDrawer = false});
  final List<ReceiptRow> rows;
  final String? barcode;
  final String? qr;
  final bool openDrawer;
}

final _date = DateFormat('dd/MM/yyyy HH:mm');

String _vatLabel(SaleRecord sale) {
  double rate = 0;
  for (final line in sale.lines) {
    if (line.taxRate > 0) {
      rate = line.taxRate;
      break;
    }
  }
  if (rate <= 0) return 'VAT';
  return 'VAT ${formatVatPercent(rate)}';
}

ReceiptDoc buildSaleReceipt(SaleRecord sale, {OrgInfo? org, String footer = '', bool copy = false, bool openDrawer = false}) {
  final rows = <ReceiptRow>[
    ReceiptRow(org?.name ?? 'Zaam', '', ReceiptStyle.large),
    if (org?.address != null && org!.address!.isNotEmpty) ReceiptRow(org.address!, '', ReceiptStyle.center),
    if (org?.phone != null && org!.phone!.isNotEmpty) ReceiptRow('Tel ${org.phone}', '', ReceiptStyle.center),
    if (org?.vatNumber != null && org!.vatNumber!.isNotEmpty) ReceiptRow('VAT No. ${org.vatNumber}', '', ReceiptStyle.center),
    const ReceiptRow('', '', ReceiptStyle.gap),
    if (copy) const ReceiptRow('*** COPY RECEIPT ***', '', ReceiptStyle.centerBold),
    if (sale.status == 'voided') const ReceiptRow('*** VOIDED ***', '', ReceiptStyle.centerBold),
    ReceiptRow('Receipt', sale.receiptNumber),
    ReceiptRow('Date', _date.format(sale.soldAt)),
    if (sale.registerName != null) ReceiptRow('Register', sale.registerName!),
    if (sale.staffName != null) ReceiptRow('Served by', sale.staffName!),
    if (sale.saleType != 'instore') ReceiptRow('Order', sale.saleType == 'eat_in' ? 'Eat in' : 'Take away'),
    if (sale.tableRef != null) ReceiptRow('Table', sale.tableRef!),
    if (sale.customerName != null) ReceiptRow('Customer', sale.customerName!),
    const ReceiptRow('', '', ReceiptStyle.divider),
  ];
  for (final l in sale.lines) {
    rows.add(ReceiptRow('${l.quantity} x ${l.name}', formatPence(l.unitPence * l.quantity)));
    if (l.quantity > 1) rows.add(ReceiptRow('   @ ${formatPence(l.unitPence)}', '', ReceiptStyle.small));
    for (final m in l.modifiers) {
      rows.add(ReceiptRow('   + $m', '', ReceiptStyle.small));
    }
    if (l.discountPence > 0) rows.add(ReceiptRow('   Discount', '-${formatPence(l.discountPence)}', ReceiptStyle.small));
    if (l.note != null && l.note!.isNotEmpty) rows.add(ReceiptRow('   Note: ${l.note}', '', ReceiptStyle.small));
    if (l.refundedQuantity > 0) rows.add(ReceiptRow('   Refunded x${l.refundedQuantity}', '', ReceiptStyle.small));
  }
  rows.addAll([
    const ReceiptRow('', '', ReceiptStyle.divider),
    ReceiptRow('Subtotal', formatPence(sale.subtotalPence)),
    if (sale.discountPence > 0) ReceiptRow('Discounts', '-${formatPence(sale.discountPence)}'),
    if (sale.taxPence > 0) ReceiptRow(_vatLabel(sale), formatPence(sale.taxPence)),
    ReceiptRow('TOTAL', formatPence(sale.totalPence), ReceiptStyle.large),
    const ReceiptRow('', '', ReceiptStyle.gap),
  ]);
  for (final p in sale.payments) {
    if (p.isRefund) continue;
    rows.add(ReceiptRow(p.label, formatPence(p.tenderedPence ?? p.amountPence)));
  }
  if (sale.changePence > 0) rows.add(ReceiptRow('Change', formatPence(sale.changePence), ReceiptStyle.bold));
  if (sale.tipPence > 0) rows.add(ReceiptRow('Tip', formatPence(sale.tipPence)));
  if (sale.refundedPence > 0) rows.add(ReceiptRow('Refunded', '-${formatPence(sale.refundedPence)}', ReceiptStyle.bold));
  rows.add(const ReceiptRow('', '', ReceiptStyle.gap));
  if (footer.isNotEmpty) rows.add(ReceiptRow(footer, '', ReceiptStyle.center));
  if (org?.website != null && org!.website!.isNotEmpty) rows.add(ReceiptRow(org.website!, '', ReceiptStyle.center));
  return ReceiptDoc(rows: rows, barcode: sale.receiptNumber, openDrawer: openDrawer);
}

ReceiptDoc buildRefundReceipt(SaleRecord sale, {required int amountPence, required String method, required List<(String, int, int)> lines, OrgInfo? org}) {
  return ReceiptDoc(rows: [
    ReceiptRow(org?.name ?? 'Zaam', '', ReceiptStyle.large),
    const ReceiptRow('REFUND', '', ReceiptStyle.centerBold),
    ReceiptRow('Original receipt', sale.receiptNumber),
    ReceiptRow('Date', _date.format(DateTime.now())),
    const ReceiptRow('', '', ReceiptStyle.divider),
    for (final (name, qty, pence) in lines) ReceiptRow('$qty x $name', '-${formatPence(pence)}'),
    const ReceiptRow('', '', ReceiptStyle.divider),
    ReceiptRow('REFUND TOTAL', '-${formatPence(amountPence)}', ReceiptStyle.large),
    ReceiptRow('Refunded to', method),
  ], barcode: sale.receiptNumber, openDrawer: method.toLowerCase() == 'cash');
}

/// Cash paid-out slip for Direct Sale / register payouts.
ReceiptDoc buildPayoutReceipt({
  required int amountPence,
  required DateTime at,
  String? reason,
  String? registerName,
  String? staffName,
  String? orgName,
  bool openDrawer = false,
}) {
  return ReceiptDoc(
    rows: [
      ReceiptRow(orgName ?? 'Zaam', '', ReceiptStyle.large),
      const ReceiptRow('PAYOUT', '', ReceiptStyle.centerBold),
      const ReceiptRow('*** PAID OUT ***', '', ReceiptStyle.centerBold),
      const ReceiptRow('', '', ReceiptStyle.gap),
      ReceiptRow('Date', _date.format(at)),
      if (registerName != null && registerName.isNotEmpty) ReceiptRow('Till', registerName),
      if (staffName != null && staffName.isNotEmpty) ReceiptRow('User', staffName),
      const ReceiptRow('', '', ReceiptStyle.divider),
      ReceiptRow('Amount', formatPence(amountPence), ReceiptStyle.large),
      if (reason != null && reason.isNotEmpty) ReceiptRow('Reason', reason),
      const ReceiptRow('', '', ReceiptStyle.gap),
      const ReceiptRow('Cash removed from drawer', '', ReceiptStyle.center),
    ],
    openDrawer: openDrawer,
  );
}

/// Early (hourly) sales report — matches classic POS “Hourly Report” layout.
ReceiptDoc buildHourlyReportReceipt({
  required List<({String label, int amountPence, double percent})> hours,
  required int totalPence,
  String? registerName,
  String? orgName,
}) {
  final rows = <ReceiptRow>[
    ReceiptRow(orgName ?? 'Zaam', '', ReceiptStyle.large),
    const ReceiptRow('HOURLY REPORT', '', ReceiptStyle.centerBold),
    if (registerName != null) ReceiptRow('Register', registerName),
    ReceiptRow('Printed', _date.format(DateTime.now())),
    const ReceiptRow('', '', ReceiptStyle.divider),
    const ReceiptRow('Hours', 'Sale / %', ReceiptStyle.bold),
    for (final h in hours) ReceiptRow(h.label, '${formatPence(h.amountPence)}  ${h.percent.toStringAsFixed(2)}%'),
    const ReceiptRow('', '', ReceiptStyle.divider),
    ReceiptRow('Total of the Day', formatPence(totalPence), ReceiptStyle.bold),
    const ReceiptRow('100.00%', '', ReceiptStyle.small),
  ];
  return ReceiptDoc(rows: rows);
}

ReceiptDoc buildShiftReportReceipt(ShiftReport r, {String? registerName, OrgInfo? org}) {
  final isZ = r.type.toUpperCase() == 'Z';
  final rows = <ReceiptRow>[
    ReceiptRow(org?.name ?? 'Zaam', '', ReceiptStyle.large),
    ReceiptRow(isZ ? 'Z-READ (END OF DAY)' : (r.isRange ? 'X-READ (RANGE)' : 'X-READ'), '', ReceiptStyle.centerBold),
    if (registerName != null) ReceiptRow('Register', registerName),
    if (r.isRange && r.rangeFrom != null && r.rangeTo != null) ...[
      ReceiptRow('From', _date.format(r.rangeFrom!)),
      ReceiptRow('To', _date.format(r.rangeTo!)),
    ] else ...[
      ReceiptRow('Opened', _date.format(r.openedAt)),
      if (r.closedAt != null) ReceiptRow('Closed', _date.format(r.closedAt!)),
    ],
    ReceiptRow('Printed', _date.format(r.generatedAt)),
    const ReceiptRow('', '', ReceiptStyle.divider),
    ReceiptRow('Sales', '${r.salesCount}'),
    ReceiptRow('Gross sales', formatPence(r.grossPence)),
    ReceiptRow('Discounts', '-${formatPence(r.discountsPence)}'),
    ReceiptRow('Refunds (${r.refundCount})', '-${formatPence(r.refundPence)}'),
    ReceiptRow('Voids (${r.voidCount})', formatPence(r.voidPence)),
    ReceiptRow('Net sales', formatPence(r.netPence), ReceiptStyle.bold),
    ReceiptRow('VAT', formatPence(r.taxPence)),
    if (r.tipsPence > 0) ReceiptRow('Tips', formatPence(r.tipsPence)),
    ReceiptRow('Average sale', formatPence(r.averageSalePence)),
    const ReceiptRow('', '', ReceiptStyle.divider),
    const ReceiptRow('PAYMENTS', '', ReceiptStyle.bold),
    for (final p in r.payments) ReceiptRow('${p.provider == null ? p.method : '${p.method} (${p.provider})'} x${p.count}', formatPence(p.netPence)),
    const ReceiptRow('', '', ReceiptStyle.divider),
    const ReceiptRow('CASH', '', ReceiptStyle.bold),
    ReceiptRow('Opening float', formatPence(r.openingFloatPence)),
    ReceiptRow('Paid in', formatPence(r.paidInPence)),
    ReceiptRow('Paid out', '-${formatPence(r.paidOutPence)}'),
    ReceiptRow('Cash drops', '-${formatPence(r.dropsPence)}'),
    ReceiptRow('No sales', '${r.noSales}'),
    ReceiptRow('Expected in drawer', formatPence(r.expectedCashPence), ReceiptStyle.bold),
    if (r.countedCashPence != null) ReceiptRow('Counted', formatPence(r.countedCashPence!)),
    if (r.variancePence != null) ReceiptRow('Variance', formatPenceSigned(r.variancePence!), ReceiptStyle.bold),
    if (r.categories.isNotEmpty) ...[
      const ReceiptRow('', '', ReceiptStyle.divider),
      const ReceiptRow('CATEGORIES', '', ReceiptStyle.bold),
      for (final c in r.categories) ReceiptRow('${c.name} x${c.count}', formatPence(c.amountPence)),
    ],
    if (r.staff.isNotEmpty) ...[
      const ReceiptRow('', '', ReceiptStyle.divider),
      const ReceiptRow('STAFF', '', ReceiptStyle.bold),
      for (final s in r.staff) ReceiptRow('${s.name} x${s.count}', formatPence(s.amountPence)),
    ],
    if (r.source != 'server') const ReceiptRow('Calculated on this device (offline)', '', ReceiptStyle.small),
  ];
  return ReceiptDoc(rows: rows);
}

/// Previous Sales filtered summary for the till printer.
ReceiptDoc buildSalesListReceipt({
  required int totalCount,
  required int netPence,
  required int voidedPence,
  required int refundedPence,
  required List<({String status, int count, int amountPence})> byStatus,
  required List<({String method, int count, int amountPence})> byPayment,
  required List<({String receipt, DateTime soldAt, int totalPence, String status})> sample,
  required int sampleLimit,
  String? registerLabel,
  String? dayLabel,
  String? search,
  String? orgName,
}) {
  final rows = <ReceiptRow>[
    ReceiptRow(orgName ?? 'Zaam', '', ReceiptStyle.large),
    const ReceiptRow('PREVIOUS SALES', '', ReceiptStyle.centerBold),
    if (registerLabel != null && registerLabel.isNotEmpty) ReceiptRow('Register', registerLabel),
    if (dayLabel != null && dayLabel.isNotEmpty) ReceiptRow('Date', dayLabel),
    if (search != null && search.isNotEmpty) ReceiptRow('Search', search),
    ReceiptRow('Printed', _date.format(DateTime.now())),
    const ReceiptRow('', '', ReceiptStyle.divider),
    ReceiptRow('Sales found', '$totalCount', ReceiptStyle.bold),
    ReceiptRow('Net sales', formatPence(netPence), ReceiptStyle.bold),
    if (voidedPence > 0) ReceiptRow('Voided', formatPence(voidedPence)),
    if (refundedPence > 0) ReceiptRow('Refunded', '-${formatPence(refundedPence)}'),
    if (byStatus.isNotEmpty) ...[
      const ReceiptRow('', '', ReceiptStyle.divider),
      const ReceiptRow('BY STATUS', '', ReceiptStyle.bold),
      for (final s in byStatus) ReceiptRow('${s.status} x${s.count}', formatPence(s.amountPence)),
    ],
    if (byPayment.isNotEmpty) ...[
      const ReceiptRow('', '', ReceiptStyle.divider),
      const ReceiptRow('BY PAYMENT', '', ReceiptStyle.bold),
      for (final p in byPayment) ReceiptRow('${p.method} x${p.count}', formatPence(p.amountPence)),
    ],
    if (sample.isNotEmpty) ...[
      const ReceiptRow('', '', ReceiptStyle.divider),
      ReceiptRow(totalCount > sample.length ? 'RECENT (first ${sample.length})' : 'SALES', '', ReceiptStyle.bold),
      for (final s in sample)
        ReceiptRow(
          '${_date.format(s.soldAt)} ${s.receipt}',
          '${formatPence(s.totalPence)}${s.status == 'completed' ? '' : ' ${s.status}'}',
          ReceiptStyle.small,
        ),
      if (totalCount > sample.length) ReceiptRow('+ ${totalCount - sample.length} more not printed', '', ReceiptStyle.small),
    ],
  ];
  return ReceiptDoc(rows: rows);
}
