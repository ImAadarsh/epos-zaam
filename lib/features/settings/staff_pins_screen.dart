import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/security/permissions.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/models/org.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/session.dart';

/// Set staff PINs and POS roles (cashier / supervisor / manager). Needs a connection.
class StaffPinsScreen extends ConsumerStatefulWidget {
  const StaffPinsScreen({super.key});

  @override
  ConsumerState<StaffPinsScreen> createState() => _StaffPinsScreenState();
}

class _StaffPinsScreenState extends ConsumerState<StaffPinsScreen> {
  bool _busy = false;

  Future<void> _edit(StaffMember s) async {
    if (!await requirePermission(context, ref, Perm.staffPins) || !mounted) return;
    final role = await pickOption<PosRole>(context, title: '${s.name}: POS role', options: const [
      (PosRole.cashier, 'Cashier: sell, park, clock in'),
      (PosRole.supervisor, 'Supervisor: + refunds, voids, discounts, cash in/out, close register'),
      (PosRole.manager, 'Manager: + settings, staff PINs, reset app'),
    ]);
    if (role == null || !mounted) return;
    final pin = await promptText(context, title: 'New PIN for ${s.name}', hint: '4–8 digits${s.hasPin ? ' (leave blank to keep current)' : ''}', keyboardType: TextInputType.number, allowEmpty: s.hasPin, confirmLabel: 'Save');
    if (pin == null) return;
    if (pin.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      if (mounted) showMessage(context, 'PIN must be 4 to 8 digits', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).put('/api/pos/staff/${s.id}/pin', data: {'pin': pin.isEmpty ? null : pin, 'posRole': role.name});
      await ref.read(bootstrapProvider.notifier).refresh();
      if (mounted) showMessage(context, 'Saved ${s.name}');
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(bootstrapProvider).staff;
    return Scaffold(
      appBar: AppBar(title: const Text('Staff PINs')),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Staff come from Zaam ERP users. Add users with the POS Cashier or POS Manager role in the ERP, then set their PIN here.'),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: staff.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, i) {
              final s = staff[i];
              return ListTile(
                leading: CircleAvatar(child: Text(s.initials)),
                title: Text(s.name),
                subtitle: Text('${s.posRole.name[0].toUpperCase()}${s.posRole.name.substring(1)} · ${s.hasPin ? 'PIN set' : 'No PIN'}${s.email != null ? ' · ${s.email}' : ''}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _busy ? null : () => _edit(s),
              );
            },
          ),
        ),
      ]),
    );
  }
}
