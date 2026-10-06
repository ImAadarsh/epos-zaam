import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../models/org.dart';
import 'initial_data.dart';
import 'session.dart';

/// Organisation, registers, staff and tax codes (`GET /api/pos/bootstrap`), cached offline.
class BootstrapController extends Notifier<BootstrapData> {
  @override
  BootstrapData build() {
    final j = ref.read(initialDataProvider).bootstrap;
    return j == null ? const BootstrapData() : BootstrapData.fromJson(j);
  }

  Future<BootstrapData> refresh() async {
    final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/bootstrap') as Map);
    state = BootstrapData.fromJson(res);
    await ref.read(localDbProvider).putKv('bootstrap', state.toJson());
    return state;
  }

  Future<void> clear() async {
    state = const BootstrapData();
    await ref.read(localDbProvider).deleteKv('bootstrap');
  }
}

final bootstrapProvider = NotifierProvider<BootstrapController, BootstrapData>(BootstrapController.new);

final currentRegisterProvider = Provider<Register?>((ref) {
  final id = ref.watch(sessionProvider.select((s) => s.registerId));
  return ref.watch(bootstrapProvider).register(id);
});

/// Organisation details for receipts, with the current register's location address.
final receiptOrgProvider = Provider<OrgInfo?>((ref) {
  final org = ref.watch(bootstrapProvider).org;
  final address = ref.watch(currentRegisterProvider)?.warehouseAddress;
  return org == null || address == null || address.isEmpty ? org : org.withAddress(address);
});

final currentStaffProvider = Provider<StaffMember?>((ref) {
  final session = ref.watch(sessionProvider);
  final boot = ref.watch(bootstrapProvider);
  final member = boot.staffMember(session.staffId);
  if (member != null) return member;
  final user = session.user;
  if (user == null || session.staffId != user.id) return null;
  final isManager = user.roles.any((r) => const ['ADMIN', 'SUPER_ADMIN', 'POS_MANAGER'].contains(r));
  return StaffMember(id: user.id, name: user.name, email: user.email, roles: user.roles, posRole: isManager ? PosRole.manager : PosRole.cashier);
});
