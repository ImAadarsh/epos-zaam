import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/brand.dart';
import '../../data/repositories/bootstrap_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/session.dart';
import '../../data/repositories/settings_repository.dart';

/// Signs this device in with a Zaam ERP account (admin, manager or POS user).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final _server = TextEditingController(text: ref.read(sessionProvider).baseUrl);
  bool _busy = false;
  bool _showServer = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(baseUrl: _server.text, email: _email.text, password: _password.text);
      await ref.read(bootstrapProvider.notifier).refresh();
      await ref.read(settingsProvider.notifier).applyOrgVat(ref.read(bootstrapProvider).taxCodes);
      ref.read(catalogProvider.notifier).sync(full: true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: ZaamLogo(height: 64)),
                    const SizedBox(height: 12),
                    Text('EPOS', textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w300)),
                    const SizedBox(height: 32),
                    Text('Sign in this till', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Use your Zaam ERP account. Staff then unlock the till with their PIN.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure)),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    if (_showServer) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'Server URL', prefixIcon: Icon(Icons.dns_outlined), helperText: 'Zaam API, e.g. https://erp-api.zaamaitech.co.uk'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _showServer = !_showServer),
                      icon: const Icon(Icons.settings_ethernet, size: 18),
                      label: Text(_showServer ? 'Hide server settings' : 'Server settings'),
                    ),
                    const SizedBox(height: 16),
                    Text('Zaam EPOS v${AppConfig.appVersion}', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
