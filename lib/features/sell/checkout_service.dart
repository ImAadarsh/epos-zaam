import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display/customer_display.dart';
import '../../core/hardware/printer/printer_service.dart';
import '../../core/hardware/printer/receipt.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/ids.dart';
import '../../data/models/cart.dart';
import '../../data/models/outbox.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/parked_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/shift_repository.dart';
import 'cart_controller.dart';

/// Turns the current cart plus collected payments into a recorded sale.
/// Works fully offline: the sale is stored locally and queued for sync.
class CheckoutService {
  CheckoutService(this.ref);
  final Ref ref;

  Future<SaleRecord> complete({required List<SalePayment> payments, int tipPence = 0}) async {
    final cart = ref.read(cartProvider);
    final totals = ref.read(cartTotalsProvider);
    final session = ref.read(sessionProvider);
    final register = ref.read(currentRegisterProvider);
    final staff = ref.read(currentStaffProvider);
    final shift = ref.read(shiftProvider);

    final paid = payments.fold(0, (s, p) => s + p.amountPence);
    if (paid < totals.totalPence) throw StateError('Payments do not cover the total');
    final change = payments.fold(0, (s, p) => s + ((p.tenderedPence ?? p.amountPence) - p.amountPence));

    final sale = SaleRecord(
      clientId: newId(),
      receiptNumber: await ref.read(localSalesProvider.notifier).nextReceiptNumber(),
      registerId: register?.id ?? session.registerId,
      registerName: register?.name,
      shiftId: shift?.serverId,
      shiftClientId: shift?.clientId,
      staffUserId: staff?.id,
      staffName: staff?.name,
      deviceId: session.deviceId,
      soldAt: DateTime.now(),
      saleType: cart.saleType.api,
      tableRef: cart.tableRef,
      customerId: cart.customer?.id,
      customerName: cart.customer?.name,
      customerEmail: cart.customer?.email,
      subtotalPence: totals.subtotalPence,
      discountPence: totals.discountPence,
      taxPence: totals.taxPence,
      totalPence: totals.totalPence,
      tipPence: tipPence,
      changePence: change,
      notes: _notes(cart),
      lines: [
        for (final lt in totals.lines)
          SaleLine(
            variantId: lt.line.product.variantId,
            sku: lt.line.product.sku,
            name: lt.line.product.displayName,
            quantity: lt.line.quantity,
            unitPence: lt.line.unitPence,
            discountPence: lt.discountPence,
            taxRate: cart.taxRateFor(lt.line),
            taxPence: lt.taxPence,
            totalPence: lt.totalPence,
            costPence: lt.line.product.costPence,
            modifiers: lt.line.modifiers.map((m) => m.name).toList(),
            note: lt.line.note,
            category: lt.line.product.category,
          ),
      ],
      payments: payments,
    );

    await ref.read(localSalesProvider.notifier).add(sale);
    if (cart.parkedId != null) await ref.read(parkedSalesProvider.notifier).remove(cart.parkedId!);
    ref.read(cartProvider.notifier).clear();
    AppLog.info('Sale ${sale.receiptNumber} ${sale.totalPence}p completed');

    final org = ref.read(bootstrapProvider).org;
    ref.read(customerDisplayProvider).show(DisplayState(
          mode: 'done',
          storeName: org?.name ?? '',
          totalPence: sale.totalPence,
          paidPence: paid + change,
          changePence: change,
          message: 'Thank you!',
        ));

    final settings = ref.read(settingsProvider);
    if (settings.openDrawerOnCash && payments.any((p) => p.method == PaymentMethod.cash)) {
      ref.read(printerServiceProvider).openDrawer().catchError((Object e) => AppLog.warn('Drawer: $e'));
    }
    return sale;
  }

  String? _notes(Cart cart) {
    final parts = [
      if (cart.note != null && cart.note!.isNotEmpty) cart.note!,
      if (cart.cartDiscount?.reason != null && cart.cartDiscount!.reason!.isNotEmpty) 'Discount: ${cart.cartDiscount!.reason}',
    ];
    return parts.isEmpty ? null : parts.join(' | ');
  }

  Future<void> printReceipt(SaleRecord sale, {bool copy = false}) {
    final settings = ref.read(settingsProvider);
    final doc = buildSaleReceipt(sale, org: ref.read(receiptOrgProvider), footer: settings.receiptFooter, copy: copy);
    return ref.read(printerServiceProvider).print(doc, jobName: 'Receipt ${sale.receiptNumber}');
  }

  /// Queued so it also works offline; the server sends it once the sale has synced.
  Future<void> emailReceipt(SaleRecord sale, String email) async {
    final code = sale.orderNumber ?? sale.clientId;
    await ref.read(outboxProvider.notifier).enqueue(OutboxType.emailReceipt, {'saleCode': code, 'email': email}, summary: 'Email ${sale.receiptNumber}');
  }
}

final checkoutServiceProvider = Provider<CheckoutService>((ref) => CheckoutService(ref));
