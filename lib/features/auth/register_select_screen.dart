import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/outbox.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/shift_repository.dart';

/// Choose which register (till) this device is. Used at first sign-in and from "Change Register".
class RegisterSelectScreen extends ConsumerStatefulWidget {
  const RegisterSelectScreen({super.key, this.changing = false});

  final bool changing;

  @override
  ConsumerState<RegisterSelectScreen> createState() => _RegisterSelectScreenState();
}

class _RegisterSelectScreenState extends ConsumerState<RegisterSelectScreen> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (ref.read(bootstrapProvider).registers.isEmpty) Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(bootstrapProvider.notifier).refresh();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final name = await promptText(context, title: 'New register', hint: 'e.g. Front Counter', confirmLabel: 'Create');
    if (name == null || !mounted) return;
    try {
      await ref.read(apiClientProvider).post('/api/pos/registers', data: {'name': name});
      await _refresh();
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e), error: true);
    }
  }

  Future<void> _select(String id) async {
    final session = ref.read(sessionProvider);
    if (widget.changing && id != session.registerId) {
      final shift = ref.read(shiftProvider);
      final pending = ref.read(outboxProvider).entries.where((e) => e.type != OutboxType.clock).length;
      if (shift != null) {
        final ok = await confirm(context,
            title: 'Register is still open',
            message: 'This register has an open session. Close it first to keep the cash count accurate, or switch anyway and leave it open.',
            confirmLabel: 'Switch anyway');
        if (!ok) return;
      }
      if (pending > 0 && mounted) showMessage(context, '$pending change(s) still syncing; they will be sent in the background.');
      await ref.read(shiftProvider.notifier).clearLocal();
    }
    await ref.read(sessionProvider.notifier).selectRegister(id);
    await ref.read(shiftProvider.notifier).reconcile();
    if (widget.changing && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(bootstrapProvider);
    final active = ref.watch(sessionProvider.select((s) => s.registerId));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.changing ? 'Change Register' : 'Choose register'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
          if (!widget.changing)
            TextButton(onPressed: () => ref.read(sessionProvider.notifier).logout(), child: const Text('Sign out')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              for (final r in boot.registers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: const CircleAvatar(child: Icon(Icons.point_of_sale)),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([r.code, if (r.warehouseName != null) r.warehouseName!].join(' · ')),
                      trailing: r.id == active
                          ? Chip(label: const Text('Register Active'), avatar: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary))
                          : const Icon(Icons.chevron_right),
                      onTap: () => _select(r.id),
                    ),
                  ),
                ),
              if (boot.registers.isEmpty && !_loading) const Padding(padding: EdgeInsets.all(24), child: Text('No registers yet. Create one to start selling.', textAlign: TextAlign.center)),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New register')),
            ],
          ),
        ),
      ),
    );
  }
}
