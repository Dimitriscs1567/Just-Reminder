import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import '../../../services/widget/widget_snapshot.dart';
import '../../components/status_icon.dart';
import '../../theme/app_theme.dart';

/// Android: the app around a widget setup screen. The launcher opens it in
/// its own activity and engine when a widget is added (or set up again).
class WidgetSetupApp extends StatelessWidget {
  const WidgetSetupApp({required this.title, required this.home, super.key});

  final String title;
  final Widget home;

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (lightDynamic, darkDynamic) => MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        lightDynamic?.harmonized() ?? fallbackColorScheme(Brightness.light),
      ),
      darkTheme: buildAppTheme(
        darkDynamic?.harmonized() ?? fallbackColorScheme(Brightness.dark),
      ),
      home: home,
    ),
  );
}

/// The app's icon for what a widget shows.
StatusIconKind widgetStatusIconKind(WidgetStatusKind kind) => switch (kind) {
  WidgetStatusKind.firing => StatusIconKind.firing,
  WidgetStatusKind.missed => StatusIconKind.missed,
  WidgetStatusKind.done => StatusIconKind.done,
  WidgetStatusKind.paused => StatusIconKind.paused,
  WidgetStatusKind.archived || WidgetStatusKind.deleted => StatusIconKind.muted,
};
