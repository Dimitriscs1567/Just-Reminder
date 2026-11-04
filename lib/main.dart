import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/core/app_constants.dart';
import 'src/data/app_database.dart';
import 'src/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS: widget data lives in the App Group shared with the widget.
  await HomeWidget.setAppGroupId(iosAppGroupId);
  final database = await openAppDatabase();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const JustReminderApp(),
    ),
  );
}
