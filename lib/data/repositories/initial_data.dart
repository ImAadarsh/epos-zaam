import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/ids.dart';

/// Snapshot of persisted state read before `runApp`, so providers can build
/// synchronously on start-up (including fully offline starts).
class InitialData {
  const InitialData({
    required this.deviceId,
    this.session,
    this.settings,
    this.bootstrap,
    this.shift,
    this.cart,
    this.meta = const {},
  });

  final String deviceId;
  final Map<String, dynamic>? session;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? bootstrap;
  final Map<String, dynamic>? shift;
  final Map<String, dynamic>? cart;
  final Map<String, dynamic> meta;

  static Future<InitialData> load(LocalDb db) async {
    var device = await db.getKv('device');
    if (device == null || device['id'] == null) {
      device = {'id': newId()};
      await db.putKv('device', device);
    }
    return InitialData(
      deviceId: '${device['id']}',
      session: await db.getKv('session'),
      settings: await db.getKv('settings'),
      bootstrap: await db.getKv('bootstrap'),
      shift: await db.getKv('shift'),
      cart: await db.getKv('cart'),
      meta: await db.getKv('meta') ?? const {},
    );
  }
}

final initialDataProvider = Provider<InitialData>((ref) => throw UnimplementedError('InitialData not loaded'));
