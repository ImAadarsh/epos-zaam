import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/hardware/printer/printer_service.dart';
import '../../core/hardware/printer/receipt.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/shift.dart';
import '../../data/repositories/bootstrap_repository.dart';

/// X-read (mid-shift) or Z-read (end of day) report.
class ShiftReportScreen extends ConsumerWidget {
  const ShiftReportScreen({super.key, required this.report});
  final ShiftReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = report;
    final isZ = r.type.toUpperCase() == 'Z';
    final theme = Theme.of(context);
    final dt = DateFormat('dd MMM yyyy HH:mm');
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
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              try {
                await ref.read(printerServiceProvider).print(buildShiftReportReceipt(r, registerName: register?.name, org: ref.read(bootstrapProvider).org), jobName: '${r.type}-read');
              } catch (e) {
                if (context.mounted) showMessage(context, 'Print failed: $e', error: true);
              }
            },
          ),
        ],
      ),
      body: Center(
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
              const SizedBox(height: 8),
              section('Session', [
                if (register != null) row('Register', register.name),
                row('Opened', dt.format(r.openedAt)),
                if (r.closedAt != null) row('Closed', dt.format(r.closedAt!)),
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
    );
  }
}
