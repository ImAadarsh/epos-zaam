import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/session.dart';
import 'data/repositories/settings_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/pin_lock_screen.dart';
import 'features/auth/register_select_screen.dart';
import 'features/shell/app_shell.dart';

class ZaamEposApp extends ConsumerWidget {
  const ZaamEposApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (mode) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
      home: const RootGate(),
    );
  }
}

/// Picks the screen from session state: sign in → choose register → PIN → till.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final Widget child;
    if (!session.isLoggedIn) {
      child = const LoginScreen();
    } else if (session.registerId == null) {
      child = const RegisterSelectScreen();
    } else if (session.locked || session.staffId == null) {
      child = const PinLockScreen();
    } else {
      child = const AppShell();
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child));
  }
}
