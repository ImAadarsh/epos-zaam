import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openPlatformDatabase(String name) async {
  final dir = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase('${dir.path}/$name.db');
}

Future<void> deletePlatformDatabase(String name) async {
  final dir = await getApplicationSupportDirectory();
  await databaseFactoryIo.deleteDatabase('${dir.path}/$name.db');
}
