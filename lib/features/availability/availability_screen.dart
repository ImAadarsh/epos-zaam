import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../data/repositories/catalog_repository.dart';

enum _Filter { all, unavailable }

/// Manage Availability: switch products and modifiers on/off for sale (e.g. sold out).
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  String _q = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final ctrl = ref.read(catalogProvider.notifier);
    final q = _q.toLowerCase();

    final products = catalog.products.values
        .where((p) => p.active)
        .where((p) => _filter == _Filter.all || !p.available)
        .where((p) => q.isEmpty || p.displayName.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    final modifiers = [
      for (final g in catalog.modifierGroups)
        for (final m in g.modifiers)
          if ((_filter == _Filter.all || !m.available) && (q.isEmpty || m.name.toLowerCase().contains(q) || g.name.toLowerCase().contains(q))) (g, m),
    ];

    Widget filters() => Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            Expanded(child: TextField(decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v.trim()))),
            const SizedBox(width: 8),
            DropdownButton<_Filter>(
              value: _filter,
              items: const [DropdownMenuItem(value: _Filter.all, child: Text('Show All')), DropdownMenuItem(value: _Filter.unavailable, child: Text('Unavailable only'))],
              onChanged: (v) => setState(() => _filter = v ?? _Filter.all),
            ),
          ]),
        );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Availability'),
          bottom: const TabBar(tabs: [Tab(text: 'Products'), Tab(text: 'Modifiers')]),
        ),
        body: TabBarView(children: [
          Column(children: [
            filters(),
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (_, i) {
                  final p = products[i];
                  return SwitchListTile(
                    title: Text(p.displayName),
                    subtitle: Text('${p.sku} · ${formatPence(p.effectivePricePence)}${p.stock != null ? ' · ${p.stock} in stock' : ''}'),
                    secondary: Text(p.available ? 'Available' : 'Unavailable', style: TextStyle(color: p.available ? null : Theme.of(context).colorScheme.error)),
                    value: p.available,
                    onChanged: (v) => ctrl.setProductAvailability(p.variantId, v),
                  );
                },
              ),
            ),
          ]),
          Column(children: [
            filters(),
            Expanded(
              child: modifiers.isEmpty
                  ? const Center(child: Text('No modifiers set up. Modifier groups are managed in the ERP (POS → Modifiers).'))
                  : ListView.builder(
                      itemCount: modifiers.length,
                      itemBuilder: (_, i) {
                        final (g, m) = modifiers[i];
                        return SwitchListTile(
                          title: Text(m.name),
                          subtitle: Text('${g.name}${m.priceDeltaPence != 0 ? ' · ${formatPenceSigned(m.priceDeltaPence)}' : ''}'),
                          value: m.available,
                          onChanged: (v) => ctrl.setModifierAvailability(m.id, v),
                        );
                      },
                    ),
            ),
          ]),
        ]),
      ),
    );
  }
}
