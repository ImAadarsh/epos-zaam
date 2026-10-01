import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/sync/connectivity.dart';
import '../../core/utils/app_log.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/shift_repository.dart';

/// Send Debug Data: uploads recent logs and device state (no secrets) for support.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload() {
    final outbox = ref.read(outboxProvider);
    final catalog = ref.read(catalogProvider);
    final shift = ref.read(shiftProvider);
    return {
      'note': _note.text.trim(),
      'online': ref.read(onlineProvider),
      'settings': ref.read(settingsProvider).toJson(includeSecrets: false),
      'catalog': {'products': catalog.products.length, 'lastSync': catalog.lastSync?.toIso8601String(), 'error': catalog.error},
      'shift': shift?.toJson(),
      'outbox': [
        for (final e in outbox.entries) {'type': e.type.name, 'status': e.status.name, 'attempts': e.attempts, 'error': e.lastError, 'summary': e.summary, 'createdAt': e.createdAt.toIso8601String()},
      ],
      'logs': AppLog.lines,
    };
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final session = ref.read(sessionProvider);
    try {
      await ref.read(apiClientProvider).post('/api/pos/debug', data: {
        'registerId': session.registerId,
        'deviceId': session.deviceId,
        'appVersion': AppConfig.appVersion,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'payload': _payload(),
      });
      if (mounted) showMessage(context, 'Debug data sent. Thank you.');
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = AppLog.lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Debug Data'),
        actions: [
          IconButton(
            tooltip: 'Copy log',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lines.join('\n')));
              showMessage(context, 'Log copied');
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'What went wrong? (optional)')),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: _busy ? null : _send, icon: const Icon(Icons.send), label: const Text('Send to Zaam support')),
            ),
            const SizedBox(height: 8),
            const Text('Includes app log, sync queue and settings. Passwords, tokens and payment keys are never sent.'),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: lines.length,
            itemBuilder: (_, i) => Text(lines[lines.length - 1 - i], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
      ]),
    );
  }
}
