import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../../../data/models/catalog.dart';

class ProductChoice {
  const ProductChoice({required this.product, required this.modifiers, required this.quantity, this.note});
  final Product product;
  final List<Modifier> modifiers;
  final int quantity;
  final String? note;
}

/// Pick a variant (size/colour/strength…), modifiers, quantity and a note.
Future<ProductChoice?> showProductOptions(BuildContext context, {required List<Product> variants, required Product initial, required List<ModifierGroup> groups}) {
  return showDialog<ProductChoice>(context: context, builder: (_) => _ProductOptionsDialog(variants: variants, initial: initial, groups: groups));
}

class _ProductOptionsDialog extends StatefulWidget {
  const _ProductOptionsDialog({required this.variants, required this.initial, required this.groups});
  final List<Product> variants;
  final Product initial;
  final List<ModifierGroup> groups;

  @override
  State<_ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}

class _ProductOptionsDialogState extends State<_ProductOptionsDialog> {
  late Product _variant = widget.initial;
  final Map<String, Set<String>> _selected = {};
  int _qty = 1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<Modifier> get _chosen => [
        for (final g in widget.groups)
          for (final m in g.modifiers)
            if (_selected[g.id]?.contains(m.id) ?? false) m,
      ];

  String? get _problem {
    for (final g in widget.groups) {
      final n = _selected[g.id]?.length ?? 0;
      if (n < g.minSelect) return 'Choose ${g.minSelect == 1 ? 'an option' : 'at least ${g.minSelect}'} for ${g.name}';
    }
    return null;
  }

  void _toggle(ModifierGroup g, Modifier m) {
    setState(() {
      final set = _selected.putIfAbsent(g.id, () => <String>{});
      if (set.contains(m.id)) {
        set.remove(m.id);
      } else if (g.maxSelect == 1) {
        set
          ..clear()
          ..add(m.id);
      } else if (g.maxSelect <= 0 || set.length < g.maxSelect) {
        set.add(m.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = _variant.effectivePricePence + _chosen.fold<int>(0, (s, m) => s + m.priceDeltaPence);
    final problem = _problem;
    return AlertDialog(
      title: Text(widget.initial.name),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.variants.length > 1) ...[
                Text('Option', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in widget.variants)
                      ChoiceChip(
                        selected: v.variantId == _variant.variantId,
                        onSelected: v.available && v.active ? (_) => setState(() => _variant = v) : null,
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(v.variantLabel ?? v.sku),
                            Text(
                              '${formatPence(v.effectivePricePence)}${v.stock != null ? ' · ${v.stock} in stock' : ''}${!v.available ? ' · unavailable' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(color: v.outOfStock ? theme.colorScheme.error : null),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              for (final g in widget.groups) ...[
                Text(
                  '${g.name}${g.minSelect > 0 ? ' (required)' : ''}${g.maxSelect > 1 ? ' · up to ${g.maxSelect}' : ''}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in g.modifiers)
                      FilterChip(
                        selected: _selected[g.id]?.contains(m.id) ?? false,
                        onSelected: m.available ? (_) => _toggle(g, m) : null,
                        label: Text('${m.name}${m.priceDeltaPence != 0 ? ' ${m.priceDeltaPence > 0 ? '+' : ''}${formatPenceSigned(m.priceDeltaPence)}' : ''}'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Text('Quantity', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  IconButton.filledTonal(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
                  SizedBox(width: 48, child: Text('$_qty', textAlign: TextAlign.center, style: theme.textTheme.titleLarge)),
                  IconButton.filledTonal(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'Item note (optional)')),
              if (problem != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(problem, style: TextStyle(color: theme.colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: problem != null
              ? null
              : () => Navigator.pop(
                    context,
                    ProductChoice(product: _variant, modifiers: _chosen, quantity: _qty, note: _note.text.trim().isEmpty ? null : _note.text.trim()),
                  ),
          child: Text('Add · ${formatPence(unit * _qty)}'),
        ),
      ],
    );
  }
}
