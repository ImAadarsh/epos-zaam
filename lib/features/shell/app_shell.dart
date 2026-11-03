import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/scanner/socket_scanner.dart';
import '../../core/sync/sync_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/brand.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../catalog/add_product_screen.dart';
import '../catalog/add_variant_screen.dart';
import '../options/options_screen.dart';
import '../register/register_screen.dart';
import '../sales/previous_sales_screen.dart';
import '../sell/sell_screen.dart';

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);

class ShellTab extends Notifier<int> {
  @override
  int build() => 0;
  void go(int index) => state = index;
}

/// Main till layout: bottom navigation on phones, a rail on tablets/desktop.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Shell tab index for Add Prod. (manager-gated on select).
  static const addProductTab = 4;

  /// Shell tab index for Add Vt's. (manager-gated on select).
  static const addVariantTab = 5;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _idle;

  static const _destinations = [
    (Icons.shopping_basket_outlined, Icons.shopping_basket, 'Sell'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Sales'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Register'),
    (Icons.apps_outlined, Icons.apps, 'Options'),
    (Icons.add_box_outlined, Icons.add_box, 'Add Prod.'),
    (Icons.style_outlined, Icons.style, "Add Vt's."),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(syncServiceProvider).start());
    _resetIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _resetIdle() {
    _idle?.cancel();
    ref.read(sessionProvider.notifier).touch();
    final secs = ref.read(settingsProvider).autoLockSeconds;
    if (secs > 0) _idle = Timer(Duration(seconds: secs), () => ref.read(sessionProvider.notifier).lock());
  }

  Future<void> _go(int i) async {
    if (i == AppShell.addProductTab || i == AppShell.addVariantTab) {
      if (!await ensureCanAddProduct(context, ref) || !mounted) return;
    }
    ref.read(shellTabProvider.notifier).go(i);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(socketScannerProvider);
    final index = ref.watch(shellTabProvider);
    final tabs = const [
      SellScreen(),
      PreviousSalesScreen(embedded: true),
      RegisterScreen(),
      OptionsScreen(),
      AddProductScreen(embedded: true),
      AddVariantScreen(embedded: true),
    ];
    final body = IndexedStack(index: index, children: tabs);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f1): () => _go(0),
      const SingleActivator(LogicalKeyboardKey.f2): () => _go(1),
      const SingleActivator(LogicalKeyboardKey.f3): () => _go(2),
      const SingleActivator(LogicalKeyboardKey.f4): () => _go(3),
      const SingleActivator(LogicalKeyboardKey.f6): () => _go(AppShell.addProductTab),
      const SingleActivator(LogicalKeyboardKey.f7): () => _go(AppShell.addVariantTab),
      const SingleActivator(LogicalKeyboardKey.f5): () => ref.read(syncServiceProvider).syncNow(),
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => ref.read(sessionProvider.notifier).lock(),
      const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () => ref.read(sessionProvider.notifier).lock(),
    };

    final Widget layout;
    if (context.isCompact) {
      // 6 destinations: only show the selected label so Add Prod. / Add Vt's. stay on-screen.
      layout = Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _go,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3, tooltip: d.$3),
          ],
        ),
      );
    } else {
      // Custom scrollable rail — Material NavigationRail clips tall destination lists
      // on laptop heights (Options / Add Prod. / Add Vt's. fall below the fold).
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
