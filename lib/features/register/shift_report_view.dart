import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/hardware/printer/printer_service.dart';
import '../../core/hardware/printer/receipt.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/shift.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/shift_repository.dart';

/// X-read (mid-shift) or Z-read (end of day) report.
///
/// Default figures = current open shift (Ethos behaviour). AppBar date-range
/// reloads via `GET /api/pos/reports/x-read` for previous days (max 31 days).
class ShiftReportScreen extends ConsumerStatefulWidget {
  const ShiftReportScreen({super.key, required this.report});
  final ShiftReport report;

  @override
  ConsumerState<ShiftReportScreen> createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends ConsumerState<ShiftReportScreen> {
  late ShiftReport _report;
  DateTimeRange? _range;
  bool _loading = false;
  ShiftReport? _shiftBaseline;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _shiftBaseline = widget.report.isRange ? null : widget.report;
    if (widget.report.isRange && widget.report.rangeFrom != null && widget.report.rangeTo != null) {
      _range = DateTimeRange(start: widget.report.rangeFrom!, end: widget.report.rangeTo!);
    }
  }

  String _rangeChipLabel() {
    if (_range == null) return 'Open shift';
    final fmt = DateFormat('d MMM');
    final a = _range!.start;
    final b = _range!.end;
    if (DateUtils.isSameDay(a, b)) return fmt.format(a);
    return '${fmt.format(a)} – ${fmt.format(b)}';
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _range ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: DateTime(initial.start.year, initial.start.month, initial.start.day),
        end: DateTime(initial.end.year, initial.end.month, initial.end.day),
      ),
      helpText: 'X-Read date range',
      saveText: 'Apply',
    );
    if (picked == null || !mounted) return;
    final from = DateTime(picked.start.year, picked.start.month, picked.start.day);
    final to = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
    await _loadRange(DateTimeRange(start: from, end: to));
  }

  Future<void> _loadRange(DateTimeRange range) async {
    setState(() {
      _loading = true;
      _range = range;
    });
    try {
      final r = await ref.read(shiftProvider.notifier).rangeReport(from: range.start, to: range.end);
      if (!mounted) return;
      setState(() => _report = r);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not load range: ${errorMessage(e)}', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetToShift() async {
    setState(() {
      _loading = true;
      _range = null;
    });
    try {
      final r = _shiftBaseline ?? await ref.read(shiftProvider.notifier).report();
      if (!mounted) return;
      if (r == null) {
        showMessage(context, 'No open shift report available', error: true);
        return;
      }
      _shiftBaseline ??= r;
      setState(() => _report = r);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not reload shift: ${errorMessage(e)}', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _print() async {
    final register = ref.read(currentRegisterProvider);
    try {
      await ref.read(printerServiceProvider).print(
            buildShiftReportReceipt(_report, registerName: register?.name, org: ref.read(receiptOrgProvider)),
            jobName: '${_report.type}-read',
          );
    } catch (e) {
      if (mounted) showMessage(context, 'Print failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final isZ = r.type.toUpperCase() == 'Z';
    final theme = Theme.of(context);
    final dt = DateFormat('dd MMM yyyy HH:mm');
    final day = DateFormat('dd MMM yyyy');
    final register = ref.watch(currentRegisterProvider);

    Widget section(String title, List<Widget> rows) => Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700))),
              ...rows,
            ]),
          ),
        );
    Widget row(String l, String v, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(children: [
            Expanded(child: Text(l, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null)),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(isZ ? 'Z-Read (register closed)' : 'X-Read'),
        actions: [
          if (!isZ) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: InputChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_rangeChipLabel()),
                onPressed: _loading ? null : _pickRange,
                onDeleted: _range == null || _loading ? null : _resetToShift,
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: _loading ? null : _print,
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (r.source != 'server')
                    Card(
                      color: ZaamColors.amber.withValues(alpha: 0.15),
                      child: const ListTile(leading: Icon(Icons.cloud_off), title: Text('Calculated on this device'), subtitle: Text('Offline or not yet synced. Figures cover sales made on this till only.')),
                    ),
                  if (r.isRange)
                    Card(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                      child: ListTile(
                        leading: const Icon(Icons.date_range),
                        title: const Text('Custom date range'),
                        subtitle: Text(
                          r.rangeFrom != null && r.rangeTo != null
                              ? '${day.format(r.rangeFrom!)} – ${day.format(r.rangeTo!)}'
                              : 'Sales, payments and cash movements in the selected window.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  section(r.isRange ? 'Period' : 'Session', [
                    if (register != null) row('Register', register.name),
                    if (r.isRange) ...[
                      if (r.rangeFrom != null) row('From', dt.format(r.rangeFrom!)),
                      if (r.rangeTo != null) row('To', dt.format(r.rangeTo!)),
                      row('Opened (float shift)', dt.format(r.openedAt)),
                    ] else ...[
                      row('Opened', dt.format(r.openedAt)),
                      if (r.closedAt != null) row('Closed', dt.format(r.closedAt!)),
                    ],
                    row('Generated', dt.format(r.generatedAt)),
                  ]),
                  const SizedBox(height: 10),
                  section('Sales', [
                    row('Transactions', '${r.salesCount}'),
                    row('Gross sales', formatPence(r.grossPence)),
                    row('Discounts', '-${formatPence(r.discountsPence)}'),
                    row('Refunds (${r.refundCount})', '-${formatPence(r.refundPence)}'),
                    row('Voids (${r.voidCount})', formatPence(r.voidPence)),
                    row('Net sales', formatPence(r.netPence), bold: true),
                    row('VAT', formatPence(r.taxPence)),
                    if (r.tipsPence > 0) row('Tips', formatPence(r.tipsPence)),
                    row('Average sale', formatPence(r.averageSalePence)),
                  ]),
                  const SizedBox(height: 10),
                  section('Payments', [
                    if (r.payments.isEmpty) row('No payments', ''),
                    for (final p in r.payments)
                      row('${p.method[0].toUpperCase()}${p.method.substring(1)}${p.provider != null && p.provider != 'external' ? ' (${p.provider})' : ''} × ${p.count}',
                          p.refundedPence != 0 ? '${formatPence(p.takenPence)} / ${formatPenceSigned(p.refundedPence)} = ${formatPence(p.netPence)}' : formatPence(p.netPence)),
                  ]),
                  const SizedBox(height: 10),
                  section('Cash drawer', [
                    row('Opening float', formatPence(r.openingFloatPence)),
                    row('Paid in', formatPence(r.paidInPence)),
                    row('Paid out', '-${formatPence(r.paidOutPence)}'),
                    row('Cash drops', '-${formatPence(r.dropsPence)}'),
                    row('No sale opens', '${r.noSales}'),
                    row('Expected in drawer', formatPence(r.expectedCashPence), bold: true),
                    if (r.countedCashPence != null) row('Counted', formatPence(r.countedCashPence!), bold: true),
                    if (r.variancePence != null)
                      row('Variance', formatPenceSigned(r.variancePence!), bold: true, color: r.variancePence == 0 ? ZaamColors.green : (r.variancePence! < 0 ? ZaamColors.red : ZaamColors.amber)),
                  ]),
                  if (r.categories.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    section('Categories', [for (final c in r.categories) row('${c.name} × ${c.count}', formatPence(c.amountPence))]),
                  ],
                  if (r.staff.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    section('Staff', [for (final s in r.staff) row('${s.name} × ${s.count}', formatPence(s.amountPence))]),
                  ],
                ],
              ),
            ),
          ),
          if (_loading) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}
