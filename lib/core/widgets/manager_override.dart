import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/bootstrap_repository.dart';
import '../security/permissions.dart';
import '../security/pin.dart';
import '../utils/app_log.dart';
import 'dialogs.dart';
import 'pin_entry.dart';

/// Returns true if the signed-in staff member may do [perm], otherwise asks a
/// supervisor/manager to authorise with their PIN (checked by the server; cached PINs when offline).
Future<bool> requirePermission(BuildContext context, WidgetRef ref, Perm perm) async {
  final staff = ref.read(currentStaffProvider);
  if (can(staff, perm)) return true;
  final boot = ref.read(bootstrapProvider);
  final approvers = boot.staff.where((s) => can(s, perm) && s.hasPin).toList();
  if (approvers.isEmpty) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Manager approval needed'),
          content: Text('${perm.label} needs a ${perm.minimumRole.name} or above, and no manager has a PIN set yet. Set PINs in Settings → Staff PINs.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Manager approval'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${perm.label}\nEnter a ${perm.minimumRole.name} PIN to continue.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            PinEntry(onSubmit: (pin) async {
              final verifier = ref.read(pinVerifierProvider);
              final r = await verifier.verify(pin, among: approvers);
              final m = r.staff;
              if (m == null) {
                if (r.message != null && ctx.mounted) showMessage(ctx, r.message!, error: true);
                return false;
              }
              verifier.rememberOverride(r.staffToken);
              AppLog.info('${perm.name} approved by ${m.name}');
              if (ctx.mounted) Navigator.pop(ctx, true);
              return true;
            }),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))],
    ),
  );
  return ok ?? false;
}
