import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const bool crossWindowDisplaySupported = true;

const _name = 'zaam-epos-customer-display';
web.BroadcastChannel? _channel;
final _local = StreamController<Map<String, dynamic>>.broadcast();

web.BroadcastChannel get _ch {
  final existing = _channel;
  if (existing != null) return existing;
  final c = web.BroadcastChannel(_name);
  c.onmessage = ((web.MessageEvent e) {
    final data = e.data;
    if (data == null) return;
    try {
      final decoded = jsonDecode((data as JSString).toDart);
      if (decoded is Map) _local.add(Map<String, dynamic>.from(decoded));
    } catch (_) {}
  }).toJS;
  _channel = c;
  return c;
}

void postDisplayMessage(Map<String, dynamic> message) {
  _ch.postMessage(jsonEncode(message).toJS);
  _local.add(message);
}

Stream<Map<String, dynamic>> displayMessages() {
  _ch;
  return _local.stream;
}

/// Opens the customer display in a new browser window (drag it to the second screen).
void openDisplayWindow() {
  final loc = web.window.location;
  final url = '${loc.origin}${loc.pathname}?display=1';
  web.window.open(url, 'zaam_customer_display', 'popup=yes,width=1024,height=768');
}
