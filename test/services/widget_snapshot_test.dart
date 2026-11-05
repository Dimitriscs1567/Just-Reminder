import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/background/background_handlers.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/runtime_advance.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';
import 'package:just_reminder/src/services/app_events.dart';
import 'package:just_reminder/src/services/widget/widget_snapshot.dart';

const engine = ScheduleEngine();
final created = DateTime(2026, 11, 4, 8);
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 11, 4, hour, minute);

/// 09:00–10:00 (missed at 10:00), 12:00 and 15:00, every day.
final reminder = Reminder(
  id: 'r',
  name: 'Drink water',
  displayName: 'Water',
  schedule: const Schedule(
    recurrence: RepeatRecurrence(
      unit: RepeatUnit.day,
      startDate: LocalDate(2026, 11, 4),
    ),
    times: [
      ReminderTime(start: LocalTime(9, 0), end: LocalTime(10, 0)),
      ReminderTime(start: LocalTime(12, 0)),
      ReminderTime(start: LocalTime(15, 0)),
    ],
  ),
  createdAt: created,
  updatedAt: created,
  activeSince: created,
);

/// Like storage: through a JSON string.
Map<String, Object?> stored(Map<String, Object?> snapshot) =>
    jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>;

/// The snapshot taken at [now], with the runtime as the app has it then.
Map<String, Object?> snapshotAt(DateTime now, {Reminder? of}) {
  final target = of ?? reminder;
  return stored(
    buildWidgetSnapshot(
      reminder: target,
      runtime: advanceReminder(
        reminder: target,
        runtime: ReminderRuntime.initial(target.id, created),
        engine: engine,
        now: now,
      ).runtime,
      engine: engine,
      now: now,
    ),
  );
}

void main() {
  test('lists when the next times become due, once per time', () {
    final snapshot = snapshotAt(at(8));
    expect(snapshot['displayName'], 'Water');
    expect(snapshot['state'], 'live');
    expect(
      (snapshot['upcoming']! as List<Object?>).take(3),
      [for (final hour in [9, 12, 15]) at(hour).millisecondsSinceEpoch],
    );
    expect((snapshot['occurrences']! as List<Object?>).first, {
      'start': at(9).millisecondsSinceEpoch,
      'due': at(9).millisecondsSinceEpoch,
      'missesAt': at(10).millisecondsSinceEpoch,
    });

    expect(widgetStatusAt(snapshot, at(8, 59)).kind, WidgetStatusKind.clear);
    expect(widgetStatusAt(snapshot, at(9)).isWaiting, isTrue);
  });

  test('a due time and its day’s missed count carry over', () {
    // 09:00 was missed at 10:00, 12:00 is due.
    final snapshot = snapshotAt(at(12, 5));
    expect(snapshot['pendingAt'], at(12).millisecondsSinceEpoch);
    expect(snapshot['missedCount'], 1);
    final status = widgetStatusAt(snapshot, at(12, 6));
    expect(status.isWaiting, isTrue);
    expect(status.missed, 1);
  });

  test('archived, paused and deleted reminders', () {
    expect(
      widgetStatusAt(
        snapshotAt(at(8), of: reminder.copyWith(archivedAt: at(8))),
        at(10),
      ).kind,
      WidgetStatusKind.archived,
    );
    final paused = snapshotAt(at(8), of: reminder.copyWith(paused: true));
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

  test('Done outside the app clears it and keeps the schedule', () {
    final due = snapshotAt(at(12, 5));
    final done = stored(doneWidgetSnapshot(due, at: at(12, 30), engine: engine));
    expect(widgetStatusAt(done, at(12, 31)).kind, WidgetStatusKind.clear);
    expect(done['pendingAt'], isNull);
    expect(done['pending'], isNull);
    // The next time still makes it due.
    expect(widgetStatusAt(done, at(15)).isWaiting, isTrue);
  });

  test('a Done finishes the latest due time that is not missed yet', () {
    final morning = snapshotAt(at(8));
    expect(dueOccurrenceStartAt(morning, at(8, 30)), isNull);
    expect(dueOccurrenceStartAt(morning, at(9, 30)), at(9));
    // 09:00–10:00 is missed at 10:00: nothing to finish until 12:00.
    expect(dueOccurrenceStartAt(morning, at(11)), isNull);
    expect(dueOccurrenceStartAt(morning, at(12, 5)), at(12));
    // From the snapshot's own due time.
    expect(dueOccurrenceStartAt(snapshotAt(at(12, 5)), at(12, 30)), at(12));
  });

  test('widget URIs map to actions', () {
    expect(
      reminderToMarkDone(Uri.parse('justreminder://acknowledge?id=abc')),
      'abc',
    );
    expect(reminderToMarkDone(Uri.parse('justreminder://acknowledge')), isNull);
    expect(reminderToMarkDone(Uri.parse('justreminder://reminder/abc')), isNull);

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
