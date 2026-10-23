import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/security/permissions.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';
import '../../data/models/cart.dart';
import '../../data/models/catalog.dart';
import '../../data/models/org.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'cart_controller.dart';
import 'widgets/discount_dialog.dart';
import 'widgets/product_options_dialog.dart';

enum _PriceChangeScope { thisSaleOnly, permanent }

bool _overLimit(Discount d, int basePence, int maxPercent) {
  if (basePence <= 0) return false;
  return d.amountOn(basePence) * 100 > basePence * maxPercent;
}

/// Adds a product to the cart with the prompts configured in Settings:
/// unavailable / out-of-stock warnings, allergen question, variants and modifiers.
Future<void> addProductToCart(BuildContext context, WidgetRef ref, Product product, {bool fromScan = false}) async {
  final settings = ref.read(settingsProvider);
  final catalog = ref.read(catalogProvider);
  final cart = ref.read(cartProvider.notifier);

  final variants = catalog.variantsOf(product.catalogItemId).where((v) => v.active).toList();
  final groups = catalog.groupsFor(product);
  final needsChoice = (!fromScan && variants.length > 1) || groups.isNotEmpty;

  var chosen = product;
  var modifiers = const <Modifier>[];
  var quantity = 1;
  String? note;

  if (needsChoice) {
    final initial = variants.contains(product) ? product : (variants.firstWhere((v) => v.available && !v.outOfStock, orElse: () => product));
    final choice = await showProductOptions(context, variants: fromScan ? [product] : variants, initial: initial, groups: groups);
    if (choice == null || !context.mounted) return;
    chosen = choice.product;
    modifiers = choice.modifiers;
    quantity = choice.quantity;
    note = choice.note;
  }

  if (!chosen.available) {
    showMessage(context, '${chosen.displayName} is marked unavailable (Manage Availability).', error: true);
    return;
  }
  final stockProblem = cart.stockProblem(chosen, quantity);
  if (stockProblem != null) {
    showMessage(context, stockProblem, error: true);
    return;
  }
  if (settings.sellBeyondStock && settings.outOfStockPrompt && chosen.outOfStock) {
    final ok = await confirm(context, title: 'Out of stock', message: '${chosen.displayName} shows ${chosen.stock ?? 0} in stock. Sell it anyway?', confirmLabel: 'Sell anyway');
    if (!ok || !context.mounted) return;
  }
  if (settings.allergenPopup && !ref.read(cartProvider).allergenAsked) {
    final allergy = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Allergies'),
        content: const Text('Does the customer have any allergies we should know about?'),
        actions: [
          TextButton(
            onPressed: () async {
              final v = await promptText(ctx, title: 'Allergy details', hint: 'e.g. nuts, latex', confirmLabel: 'Add to order');
              if (ctx.mounted) Navigator.pop(ctx, v ?? '');
            },
            child: const Text('Yes'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('No')),
        ],
      ),
    );
    cart.markAllergenAsked();
    if (allergy != null && allergy.isNotEmpty) {
      final existing = ref.read(cartProvider).note;
      cart.setNote([if (existing != null && existing.isNotEmpty) existing, 'ALLERGY: $allergy'].join(' | '));
    }
    if (!context.mounted) return;
  }

  final error = cart.add(chosen, quantity: quantity, modifiers: modifiers, note: note);
  if (error != null && context.mounted) showMessage(context, error, error: true);
}

/// Applies a discount to the whole cart, asking for approval above the cashier limit.
Future<void> editCartDiscount(BuildContext context, WidgetRef ref) async {
  final cart = ref.read(cartProvider);
  final totals = ref.read(cartTotalsProvider);
  final base = totals.subtotalPence - totals.itemDiscountPence;
  final res = await showDiscountDialog(
    context,
    title: 'Cart discount',
    current: cart.cartDiscount,
    basePence: base,
    presets: ref.read(bootstrapProvider).discountPresets,
  );
  if (res == null || !context.mounted) return;
  final d = res.discount;
  if (d != null && _overLimit(d, base, ref.read(settingsProvider).maxCashierDiscountPercent)) {
    if (!await requirePermission(context, ref, Perm.discountOverLimit)) return;
  }
  ref.read(cartProvider.notifier).setCartDiscount(d);
}

/// Bottom sheet to change one cart line: quantity, price, discount, note or remove.
Future<void> editCartLine(BuildContext context, WidgetRef ref, CartLine line) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _LineEditor(lineId: line.id),
  );
}

/// Opens the "New quantity" keypad and applies the result via [CartController.setQuantity].
Future<void> editLineQuantity(BuildContext context, WidgetRef ref, CartLine line) async {
  final q = await promptQuantity(context, title: 'New quantity', initial: line.quantity, confirmLabel: 'Set quantity');
  if (q == null || !context.mounted) return;
  final error = ref.read(cartProvider.notifier).setQuantity(line.id, q);
  if (error != null) showMessage(context, error, error: true);
}

class _LineEditor extends ConsumerWidget {
  const _LineEditor({required this.lineId});
  final String lineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final line = cart.lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return const SizedBox(height: 120, child: Center(child: Text('Item removed')));
    final ctrl = ref.read(cartProvider.notifier);
    final theme = Theme.of(context);
    final settings = ref.read(settingsProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(line.product.displayName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            if (line.modifiers.isNotEmpty) Text(line.modifiers.map((m) => m.name).join(', ')),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Quantity'),
                const Spacer(),
                IconButton.filledTonal(iconSize: 28, onPressed: () => ctrl.increment(line.id, -1), icon: const Icon(Icons.remove)),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => editLineQuantity(context, ref, line),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SizedBox(width: 48, child: Text('${line.quantity}', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall)),
                  ),
                ),
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: () {
                    final error = ctrl.increment(line.id, 1);
                    if (error != null) showMessage(context, error, error: true);
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(line.discount == null ? 'Discount' : 'Discount ${line.discount!.label(formatPence)}'),
                  onPressed: () async {
                    final res = await showDiscountDialog(
                      context,
                      title: 'Item discount',
                      current: line.discount,
                      basePence: line.grossPence,
                      presets: ref.read(bootstrapProvider).discountPresets,
                    );
                    if (res == null || !context.mounted) return;
                    final d = res.discount;
                    if (d != null && _overLimit(d, line.grossPence, settings.maxCashierDiscountPercent)) {
                      if (!await requirePermission(context, ref, Perm.discountOverLimit)) return;
                    }
                    ctrl.updateLine(d == null ? line.copyWith(clearDiscount: true) : line.copyWith(discount: d));
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.pin_outlined),
                  label: const Text('Change quantity'),
                  onPressed: () => editLineQuantity(context, ref, line),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(line.priceOverridePence == null ? 'Change price' : 'Price changed'),
                  onPressed: () => editLinePrice(context, ref, line),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  label: Text(line.note == null || line.note!.isEmpty ? 'Note' : 'Edit note'),
                  onPressed: () async {
                    final n = await promptText(context, title: 'Item note', initial: line.note, allowEmpty: true);
                    if (n != null) ctrl.updateLine(line.copyWith(note: n));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: Colors.white),
              onPressed: () {
                ctrl.removeLine(line.id);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove item'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Change price: choose this-sale override vs permanent catalogue update, then keypad.
Future<void> editLinePrice(BuildContext context, WidgetRef ref, CartLine line) async {
  if (!await requirePermission(context, ref, Perm.priceOverride)) return;
  if (!context.mounted) return;

  if (line.priceOverridePence != null) {
    final restore = await confirm(
      context,
      title: 'Price already changed for this sale',
      message: 'Restore the catalogue price of ${formatPence(line.product.effectivePricePence)} on this line?',
      confirmLabel: 'Restore',
    );
    if (restore) {
      ref.read(cartProvider.notifier).updateLine(line.copyWith(clearPriceOverride: true));
      return;
    }
    if (!context.mounted) return;
  }

  final scope = await _pickPriceChangeScope(context, ref);
  if (scope == null || !context.mounted) return;

  if (scope == _PriceChangeScope.permanent) {
    if (!await requirePermission(context, ref, Perm.editCatalogPrice)) return;
    if (!context.mounted) return;
    if (!ref.read(onlineProvider)) {
      showMessage(context, 'Permanently changing the product price needs an online connection.', error: true);
      return;
    }
  }

  final pence = await promptAmount(
    context,
    title: scope == _PriceChangeScope.permanent ? 'New product price' : 'New unit price',
    initialPence: line.priceOverridePence ?? line.product.effectivePricePence,
    confirmLabel: scope == _PriceChangeScope.permanent ? 'Save permanently' : 'Set price',
    message: scope == _PriceChangeScope.permanent
        ? 'This updates the catalogue sell price for future sales too.'
        : 'Applies to this sale only. The product grid price stays the same.',
  );
  if (pence == null || !context.mounted) return;

  final ctrl = ref.read(cartProvider.notifier);
  if (scope == _PriceChangeScope.thisSaleOnly) {
    ctrl.updateLine(line.copyWith(priceOverridePence: pence));
    return;
  }

  try {
    final updated = await ref.read(catalogProvider.notifier).setPermanentSellPrice(line.product.variantId, pence);
    if (!context.mounted) return;
    ctrl.applyCatalogProduct(updated);
    showMessage(context, 'Product price saved as ${formatPence(updated.pricePence)}.');
  } catch (e) {
    if (context.mounted) {
      showMessage(context, 'Could not save permanent price: ${errorMessage(e)}. Cart and catalogue were left unchanged.', error: true);
    }
  }
}

Future<_PriceChangeScope?> _pickPriceChangeScope(BuildContext context, WidgetRef ref) {
  final staff = ref.read(currentStaffProvider);
  final canPermanent = can(staff, Perm.editCatalogPrice);
  final hasManagerPin = ref.read(bootstrapProvider).staff.any((s) => can(s, Perm.editCatalogPrice) && s.hasPin);

  return showDialog<_PriceChangeScope>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Change price'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('How should this price change apply?'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _PriceChangeScope.thisSaleOnly),
              child: const Text('This sale only'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: canPermanent || hasManagerPin
                  ? () => Navigator.pop(ctx, _PriceChangeScope.permanent)
                  : null,
              child: const Text('Permanently change product price'),
            ),
            if (!canPermanent && !hasManagerPin)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Permanent catalogue changes need a ${PosRole.manager.name}. Set a manager PIN in Settings → Staff PINs.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.error),
                ),
              )
            else if (!canPermanent)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'A manager PIN will be required to save permanently.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
    ),
  );
}
