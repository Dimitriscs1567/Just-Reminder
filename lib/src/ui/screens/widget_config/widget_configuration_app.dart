import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';

import '../../../services/widget/widget_bridge.dart';
import '../../../services/widget/widget_snapshot.dart';
import '../../components/empty_state.dart';
import '../../components/status_icon.dart';
import '../../theme/app_theme.dart';

/// Android: picks the reminder a home screen widget shows. Runs in its own
/// activity and engine, opened by the launcher when the widget is added (or
/// by tapping a widget whose reminder is gone).
class WidgetConfigurationApp extends StatelessWidget {
  const WidgetConfigurationApp({required this.appWidgetId, super.key});

  final int appWidgetId;

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (lightDynamic, darkDynamic) => MaterialApp(
      title: 'Choose a reminder',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        lightDynamic?.harmonized() ?? fallbackColorScheme(Brightness.light),
      ),
      darkTheme: buildAppTheme(
        darkDynamic?.harmonized() ?? fallbackColorScheme(Brightness.dark),
      ),
      home: WidgetConfigurationScreen(appWidgetId: appWidgetId),
    ),
  );
}

class WidgetConfigurationScreen extends StatefulWidget {
  const WidgetConfigurationScreen({
    required this.appWidgetId,
    this.bridge = const WidgetBridge(),
    super.key,
  });

  final int appWidgetId;
  final WidgetBridge bridge;

  @override
  State<WidgetConfigurationScreen> createState() =>
      _WidgetConfigurationScreenState();
}

typedef _Choice = ({WidgetIndexEntry entry, WidgetStatus status});

class _WidgetConfigurationScreenState extends State<WidgetConfigurationScreen> {
  late final Future<List<_Choice>> _choices = _load();
  bool _saving = false;

  Future<List<_Choice>> _load() async {
    final now = DateTime.now();
    return [
      for (final entry in await widget.bridge.readIndex())
        if (!entry.archived)
          (
            entry: entry,
            status: widgetStatusAt(
              await widget.bridge.readSnapshot(entry.id),
              now,
            ),
          ),
    ];
  }

  Future<void> _choose(WidgetIndexEntry entry) async {
    setState(() => _saving = true);
    await widget.bridge.assignAndroidWidget(widget.appWidgetId, entry.id);
    await HomeWidget.finishHomeWidgetConfigure();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(onPressed: SystemNavigator.pop),
        title: const Text('Choose a reminder'),
      ),
      body: FutureBuilder(
        future: _choices,
        builder: (context, snapshot) {
          final choices = snapshot.data;
          if (choices == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (choices.isEmpty) {
            return const EmptyState(
              icon: Icons.widgets_outlined,
              title: 'No reminders yet',
              message:
                  'Create a reminder in Just Reminder first, then add the '
                  'widget again.',
              action: FilledButton(
                onPressed: SystemNavigator.pop,
                child: Text('Close'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: choices.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'The widget shows its display name and a thumbs up or '
                    'down. Tap the thumbs down on the widget to mark it done.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final (:entry, :status) = choices[index - 1];
              return Card(
                child: ListTile(
                  enabled: !_saving,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: StatusIcon(
                    kind: status.isWaiting
                        ? StatusIconKind.firing
                        : StatusIconKind.done,
                    size: 40,
                  ),
                  title: Text(entry.displayName),
                  subtitle: Text(entry.name),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _choose(entry),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
