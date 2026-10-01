import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display/customer_display.dart';

/// Connect Display: open the customer-facing screen.
class ConnectDisplayScreen extends ConsumerWidget {
  const ConnectDisplayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
              Text('Show the basket, total and change to the customer.', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              const SizedBox(height: 24),
              if (crossWindowDisplaySupported)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('Open customer display window'),
                    subtitle: const Text('Opens a second window. Drag it onto the customer-facing monitor and make it full screen.'),
                    onTap: openDisplayWindow,
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
