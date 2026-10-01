import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/money.dart';
import '../models/outbox.dart';
import '../models/sale.dart';
import 'bootstrap_repository.dart';
import 'catalog_repository.dart';
import 'outbox_repository.dart';
import 'session.dart';

/// Sales made on this device (last 30 days), for offline Previous Sales,
/// refunds and device X-reads. The server remains the source of truth.
class LocalSalesController extends Notifier<List<SaleRecord>> {
  @override
  List<SaleRecord> build() {
    Future.microtask(_load);
    return const [];
  }

  LocalDb get _db => ref.read(localDbProvider);

  Future<void> _load() async {
    final rows = await _db.all(LocalDb.sales, finder: Finder(sortOrders: [SortOrder('soldAt', false)]));
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final keep = <SaleRecord>[];
    final drop = <String>[];
    for (final r in rows) {
      final s = SaleRecord.fromJson(r);
      if (s.soldAt.isBefore(cutoff) && s.sync == SyncState.synced) {
        drop.add(s.clientId);
      } else {
        keep.add(s);
      }
    }
    if (drop.isNotEmpty) await _db.deleteMany(LocalDb.sales, drop);
    state = keep;
  }

  /// Next receipt number for this device, e.g. `M-7F3A-00042`. Unique per device
  /// without needing the server, so it works offline.
  Future<String> nextReceiptNumber() async {
    final session = ref.read(sessionProvider);
    final register = ref.read(currentRegisterProvider);
    final prefix = (register?.receiptPrefix?.isNotEmpty ?? false) ? register!.receiptPrefix! : (register?.code ?? 'POS');
    final seqRow = await _db.getKv('receipt_seq') ?? {};
    final seq = ((seqRow['value'] as num?)?.toInt() ?? 0) + 1;
    await _db.putKv('receipt_seq', {'value': seq});
    return '$prefix-${deviceTag(session.deviceId)}-${seq.toString().padLeft(5, '0')}';
  }

  Future<void> add(SaleRecord sale) async {
    await _db.put(LocalDb.sales, sale.clientId, sale.toJson());
    state = [sale, ...state];
    await ref.read(catalogProvider.notifier).adjustStock({for (final l in sale.lines) l.variantId: -l.quantity});
    await ref.read(outboxProvider.notifier).enqueue(
      OutboxType.sale,
      sale.toApi(),
      summary: sale.receiptNumber,
      amountPence: sale.totalPence,
    );
  }

  Future<void> _replace(SaleRecord sale) async {
    await _db.put(LocalDb.sales, sale.clientId, sale.toJson());
    state = [for (final s in state) s.clientId == sale.clientId ? sale : s];
  }

  Future<void> markSynced(String clientId, String? serverId, String? orderNumber) async {
    final s = find(clientId);
    if (s == null) return;
    await _replace(s.copyWith(sync: SyncState.synced, serverId: serverId, orderNumber: orderNumber));
  }

  Future<void> applyRefund(String clientId, int amountPence, Map<String, int> quantitiesByVariant) async {
    final s = find(clientId);
    if (s == null) return;
    final remaining = Map.of(quantitiesByVariant);
    final lines = s.lines.map((l) {
      final q = remaining[l.variantId] ?? 0;
      if (q <= 0) return l;
      final take = q.clamp(0, l.refundableQuantity);
      remaining[l.variantId] = q - take;
      return l.copyWith(refundedQuantity: l.refundedQuantity + take);
    }).toList();
    final refunded = s.refundedPence + amountPence;
    await _replace(s.copyWith(refundedPence: refunded, lines: lines, status: refunded >= s.totalPence ? 'refunded' : 'partially_refunded'));
  }

  Future<void> markVoided(String clientId) async {
    final s = find(clientId);
    if (s == null) return;
    await _replace(s.copyWith(status: 'voided'));
    await ref.read(catalogProvider.notifier).adjustStock({for (final l in s.lines) l.variantId: l.quantity});
  }

  SaleRecord? find(String code) {
    final c = code.trim();
    for (final s in state) {
      if (s.clientId == c || s.receiptNumber == c || s.orderNumber == c || s.serverId == c || 'POS-${s.receiptNumber}' == c) return s;
    }
    return null;
  }

  /// Queues a refund against a sale (by server order number once synced, else its client id)
  /// and updates the local copy straight away.
  Future<void> refund({
    required SaleRecord sale,
    required List<({SaleLine line, int quantity, int amountPence})> lines,
    required int amountPence,
    required PaymentMethod method,
    required bool restock,
    String? reason,
    String? shiftId,
    String? shiftClientId,
  }) async {
    final session = ref.read(sessionProvider);
    final code = sale.serverId != null && sale.sync == SyncState.synced ? (sale.orderNumber ?? sale.serverId!) : sale.clientId;
    await ref.read(outboxProvider.notifier).enqueue(
      OutboxType.refund,
      {
        'saleCode': code,
        'clientId': newId(),
        'lines': [
          for (final l in lines)
            if (l.quantity > 0)
              {'orderLineId': l.line.orderLineId, 'variantId': l.line.variantId, 'quantity': l.quantity, 'amount': fromPence(l.amountPence)},
        ],
        'amount': fromPence(amountPence),
        'restock': restock,
        'reason': reason,
        'payments': [
          {'method': method.name, 'amount': fromPence(amountPence)},
        ],
        'staffUserId': session.staffId,
        'registerId': session.registerId,
        'shiftId': shiftId,
        'shiftClientId': shiftClientId,
        'refundedAt': DateTime.now().toUtc().toIso8601String(),
      },
      summary: 'Refund ${sale.receiptNumber}',
      amountPence: amountPence,
    );
    final qty = <String, int>{};
    for (final l in lines) {
      qty[l.line.variantId] = (qty[l.line.variantId] ?? 0) + l.quantity;
    }
    if (find(sale.clientId) != null) await applyRefund(sale.clientId, amountPence, qty);
    if (restock) await ref.read(catalogProvider.notifier).adjustStock(qty);
  }

  Future<void> clear() async {
    await _db.replaceAll(LocalDb.sales, {});
    state = const [];
  }
}

final localSalesProvider = NotifierProvider<LocalSalesController, List<SaleRecord>>(LocalSalesController.new);

