import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'ui/routing/app_router.dart';
import 'ui/sync_scope.dart';
import 'ui/theme/app_theme.dart';

class JustReminderApp extends ConsumerWidget {
  const JustReminderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp.router(
        title: 'Just Reminder',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
          lightDynamic?.harmonized() ?? fallbackColorScheme(Brightness.light),
        ),
        darkTheme: buildAppTheme(
          darkDynamic?.harmonized() ?? fallbackColorScheme(Brightness.dark),
        ),
        routerConfig: router,
        builder: (context, child) => SyncScope(child: child!),
      ),
    );
  }
}
