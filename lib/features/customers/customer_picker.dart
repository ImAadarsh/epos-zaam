import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/scanner/camera_scanner.dart';
import '../../core/utils/money.dart';
import '../../data/models/customer.dart';
import '../../data/repositories/session.dart';

/// Search ERP customers (name, email, phone, number), scan a customer QR or add a new one.
Future<Customer?> showCustomerPicker(BuildContext context) =>
    showDialog<Customer>(context: context, builder: (_) => const _CustomerPicker());

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Customer> _results = [];
  bool _loading = false;
  String? _error;
  bool _creating = false;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _optIn = true;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_search, _first, _last, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(apiClientProvider).get('/api/pos/customers', query: {'search': q, 'limit': 30}) as List;
      if (!mounted) return;
      setState(() => _results = rows.map((r) => Customer.fromJson(Map<String, dynamic>.from(r as Map))).toList());
    } catch (e) {
      if (mounted) setState(() => _error = (e is ApiException && e.isNetwork) ? 'Customer search needs a connection.' : errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiClientProvider).post('/api/pos/customers', data: {
        'firstName': _first.text.trim().isEmpty ? null : _first.text.trim(),
        'lastName': _last.text.trim().isEmpty ? null : _last.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'marketingOptIn': _optIn,
      });
      if (mounted) Navigator.pop(context, Customer.fromJson(Map<String, dynamic>.from(res as Map)));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_creating ? 'New customer' : 'Customer'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: _creating
            ? ListView(children: [
                Row(children: [
                  Expanded(child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'First name'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _last, decoration: const InputDecoration(labelText: 'Last name'))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 10),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
                CheckboxListTile(value: _optIn, onChanged: (v) => setState(() => _optIn = v ?? false), title: const Text('Happy to receive offers by email'), contentPadding: EdgeInsets.zero),
                if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ])
            : Column(children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Name, email, phone or number', prefixIcon: Icon(Icons.search)),
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () => _run(v.trim()));
                      },
                    ),
                  ),
                  if (cameraScanSupported)
                    IconButton(
                      tooltip: 'Scan customer QR',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () async {
                        final code = await scanWithCamera(context, title: 'Scan customer QR');
                        if (code == null) return;
                        final c = code.toUpperCase().startsWith('CUST:') ? code.substring(5) : code;
                        _search.text = c;
                        _run(c);
                      },
                    ),
                ]),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                Expanded(
                  child: ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final c = _results[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                        title: Text(c.name),
                        subtitle: Text([c.email, c.phone, c.customerNumber].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
                        trailing: c.totalOrders > 0 ? Text('${c.totalOrders} orders\n${formatPence(toPence(c.lifetimeValue))}', textAlign: TextAlign.end, style: theme.textTheme.bodySmall) : null,
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
                ),
              ]),
      ),
      actions: _creating
          ? [
              TextButton(onPressed: () => setState(() => _creating = false), child: const Text('Back')),
              FilledButton(onPressed: _loading ? null : _create, child: const Text('Add customer')),
            ]
          : [
              TextButton.icon(onPressed: () => setState(() => _creating = true), icon: const Icon(Icons.person_add_alt), label: const Text('New customer')),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
    );
  }
}
