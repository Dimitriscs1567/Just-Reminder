import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/occurrence.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';

// Dates are in November 2026 and early 2027 on purpose: far from DST
// changes in common time zones, so the tests pass wherever they run.
const engine = ScheduleEngine();
const id = 'reminder-1';
const nov4 = LocalDate(2026, 11, 4); // a Wednesday
const daily = RepeatRecurrence(unit: RepeatUnit.day, startDate: nov4);

Schedule onceOn(LocalDate date, List<ReminderTime> times) =>
    Schedule(recurrence: OnceRecurrence(date), times: times);

Schedule repeating(RepeatRecurrence recurrence, List<ReminderTime> times) =>
    Schedule(recurrence: recurrence, times: times);

LocalTime t(int hour, [int minute = 0]) => LocalTime(hour, minute);
DateTime nov(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute);

final nineAm = ReminderTime(start: t(9));

ReminderTime repeat(
  LocalTime start, {
  LocalTime? end,
  int every = 60,
  int? max,
}) => ReminderTime(
  start: start,
  end: end,
  mode: NotifyMode.repeat,
  intervalMinutes: every,
  maxNotifications: max,
);

ReminderTime random(LocalTime start, LocalTime end, int count) => ReminderTime(
  start: start,
  end: end,
  mode: NotifyMode.random,
  randomCount: count,
);

List<DateTime> starts(Iterable<Occurrence> occurrences) => [
  for (final occurrence in occurrences) occurrence.start,
];

/// The first [limit] notifications (repeating ones may never end).
List<DateTime> notes(Occurrence occurrence, {int limit = 50}) =>
    occurrence.notifications.take(limit).toList();

/// The occurrences of [schedule] on Nov 4 (and their next starts).
List<Occurrence> onNov4(Schedule schedule) => [
  for (final occurrence in engine.occurrencesFrom(id, schedule, nov4))
    if (occurrence.date == nov4) occurrence,
];

void main() {
  group('one time', () {
    final schedule = onceOn(const LocalDate(2026, 11, 5), [nineAm]);

    test('is due once, at its start', () {
      final all = engine.upcoming(id, schedule, nov(4, 8), count: 5);
      expect(starts(all), [nov(5, 9)]);
      expect(all.single.dueAt, nov(5, 9));
      expect(notes(all.single), [nov(5, 9)]);
    });

    test('upcoming is strictly after, dueBetween is (from, to]', () {
      expect(engine.upcoming(id, schedule, nov(5, 9)), isEmpty);
      expect(
        starts(engine.dueBetween(id, schedule, nov(5, 8, 59), nov(5, 9))),
        [nov(5, 9)],
      );
      expect(engine.dueBetween(id, schedule, nov(5, 9), nov(5, 10)), isEmpty);
    });

    test('the last time has no next time, so it is never missed', () {
      final only = engine.upcoming(id, schedule, nov(4, 8)).single;
      expect(only.nextStart, isNull);
      expect(only.missesAt, isNull);
    });
  });

  group('several times a day', () {
    final schedule = repeating(daily, [
      ReminderTime(start: t(15)),
      repeat(t(9), end: t(12), every: 30),
      ReminderTime(start: t(20)),
    ]);

    test('come in start order, each knowing the next start', () {
      final day = onNov4(schedule);
      expect(starts(day), [nov(4, 9), nov(4, 15), nov(4, 20)]);
      expect([for (final o in day) o.nextStart], [
        nov(4, 15),
        nov(4, 20),
        nov(5, 9),
      ]);
    });

    test('a time with an end is missed at its end, others at the next', () {
      final day = onNov4(schedule);
      expect([for (final o in day) o.missesAt], [
        nov(4, 12),
        nov(4, 20),
        nov(5, 9),
      ]);
    });

    test('upcoming lists each time once', () {
      final next = engine.upcoming(id, schedule, nov(4, 10), count: 4);
      expect(starts(next), [nov(4, 15), nov(4, 20), nov(5, 9), nov(5, 15)]);
    });
  });

  group('repeat', () {
    test('stops before the end: it is missed then', () {
      final occurrence = onNov4(
        repeating(daily, [repeat(t(9), end: t(17))]),
      ).single;
      final times = notes(occurrence);
      expect(times, hasLength(8));
      expect(times.first, nov(4, 9));
      expect(times.last, nov(4, 16));
    });

    test('stops at the maximum', () {
      final occurrence = onNov4(
        repeating(daily, [repeat(t(9), end: t(17), max: 5)]),
      ).single;
      expect(notes(occurrence), [for (var h = 9; h <= 13; h++) nov(4, h)]);
    });

    test('stops before the end when the steps do not land on it', () {
      final occurrence = onNov4(
        repeating(daily, [repeat(t(9), end: t(10), every: 25)]),
      ).single;
      expect(notes(occurrence), [nov(4, 9), nov(4, 9, 25), nov(4, 9, 50)]);
    });

    test('without an end it repeats until the next time starts', () {
      final day = onNov4(
        repeating(daily, [repeat(t(9)), ReminderTime(start: t(12))]),
      );
      expect(notes(day.first), [nov(4, 9), nov(4, 10), nov(4, 11)]);
      // The day's last time repeats overnight, until tomorrow's first.
      final last = onNov4(repeating(daily, [repeat(t(20), every: 240)])).single;
      expect(notes(last), [
        nov(4, 20),
        nov(5, 0),
        nov(5, 4),
        nov(5, 8),
        nov(5, 12),
        nov(5, 16),
      ]);
    });

    test('back to back: no notification at the shared minute', () {
      final day = onNov4(
        repeating(daily, [
          repeat(t(9), end: t(12)),
          repeat(t(12), end: t(14)),
        ]),
      );
      expect(notes(day.first), [nov(4, 9), nov(4, 10), nov(4, 11)]);
      expect(notes(day.last), [nov(4, 12), nov(4, 13)]);
    });

    test('a one-time reminder repeats until done, or the maximum', () {
      final endless = engine.upcoming(
        id,
        onceOn(nov4, [repeat(t(9), every: 30)]),
        nov(4, 8),
      ).single;
      expect(notes(endless, limit: 100), hasLength(100));
      final capped = engine.upcoming(
        id,
        onceOn(nov4, [repeat(t(9), every: 30, max: 3)]),
        nov(4, 8),
      ).single;
      expect(notes(capped), [nov(4, 9), nov(4, 9, 30), nov(4, 10)]);
    });

    test('an end before the start runs past midnight', () {
      final occurrence = onNov4(
        repeating(daily, [repeat(t(22), end: t(2))]),
      ).single;
      expect(occurrence.date, nov4);
      expect(occurrence.end, nov(5, 2));
      expect(notes(occurrence), [
        nov(4, 22),
        nov(4, 23),
        nov(5, 0),
        nov(5, 1),
      ]);
    });
  });

  group('random', () {
    final time = random(t(9), t(17), 4);
    Occurrence on(LocalDate date, {String reminderId = id}) =>
        engine
            .occurrencesFrom(reminderId, repeating(daily, [time]), date)
            .first;

    test('places exactly N notifications, one in each equal part', () {
      final times = notes(on(nov4));
      expect(times, hasLength(4));
      for (var i = 0; i < 4; i++) {
        final partStart = nov(4, 9 + 2 * i);
        final partEnd = partStart.add(const Duration(hours: 2));
        expect(times[i].isBefore(partStart), isFalse, reason: 'part $i');
        expect(times[i].isBefore(partEnd), isTrue, reason: 'part $i');
        expect(times[i].second, 0);
      }
    });

    test('is due at its first notification, not at its start', () {
      final occurrence = on(nov4);
      expect(occurrence.dueAt, notes(occurrence).first);
      expect(occurrence.missesAt, nov(4, 17));
    });

    test('is the same every time for a reminder, day and time', () {
      expect(notes(on(nov4)), notes(on(nov4)));
    });

    test('differs between days, reminders and times of a day', () {
      List<Duration> offsets(Occurrence occurrence) => [
        for (final at in notes(occurrence)) at.difference(occurrence.start),
      ];
      final base = offsets(on(nov4));
      expect(offsets(on(nov4.addDays(1))), isNot(base));
      expect(offsets(on(nov4, reminderId: 'reminder-2')), isNot(base));
      final twoRanges = onNov4(
        repeating(daily, [random(t(9), t(12), 3), random(t(13), t(16), 3)]),
      );
      expect(offsets(twoRanges.first), isNot(offsets(twoRanges.last)));
    });

    test('a range past midnight still belongs to its first day', () {
      final late = repeating(daily, [random(t(22), t(2), 4)]);
      final occurrence = onNov4(late).single;
      final times = notes(occurrence);
      for (var i = 0; i < 4; i++) {
        final partStart = DateTime(2026, 11, 4, 22 + i);
        expect(times[i].isBefore(partStart), isFalse, reason: 'part $i');
        expect(
          times[i].isBefore(partStart.add(const Duration(hours: 1))),
          isTrue,
          reason: 'part $i',
        );
      }
      // Its first notification is found when scanning from that day.
      expect(
        engine.upcoming(id, late, nov(4, 21)).single.start,
        nov(4, 22),
      );
    });

    test('never more notifications than there are minutes', () {
      final tiny = onNov4(repeating(daily, [random(t(9), t(9, 3), 10)]));
      expect(notes(tiny.single), [nov(4, 9), nov(4, 9, 1), nov(4, 9, 2)]);
    });

    test('a range that started can still be upcoming until it is due', () {
      final schedule = onceOn(nov4, [random(t(9), t(17), 1)]);
      final occurrence = engine.upcoming(id, schedule, nov(4, 8)).single;
      final justBefore = occurrence.dueAt.subtract(const Duration(minutes: 1));
      expect(
        engine.upcoming(id, schedule, justBefore).single.start,
        nov(4, 9),
      );
      expect(engine.upcoming(id, schedule, occurrence.dueAt), isEmpty);
    });
  });

  group('daily', () {
    test('every 2 days from the start date', () {
      final schedule = repeating(
        const RepeatRecurrence(unit: RepeatUnit.day, every: 2, startDate: nov4),
        [nineAm],
      );
      expect(starts(engine.upcoming(id, schedule, nov(1, 0), count: 3)), [
        nov(4, 9),
        nov(6, 9),
        nov(8, 9),
      ]);
    });

    test('the end date is inclusive', () {
      final schedule = repeating(
        const RepeatRecurrence(
          unit: RepeatUnit.day,
          startDate: nov4,
          endDate: LocalDate(2026, 11, 6),
        ),
        [nineAm],
      );
      expect(starts(engine.upcoming(id, schedule, nov(4, 0), count: 10)), [
        nov(4, 9),
        nov(5, 9),
        nov(6, 9),
      ]);
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
        [nineAm],
      );
      expect(starts(engine.upcoming(id, schedule, nov(4, 0), count: 5)), [
        nov(4, 9), // Wed
        nov(5, 9), // Thu
        nov(6, 9), // Fri
        nov(9, 9), // Mon
        nov(10, 9), // Tue
      ]);
    });

    test('every 2 weeks, counted from the start week', () {
      final schedule = repeating(
        const RepeatRecurrence(
          unit: RepeatUnit.week,
          every: 2,
          startDate: nov4,
          weekdays: {DateTime.monday, DateTime.saturday},
        ),
        [nineAm],
      );
      expect(starts(engine.upcoming(id, schedule, nov(4, 0), count: 4)), [
        nov(7, 9), // Sat, start week (Mon 2nd is before the start)
        nov(16, 9), // Mon, two weeks later
        nov(21, 9), // Sat
        nov(30, 9), // Mon
      ]);
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
        [nineAm],
      );
      expect(
        starts(engine.upcoming(id, schedule, DateTime(2027, 1, 1), count: 4)),
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
        [nineAm],
      );
      expect(starts(engine.upcoming(id, schedule, DateTime(2028, 2, 1))), [
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
        [nineAm],
      );
      expect(starts(engine.upcoming(id, schedule, nov(20, 0), count: 2)), [
        DateTime(2027, 1, 15, 9),
        DateTime(2027, 3, 15, 9),
      ]);
    });
  });

  group('reminders', () {
    Reminder reminder({
      bool paused = false,
      DateTime? archivedAt,
      List<ReminderTime>? times,
    }) => Reminder(
      id: id,
      name: 'Water',
      displayName: 'Water',
      schedule: repeating(daily, times ?? [nineAm]),
      createdAt: nov(4, 8),
      updatedAt: nov(4, 8),
      // Today's 09:00 is before this, so it never happens.
      activeSince: nov(4, 10),
      paused: paused,
      archivedAt: archivedAt,
    );

    test('upcomingFor starts after activeSince', () {
      expect(starts(engine.upcomingFor(reminder(), nov(4, 8))), [nov(5, 9)]);
    });

    test('paused or archived reminders have nothing upcoming', () {
      expect(engine.upcomingFor(reminder(paused: true), nov(4, 8)), isEmpty);
      expect(
        engine.upcomingFor(reminder(archivedAt: nov(4, 8)), nov(4, 8)),
        isEmpty,
      );
    });

    test('isFinished only when the schedule can never remind again', () {
      final once = reminder().copyWith(
        schedule: onceOn(const LocalDate(2026, 11, 5), [nineAm]),
      );
      expect(engine.isFinished(once, nov(5, 8)), isFalse);
      expect(engine.isFinished(once, nov(5, 9)), isTrue);
      // Paused but could still remind after resuming: not finished.
      expect(
        engine.isFinished(reminder(paused: true), DateTime(2026, 12, 1)),
        isFalse,
      );
    });

    test('a due time without an end is missed when a real next time starts',
        () {
      final edited = reminder(
        times: [ReminderTime(start: t(9, 30)), ReminderTime(start: t(14))],
      );
      final pending = PendingOccurrence(
        date: nov4,
        time: nineAm,
        start: nov(4, 9),
        dueAt: nov(4, 9),
      );
      // 09:30 comes before activeSince (10:00), so it never happens.
      expect(engine.missesAt(edited, pending), nov(4, 14));
      // Paused: no next time comes.
      expect(
        engine.missesAt(edited.copyWith(paused: true), pending),
        isNull,
      );
      // With an end, the end decides.
      expect(
        engine.missesAt(
          edited.copyWith(paused: true),
          PendingOccurrence(
            date: nov4,
            time: nineAm,
            start: nov(4, 9),
            dueAt: nov(4, 9),
            end: nov(4, 11),
          ),
        ),
        nov(4, 11),
      );
    });
  });
}
