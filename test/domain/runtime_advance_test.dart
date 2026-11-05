import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/occurrence_record.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/reminder_standing.dart';
import 'package:just_reminder/src/domain/runtime_advance.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';

const engine = ScheduleEngine();
const nov4 = LocalDate(2026, 11, 4);
const nov5 = LocalDate(2026, 11, 5);

DateTime nov(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute);
LocalTime t(int hour, [int minute = 0]) => LocalTime(hour, minute);

/// A daily reminder created on Nov 4 at 08:00.
Reminder daily(List<ReminderTime> times) => Reminder(
  id: 'r',
  name: 'Water',
  displayName: 'Water',
  schedule: Schedule(
    recurrence: const RepeatRecurrence(unit: RepeatUnit.day, startDate: nov4),
    times: times,
  ),
  createdAt: nov(4, 8),
  updatedAt: nov(4, 8),
  activeSince: nov(4, 8),
);

/// 09:00 (once, until the next time) and 12:00–13:00 (every 30 min).
final nineAndNoon = daily([
  ReminderTime(start: t(9)),
  ReminderTime(
    start: t(12),
    end: t(13),
    mode: NotifyMode.repeat,
    intervalMinutes: 30,
  ),
]);

RuntimeAdvance advance(
  Reminder reminder,
  DateTime now, {
  ReminderRuntime? from,
  List<DateTime> done = const [],
}) => advanceReminder(
  reminder: reminder,
  runtime: from ?? ReminderRuntime.initial(reminder.id, reminder.activeSince),
  engine: engine,
  now: now,
  acknowledgments: done,
);

OccurrenceRecord record(
  DateTime start,
  OccurrenceStatus status, {
  DateTime? end,
  DateTime? dueAt,
  DateTime? doneAt,
}) => OccurrenceRecord(
  reminderId: 'r',
  start: start,
  end: end,
  dueAt: dueAt ?? start,
  status: status,
  doneAt: doneAt,
);

void main() {
  test('a time becomes due at its first notification', () {
    final result = advance(nineAndNoon, nov(4, 9, 5));
    expect(result.runtime.pending?.start, nov(4, 9));
    expect(result.runtime.processedUntil, nov(4, 9, 5));
    expect(result.records, [record(nov(4, 9), OccurrenceStatus.pending)]);
  });

  test('Done finishes it; the missed count stays', () {
    final result = advance(nineAndNoon, nov(4, 9, 30), done: [nov(4, 9, 20)]);
    expect(result.runtime.isFiring, isFalse);
    expect(result.runtime.last?.status, OccurrenceStatus.done);
    expect(result.runtime.last?.at, nov(4, 9, 20));
    expect(result.runtime.appliedAckUntil, nov(4, 9, 20));
    expect(result.records, [
      record(nov(4, 9), OccurrenceStatus.done, doneAt: nov(4, 9, 20)),
    ]);
  });

  test('without an end it is missed when the next time starts', () {
    final result = advance(nineAndNoon, nov(4, 12, 10));
    expect(result.runtime.pending?.start, nov(4, 12));
    expect(result.runtime.missedOn(nov4), 1);
    expect(result.records, unorderedEquals([
      record(nov(4, 9), OccurrenceStatus.missed),
      record(nov(4, 12), OccurrenceStatus.pending, end: nov(4, 13)),
    ]));
  });

  test('with an end it is missed at its end', () {
    final result = advance(
      nineAndNoon,
      nov(4, 13, 30),
      done: [nov(4, 9, 10)],
    );
    expect(result.runtime.isFiring, isFalse);
    expect(result.runtime.missedOn(nov4), 1);
    expect(result.runtime.last?.isMissed, isTrue);
    expect(result.runtime.last?.at, nov(4, 13));
    expect(
      result.records,
      contains(record(nov(4, 12), OccurrenceStatus.missed, end: nov(4, 13))),
    );
  });

  test('Done in time beats the end', () {
    final result = advance(
      nineAndNoon,
      nov(4, 14),
      done: [nov(4, 9, 10), nov(4, 12, 40)],
    );
    expect(result.runtime.missedOn(nov4), 0);
    expect(result.runtime.last?.status, OccurrenceStatus.done);
  });

  test('Done before anything is due does nothing', () {
    final result = advance(nineAndNoon, nov(4, 9, 5), done: [nov(4, 8, 30)]);
    expect(result.runtime.pending?.start, nov(4, 9));
    expect(result.runtime.appliedAckUntil, nov(4, 8, 30));
  });

  test('back to back: missed at the shared minute, then the next is due', () {
    final reminder = daily([
      ReminderTime(start: t(9), end: t(12)),
      ReminderTime(start: t(12)),
    ]);
    final result = advance(reminder, nov(4, 12));
    expect(result.runtime.pending?.start, nov(4, 12));
    expect(result.runtime.missedOn(nov4), 1);
  });

  test('a random time is not due before its first notification', () {
    final reminder = daily([
      ReminderTime(
        start: t(9),
        end: t(17),
        mode: NotifyMode.random,
        randomCount: 2,
      ),
    ]);
    final due = engine.upcoming(reminder.id, reminder.schedule, nov(4, 8));
    final dueAt = due.single.dueAt;
    expect(
      advance(reminder, dueAt.subtract(const Duration(minutes: 1)))
          .runtime
          .isFiring,
      isFalse,
    );
    final firing = advance(reminder, dueAt).runtime;
    expect(firing.pending?.start, nov(4, 9));
    expect(firing.pending?.dueAt, dueAt);
  });

  test('misses count per day; a time past midnight counts for its day', () {
    // 20:00 stays due overnight and is missed at 09:00 the next day.
    final reminder = daily([
      ReminderTime(start: t(9)),
      ReminderTime(start: t(20)),
    ]);
    final result = advance(reminder, nov(5, 9, 30));
    expect(result.runtime.pending?.start, nov(5, 9));
    expect(result.runtime.missedDate, nov4);
    expect(result.runtime.missedOn(nov4), 2);
    expect(result.runtime.missedOn(nov5), 0);

    final later = advance(reminder, nov(5, 21), from: result.runtime);
    expect(later.runtime.missedOn(nov5), 1);
    expect(later.runtime.missedOn(nov4), 0);
  });

  test('advancing step by step equals advancing at once', () {
    final once = advance(nineAndNoon, nov(5, 10)).runtime;
    var stepped = ReminderRuntime.initial('r', nov(4, 8));
    for (final now in [nov(4, 9), nov(4, 12, 30), nov(4, 13), nov(5, 10)]) {
      stepped = advance(nineAndNoon, now, from: stepped).runtime;
    }
    expect(stepped, once);
  });

  test('nothing new: only processedUntil moves', () {
    final first = advance(nineAndNoon, nov(4, 9, 5));
    final second = advance(nineAndNoon, nov(4, 9, 6), from: first.runtime);
    expect(second.records, isEmpty);
    expect(second.runtime.pending, first.runtime.pending);
  });

  test('closePendingAsMissed records the due time as missed', () {
    final firing = advance(nineAndNoon, nov(4, 9, 5)).runtime;
    final closed = closePendingAsMissed(firing, nov(4, 10));
    expect(closed.runtime.isFiring, isFalse);
    expect(closed.runtime.missedOn(nov4), 1);
    expect(closed.records, [record(nov(4, 9), OccurrenceStatus.missed)]);
    expect(closePendingAsMissed(closed.runtime, nov(4, 11)).records, isEmpty);
  });

  group('standing', () {
    test('firing, with the missed times of its day', () {
      final runtime = advance(nineAndNoon, nov(4, 12, 10)).runtime;
      final standing = ReminderStanding.at(runtime, nov(4, 12, 10));
      expect(standing.phase, ReminderPhase.firing);
      expect(standing.missedCount, 1);
      expect(standing.pending?.start, nov(4, 12));
    });

    test('missed when today’s latest time was missed', () {
      final runtime = advance(
        nineAndNoon,
        nov(4, 14),
        done: [nov(4, 9, 10)],
      ).runtime;
      final standing = ReminderStanding.at(runtime, nov(4, 14));
      expect(standing.phase, ReminderPhase.missed);
      expect(standing.missedCount, 1);
      expect(standing.last?.start, nov(4, 12));
    });

    test('done after Done, still showing the day’s missed count', () {
      final runtime = advance(
        nineAndNoon,
        nov(4, 14),
        done: [nov(4, 12, 15)],
      ).runtime;
      final standing = ReminderStanding.at(runtime, nov(4, 14));
      expect(standing.phase, ReminderPhase.done);
      expect(standing.missedCount, 1); // 09:00
      expect(standing.last?.status, OccurrenceStatus.done);
    });

    test('a new day starts clean', () {
      final runtime = advance(nineAndNoon, nov(4, 14)).runtime;
      final standing = ReminderStanding.at(runtime, nov(5, 7));
      expect(standing.phase, ReminderPhase.done);
      expect(standing.missedCount, 0);
      expect(standing.last, isNull);
    });

    test('a time still due past midnight keeps firing with its day’s count',
        () {
      final reminder = daily([
        ReminderTime(start: t(9)),
        ReminderTime(start: t(20)),
      ]);
      final runtime = advance(reminder, nov(5, 1)).runtime;
      final standing = ReminderStanding.at(runtime, nov(5, 1));
      expect(standing.phase, ReminderPhase.firing);
      expect(standing.pending?.date, nov4);
      expect(standing.missedCount, 1);
    });
  });
}
