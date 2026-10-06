import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display/customer_display.dart';
import '../../core/network/api_exception.dart';
import '../../core/scanner/camera_scanner.dart';
import '../../core/scanner/scan_bus.dart';
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
    final catalog = ref.read(catalogProvider);
    var product = catalog.byCode(code);
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
    try {
      product = await ref.read(catalogProvider.notifier).lookupRemote(code);
    } catch (_) {
      product = null;
    }
    if (!mounted) return;
    if (product != null) {
      await addProductToCart(context, ref, product, fromScan: true);
    } else {
      SystemSound.play(SystemSoundType.alert);
      showMessage(context, 'No product found for "$code"', error: true);
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
    return p.name.toLowerCase().contains(s) ||
        p.sku.toLowerCase().contains(s) ||
        (p.variantName?.toLowerCase().contains(s) ?? false) ||
        (p.brand?.toLowerCase().contains(s) ?? false) ||
        p.barcodes.any((b) => b.contains(s));
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
    final filtered = all.where((p) => (_category == null || p.category == _category) && _matches(p, _query)).toList();

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
      tiles = filtered;
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
                  onPressed: catalog.syncing ? null : () => ref.read(catalogProvider.notifier).sync(),
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
        Expanded(
          child: !catalog.loaded
              ? const Center(child: CircularProgressIndicator())
              : all.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('No products downloaded yet.'),
                        const SizedBox(height: 8),
                        if (catalog.error != null) Text(catalog.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 8),
                        FilledButton.tonal(onPressed: () => ref.read(catalogProvider.notifier).sync(full: true), child: const Text('Download products')),
                      ]),
                    )
                  : ProductGrid(
                      items: tiles,
                      variantCounts: _query.isEmpty ? variantCounts : const {},
                      minPrices: minPrices,
                      onTap: (p) => addProductToCart(context, ref, p),
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
