import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';

// Dates are in November 2026 and early 2027 on purpose: far from DST
// changes in common time zones, so the tests pass wherever they run.
const engine = ScheduleEngine();
const id = 'reminder-1';
const nov4 = LocalDate(2026, 11, 4); // a Wednesday

Schedule onceOn(LocalDate date, Timing timing) =>
    Schedule(recurrence: OnceRecurrence(date), timing: timing);

Schedule repeating(RepeatRecurrence recurrence, Timing timing) =>
    Schedule(recurrence: recurrence, timing: timing);

const nineAm = FixedTiming(LocalTime(9, 0));

RangeTiming interval(
  LocalTime start,
  LocalTime end,
  int minutes, {
  int? max,
}) => RangeTiming(
  start: start,
  end: end,
  mode: RangeMode.interval,
  intervalMinutes: minutes,
  maxActivations: max,
);

RangeTiming random(LocalTime start, LocalTime end, int count) => RangeTiming(
  start: start,
  end: end,
  mode: RangeMode.random,
  maxActivations: count,
);

void main() {
  group('one-time', () {
    final schedule = onceOn(const LocalDate(2026, 11, 5), nineAm);

    test('activates once at the fixed time', () {
      expect(
        engine.upcoming(id, schedule, DateTime(2026, 11, 4, 8), count: 5),
        [DateTime(2026, 11, 5, 9)],
      );
    });

    test('upcoming is strictly after, between is (from, to]', () {
      expect(engine.upcoming(id, schedule, DateTime(2026, 11, 5, 9)), isEmpty);
      expect(
        engine.between(
          id,
          schedule,
          DateTime(2026, 11, 5, 8, 59),
          DateTime(2026, 11, 5, 9),
        ),
        [DateTime(2026, 11, 5, 9)],
      );
      expect(
        engine.between(
          id,
          schedule,
          DateTime(2026, 11, 5, 9),
          DateTime(2026, 11, 5, 10),
        ),
        isEmpty,
      );
    });
  });

  group('interval range', () {
    test('includes the range end when it lands on a step', () {
      final times = engine.windowActivations(
        id,
        interval(const LocalTime(9, 0), const LocalTime(17, 0), 60),
        nov4,
      );
      expect(times, hasLength(9));
      expect(times.first, DateTime(2026, 11, 4, 9));
      expect(times.last, DateTime(2026, 11, 4, 17));
    });

    test('stops at the max activations', () {
      final times = engine.windowActivations(
        id,
        interval(const LocalTime(9, 0), const LocalTime(17, 0), 60, max: 5),
        nov4,
      );
      expect(times, [
        for (var hour = 9; hour <= 13; hour++) DateTime(2026, 11, 4, hour),
      ]);
    });

    test('stops before the end when the steps do not land on it', () {
      final times = engine.windowActivations(
        id,
        interval(const LocalTime(9, 0), const LocalTime(10, 0), 25),
        nov4,
      );
      expect(times, [
        DateTime(2026, 11, 4, 9),
        DateTime(2026, 11, 4, 9, 25),
        DateTime(2026, 11, 4, 9, 50),
      ]);
    });

    test('an end before the start runs past midnight', () {
      final schedule = onceOn(
        nov4,
        interval(const LocalTime(22, 0), const LocalTime(2, 0), 60),
      );
      final all = engine.upcoming(
        id,
        schedule,
        DateTime(2026, 11, 4),
        count: 10,
      );
      expect(all, [
        DateTime(2026, 11, 4, 22),
        DateTime(2026, 11, 4, 23),
        DateTime(2026, 11, 5, 0),
        DateTime(2026, 11, 5, 1),
        DateTime(2026, 11, 5, 2),
      ]);

      // The window started the previous day but is still found.
      expect(
        engine.between(
          id,
          schedule,
          DateTime(2026, 11, 5, 0, 30),
          DateTime(2026, 11, 5, 3),
        ),
        [DateTime(2026, 11, 5, 1), DateTime(2026, 11, 5, 2)],
      );
    });
  });

  group('random range', () {
    final timing = random(const LocalTime(9, 0), const LocalTime(17, 0), 4);

    test('places exactly N times, one in each equal slot', () {
      final times = engine.windowActivations(id, timing, nov4);
      expect(times, hasLength(4));
      final windowStart = DateTime(2026, 11, 4, 9);
      for (var i = 0; i < 4; i++) {
        final slotStart = windowStart.add(Duration(hours: 2 * i));
        final slotEnd = slotStart.add(const Duration(hours: 2));
        expect(times[i].isBefore(slotStart), isFalse, reason: 'slot $i');
        expect(times[i].isBefore(slotEnd), isTrue, reason: 'slot $i');
        expect(times[i].second, 0);
      }
    });

    test('is the same every time for a reminder and day', () {
      expect(
        engine.windowActivations(id, timing, nov4),
        engine.windowActivations(id, timing, nov4),
      );
    });

    test('differs between days and between reminders', () {
      final base = engine.windowActivations(id, timing, nov4);
      List<Duration> offsets(List<DateTime> times, LocalDate date) => [
        for (final at in times) at.difference(date.at(const LocalTime(9, 0))),
      ];
      final otherDay = engine.windowActivations(id, timing, nov4.addDays(1));
      expect(
        offsets(otherDay, nov4.addDays(1)),
        isNot(offsets(base, nov4)),
      );
      expect(
        engine.windowActivations('reminder-2', timing, nov4),
        isNot(base),
      );
    });

    test('never places more times than there are minutes', () {
      final tiny = random(const LocalTime(9, 0), const LocalTime(9, 3), 10);
      expect(engine.windowActivations(id, tiny, nov4), [
        DateTime(2026, 11, 4, 9),
        DateTime(2026, 11, 4, 9, 1),
        DateTime(2026, 11, 4, 9, 2),
      ]);
    });
  });

  group('daily', () {
    test('every 2 days from the start date', () {
      final schedule = repeating(
        const RepeatRecurrence(unit: RepeatUnit.day, every: 2, startDate: nov4),
        nineAm,
      );
      expect(
        engine.upcoming(id, schedule, DateTime(2026, 11, 1), count: 3),
        [
          DateTime(2026, 11, 4, 9),
          DateTime(2026, 11, 6, 9),
          DateTime(2026, 11, 8, 9),
        ],
      );
    });

    test('the end date is inclusive', () {
      final schedule = repeating(
        const RepeatRecurrence(
          unit: RepeatUnit.day,
          startDate: nov4,
          endDate: LocalDate(2026, 11, 6),
        ),
        nineAm,
      );
      expect(
        engine.upcoming(id, schedule, DateTime(2026, 11, 4), count: 10),
        [
          DateTime(2026, 11, 4, 9),
          DateTime(2026, 11, 5, 9),
          DateTime(2026, 11, 6, 9),
        ],
      );
    });
  });

  group('weekly', () {
    test('on selected weekdays', () {
      final schedule = repeating(
        const RepeatRecurrence(
          unit: RepeatUnit.week,
          startDate: nov4,
          weekdays: {1, 2, 3, 4, 5},
        ),
        nineAm,
      );
      expect(
        engine.upcoming(id, schedule, DateTime(2026, 11, 4), count: 5),
        [
          DateTime(2026, 11, 4, 9), // Wed
          DateTime(2026, 11, 5, 9), // Thu
          DateTime(2026, 11, 6, 9), // Fri
          DateTime(2026, 11, 9, 9), // Mon
          DateTime(2026, 11, 10, 9), // Tue
        ],
      );
    });

    test('every 2 weeks, counted from the start week', () {
      final schedule = repeating(
        const RepeatRecurrence(
          unit: RepeatUnit.week,
          every: 2,
          startDate: nov4,
          weekdays: {DateTime.monday, DateTime.saturday},
        ),
        nineAm,
      );
      expect(
        engine.upcoming(id, schedule, DateTime(2026, 11, 4), count: 4),
        [
          DateTime(2026, 11, 7, 9), // Sat, start week (Mon 2nd is before start)
          DateTime(2026, 11, 16, 9), // Mon, two weeks later
          DateTime(2026, 11, 21, 9), // Sat
          DateTime(2026, 11, 30, 9), // Mon
        ],
      );
    });
  });

  group('monthly', () {
    test('a missing day falls on the last day of the month', () {
      final schedule = repeating(
        const RepeatRecurrence(
          unit: RepeatUnit.month,
          startDate: LocalDate(2027, 1, 1),
          dayOfMonth: 31,
        ),
        nineAm,
      );
      expect(
        engine.upcoming(id, schedule, DateTime(2027, 1, 1), count: 4),
        [
          DateTime(2027, 1, 31, 9),
          DateTime(2027, 2, 28, 9),
          DateTime(2027, 3, 31, 9),
          DateTime(2027, 4, 30, 9),
        ],
      );
    });

    test('uses Feb 29 in leap years', () {
      final schedule = repeating(
        const RepeatRecurrence(
          unit: RepeatUnit.month,
          startDate: LocalDate(2028, 2, 1),
          dayOfMonth: 30,
        ),
        nineAm,
      );
      expect(engine.upcoming(id, schedule, DateTime(2028, 2, 1)), [
        DateTime(2028, 2, 29, 9),
      ]);
    });

    test('every 2 months, counted from the start month', () {
      final schedule = repeating(
        const RepeatRecurrence(
          unit: RepeatUnit.month,
          every: 2,
          startDate: LocalDate(2026, 11, 20),
          dayOfMonth: 15,
        ),
        nineAm,
      );
      expect(
        engine.upcoming(id, schedule, DateTime(2026, 11, 20), count: 2),
        [DateTime(2027, 1, 15, 9), DateTime(2027, 3, 15, 9)],
      );
    });
  });

  group('reminders', () {
    Reminder reminder({bool paused = false, DateTime? archivedAt}) => Reminder(
      id: id,
      name: 'Water',
      displayName: 'Water',
      schedule: repeating(
        const RepeatRecurrence(unit: RepeatUnit.day, startDate: nov4),
        nineAm,
      ),
      createdAt: DateTime(2026, 11, 4, 8),
      updatedAt: DateTime(2026, 11, 4, 8),
      // Today's 09:00 is before this, so it never happens.
      activeSince: DateTime(2026, 11, 4, 10),
      paused: paused,
      archivedAt: archivedAt,
    );

    test('upcomingFor starts after activeSince', () {
      expect(engine.upcomingFor(reminder(), DateTime(2026, 11, 4, 8)), [
        DateTime(2026, 11, 5, 9),
      ]);
    });

    test('paused or archived reminders have nothing upcoming', () {
      final after = DateTime(2026, 11, 4, 8);
      expect(engine.upcomingFor(reminder(paused: true), after), isEmpty);
      expect(
        engine.upcomingFor(reminder(archivedAt: after), after),
        isEmpty,
      );
    });

    test('isFinished only when the schedule can never activate again', () {
      final once = reminder().copyWith(
        schedule: onceOn(const LocalDate(2026, 11, 5), nineAm),
      );
      expect(engine.isFinished(once, DateTime(2026, 11, 5, 8)), isFalse);
      expect(engine.isFinished(once, DateTime(2026, 11, 5, 9)), isTrue);
      // Paused but could still activate after resuming: not finished.
      expect(
        engine.isFinished(reminder(paused: true), DateTime(2026, 12, 1)),
        isFalse,
      );
    });
  });
}
