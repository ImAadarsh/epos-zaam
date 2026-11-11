import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display/customer_display.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../sell/cart_controller.dart';

/// Connect Display: open the customer-facing marketing screen.
class ConnectDisplayScreen extends ConsumerWidget {
  const ConnectDisplayScreen({super.key});

  void _pushState(WidgetRef ref) {
    final org = ref.read(bootstrapProvider).org;
    final yt = ref.read(settingsProvider).customerDisplayYoutubeUrl;
    final cart = ref.read(cartProvider);
    ref.read(customerDisplayProvider).show(
          DisplayState.fromCart(cart, ref.read(cartTotalsProvider), org?.name ?? '', youtubeUrl: yt),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final yt = ref.watch(settingsProvider).customerDisplayYoutubeUrl;
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Display')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Icon(Icons.connected_tv, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Customer screen shows a YouTube marketing video — not basket prices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                yt.isEmpty
                    ? 'Set the video in Settings → Customer display first.'
                    : 'Video: $yt',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (crossWindowDisplaySupported)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('Open customer display window'),
                    subtitle: const Text('Drag it onto the customer-facing monitor and make it full screen.'),
                    onTap: () {
                      _pushState(ref);
                      openDisplayWindow(youtubeUrl: yt);
                      // Re-push after the popup has started Flutter (BroadcastChannel is fire-and-forget).
                      Future<void>.delayed(const Duration(milliseconds: 800), () {
                        _pushState(ref);
                      });
                      Future<void>.delayed(const Duration(milliseconds: 2500), () {
                        _pushState(ref);
                      });
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                crossWindowDisplaySupported
                    ? 'The display window must be opened from this browser on the same computer.'
                    : 'A separate customer display for this till works with the web version on a second monitor. Pairing a separate display device over the network is not available yet.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
