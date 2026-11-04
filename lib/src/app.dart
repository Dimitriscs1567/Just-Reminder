import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import 'ui/routing/app_router.dart';

/// Fallback seed used when the platform offers no Material You colors
/// (iOS, Android < 12): indigo with teal accents.
const _fallbackSeed = Color(0xFF4F46E5);

class JustReminderApp extends StatelessWidget {
  const JustReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light =
            lightDynamic?.harmonized() ??
            ColorScheme.fromSeed(seedColor: _fallbackSeed);
        final dark =
            darkDynamic?.harmonized() ??
            ColorScheme.fromSeed(
              seedColor: _fallbackSeed,
              brightness: Brightness.dark,
            );
        return MaterialApp.router(
          title: 'Just Reminder',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: light),
          darkTheme: ThemeData(colorScheme: dark),
          routerConfig: appRouter,
        );
      },
    );
  }
}
