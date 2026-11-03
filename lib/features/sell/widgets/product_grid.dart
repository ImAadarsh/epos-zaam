import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/settings_repository.dart';

/// One tile per catalogue item; items with several variants open the options dialog.
class ProductGrid extends ConsumerWidget {
  const ProductGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.onDetails,
    this.variantCounts = const {},
    this.minPrices = const {},
  });

  final List<Product> items;
  final Map<String, int> variantCounts;
  final Map<String, int> minPrices;
  final ValueChanged<Product> onTap;
  final ValueChanged<Product>? onLongPress;
  final ValueChanged<Product>? onDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No products match this search or category.\nClear the search or tap All to see everything.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = settings.gridColumns > 0 ? settings.gridColumns : (c.maxWidth / 170).floor().clamp(2, 8);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          // Extra vertical room so barcode/SKU under the name stays visible.
          childAspectRatio: settings.showProductImages ? 0.72 : 1.05,
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
            onLongPress: onLongPress == null ? null : () => onLongPress!(p),
            onDetails: onDetails == null ? null : () => onDetails!(p),
          );
        },
      );
    });
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    this.onLongPress,
    this.onDetails,
    this.showImage = true,
    this.variants = 1,
    this.fromPrice,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDetails;
  final bool showImage;
  final int variants;
  final int? fromPrice;

  static const _palette = [Color(0xFFD4A017), Color(0xFF34495E), Color(0xFF8E6C8A), Color(0xFF2E8B57), Color(0xFFB5651D), Color(0xFF4A6FA5), Color(0xFF7B8D42)];

  /// Prefer barcode; fall back to SKU so staff can still verify the code on the tile.
  /// Multi-variant parent tiles omit a single barcode (misleading for other SKUs).
  String? get _codeLabel {
    if (variants > 1) return null;
    final barcode = product.barcodes.map((b) => b.trim()).firstWhere((b) => b.isNotEmpty, orElse: () => '');
    if (barcode.isNotEmpty) return barcode;
    final sku = product.sku.trim();
    return sku.isEmpty ? null : sku;
  }

  bool get _codeIsBarcode {
    final barcode = product.barcodes.map((b) => b.trim()).firstWhere((b) => b.isNotEmpty, orElse: () => '');
    return barcode.isNotEmpty;
  }

  String get _tileTitle => variants > 1 ? product.name : product.displayName;

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
          onLongPress: onLongPress,
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
                        child: Text(_tileTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
                      ),
                      if (_codeLabel != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          _codeIsBarcode ? _codeLabel! : 'SKU ${_codeLabel!}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.15,
                            height: 1.1,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(child: Text(price, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700))),
                          if (!showImage && (out || low)) Icon(Icons.inventory_2_outlined, size: 16, color: out ? ZaamColors.red : ZaamColors.amber),
                          if (onDetails != null) ...[
                            const SizedBox(width: 4),
                            // Nested InkWell so DETAILS does not fire the card's add-to-basket tap.
                            // Min 44×44 hit target for till touch (WCAG / ux-heuristics).
                            Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                onTap: onDetails,
                                borderRadius: BorderRadius.circular(8),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      child: Text(
                                        'DETAILS',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: ZaamColors.info,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
