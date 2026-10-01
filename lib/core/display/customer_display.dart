import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/cart.dart';
import 'display_channel_io.dart' if (dart.library.js_interop) 'display_channel_web.dart' as channel;

export 'display_channel_io.dart' if (dart.library.js_interop) 'display_channel_web.dart' show crossWindowDisplaySupported, openDisplayWindow;

/// What the customer-facing screen shows.
class DisplayState {
  const DisplayState({this.mode = 'idle', this.storeName = '', this.lines = const [], this.totalPence = 0, this.discountPence = 0, this.paidPence = 0, this.changePence = 0, this.message});

  /// idle | cart | paying | done
  final String mode;
  final String storeName;
  final List<({String name, int qty, int pence})> lines;
  final int totalPence;
  final int discountPence;
  final int paidPence;
  final int changePence;
  final String? message;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'storeName': storeName,
        'lines': [for (final l in lines) {'name': l.name, 'qty': l.qty, 'pence': l.pence}],
        'totalPence': totalPence,
        'discountPence': discountPence,
        'paidPence': paidPence,
        'changePence': changePence,
        'message': message,
      };

  factory DisplayState.fromJson(Map<String, dynamic> j) => DisplayState(
        mode: '${j['mode'] ?? 'idle'}',
        storeName: '${j['storeName'] ?? ''}',
        lines: [
          for (final l in (j['lines'] as List? ?? []))
            (name: '${(l as Map)['name']}', qty: (l['qty'] as num?)?.toInt() ?? 1, pence: (l['pence'] as num?)?.toInt() ?? 0),
        ],
        totalPence: (j['totalPence'] as num?)?.toInt() ?? 0,
        discountPence: (j['discountPence'] as num?)?.toInt() ?? 0,
        paidPence: (j['paidPence'] as num?)?.toInt() ?? 0,
        changePence: (j['changePence'] as num?)?.toInt() ?? 0,
        message: j['message'] as String?,
      );

  static DisplayState fromCart(Cart cart, CartTotals totals, String storeName) => cart.isEmpty
      ? DisplayState(storeName: storeName)
      : DisplayState(
          mode: 'cart',
          storeName: storeName,
          lines: [for (final l in totals.lines) (name: l.line.product.displayName, qty: l.line.quantity, pence: l.totalPence)],
          totalPence: totals.totalPence,
          discountPence: totals.discountPence,
        );
}

class CustomerDisplay {
  void show(DisplayState state) => channel.postDisplayMessage(state.toJson());

  Stream<DisplayState> get updates => channel.displayMessages().map(DisplayState.fromJson);
}

final customerDisplayProvider = Provider<CustomerDisplay>((ref) => CustomerDisplay());
