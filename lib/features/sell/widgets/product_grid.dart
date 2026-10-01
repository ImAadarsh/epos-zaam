import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/settings_repository.dart';

/// One tile per catalogue item; items with several variants open the options dialog.
class ProductGrid extends ConsumerWidget {
  const ProductGrid({super.key, required this.items, required this.onTap, this.variantCounts = const {}, this.minPrices = const {}});

  final List<Product> items;
  final Map<String, int> variantCounts;
  final Map<String, int> minPrices;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (items.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No products match', textAlign: TextAlign.center)));
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = settings.gridColumns > 0 ? settings.gridColumns : (c.maxWidth / 170).floor().clamp(2, 8);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: settings.showProductImages ? 0.82 : 1.25,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final p = items[i];
          final count = variantCounts[p.catalogItemId] ?? 1;
          return ProductTile(
            product: p,
            showImage: settings.showProductImages,
            variants: count,
            fromPrice: count > 1 ? minPrices[p.catalogItemId] : null,
            onTap: () => onTap(p),
          );
        },
      );
    });
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap, this.showImage = true, this.variants = 1, this.fromPrice});

  final Product product;
  final VoidCallback onTap;
  final bool showImage;
  final int variants;
  final int? fromPrice;

  static const _palette = [Color(0xFFD4A017), Color(0xFF34495E), Color(0xFF8E6C8A), Color(0xFF2E8B57), Color(0xFFB5651D), Color(0xFF4A6FA5), Color(0xFF7B8D42)];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unavailable = !product.available;
    final stock = variants > 1 ? null : product.stock;
    final low = stock != null && stock > 0 && stock <= 3;
    final out = stock != null && stock <= 0;
    final tint = _palette[product.name.hashCode.abs() % _palette.length];
    final price = fromPrice != null ? 'from ${formatPence(fromPrice!)}' : formatPence(product.effectivePricePence);

    Widget placeholder() => Container(
          color: tint.withValues(alpha: 0.18),
          alignment: Alignment.center,
          child: Text(
            product.name.trim().isEmpty ? '?' : product.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join(),
            style: theme.textTheme.headlineSmall?.copyWith(color: tint, fontWeight: FontWeight.w700),
          ),
        );

    return Opacity(
      opacity: unavailable ? 0.45 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showImage)
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      product.imageUrl == null || product.imageUrl!.isEmpty
                          ? placeholder()
                          : Image.network(product.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder()),
                      if (out || low || unavailable || variants > 1)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: _Badge(
                            text: unavailable ? 'Unavailable' : out ? 'Out of stock' : low ? '$stock left' : '$variants options',
                            color: unavailable || out ? ZaamColors.red : low ? ZaamColors.amber : ZaamColors.info,
                          ),
                        ),
                      if (product.promoPricePence != null) const Positioned(top: 6, right: 6, child: _Badge(text: 'Offer', color: ZaamColors.green)),
                    ],
                  ),
                ),
              Expanded(
                flex: showImage ? 3 : 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
                      ),
                      Row(
                        children: [
                          Expanded(child: Text(price, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700))),
                          if (!showImage && (out || low)) Icon(Icons.inventory_2_outlined, size: 16, color: out ? ZaamColors.red : ZaamColors.amber),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}
