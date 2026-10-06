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

  @override
  Widget build(BuildContext context) {
    ref.watch(socketScannerProvider);
    final index = ref.watch(shellTabProvider);
    final tabs = const [SellScreen(), PreviousSalesScreen(embedded: true), RegisterScreen(), OptionsScreen()];
    final body = IndexedStack(index: index, children: tabs);
    void go(int i) => ref.read(shellTabProvider.notifier).go(i);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f1): () => go(0),
      const SingleActivator(LogicalKeyboardKey.f2): () => go(1),
      const SingleActivator(LogicalKeyboardKey.f3): () => go(2),
      const SingleActivator(LogicalKeyboardKey.f4): () => go(3),
      const SingleActivator(LogicalKeyboardKey.f5): () => ref.read(syncServiceProvider).syncNow(),
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => ref.read(sessionProvider.notifier).lock(),
      const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () => ref.read(sessionProvider.notifier).lock(),
    };

    final Widget layout;
    if (context.isCompact) {
      layout = Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: go,
          destinations: [for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
        ),
      );
    } else {
      layout = Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                selectedIndex: index,
                onDestinationSelected: go,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: ZaamLogo(height: 36, mark: true)),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3), padding: const EdgeInsets.symmetric(vertical: 4)),
                ],
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
