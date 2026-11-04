import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/background/background_handlers.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';
import 'package:just_reminder/src/services/app_events.dart';
import 'package:just_reminder/src/services/widget/widget_snapshot.dart';

const engine = ScheduleEngine();
final now = DateTime(2026, 11, 4, 8);
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 11, 4, hour, minute);

final hourly = Reminder(
  id: 'r',
  name: 'Drink water',
  displayName: 'Water',
  schedule: const Schedule(
    recurrence: RepeatRecurrence(
      unit: RepeatUnit.day,
      startDate: LocalDate(2026, 11, 4),
    ),
    timing: RangeTiming(
      start: LocalTime(9, 0),
      end: LocalTime(12, 0),
      mode: RangeMode.interval,
    ),
  ),
  createdAt: now,
  updatedAt: now,
  activeSince: now,
);

/// Like storage: through a JSON string.
Map<String, Object?> stored(Map<String, Object?> snapshot) =>
    jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>;

Map<String, Object?> snapshotOf(Reminder reminder, ReminderRuntime runtime) =>
    stored(
      buildWidgetSnapshot(
        reminder: reminder,
        runtime: runtime,
        engine: engine,
        now: now,
      ),
    );

void main() {
  final fresh = ReminderRuntime.initial('r', now);

  test('lists upcoming activations and flips to waiting at each', () {
    final snapshot = snapshotOf(hourly, fresh);
    expect(snapshot['displayName'], 'Water');
    expect(snapshot['state'], 'live');
    expect(
      (snapshot['upcoming']! as List<Object?>).take(4),
      [for (final hour in [9, 10, 11, 12]) at(hour).millisecondsSinceEpoch],
    );

    expect(widgetStatusAt(snapshot, at(8, 59)).kind, WidgetStatusKind.clear);
    final atNine = widgetStatusAt(snapshot, at(9));
    expect(atNine.isWaiting, isTrue);
    expect(atNine.missed, 0);
    // Not acknowledged by 11:30: the 09:00 and 10:00 ones were missed.
    expect(widgetStatusAt(snapshot, at(11, 30)).missed, 2);
  });

  test('a waiting activation and its missed count carry over', () {
    final runtime = fresh.copyWith(pendingAt: at(7), missedCount: 1);
    final status = widgetStatusAt(snapshotOf(hourly, runtime), at(8));
    expect(status.isWaiting, isTrue);
    expect(status.missed, 1);
  });

  test('archived, paused and deleted reminders', () {
    expect(
      widgetStatusAt(
        snapshotOf(hourly.copyWith(archivedAt: now), fresh),
        at(10),
      ).kind,
      WidgetStatusKind.archived,
    );
    final paused = snapshotOf(hourly.copyWith(paused: true), fresh);
    expect(paused['state'], 'paused');
    expect(widgetStatusAt(paused, at(10)).kind, WidgetStatusKind.clear);
    expect(
      widgetStatusAt(
        stored(deletedWidgetSnapshot(id: 'r', name: 'x', displayName: 'y')),
        at(10),
      ).kind,
      WidgetStatusKind.deleted,
    );
    expect(widgetStatusAt(null, at(10)).kind, WidgetStatusKind.deleted);
  });

  test('acknowledging outside the app clears it and keeps the schedule', () {
    final waiting = snapshotOf(
      hourly,
      fresh.copyWith(pendingAt: at(7), missedCount: 2),
    );
    final acknowledged = stored(
      acknowledgedWidgetSnapshot(waiting, at: at(9, 30), engine: engine),
    );
    expect(widgetStatusAt(acknowledged, at(9, 31)).kind, WidgetStatusKind.clear);
    expect(acknowledged['pendingAt'], isNull);
    expect(acknowledged['missedCount'], 0);
    // The next activation still flips it.
    expect(widgetStatusAt(acknowledged, at(10)).isWaiting, isTrue);
  });

  test('widget URIs map to actions', () {
    expect(
      reminderToAcknowledge(Uri.parse('justreminder://acknowledge?id=abc')),
      'abc',
    );
    expect(reminderToAcknowledge(Uri.parse('justreminder://acknowledge')), isNull);
    expect(reminderToAcknowledge(Uri.parse('justreminder://reminder/abc')), isNull);

    expect(
      appEventForWidgetUri(Uri.parse('justreminder://reminder/abc?homeWidget')),
      isA<OpenReminder>().having((e) => e.reminderId, 'id', 'abc'),
    );
    expect(
      appEventForWidgetUri(Uri.parse('justreminder://widget-help?homeWidget')),
      isA<ExplainWidgetEditing>(),
    );
    expect(appEventForWidgetUri(Uri.parse('justreminder://other')), isNull);
  });
}
