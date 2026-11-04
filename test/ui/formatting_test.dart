import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/ui/formatting.dart';

const h24 = TimeFormatter(use24Hour: true);
const h12 = TimeFormatter(use24Hour: false);
const today = LocalDate(2026, 11, 4);

RepeatRecurrence weekly(Set<int> days, {int every = 1}) => RepeatRecurrence(
  unit: RepeatUnit.week,
  every: every,
  startDate: today,
  weekdays: days,
);

void main() {
  test('times follow the 12/24-hour setting', () {
    expect(h24.time(const LocalTime(9, 5)), '09:05');
    // intl separates AM/PM with a narrow no-break space.
    expect(h12.time(const LocalTime(21, 30)), '9:30 PM');
  });

  test('days are relative when close, dates otherwise', () {
    expect(formatDay(today, today), 'Today');
    expect(formatDay(today.addDays(1), today), 'Tomorrow');
    expect(formatDay(today.addDays(-1), today), 'Yesterday');
    expect(formatDay(const LocalDate(2026, 11, 10), today), 'Tue, Nov 10');
    expect(formatDay(const LocalDate(2027, 1, 5), today), 'Tue, Jan 5, 2027');
  });

  test('compact moments drop "Today"', () {
    final now = DateTime(2026, 11, 4, 8);
    expect(formatCompactMoment(DateTime(2026, 11, 4, 9), now, h24), '09:00');
    expect(
      formatCompactMoment(DateTime(2026, 11, 5, 9), now, h24),
      'Tomorrow · 09:00',
    );
  });

  test('ordinals and intervals', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 31].map(ordinal), [
      '1st',
      '2nd',
      '3rd',
      '4th',
      '11th',
      '12th',
      '13th',
      '21st',
      '22nd',
      '31st',
    ]);
    expect(formatInterval(15), '15 min');
    expect(formatInterval(60), '1 h');
    expect(formatInterval(90), '1 h 30 min');
  });

  test('recurrences read naturally', () {
    String describe(Recurrence recurrence) =>
        describeRecurrence(recurrence, today: today);

    expect(describe(OnceRecurrence(today.addDays(1))), 'Once · Tomorrow');
    expect(
      describe(const RepeatRecurrence(unit: RepeatUnit.day, startDate: today)),
      'Every day',
    );
    expect(
      describe(
        const RepeatRecurrence(unit: RepeatUnit.day, every: 3, startDate: today),
      ),
      'Every 3 days',
    );
    expect(describe(weekly({1, 2, 3, 4, 5})), 'Every weekday');
    expect(describe(weekly({6, 7})), 'Every weekend');
    expect(describe(weekly({1, 3})), 'Every Mon, Wed');
    expect(describe(weekly({1, 6}, every: 2)), 'Every 2 weeks on Mon, Sat');
    expect(
      describe(
        const RepeatRecurrence(
          unit: RepeatUnit.month,
          startDate: today,
          dayOfMonth: 31,
        ),
      ),
      'Monthly on the 31st (or last day)',
    );
  });

  test('timings read naturally', () {
    expect(describeTiming(const FixedTiming(LocalTime(9, 0)), h24), '09:00');
    expect(
      describeTiming(
        const RangeTiming(
          start: LocalTime(9, 0),
          end: LocalTime(17, 0),
          mode: RangeMode.interval,
          intervalMinutes: 30,
          maxActivations: 5,
        ),
        h24,
      ),
      '09:00–17:00, every 30 min, max 5',
    );
    expect(
      describeTiming(
        const RangeTiming(
          start: LocalTime(9, 0),
          end: LocalTime(17, 0),
          mode: RangeMode.interval,
        ),
        h24,
      ),
      '09:00–17:00, every hour',
    );
    expect(
      describeTiming(
        const RangeTiming(
          start: LocalTime(9, 0),
          end: LocalTime(17, 0),
          mode: RangeMode.random,
          maxActivations: 3,
        ),
        h24,
      ),
      '3 random times, 09:00–17:00',
    );
  });

  test('one-time schedules can leave out the date', () {
    final schedule = Schedule(
      recurrence: OnceRecurrence(today.addDays(1)),
      timing: const FixedTiming(LocalTime(19, 30)),
    );
    expect(
      describeSchedule(schedule, h24, today: today),
      'Once · Tomorrow · 19:30',
    );
    expect(
      describeSchedule(schedule, h24, today: today, includeOnceDate: false),
      'Once · 19:30',
    );
  });
}
