import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/cart.dart';
import 'display_channel_io.dart' if (dart.library.js_interop) 'display_channel_web.dart' as channel;

export 'display_channel_io.dart' if (dart.library.js_interop) 'display_channel_web.dart'
    show crossWindowDisplaySupported, openDisplayWindow, readStoredDisplayMessage;

/// What the customer-facing screen shows.
///
/// Sale prices are never shown on the customer monitor — retailers play a
/// YouTube marketing video instead. [mode] `done` can briefly overlay a thank-you.
class DisplayState {
  const DisplayState({
    this.mode = 'idle',
    this.storeName = '',
    this.youtubeUrl = '',
    this.changePence = 0,
    this.message,
  });

  /// idle | cart | paying | done — cart/paying still play marketing (no prices).
  final String mode;
  final String storeName;
  final String youtubeUrl;
  final int changePence;
  final String? message;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'storeName': storeName,
        'youtubeUrl': youtubeUrl,
        'changePence': changePence,
        'message': message,
      };

  factory DisplayState.fromJson(Map<String, dynamic> j) => DisplayState(
        mode: '${j['mode'] ?? 'idle'}',
        storeName: '${j['storeName'] ?? ''}',
        youtubeUrl: '${j['youtubeUrl'] ?? ''}',
        changePence: (j['changePence'] as num?)?.toInt() ?? 0,
        message: j['message'] as String?,
      );

  static DisplayState fromCart(Cart cart, CartTotals totals, String storeName, {String youtubeUrl = ''}) => DisplayState(
        mode: cart.isEmpty ? 'idle' : 'cart',
        storeName: storeName,
        youtubeUrl: youtubeUrl,
      );

  DisplayState withMode(String mode) => DisplayState(
        mode: mode,
        storeName: storeName,
        youtubeUrl: youtubeUrl,
        changePence: changePence,
        message: message,
      );
}

DisplayState? readStoredDisplayState() {
  final j = channel.readStoredDisplayMessage();
  if (j == null || j['type'] == 'requestSync') return null;
  return DisplayState.fromJson(j);
}

class CustomerDisplay {
  void show(DisplayState state) => channel.postDisplayMessage(state.toJson());

  /// Customer window asks the till to re-broadcast (BroadcastChannel has no backlog).
  void requestSync() => channel.postDisplayMessage(const {'type': 'requestSync'});

  Stream<DisplayState> get updates => channel.displayMessages().where((m) => m['type'] != 'requestSync').map(DisplayState.fromJson);

  Stream<void> get syncRequests => channel.displayMessages().where((m) => m['type'] == 'requestSync').map((_) {});
}

final customerDisplayProvider = Provider<CustomerDisplay>((ref) => CustomerDisplay());
