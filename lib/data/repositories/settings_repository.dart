import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/app_log.dart';
import '../models/settings.dart';
import 'initial_data.dart';
import 'session.dart';

class SettingsController extends Notifier<PosSettings> {
  @override
  PosSettings build() {
    final j = ref.read(initialDataProvider).settings;
    return j == null ? const PosSettings() : PosSettings.fromJson(j);
  }

  Future<void> update(PosSettings Function(PosSettings s) change) async {
    state = change(state);
    await ref.read(localDbProvider).putKv('settings', state.toJson());
    _pushToRegister();
  }

  /// Adopts the register's saved settings the first time this device uses that register,
  /// keeping local secrets. Later edits on this device win.
  Future<void> applyRegisterDefaults(String registerId, Map<String, dynamic> registerSettings) async {
    final db = ref.read(localDbProvider);
    final applied = await db.getKv('register_defaults');
    if (registerSettings.isEmpty || applied?['registerId'] == registerId) return;
    final merged = {...state.toJson(), ...registerSettings, 'sumupApiKey': state.sumupApiKey};
    state = PosSettings.fromJson(merged);
    await db.putKv('settings', state.toJson());
    await db.putKv('register_defaults', {'registerId': registerId});
  }

  /// Best-effort: store non-secret settings on the register profile so other devices can reuse them.
  Future<void> _pushToRegister() async {
    final session = ref.read(sessionProvider);
    if (!session.isLoggedIn || session.registerId == null) return;
    try {
      await ref.read(apiClientProvider).patch('/api/pos/registers/${session.registerId}', data: {'settings': state.toJson(includeSecrets: false)});
    } catch (e) {
      AppLog.warn('Could not save settings to register: $e');
    }
  }
}

final settingsProvider = NotifierProvider<SettingsController, PosSettings>(SettingsController.new);
