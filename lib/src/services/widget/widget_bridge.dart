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

  /// Fully qualified Android `AppWidgetProvider` of the one-reminder
  /// widget.
  static const androidProvider =
      'com.example.just_reminder.ReminderWidgetProvider';

  /// Fully qualified Android `AppWidgetProvider` of the list widget.
  static const androidListProvider =
      'com.example.just_reminder.ReminderListWidgetProvider';

  /// iOS WidgetKit `kind` of the one-reminder widget.
  static const iosKind = 'ReminderWidget';

  /// iOS WidgetKit `kind` of the list widget.
  static const iosListKind = 'ReminderListWidget';

  /// Android redraws the widgets at this many upcoming changes at most.
  static const maxScheduledRefreshes = 500;

  /// Writes every reminder's snapshot and the index, leaves tombstones for
  /// deleted reminders, schedules widget redraws at the upcoming changes
  /// (Android; iOS timelines have an entry per change) and redraws the
  /// widgets.
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
      refreshes.addAll([
        for (final time in widgetChangeTimes(snapshot))
          time.millisecondsSinceEpoch,
      ]);
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
      final times = [
        for (final time in (refreshes.toList()..sort()).take(
          maxScheduledRefreshes,
        ))
          DateTime.fromMillisecondsSinceEpoch(time),
      ];
      // One schedule per provider (home_widget keeps them apart).
      for (final provider in [androidProvider, androidListProvider]) {
        await HomeWidget.scheduleWidgetUpdates(
          times,
          qualifiedAndroidName: provider,
        );
      }
    }
    await updateWidgets();
  }

  /// Redraws all widgets (one-reminder and list widgets).
  Future<void> updateWidgets() async {
    await HomeWidget.updateWidget(
      qualifiedAndroidName: androidProvider,
      iOSName: iosKind,
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: androidListProvider,
      iOSName: iosListKind,
    );
  }

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

  /// Android: the reminders list widget [appWidgetId] shows, in order
  /// (empty when it isn't set up yet).
  Future<List<String>> readAndroidList(int appWidgetId) async {
    final raw = await HomeWidget.getWidgetData<String>(
      WidgetStorageKeys.androidListWidget(appWidgetId),
    );
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List<Object?>
          ? decoded.whereType<String>().toList()
          : const [];
    } on FormatException {
      return const [];
    }
  }

  /// Android: makes list widget [appWidgetId] show [reminderIds], in this
  /// order.
  Future<void> assignAndroidList(
    int appWidgetId,
    List<String> reminderIds,
  ) async {
    await HomeWidget.saveWidgetData<String>(
      WidgetStorageKeys.androidListWidget(appWidgetId),
      jsonEncode(reminderIds),
    );
    await updateWidgets();
  }

  Future<void> _writeJson(String key, Map<String, Object?> value) =>
      HomeWidget.saveWidgetData<String>(key, jsonEncode(value));
}
