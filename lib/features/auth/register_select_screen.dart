import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/org.dart';
import '../../data/models/outbox.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
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
    if (ref.read(bootstrapProvider).warehouses.isEmpty) await _refresh();
    if (!mounted) return;
    final result = await showDialog<({String name, String warehouseId})>(
      context: context,
      builder: (_) => _RegisterDialog(warehouses: ref.read(bootstrapProvider).warehouses),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(apiClientProvider).post('/api/pos/registers', data: {'name': result.name, 'warehouseId': result.warehouseId});
      await _refresh();
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e), error: true);
    }
  }

  Future<void> _changeLocation(Register r) async {
    if (ref.read(bootstrapProvider).warehouses.isEmpty) await _refresh();
    if (!mounted) return;
    final result = await showDialog<({String name, String warehouseId})>(
      context: context,
      builder: (_) => _RegisterDialog(warehouses: ref.read(bootstrapProvider).warehouses, register: r),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(apiClientProvider).patch('/api/pos/registers/${r.id}', data: {'name': result.name, 'warehouseId': result.warehouseId});
      await _refresh();
      if (r.id == ref.read(sessionProvider).registerId) await ref.read(catalogProvider.notifier).sync(full: true);
      if (mounted) showMessage(context, '${result.name} updated.');
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
                      subtitle: Text([
                        r.code,
                        if (r.warehouseName != null) r.warehouseName!,
                        if (r.warehouseAddress != null && r.warehouseAddress != r.warehouseName) r.warehouseAddress!,
                      ].join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(tooltip: 'Name & stock location', icon: const Icon(Icons.edit_location_alt_outlined), onPressed: () => _changeLocation(r)),
                          r.id == active
                              ? Chip(label: const Text('Register Active'), avatar: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary))
                              : const Icon(Icons.chevron_right),
                        ],
                      ),
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

/// Name plus the stock location (warehouse) a register sells from; its stock and address follow that location.
class _RegisterDialog extends StatefulWidget {
  const _RegisterDialog({required this.warehouses, this.register});

  final List<WarehouseInfo> warehouses;
  final Register? register;

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  late final _name = TextEditingController(text: widget.register?.name ?? '');
  late String? _warehouseId = widget.warehouses.any((w) => w.id == widget.register?.warehouseId) ? widget.register!.warehouseId : null;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Enter a register name');
    if (_warehouseId == null) return setState(() => _error = 'Choose the stock location this register sells from');
    Navigator.pop(context, (name: name, warehouseId: _warehouseId!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.register == null ? 'New register' : 'Edit ${widget.register!.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.register == null,
              decoration: const InputDecoration(labelText: 'Register name', hintText: 'e.g. Front Counter'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            if (widget.warehouses.isEmpty)
              const Text('No stock locations found. Add a warehouse in Zaam ERP → Inventory first.')
            else
              DropdownButtonFormField<String>(
                initialValue: _warehouseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Stock location', helperText: 'Stock, products on hand and the receipt address come from here'),
                items: [
                  for (final w in widget.warehouses)
                    DropdownMenuItem(
                      value: w.id,
                      child: Text(w.address != null && w.address != w.name ? '${w.name} · ${w.address}' : w.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _warehouseId = v;
                  _error = null;
                }),
              ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: widget.warehouses.isEmpty ? null : _submit, child: Text(widget.register == null ? 'Create' : 'Save')),
      ],
    );
  }
}
