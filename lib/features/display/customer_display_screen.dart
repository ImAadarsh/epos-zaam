import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/display/customer_display.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/brand.dart';

/// Standalone app for the customer display window (`?display=1`).
class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zaam – Customer display',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const CustomerDisplayView(),
    );
  }
}

class CustomerDisplayView extends StatefulWidget {
  const CustomerDisplayView({super.key});

  @override
  State<CustomerDisplayView> createState() => _CustomerDisplayViewState();
}

class _CustomerDisplayViewState extends State<CustomerDisplayView> {
  final _display = CustomerDisplay();
  StreamSubscription<DisplayState>? _sub;
  DisplayState _state = const DisplayState();
  Timer? _reset;

  @override
  void initState() {
    super.initState();
    _sub = _display.updates.listen((s) {
      _reset?.cancel();
      setState(() => _state = s);
      if (s.mode == 'done') _reset = Timer(const Duration(seconds: 15), () => setState(() => _state = DisplayState(storeName: s.storeName)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _state;
    Widget body;
    switch (s.mode) {
      case 'cart':
      case 'paying':
        body = Row(children: [
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.all(32),
              children: [
                for (final l in s.lines.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Text('${l.qty} ×', style: theme.textTheme.titleLarge?.copyWith(color: ZaamColors.gold)),
                      const SizedBox(width: 16),
                      Expanded(child: Text(l.name, style: theme.textTheme.titleLarge)),
                      Text(formatPence(l.pence), style: theme.textTheme.titleLarge),
                    ]),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: ZaamColors.charcoal,
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (s.discountPence > 0) Text('You saved ${formatPence(s.discountPence)}', style: theme.textTheme.titleLarge?.copyWith(color: ZaamColors.green)),
                const SizedBox(height: 12),
                Text(s.mode == 'paying' ? 'To pay' : 'Total', style: theme.textTheme.headlineSmall),
                FittedBox(child: Text(formatPence(s.totalPence - s.paidPence), style: theme.textTheme.displayLarge?.copyWith(color: ZaamColors.gold, fontWeight: FontWeight.w800))),
                if (s.paidPence > 0) Text('Paid ${formatPence(s.paidPence)} of ${formatPence(s.totalPence)}', style: theme.textTheme.titleMedium),
              ]),
            ),
          ),
        ]);
      case 'done':
        body = Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, size: 120, color: ZaamColors.green),
            const SizedBox(height: 16),
            Text(s.message ?? 'Thank you!', style: theme.textTheme.displaySmall),
            if (s.changePence > 0) ...[
              const SizedBox(height: 24),
              Text('Your change', style: theme.textTheme.headlineSmall),
              Text(formatPence(s.changePence), style: theme.textTheme.displayLarge?.copyWith(color: ZaamColors.gold, fontWeight: FontWeight.w800)),
            ],
          ]),
        );
      default:
        body = Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ZaamLogo(height: 96, mark: true),
            const SizedBox(height: 24),
            Text(s.storeName.isEmpty ? 'Welcome' : 'Welcome to ${s.storeName}', style: theme.textTheme.displaySmall),
          ]),
        );
    }
    return Scaffold(
      backgroundColor: ZaamColors.black,
      body: body,
    );
  }
}
