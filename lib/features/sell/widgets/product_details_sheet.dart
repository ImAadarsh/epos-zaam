import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/catalog_repository.dart';

/// Product details bar/sheet used from the line-item card and product grid.
Future<void> showProductDetails(BuildContext context, WidgetRef ref, Product product) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ProductDetailsSheet(variantId: product.variantId),
  );
}

class _ProductDetailsSheet extends ConsumerWidget {
  const _ProductDetailsSheet({required this.variantId});
  final String variantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalog = ref.watch(catalogProvider);
    final product = catalog.products[variantId];
    if (product == null) {
      return const SafeArea(child: SizedBox(height: 120, child: Center(child: Text('Product not found'))));
    }

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Expanded(child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
            ],
          ),
        );

    final stockLabel = product.stock == null ? 'Not tracked' : '${product.stock}';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text('Product details', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      product.imageUrl!,
                      fit: BoxFit.cover,
                      semanticLabel: 'Product image for ${product.displayName}',
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (product.imageUrl != null && product.imageUrl!.isNotEmpty) const SizedBox(height: 12),
              Text(product.displayName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              row('SKU', product.sku.isEmpty ? '—' : product.sku),
              row('Barcode', product.barcodes.isEmpty ? '—' : product.barcodes.join(', ')),
              row('Price', formatPence(product.effectivePricePence)),
              if (product.promoPricePence != null) row('Catalogue', formatPence(product.pricePence)),
              row('Stock on hand', stockLabel),
              if (product.category != null && product.category!.isNotEmpty) row('Category', product.category!),
              if (product.brand != null && product.brand!.isNotEmpty) row('Brand', product.brand!),
              row('Available', product.available ? 'Yes' : 'No'),
              if (product.description != null && product.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Description', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(product.description!.trim()),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }
}
