import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/session.dart';

/// Normalises receipt / order barcodes: `POS-M-…` ↔ `M-…`.
List<String> saleLookupCodes(String code) {
  final c = code.trim();
  if (c.isEmpty) return const [];
  final bare = c.toUpperCase().startsWith('POS-') ? c.substring(4) : c;
  final withPos = c.toUpperCase().startsWith('POS-') ? c : 'POS-$c';
  return {c, bare, withPos}.toList();
}

/// Finds a sale by receipt number / order number / id: server first (has refunds
/// from other tills), falling back to this device's copy when offline or unsynced.
Future<SaleRecord?> loadSale(WidgetRef ref, String code) async {
  final codes = saleLookupCodes(code);
  SaleRecord? local;
  for (final c in codes) {
    local = ref.read(localSalesProvider.notifier).find(c);
    if (local != null) break;
  }
  if (local != null && local.sync != SyncState.synced) return local;

  ApiException? last404;
  for (final c in codes) {
    try {
      final res = await ref.read(apiClientProvider).get('/api/pos/sales/${Uri.encodeComponent(c)}');
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
      if (e.statusCode == 404) {
        last404 = e;
        continue;
      }
      if (local != null) return local;
      rethrow;
    }
  }
  if (local != null) return local;
  if (last404 != null) return null;
  return null;
}
