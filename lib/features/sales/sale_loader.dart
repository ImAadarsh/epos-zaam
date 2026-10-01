import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/session.dart';

/// Finds a sale by receipt number / order number / id: server first (has refunds
/// from other tills), falling back to this device's copy when offline or unsynced.
Future<SaleRecord?> loadSale(WidgetRef ref, String code) async {
  final local = ref.read(localSalesProvider.notifier).find(code);
  if (local != null && local.sync != SyncState.synced) return local;
  try {
    final res = await ref.read(apiClientProvider).get('/api/pos/sales/${Uri.encodeComponent(code.trim())}');
    final remote = SaleRecord.fromServer(Map<String, dynamic>.from(res as Map));
    if (local == null) return remote;
    // Keep local-only fields (client id, staff/register names) alongside server truth.
    return SaleRecord.fromJson({
      ...local.toJson(),
      'orderNumber': remote.orderNumber,
      'serverId': remote.serverId,
      'status': remote.status,
      'refundedPence': remote.refundedPence,
      'lines': remote.lines.map((l) => l.toJson()).toList(),
      'sync': SyncState.synced.name,
    });
  } on ApiException catch (e) {
    if (e.statusCode == 404) return local;
    if (local != null) return local;
    rethrow;
  }
}
