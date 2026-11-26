import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display/customer_display.dart';
import '../../core/scanner/socket_scanner.dart';
import '../../core/sync/sync_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/brand.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../dsale/direct_sale_screen.dart';
import '../options/options_screen.dart';
import '../register/register_screen.dart';
import '../sales/previous_sales_screen.dart';
import '../sell/cart_controller.dart';
import '../sell/sell_screen.dart';

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);

class ShellTab extends Notifier<int> {
  @override
  int build() => 0;
  void go(int index) => state = index;
}

/// Main till layout: Sell / D-Sale / Sales / Register / Options.
/// D-Sale is a temporary parallel Direct Sale till; product Sell is unchanged.
/// Add product & settings live under Options (manager-gated), not the main rail.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  static const dSaleTab = 1;
  static const salesTab = 2;
  static const registerTab = 3;
  static const optionsTab = 4;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _idle;
  StreamSubscription<void>? _displaySync;

  static const _destinations = [
    (Icons.shopping_basket_outlined, Icons.shopping_basket, 'Sell'),
    (Icons.calculate_outlined, Icons.calculate, 'D-Sale'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Sales'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Register'),
    (Icons.apps_outlined, Icons.apps, 'Options'),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(syncServiceProvider).start();
      _pushCustomerDisplay();
      _displaySync = ref.read(customerDisplayProvider).syncRequests.listen((_) => _pushCustomerDisplay());
    });
    _resetIdle();
  }

  void _pushCustomerDisplay() {
    final org = ref.read(bootstrapProvider).org;
    final yt = ref.read(settingsProvider).customerDisplayYoutubeUrl;
    final cart = ref.read(cartProvider);
    ref.read(customerDisplayProvider).show(
          DisplayState.fromCart(cart, ref.read(cartTotalsProvider), org?.name ?? '', youtubeUrl: yt),
        );
  }

  @override
  void dispose() {
    _idle?.cancel();
    _displaySync?.cancel();
    super.dispose();
  }

  void _resetIdle() {
    _idle?.cancel();
    final session = ref.read(sessionProvider.notifier);
    session.touch();
    // Re-check tokens on activity so a dead session cannot keep taking sales.
    Future.microtask(session.ensureAuthValid);
    final secs = ref.read(settingsProvider).autoLockSeconds;
    if (secs > 0) _idle = Timer(Duration(seconds: secs), () => ref.read(sessionProvider.notifier).lock());
  }

  void _go(int i) => ref.read(shellTabProvider.notifier).go(i);

  @override
  Widget build(BuildContext context) {
    ref.watch(socketScannerProvider);
    ref.listen(settingsProvider, (prev, next) {
      if (prev?.customerDisplayYoutubeUrl != next.customerDisplayYoutubeUrl) {
        _pushCustomerDisplay();
      }
    });
    final index = ref.watch(shellTabProvider).clamp(0, _destinations.length - 1);
    // Direct Sale is immersive till mode — hide the shell rail while active.
    final immersiveDirectSale = index == AppShell.dSaleTab;
    final tabs = const [
      SellScreen(),
      DirectSaleScreen(),
      PreviousSalesScreen(embedded: true),
      RegisterScreen(),
      OptionsScreen(),
    ];
    final body = IndexedStack(index: index, children: tabs);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f1): () => _go(0),
      const SingleActivator(LogicalKeyboardKey.f2): () => _go(1),
      const SingleActivator(LogicalKeyboardKey.f3): () => _go(2),
      const SingleActivator(LogicalKeyboardKey.f4): () => _go(3),
      const SingleActivator(LogicalKeyboardKey.f5): () => _go(4),
      const SingleActivator(LogicalKeyboardKey.f6): () => ref.read(syncServiceProvider).syncNow(),
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => ref.read(sessionProvider.notifier).lock(),
      const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () => ref.read(sessionProvider.notifier).lock(),
    };

    final Widget layout;
    if (context.isCompact) {
      layout = Scaffold(
        body: body,
        bottomNavigationBar: immersiveDirectSale
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: _go,
                height: 64,
                destinations: [
                  for (final d in _destinations)
                    NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3, tooltip: d.$3),
                ],
              ),
      );
    } else if (immersiveDirectSale) {
      layout = Scaffold(body: body);
    } else {
      layout = Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: SizedBox(
                width: 92,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(8, 10, 8, 6),
                        child: ZaamLogo(height: 28, mark: true),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _destinations.length,
                          itemBuilder: (ctx, i) {
                            final d = _destinations[i];
                            final selected = index == i;
                            final scheme = Theme.of(ctx).colorScheme;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Material(
                                color: selected ? scheme.secondaryContainer : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _go(i),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          selected ? d.$2 : d.$1,
                                          size: 22,
                                          color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          d.$3,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                                fontSize: 11,
                                                height: 1.1,
                                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                                color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Listener(
      onPointerDown: (_) => _resetIdle(),
      child: CallbackShortcuts(bindings: shortcuts, child: Focus(autofocus: true, child: layout)),
    );
  }
}
