import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const bool crossWindowDisplaySupported = true;

const _name = 'zaam-epos-customer-display';
const _storageKey = 'zaam_epos_customer_display';

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
  // Persist till→display state only (not sync pings) so a late-opened window can boot.
  if (message['type'] != 'requestSync') {
    try {
      web.window.localStorage.setItem(_storageKey, jsonEncode(message));
    } catch (_) {}
  }
  _ch.postMessage(jsonEncode(message).toJS);
  _local.add(message);
}

/// Last display payload written by the till (same-origin localStorage).
Map<String, dynamic>? readStoredDisplayMessage() {
  try {
    final raw = web.window.localStorage.getItem(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

Stream<Map<String, dynamic>> displayMessages() {
  _ch;
  return _local.stream;
}

/// Opens the customer display in a new browser window (drag it to the second screen).
/// [youtubeUrl] is also passed in the query so the video can start before BroadcastChannel arrives.
void openDisplayWindow({String youtubeUrl = ''}) {
  final loc = web.window.location;
  final q = <String, String>{'display': '1'};
  final yt = youtubeUrl.trim();
  if (yt.isNotEmpty) q['yt'] = yt;
  final url = Uri.parse('${loc.origin}${loc.pathname}').replace(queryParameters: q).toString();
  web.window.open(url, 'zaam_customer_display', 'popup=yes,width=1024,height=768');
}
