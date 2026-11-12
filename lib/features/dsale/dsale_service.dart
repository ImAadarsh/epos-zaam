import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hardware/printer/printer_service.dart';
import '../../core/hardware/printer/receipt.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/money.dart';
import '../../data/models/outbox.dart';
import '../../data/models/sale.dart';
import '../../data/models/settings.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../sell/checkout_service.dart';

/// Result of a Direct Sale action for inline UI feedback (no navigation).
class DSaleResult {
  const DSaleResult({required this.ok, required this.message, this.sale, this.error = false});

  final bool ok;
  final String message;
  final SaleRecord? sale;
  final bool error;
}

class HourlyBucket {
  const HourlyBucket({required this.hour, required this.label, required this.amountPence, required this.salesCount, required this.percent});

  final int hour;
  final String label;
  final int amountPence;
  final int salesCount;
  final double percent;
}

class HourlySalesReport {
  const HourlySalesReport({
    required this.hours,
    required this.totalPence,
    required this.totalSalesCount,
    required this.source,
    this.generatedAt,
  });

  final List<HourlyBucket> hours;
  final int totalPence;
  final int totalSalesCount;
  final String source; // local | server
  final DateTime? generatedAt;
}

bool isDirectSaleRecord(SaleRecord s) {
  final notes = (s.notes ?? '').toLowerCase();
  if (notes.contains('direct sale')) return true;
  return s.lines.any((l) {
    final sku = l.sku.toUpperCase();
    final cat = (l.category ?? '').toLowerCase();
    final note = (l.note ?? '').toLowerCase();
    return sku == 'MISC' || cat == 'direct sale' || note.contains('direct sale') || l.variantId.trim().isEmpty;
  });
}

/// Records miscellaneous EPOS Direct Sales and payouts without touching the Sell cart.
class DSaleService {
  DSaleService(this.ref);
  final Ref ref;

  /// Cash misc sale for [amountPence]. Stays on the Direct Sale screen.
  /// Never auto-prints — Print button reprints the last receipt explicitly.
  ///
  /// [tenderedPence] is what the customer handed over (must be >= amount). Change
  /// is recorded as tendered − amount. Defaults to exact amount when omitted.
  Future<DSaleResult> completeSale(int amountPence, {int? tenderedPence}) async {
    if (amountPence <= 0) {
      return const DSaleResult(ok: false, message: 'Enter an amount greater than zero', error: true);
    }
    final tendered = tenderedPence ?? amountPence;
    if (tendered < amountPence) {
      return const DSaleResult(ok: false, message: 'Cash tendered is less than the amount due', error: true);
    }
    final change = tendered - amountPence;
    final shift = ref.read(shiftProvider);
    if (shift == null) {
      return const DSaleResult(ok: false, message: 'Open the register before taking a sale', error: true);
    }

    final session = ref.read(sessionProvider);
    final register = ref.read(currentRegisterProvider);
    final staff = ref.read(currentStaffProvider);
    final settings = ref.read(settingsProvider);

    final sale = SaleRecord(
      clientId: newId(),
      receiptNumber: await ref.read(localSalesProvider.notifier).nextReceiptNumber(),
      registerId: register?.id ?? session.registerId,
      registerName: register?.name,
      shiftId: shift.serverId,
      shiftClientId: shift.clientId,
      staffUserId: staff?.id,
      staffName: staff?.name,
      deviceId: session.deviceId,
      soldAt: DateTime.now(),
      saleType: 'instore',
      subtotalPence: amountPence,
      discountPence: 0,
      taxPence: 0,
      totalPence: amountPence,
      tipPence: 0,
      changePence: change,
      notes: 'EPOS Direct Sale',
      lines: [
        SaleLine(
          variantId: '',
          sku: 'MISC',
          name: 'Miscellaneous sale',
          quantity: 1,
          unitPence: amountPence,
          discountPence: 0,
          taxRate: 0,
          taxPence: 0,
          totalPence: amountPence,
          note: 'Direct Sale',
          category: 'Direct Sale',
        ),
      ],
      payments: [
        SalePayment(method: PaymentMethod.cash, amountPence: amountPence, tenderedPence: tendered),
      ],
    );

    await ref.read(localSalesProvider.notifier).add(sale);
    AppLog.info('Direct Sale ${sale.receiptNumber} ${sale.totalPence}p completed (tendered ${tendered}p change ${change}p)');

    if (settings.openDrawerOnCash) {
      ref.read(printerServiceProvider).openDrawer().catchError((Object e) => AppLog.warn('Drawer: $e'));
    }

    final changeNote = change > 0 ? ' · change £${(change / 100).toStringAsFixed(2)}' : '';
    return DSaleResult(
      ok: true,
      message: 'Sale ${sale.receiptNumber} · £${(amountPence / 100).toStringAsFixed(2)} recorded$changeNote',
      sale: sale,
    );
  }

  /// Last 10 till sales for the Direct Sale left panel (Direct/misc first, then other till sales).
  List<SaleRecord> recentSales({int limit = 10}) {
    final shift = ref.read(shiftProvider);
    final sales = ref.read(localSalesProvider);
    final direct = <SaleRecord>[];
    final other = <SaleRecord>[];
    for (final s in sales) {
      if (s.status == 'voided') continue;
      if (shift != null) {
        final onShift = s.shiftClientId == shift.clientId ||
            (s.shiftClientId == null && s.registerId != null && s.registerId == shift.registerId);
        if (!onShift && s.shiftClientId != null) continue;
      }
      if (isDirectSaleRecord(s)) {
        direct.add(s);
      } else {
        other.add(s);
      }
    }
    final out = <SaleRecord>[];
    for (final s in direct) {
      if (out.length >= limit) break;
      out.add(s);
    }
    if (out.length < limit) {
      for (final s in other) {
        if (out.length >= limit) break;
        out.add(s);
      }
    }
    return out;
  }

  SaleRecord? _lastPrintableSale() {
    final sales = ref.read(localSalesProvider);
    for (final s in sales) {
      if (s.status == 'voided') continue;
      if (isDirectSaleRecord(s)) return s;
    }
    return ref.read(localSalesProvider.notifier).lastReceiptSale;
  }

  Future<DSaleResult> reprintLast() async {
    final sale = _lastPrintableSale();
    if (sale == null) {
      return const DSaleResult(ok: false, message: 'No receipt to print yet', error: true);
    }
    final settings = ref.read(settingsProvider);
    if (settings.printerType == PrinterType.none) {
      return const DSaleResult(ok: false, message: 'No printer configured. Open Settings → Printer.', error: true);
    }
    try {
      await ref.read(checkoutServiceProvider).printReceipt(sale, copy: true);
      return DSaleResult(ok: true, message: 'Reprinted ${sale.receiptNumber}');
    } catch (e) {
      AppLog.warn('Direct Sale reprint failed: $e');
      return DSaleResult(ok: false, message: 'Could not print: $e', error: true);
    }
  }

  /// Void a sale via the same outbox path as Sale Detail (PIN gated in the UI).
  Future<DSaleResult> voidSale(SaleRecord sale, {String reason = 'Voided via Direct Sale'}) async {
    if (sale.status == 'voided') {
      return const DSaleResult(ok: false, message: 'Sale is already voided', error: true);
    }
    final code = sale.sync == SyncState.synced ? (sale.orderNumber ?? sale.serverId ?? sale.clientId) : sale.clientId;
    await ref.read(outboxProvider.notifier).enqueue(
      OutboxType.voidSale,
      {'saleCode': code, 'reason': reason},
      summary: 'Void ${sale.receiptNumber}',
      amountPence: sale.totalPence,
    );
    await ref.read(localSalesProvider.notifier).markVoided(sale.clientId);
    AppLog.info('Direct Sale voided ${sale.receiptNumber}');
    return DSaleResult(ok: true, message: 'Voided ${sale.receiptNumber}');
  }

  /// Amend amount by voiding the old sale and creating a new Direct Sale (ERP-safe).
  Future<DSaleResult> editSale(SaleRecord sale, int newAmountPence, {int? tenderedPence}) async {
    if (newAmountPence <= 0) {
      return const DSaleResult(ok: false, message: 'Enter an amount greater than zero', error: true);
    }
    if (sale.status == 'voided') {
      return const DSaleResult(ok: false, message: 'Cannot edit a voided sale', error: true);
    }
    final prevTender = sale.payments.isEmpty ? sale.totalPence : (sale.payments.first.tenderedPence ?? sale.totalPence);
    final tendered = tenderedPence ?? newAmountPence;
    if (newAmountPence == sale.totalPence && tendered == prevTender) {
      return DSaleResult(ok: true, message: 'Amount unchanged · ${sale.receiptNumber}', sale: sale);
    }
    final voided = await voidSale(sale, reason: 'Amended via Direct Sale');
    if (!voided.ok) return voided;
    final created = await completeSale(newAmountPence, tenderedPence: tendered);
    if (!created.ok) {
      return DSaleResult(
        ok: false,
        message: 'Voided ${sale.receiptNumber} but new sale failed: ${created.message}',
        error: true,
      );
    }
    return DSaleResult(
      ok: true,
      message: 'Amended ${sale.receiptNumber} → ${created.sale?.receiptNumber} · £${(newAmountPence / 100).toStringAsFixed(2)}',
      sale: created.sale,
    );
  }

  /// Cash paid out of the drawer (miscellaneous payout). Always prints a payout slip when a printer is configured.
  Future<DSaleResult> payout(int amountPence, {String? reason}) async {
    if (amountPence <= 0) {
      return const DSaleResult(ok: false, message: 'Enter an amount greater than zero', error: true);
    }
    final shift = ref.read(shiftProvider);
    if (shift == null) {
      return const DSaleResult(ok: false, message: 'Open the register before a payout', error: true);
    }
    final note = (reason == null || reason.trim().isEmpty) ? 'EPOS Direct Sale payout' : reason.trim();
    final at = DateTime.now();
    await ref.read(shiftProvider.notifier).cashMovement('paid_out', amountPence, note);

    final settings = ref.read(settingsProvider);
    final register = ref.read(currentRegisterProvider);
    final staff = ref.read(currentStaffProvider);
    String printNote;
    if (settings.printerType == PrinterType.none) {
      try {
        await ref.read(printerServiceProvider).openDrawer();
      } catch (e) {
        AppLog.warn('Drawer: $e');
      }
      printNote = 'printer not configured — slip not printed';
    } else {
      try {
        await ref.read(printerServiceProvider).print(
              buildPayoutReceipt(
                amountPence: amountPence,
                at: at,
                reason: note,
                registerName: register?.name,
                staffName: staff?.name,
                orgName: ref.read(bootstrapProvider).org?.name,
                openDrawer: true,
              ),
              jobName: 'payout',
            );
        printNote = 'payout slip printed';
      } catch (e) {
        AppLog.warn('Payout print failed: $e');
        try {
          await ref.read(printerServiceProvider).openDrawer();
        } catch (e2) {
          AppLog.warn('Drawer: $e2');
        }
        printNote = 'print failed — payout still recorded';
      }
    }

    return DSaleResult(
      ok: true,
      message: 'Payout £${(amountPence / 100).toStringAsFixed(2)} recorded · $printNote',
      error: printNote.contains('failed'),
    );
  }

  /// Early reporting: hourly sales breakdown (server when online, else this till).
  Future<HourlySalesReport> hourlyReport() async {
    final shift = ref.read(shiftProvider);
    final online = ref.read(onlineProvider);
    if (online && shift != null) {
      await ref.read(outboxProvider.notifier).flush();
      final serverId = shift.serverId ?? ref.read(outboxProvider.notifier).serverShiftId(shift.clientId);
      try {
        final query = <String, dynamic>{};
        if (serverId != null) {
          query['shiftId'] = serverId;
        } else if (shift.registerId.isNotEmpty) {
          query['registerId'] = shift.registerId;
          query['day'] = DateTime.now().toIso8601String().substring(0, 10);
        }
        final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/reports/hourly', query: query) as Map);
        final hoursRaw = (res['hours'] as List?) ?? const [];
        final hours = hoursRaw.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return HourlyBucket(
            hour: (m['hour'] as num?)?.toInt() ?? 0,
            label: '${m['label'] ?? ''}',
            amountPence: toPence(m['amount']),
            salesCount: (m['salesCount'] as num?)?.toInt() ?? 0,
            percent: (m['percent'] as num?)?.toDouble() ?? 0,
          );
        }).toList();
        return HourlySalesReport(
          hours: hours,
          totalPence: toPence(res['totalAmount']),
          totalSalesCount: (res['totalSalesCount'] as num?)?.toInt() ?? 0,
          source: 'server',
          generatedAt: DateTime.tryParse('${res['generatedAt']}'),
        );
      } catch (e) {
        AppLog.warn('Hourly report server failed, using till figures: $e');
      }
    }
    return _localHourlyReport();
  }

  HourlySalesReport _localHourlyReport() {
    final shift = ref.read(shiftProvider);
    final now = DateTime.now();
    final sales = ref.read(localSalesProvider).where((s) {
      if (s.status == 'voided') return false;
      if (shift != null && s.shiftClientId == shift.clientId) return true;
      return s.soldAt.year == now.year && s.soldAt.month == now.month && s.soldAt.day == now.day;
    }).toList();

    final byHour = <int, ({int amount, int count})>{};
    for (final s in sales) {
      final h = s.soldAt.hour;
      final prev = byHour[h] ?? (amount: 0, count: 0);
      byHour[h] = (amount: prev.amount + s.totalPence - s.refundedPence, count: prev.count + 1);
    }
    final total = byHour.values.fold(0, (a, b) => a + b.amount);
    final keys = byHour.keys.toList()..sort();
    final hours = keys.map((h) {
      final b = byHour[h]!;
      final start = h.toString().padLeft(2, '0');
      final end = ((h + 1) % 24).toString().padLeft(2, '0');
      return HourlyBucket(
        hour: h,
        label: '$start:00-$end:00',
        amountPence: b.amount,
        salesCount: b.count,
        percent: total > 0 ? (b.amount / total) * 100 : 0,
      );
    }).toList();
    return HourlySalesReport(
      hours: hours,
      totalPence: total,
      totalSalesCount: sales.length,
      source: 'local',
      generatedAt: DateTime.now(),
    );
  }

  Future<DSaleResult> printHourlyReport(HourlySalesReport report) async {
    final settings = ref.read(settingsProvider);
    if (settings.printerType == PrinterType.none) {
      return const DSaleResult(ok: false, message: 'No printer configured. Open Settings → Printer.', error: true);
    }
    try {
      final org = ref.read(bootstrapProvider).org;
      final register = ref.read(currentRegisterProvider);
      await ref.read(printerServiceProvider).print(
            buildHourlyReportReceipt(
              hours: [
                for (final h in report.hours) (label: h.label, amountPence: h.amountPence, percent: h.percent),
              ],
              totalPence: report.totalPence,
              registerName: register?.name,
              orgName: org?.name,
            ),
            jobName: 'hourly-report',
          );
      return const DSaleResult(ok: true, message: 'Hourly report printed');
    } catch (e) {
      AppLog.warn('Hourly report print failed: $e');
      return DSaleResult(ok: false, message: 'Could not print: $e', error: true);
    }
  }
}

final dSaleServiceProvider = Provider<DSaleService>((ref) => DSaleService(ref));
