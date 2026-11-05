import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/background/background_handlers.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/reminder_standing.dart';
import 'package:just_reminder/src/domain/runtime_advance.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';
import 'package:just_reminder/src/services/app_events.dart';
import 'package:just_reminder/src/services/widget/widget_snapshot.dart';

const engine = ScheduleEngine();
final created = DateTime(2026, 11, 4, 8);
DateTime at(int hour, [int minute = 0, int day = 4]) =>
    DateTime(2026, 11, day, hour, minute);
int ms(DateTime time) => time.millisecondsSinceEpoch;

Reminder daily(List<ReminderTime> times, {String id = 'r'}) => Reminder(
  id: id,
  name: 'Drink water',
  displayName: 'Water',
  schedule: Schedule(
    recurrence: const RepeatRecurrence(
      unit: RepeatUnit.day,
      startDate: LocalDate(2026, 11, 4),
    ),
    times: times,
  ),
  createdAt: created,
  updatedAt: created,
  activeSince: created,
);

/// 09:00–10:00 (missed at 10:00), 12:00 and 15:00, every day.
final reminder = daily(const [
  ReminderTime(start: LocalTime(9, 0), end: LocalTime(10, 0)),
  ReminderTime(start: LocalTime(12, 0)),
  ReminderTime(start: LocalTime(15, 0)),
]);

/// Like storage: through a JSON string.
Map<String, Object?> stored(Map<String, Object?> snapshot) =>
    jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>;

ReminderRuntime runtimeAt(DateTime now, Reminder of) => advanceReminder(
  reminder: of,
  runtime: ReminderRuntime.initial(of.id, created),
  engine: engine,
  now: now,
).runtime;

/// The snapshot taken at [now], with the runtime as the app has it then.
Map<String, Object?> snapshotAt(DateTime now, {Reminder? of}) {
  final target = of ?? reminder;
  return stored(
    buildWidgetSnapshot(
      reminder: target,
      runtime: runtimeAt(now, target),
      engine: engine,
      now: now,
    ),
  );
}

WidgetStatus firing(int missed) =>
    WidgetStatus(WidgetStatusKind.firing, missed: missed);
WidgetStatus missedState(int missed) =>
    WidgetStatus(WidgetStatusKind.missed, missed: missed);
WidgetStatus done(int missed) =>
    WidgetStatus(WidgetStatusKind.done, missed: missed);

void main() {
  test('lists the next times with their day and when they are missed', () {
    final snapshot = snapshotAt(at(8));
    expect(snapshot['v'], widgetSnapshotVersion);
    expect(snapshot['displayName'], 'Water');
    expect(snapshot['state'], 'live');
    expect(snapshot['pending'], isNull);
    expect((snapshot['occurrences']! as List<Object?>).first, {
      'date': '2026-11-04',
      'start': ms(at(9)),
      'due': ms(at(9)),
      'missesAt': ms(at(10)),
    });
    expect(widgetStatusAt(snapshot, at(8, 59)), done(0));
    expect(widgetStatusAt(snapshot, at(9)), firing(0));
  });

  test('firing, missed and done with the same day’s missed count', () {
    final snapshot = snapshotAt(at(8));
    // 09:00–10:00 is missed at its end; nothing else is due until 12:00.
    expect(widgetStatusAt(snapshot, at(10)), missedState(1));
    expect(widgetStatusAt(snapshot, at(11, 59)), missedState(1));
    expect(widgetStatusAt(snapshot, at(12)), firing(1));
    // 12:00 has no end: missed when 15:00 starts.
    expect(widgetStatusAt(snapshot, at(15)), firing(2));
    // 15:00 stays due past midnight and keeps its own day's count …
    expect(widgetStatusAt(snapshot, at(0, 0, 5)), firing(2));
    // … until tomorrow's 09:00 starts: a new day with nothing missed yet.
    expect(widgetStatusAt(snapshot, at(9, 0, 5)), firing(0));
    expect(widgetStatusAt(snapshot, at(10, 0, 5)), missedState(1));
  });

  test('a new day starts clean', () {
    final morning = daily(const [
      ReminderTime(start: LocalTime(9, 0), end: LocalTime(10, 0)),
    ]);
    final snapshot = snapshotAt(at(8), of: morning);
    expect(widgetStatusAt(snapshot, at(23, 59)), missedState(1));
    expect(widgetStatusAt(snapshot, at(0, 0, 5)), done(0));
    expect(widgetStatusAt(snapshot, at(9, 0, 5)), firing(0));
  });

  test('carries the state over from when the snapshot was taken', () {
    // Taken at 12:05: 09:00 was missed, 12:00 is due.
    final snapshot = snapshotAt(at(12, 5));
    expect(snapshot['pending'], {
      'date': '2026-11-04',
      'start': ms(at(12)),
      'due': ms(at(12)),
      'missesAt': ms(at(15)),
    });
    expect(snapshot['missed'], {'date': '2026-11-04', 'count': 1});
    expect(snapshot['last'], {
      'date': '2026-11-04',
      'start': ms(at(9)),
      'status': 'missed',
      'at': ms(at(10)),
    });
    expect(widgetStatusAt(snapshot, at(12, 6)), firing(1));
    expect(widgetStatusAt(snapshot, at(15)), firing(2));
  });

  test('paused, archived and deleted reminders', () {
    final paused = snapshotAt(at(8), of: reminder.copyWith(paused: true));
    expect(paused['state'], 'paused');
    expect(
      widgetStatusAt(paused, at(10)),
      const WidgetStatus(WidgetStatusKind.paused),
    );
    // Paused while a time is due: it stays due until Done.
    final dueThenPaused = stored(
      buildWidgetSnapshot(
        reminder: reminder.copyWith(paused: true),
        runtime: runtimeAt(at(12, 5), reminder),
        engine: engine,
        now: at(12, 5),
      ),
    );
    expect(widgetStatusAt(dueThenPaused, at(20)), firing(1));

    expect(
      widgetStatusAt(
        snapshotAt(at(8), of: reminder.copyWith(archivedAt: at(8))),
        at(10),
      ).kind,
      WidgetStatusKind.archived,
    );
    expect(
      widgetStatusAt(
        stored(deletedWidgetSnapshot(id: 'r', name: 'x', displayName: 'y')),
        at(10),
      ).kind,
      WidgetStatusKind.deleted,
    );
    expect(widgetStatusAt(null, at(10)).kind, WidgetStatusKind.deleted);
  });

  test('Done outside the app keeps the count and the schedule', () {
    final due = snapshotAt(at(12, 5));
    final finished = stored(
      doneWidgetSnapshot(due, at: at(12, 30), engine: engine),
    );
    expect(finished['pending'], isNull);
    expect(finished['missed'], {'date': '2026-11-04', 'count': 1});
    expect((finished['last']! as Map<Object?, Object?>)['status'], 'done');
    expect(widgetStatusAt(finished, at(12, 31)), done(1));
    // The next time still makes it due.
    expect(widgetStatusAt(finished, at(15)), firing(1));
  });

  test('Done outside the app first catches up with the times since', () {
    // Taken at 08:00, done at 12:05: 09:00 was missed, 12:00 was due.
    final morning = snapshotAt(at(8));
    expect(dueOccurrenceStartAt(morning, at(12, 5)), at(12));
    final finished = stored(
      doneWidgetSnapshot(morning, at: at(12, 5), engine: engine),
    );
    expect(finished['asOf'], ms(at(12, 5)));
    expect(finished['missed'], {'date': '2026-11-04', 'count': 1});
    expect(finished['last'], {
      'date': '2026-11-04',
      'start': ms(at(12)),
      'status': 'done',
      'at': ms(at(12, 5)),
    });
    expect(widgetStatusAt(finished, at(12, 6)), done(1));
    expect(
      (finished['occurrences']! as List<Object?>).first,
      containsPair('start', ms(at(15))),
    );
  });

  test('a Done finishes the time that is due, if any', () {
    final morning = snapshotAt(at(8));
    expect(dueOccurrenceStartAt(morning, at(8, 30)), isNull);
    expect(dueOccurrenceStartAt(morning, at(9, 30)), at(9));
    // 09:00–10:00 is missed at 10:00: nothing to finish until 12:00.
    expect(dueOccurrenceStartAt(morning, at(11)), isNull);
    expect(dueOccurrenceStartAt(morning, at(12, 5)), at(12));
    // From the snapshot's own due time.
    expect(dueOccurrenceStartAt(snapshotAt(at(12, 5)), at(12, 30)), at(12));
  });

  test('a time due after a schedule edit misses the one still due', () {
    // 07:00–11:00 was due when the schedule changed to 09:00 only.
    final edited = daily(const [ReminderTime(start: LocalTime(9, 0))]);
    final runtime = ReminderRuntime.initial('r', created).copyWith(
      pending: PendingOccurrence(
        date: const LocalDate(2026, 11, 4),
        time: const ReminderTime(start: LocalTime(7, 0), end: LocalTime(11, 0)),
        start: at(7),
        dueAt: at(7),
        end: at(11),
      ),
    );
    final snapshot = stored(
      buildWidgetSnapshot(
        reminder: edited,
        runtime: runtime,
        engine: engine,
        now: at(8),
      ),
    );
    expect(widgetStatusAt(snapshot, at(8, 59)), firing(0));
    expect(widgetStatusAt(snapshot, at(9)), firing(1));
    // Its own end changes nothing any more.
    expect(widgetStatusAt(snapshot, at(11)), firing(1));
  });

  test('version 1 snapshots (no dates, no count) still work', () {
    final snapshot = snapshotAt(at(8));
    final legacy = {
      for (final MapEntry(:key, :value) in snapshot.entries)
        if (key != 'missed' && key != 'last') key: value,
      'v': 1,
      'occurrences': [
        for (final time in snapshot['occurrences']! as List<Object?>)
          {...time! as Map<String, Object?>}..remove('date'),
      ],
    };
    expect(widgetStatusAt(legacy, at(10)), missedState(1));
    expect(widgetStatusAt(legacy, at(12)), firing(1));
  });

  test('changes when times become due or are missed, and at midnight', () {
    final times = widgetChangeTimes(snapshotAt(at(8)));
    expect(times, orderedEquals([...times]..sort()));
    expect(times.first, at(9));
    expect(times.take(5), [at(9), at(10), at(12), at(15), at(0, 0, 5)]);
    expect(times.every((time) => time.isAfter(at(8))), isTrue);
    // A midnight for every day of the snapshot's horizon.
    expect(times, contains(at(0, 0, 19)));
    expect(
      widgetChangeTimes(
        snapshotAt(at(8), of: reminder.copyWith(archivedAt: at(8))),
      ),
      isEmpty,
    );
  });

  test('shows what the app shows, at any later time', () {
    // Random times, repeats, a time past midnight and a time without an
    // end, across two days and a snapshot taken mid-day.
    final busy = daily(const [
      ReminderTime(
        start: LocalTime(6, 0),
        end: LocalTime(7, 0),
        mode: NotifyMode.random,
      ),
      ReminderTime(
        start: LocalTime(9, 0),
        mode: NotifyMode.repeat,
        maxNotifications: 3,
      ),
      ReminderTime(start: LocalTime(13, 0), end: LocalTime(14, 0)),
      ReminderTime(
        start: LocalTime(22, 0),
        end: LocalTime(1, 30),
        mode: NotifyMode.repeat,
        intervalMinutes: 45,
      ),
    ]);
    for (final taken in [at(8), at(13, 30), at(23)]) {
      final runtime = runtimeAt(taken, busy);
      final snapshot = stored(
        buildWidgetSnapshot(
          reminder: busy,
          runtime: runtime,
          engine: engine,
          now: taken,
        ),
      );
      for (
        var now = taken;
        now.isBefore(taken.add(const Duration(days: 2)));
        now = now.add(const Duration(minutes: 5))
      ) {
        final standing = ReminderStanding.at(
          advanceReminder(
            reminder: busy,
            runtime: runtime,
            engine: engine,
            now: now,
          ).runtime,
          now,
        );
        final expected = WidgetStatus(switch (standing.phase) {
          ReminderPhase.firing => WidgetStatusKind.firing,
          ReminderPhase.missed => WidgetStatusKind.missed,
          ReminderPhase.done => WidgetStatusKind.done,
        }, missed: standing.missedCount);
        expect(
          widgetStatusAt(snapshot, now),
          expected,
          reason: 'snapshot of $taken at $now',
        );
      }
    }
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
