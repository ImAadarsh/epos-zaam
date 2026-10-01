import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/local_db.dart';
import 'core/utils/app_log.dart';
import 'data/repositories/initial_data.dart';
import 'features/display/customer_display_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // `?display=1` opens the customer-facing screen (web second window).
  if (Uri.base.queryParameters['display'] == '1') {
    runApp(const CustomerDisplayApp());
    return;
  }

  FlutterError.onError = (details) {
    AppLog.error('Flutter error', details.exceptionAsString());
    FlutterError.presentError(details);
  };

  final db = await LocalDb.open();
  final initial = await InitialData.load(db);
  AppLog.info('App started (device ${initial.deviceId})');

  runApp(ProviderScope(
    overrides: [
      localDbProvider.overrideWithValue(db),
      initialDataProvider.overrideWithValue(initial),
    ],
    child: const ZaamEposApp(),
  ));
}
