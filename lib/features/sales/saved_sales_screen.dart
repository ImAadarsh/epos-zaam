import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/parked_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../sell/cart_controller.dart';
import '../shell/app_shell.dart';

/// Saved (parked) sales, with running timers for tables when enabled.
class SavedSalesScreen extends ConsumerStatefulWidget {
  const SavedSalesScreen({super.key});

  @override
  ConsumerState<SavedSalesScreen> createState() => _SavedSalesScreenState();
}

class _SavedSalesScreenState extends ConsumerState<SavedSalesScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _elapsed(DateTime since) {
    final d = DateTime.now().difference(since);
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  Future<void> _restore(ParkedSale p) async {
    final cart = ref.read(cartProvider);
    if (!cart.isEmpty && cart.parkedId != p.id) {
      final choice = await pickOption<String>(context, title: 'Current sale has items', options: [
        ('park', 'Save current sale, then open this one'),
        ('discard', 'Discard current sale'),
      ]);
      if (choice == null) return;
      if (choice == 'park') {
        await ref.read(parkedSalesProvider.notifier).park(cart, staffName: ref.read(currentStaffProvider)?.name, totalPence: ref.read(cartTotalsProvider).totalPence);
      }
    }
    ref.read(cartProvider.notifier).restore(p.cart);
    ref.read(shellTabProvider.notifier).go(0);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(parkedSalesProvider);
    final timers = ref.watch(settingsProvider.select((s) => s.tableTimers));
    final time = DateFormat('HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Sales')),
      body: list.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No saved sales. Use "Save" on a sale to park it here.', textAlign: TextAlign.center)))
          : LayoutBuilder(builder: (context, c) {
              final cols = (c.maxWidth / 300).floor().clamp(1, 5);
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 150),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  final since = p.cart.startedAt ?? p.parkedAt;
                  final mins = DateTime.now().difference(since).inMinutes;
                  final color = mins >= 60 ? ZaamColors.red : mins >= 30 ? ZaamColors.amber : ZaamColors.green;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _restore(p),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(p.label ?? 'Sale ${time.format(p.parkedAt)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                            if (timers)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.timer_outlined, size: 14, color: color), const SizedBox(width: 4), Text(_elapsed(since), style: TextStyle(color: color, fontWeight: FontWeight.w600))]),
                              ),
                          ]),
                          const SizedBox(height: 4),
                          Text('${p.cart.itemCount} items · saved ${time.format(p.parkedAt)}${p.staffName != null ? ' by ${p.staffName}' : ''}', style: Theme.of(context).textTheme.bodySmall),
                          const Spacer(),
                          Row(children: [
                            Text(formatPence(p.totalPence), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () async {
                                if (await confirm(context, title: 'Delete saved sale?', confirmLabel: 'Delete', destructive: true)) {
                                  await ref.read(parkedSalesProvider.notifier).remove(p.id);
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  );
                },
              );
            }),
    );
  }
}
