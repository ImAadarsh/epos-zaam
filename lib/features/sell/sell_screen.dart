import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display/customer_display.dart';
import '../../core/network/api_exception.dart';
import '../../core/scanner/camera_scanner.dart';
import '../../core/scanner/scan_bus.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/money.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/catalog.dart';
import '../../data/models/customer.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/shift_repository.dart';
import '../register/open_register_card.dart';
import '../sales/refund_screen.dart';
import '../shell/app_shell.dart';
import '../shell/status_bar.dart';
import 'cart_controller.dart';
import 'payment_screen.dart';
import 'sell_actions.dart';
import 'widgets/cart_panel.dart';
import 'widgets/category_bar.dart';
import 'widgets/product_details_sheet.dart';
import 'widgets/product_grid.dart';

class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  String? _category;
  StreamSubscription<ScanEvent>? _scanSub;

  @override
  void initState() {
    super.initState();
    _scanSub = ref.read(scanBusProvider).stream.listen((e) {
      if (!mounted || ref.read(shellTabProvider) != 0) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _handleCode(e.code);
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Barcodes, SKUs, table QR (`TABLE:12`), customer QR (`CUST:C-0042`) and receipt barcodes.
  Future<void> _handleCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    final upper = code.toUpperCase();
    final cart = ref.read(cartProvider.notifier);

    if (upper.startsWith('TABLE:')) {
      cart.setTable(code.substring(6).trim());
      showMessage(context, 'Table ${code.substring(6).trim()}');
      return;
    }
    if (upper.startsWith('CUST:')) {
      await _customerFromCode(code.substring(5).trim());
      return;
    }

    final product = await _resolveProductForCode(code);
    if (!mounted) return;
    if (product != null) {
      await addProductToCart(context, ref, product, fromScan: true);
      return;
    }

    final sale = ref.read(localSalesProvider.notifier).find(code);
    if (sale != null) {
      final open = await confirm(context, title: 'Receipt ${sale.receiptNumber}', message: 'This is a receipt barcode. Start a refund for it?', confirmLabel: 'Refund');
      if (open && mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => RefundScreen(initialCode: code)));
      return;
    }

    SystemSound.play(SystemSoundType.alert);
    showMessage(context, 'No product found for "$code"', error: true);
  }

  /// Exact barcode/SKU match. If several local twins share the code, prefer
  /// in-stock/active; if still ambiguous, ask the cashier (never silent wrong add).
  Future<Product?> _resolveProductForCode(String code) async {
    final catalog = ref.read(catalogProvider);
    final local = catalog.allByCode(code);
    if (local.length == 1) return local.first;
    if (local.length > 1) {
      final best = preferBarcodeMatch(local);
      final contenders = local.where((p) {
        final stockOk = p.stock == null || p.stock! > 0;
        final bestStockOk = best.stock == null || best.stock! > 0;
        return stockOk == bestStockOk && p.available == best.available;
      }).toList();
      if (contenders.length == 1) return contenders.first;
      if (!mounted) return null;
      final picked = await pickOption<Product>(
        context,
        title: 'Multiple products for "$code"',
        options: [
          for (final p in [...local]..sort(compareBarcodeCandidates))
            (
              p,
              '${p.displayName} · ${formatPence(p.effectivePricePence)}'
              '${p.stock != null ? ' · ${p.stock} in stock' : ''}'
              '${p.outOfStock ? ' · out of stock' : ''}'
              ' · ${p.sku}',
            ),
        ],
      );
      return picked;
    }

    try {
      return await ref.read(catalogProvider.notifier).lookupRemote(code);
    } catch (_) {
      return null;
    }
  }

  Future<void> _customerFromCode(String code) async {
    try {
      final rows = await ref.read(apiClientProvider).get('/api/pos/customers', query: {'search': code, 'limit': 5}) as List;
      final list = rows.map((r) => Customer.fromJson(Map<String, dynamic>.from(r as Map))).toList();
      final match = list.where((c) => c.customerNumber == code || c.id == code || c.email == code).firstOrNull ?? (list.length == 1 ? list.first : null);
      if (!mounted) return;
      if (match == null) {
        showMessage(context, 'Customer $code not found', error: true);
      } else {
        ref.read(cartProvider.notifier).setCustomer(match);
        showMessage(context, 'Customer: ${match.name}');
      }
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e), error: true);
    }
  }

  Future<void> _pay() async {
    if (ref.read(cartProvider).isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PaymentScreen()));
  }

  void _openCartSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 1,
        builder: (_, sc) => CartPanel(
          scrollController: sc,
          onPay: () {
            Navigator.pop(ctx);
            _pay();
          },
        ),
      ),
    );
  }

  bool _matches(Product p, String q) {
    if (q.isEmpty) return true;
    final s = q.toLowerCase();
    // Full numeric barcodes must match exactly — substring contains() let stale
    // local twins (and unrelated SKUs) appear beside the real product.
    if (looksLikeBarcode(q)) {
      return p.sku.toLowerCase() == s || p.barcodes.any((b) => b.toLowerCase() == s);
    }
    return p.name.toLowerCase().contains(s) ||
        p.sku.toLowerCase().contains(s) ||
        (p.variantName?.toLowerCase().contains(s) ?? false) ||
        (p.brand?.toLowerCase().contains(s) ?? false) ||
        p.barcodes.any((b) => b.toLowerCase().contains(s));
  }

  /// For barcode searches, collapse stale local twins to the single best match.
  List<Product> _tilesForQuery(List<Product> filtered, String q) {
    if (!looksLikeBarcode(q)) return filtered;
    final byCode = <String, List<Product>>{};
    for (final p in filtered) {
      final key = p.barcodes.map((b) => b.toLowerCase()).firstWhere((b) => b == q.toLowerCase(), orElse: () => p.sku.toLowerCase());
      byCode.putIfAbsent(key, () => []).add(p);
    }
    return [
      for (final group in byCode.values) preferBarcodeMatch(group),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(shiftProvider);
    ref.listen(cartProvider, (_, cart) {
      final org = ref.read(bootstrapProvider).org;
      ref.read(customerDisplayProvider).show(DisplayState.fromCart(cart, ref.read(cartTotalsProvider), org?.name ?? ''));
    });

    final register = ref.watch(currentRegisterProvider);
    final appBar = AppBar(
      title: Text(register?.name ?? 'Sell'),
      actions: [
        if (shift != null && context.isCompact)
          IconButton(
            tooltip: 'Scan with camera',
            onPressed: () async {
              final c = await scanWithCamera(context);
              if (c != null) _handleCode(c);
            },
            icon: const Icon(Icons.qr_code_scanner),
          ),
        const ShellStatusActions(),
      ],
    );

    if (shift == null) return Scaffold(appBar: appBar, body: const OpenRegisterCard());

    final catalog = ref.watch(catalogProvider);
    final all = catalog.sellable;
    final filtered = all.where((p) {
      if (!_matches(p, _query)) return false;
      if (_category == null) return true;
      return catalog.categoryLabelOf(p) == _category;
    }).toList();

    // One tile per catalogue item unless searching (then show matching variants directly).
    final variantCounts = <String, int>{};
    final minPrices = <String, int>{};
    for (final p in all) {
      variantCounts[p.catalogItemId] = (variantCounts[p.catalogItemId] ?? 0) + 1;
      final m = minPrices[p.catalogItemId];
      if (m == null || p.effectivePricePence < m) minPrices[p.catalogItemId] = p.effectivePricePence;
    }
    final List<Product> tiles;
    if (_query.isNotEmpty) {
      tiles = _tilesForQuery(filtered, _query);
    } else {
      final seen = <String>{};
      tiles = [for (final p in filtered) if (seen.add(p.catalogItemId)) p]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    final products = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Search or scan products',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                  onSubmitted: (v) async {
                    final code = v.trim();
                    if (code.isEmpty) return;
                    final exact = ref.read(catalogProvider).byCode(code);
                    if (exact != null || tiles.length != 1) {
                      await _handleCode(code);
                    } else {
                      await addProductToCart(context, ref, tiles.first);
                    }
                    setState(() {
                      _search.clear();
                      _query = '';
                    });
                    _searchFocus.requestFocus();
                  },
                ),
              ),
              if (!context.isCompact) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Scan with camera',
                  iconSize: 28,
                  onPressed: () async {
                    final c = await scanWithCamera(context);
                    if (c != null) _handleCode(c);
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                ),
                IconButton(
                  tooltip: 'Refresh products',
                  // Full sync clears hard-deleted ghosts that delta sync never tombstones.
                  onPressed: catalog.syncing ? null : () => ref.read(catalogProvider.notifier).sync(full: true),
                  icon: catalog.syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                ),
              ],
            ],
          ),
        ),
        CategoryBar(
          categories: catalog.categories,
          selected: _category,
          onSelected: (c) => setState(() => _category = c),
        ),
        if (catalog.error != null && all.isNotEmpty)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.cloud_off_outlined, color: Theme.of(context).colorScheme.onErrorContainer),
              title: Text(
                'Catalogue refresh failed — showing last downloaded products. ${catalog.error}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 13),
              ),
              trailing: TextButton(
                onPressed: catalog.syncing ? null : () => ref.read(catalogProvider.notifier).sync(full: true),
                child: const Text('Retry'),
              ),
            ),
          ),
        Expanded(
          child: !catalog.loaded
              ? const Center(child: CircularProgressIndicator())
              : all.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(
                            ref.watch(onlineProvider)
                                ? 'No products on this till yet'
                                : 'You are offline and no products are stored on this device',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ref.watch(onlineProvider)
                                ? 'Download the organisation catalogue, or use Options → Add product (manager) to create one.'
                                : 'Reconnect, then tap Download products. Sales can still use items already on the device.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          if (catalog.error != null) ...[
                            const SizedBox(height: 12),
                            Text(catalog.error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ],
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: catalog.syncing || !ref.watch(onlineProvider)
                                ? null
                                : () => ref.read(catalogProvider.notifier).sync(full: true),
                            child: Text(catalog.syncing ? 'Downloading…' : 'Download products'),
                          ),
                        ]),
                      ),
                    )
                  : ProductGrid(
                      items: tiles,
                      variantCounts: _query.isEmpty ? variantCounts : const {},
                      minPrices: minPrices,
                      onTap: (p) => addProductToCart(context, ref, p),
                      onLongPress: (p) => showProductDetails(context, ref, p),
                      onDetails: (p) => openProductLineActions(context, ref, p),
                    ),
        ),
      ],
    );

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f8): _pay,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _pay,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => _searchFocus.requestFocus(),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => editCartDiscount(context, ref),
    };

    final Widget body;
    if (context.isCompact) {
      final cart = ref.watch(cartProvider);
      final totals = ref.watch(cartTotalsProvider);
      body = Column(
        children: [
          Expanded(child: products),
          Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _openCartSheet,
                        child: Row(children: [
                          Badge(isLabelVisible: cart.itemCount > 0, label: Text('${cart.itemCount}'), child: const Icon(Icons.shopping_basket_outlined)),
                          const SizedBox(width: 12),
                          const Text('View sale'),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(onPressed: cart.isEmpty ? null : _pay, child: Text('Pay ${formatPence(totals.totalPence)}')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      final cartWidth = context.isExpanded ? 420.0 : 360.0;
      body = Row(
        children: [
          Expanded(child: products),
          const VerticalDivider(width: 1),
          SizedBox(width: cartWidth, child: CartPanel(onPay: _pay)),
        ],
      );
    }

    return CallbackShortcuts(bindings: shortcuts, child: Scaffold(appBar: appBar, body: body));
  }
}
