import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// File name of the sembast database in the app support directory.
const databaseFileName = 'just_reminder.db';

/// Schema version; bump it and add an `onVersionChanged` migration when the
/// stored format changes.
const databaseVersion = 1;

/// Opens the app's database. Only ever call this from the main isolate:
/// sembast is not safe to open from several isolates at once.
Future<Database> openAppDatabase() async {
  final directory = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase(
    '${directory.path}/$databaseFileName',
    version: databaseVersion,
  );
}
