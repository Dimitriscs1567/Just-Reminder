import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../domain/reminder.dart';
import '../../domain/reminder_runtime.dart';
import '../../domain/schedule_engine.dart';
import '../widget_storage_keys.dart';
import 'widget_snapshot.dart';

/// A reminder as listed for widget configuration.
class WidgetIndexEntry {
  const WidgetIndexEntry({
    required this.id,
    required this.name,
    required this.displayName,
    required this.archived,
  });

  final String id;
  final String name;
  final String displayName;
  final bool archived;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'displayName': displayName,
    'archived': archived,
  };
}

/// Reads and writes the widget data in home_widget storage and refreshes
/// the native widgets. Safe to use from background isolates.
class WidgetBridge {
  const WidgetBridge();

  /// Fully qualified Android `AppWidgetProvider`.
  static const androidProvider =
      'com.example.just_reminder.ReminderWidgetProvider';

  /// iOS WidgetKit `kind` of the reminder widget.
  static const iosKind = 'ReminderWidget';

  /// Android re-renders widgets at these many upcoming activations at most.
  static const maxScheduledRefreshes = 500;

  /// Writes every reminder's snapshot and the index, leaves tombstones for
  /// deleted reminders, schedules widget refreshes at upcoming activations
  /// (Android) and redraws the widgets.
  Future<void> publish({
    required List<Reminder> reminders,
    required Map<String, ReminderRuntime> runtimes,
    required ScheduleEngine engine,
    required DateTime now,
  }) async {
    final current = {for (final reminder in reminders) reminder.id: reminder};
    for (final entry in await readIndex()) {
      if (!current.containsKey(entry.id)) {
        await _writeJson(
          WidgetStorageKeys.snapshot(entry.id),
          deletedWidgetSnapshot(
            id: entry.id,
            name: entry.name,
            displayName: entry.displayName,
          ),
        );
      }
    }

    final refreshes = <int>{};
    for (final reminder in reminders) {
      final snapshot = buildWidgetSnapshot(
        reminder: reminder,
        runtime:
            runtimes[reminder.id] ??
            ReminderRuntime.initial(reminder.id, reminder.activeSince),
        engine: engine,
        now: now,
      );
      refreshes.addAll((snapshot['upcoming']! as List<Object?>).cast<int>());
      await _writeJson(WidgetStorageKeys.snapshot(reminder.id), snapshot);
    }
    await HomeWidget.saveWidgetData<String>(
      WidgetStorageKeys.index,
      jsonEncode([
        for (final reminder in reminders)
          WidgetIndexEntry(
            id: reminder.id,
            name: reminder.name,
            displayName: reminder.displayName,
            archived: reminder.isArchived,
          ).toJson(),
      ]),
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final times = refreshes.toList()..sort();
      await HomeWidget.scheduleWidgetUpdates(
        [
          for (final time in times.take(maxScheduledRefreshes))
            DateTime.fromMillisecondsSinceEpoch(time),
        ],
        qualifiedAndroidName: androidProvider,
      );
    }
    await updateWidgets();
  }

  /// Redraws all reminder widgets.
  Future<void> updateWidgets() => HomeWidget.updateWidget(
    qualifiedAndroidName: androidProvider,
    iOSName: iosKind,
  );

  Future<List<WidgetIndexEntry>> readIndex() async {
    final raw = await HomeWidget.getWidgetData<String>(WidgetStorageKeys.index);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return const [];
      return [
        for (final item in decoded.whereType<Map<String, Object?>>())
          WidgetIndexEntry(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? '',
            displayName: item['displayName'] as String? ?? '',
            archived: item['archived'] as bool? ?? false,
          ),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<Map<String, Object?>?> readSnapshot(String reminderId) async {
    final raw = await HomeWidget.getWidgetData<String>(
      WidgetStorageKeys.snapshot(reminderId),
    );
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeSnapshot(
    String reminderId,
    Map<String, Object?> snapshot,
  ) => _writeJson(WidgetStorageKeys.snapshot(reminderId), snapshot);

  /// Android: makes app widget [appWidgetId] show [reminderId].
  Future<void> assignAndroidWidget(int appWidgetId, String reminderId) async {
    await HomeWidget.saveWidgetData<String>(
      WidgetStorageKeys.androidWidget(appWidgetId),
      reminderId,
    );
    await updateWidgets();
  }

  Future<void> _writeJson(String key, Map<String, Object?> value) =>
      HomeWidget.saveWidgetData<String>(key, jsonEncode(value));
}
