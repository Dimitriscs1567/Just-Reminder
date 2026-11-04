import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/validation.dart';

const valid = Schedule(
  recurrence: OnceRecurrence(LocalDate(2026, 11, 5)),
  timing: FixedTiming(LocalTime(9, 0)),
);

Set<ReminderField> fieldsOf(List<ValidationIssue> issues) => {
  for (final issue in issues) issue.field,
};

Set<ReminderField> scheduleIssues({
  Recurrence recurrence = const OnceRecurrence(LocalDate(2026, 11, 5)),
  Timing timing = const FixedTiming(LocalTime(9, 0)),
}) => fieldsOf(
  validateSchedule(Schedule(recurrence: recurrence, timing: timing)),
);

void main() {
  test('a complete reminder is valid', () {
    expect(
      validateReminder(name: 'Drink water', displayName: 'Water', schedule: valid),
      isEmpty,
    );
  });

  test('names are required and limited in length', () {
    expect(
      fieldsOf(validateReminder(name: '  ', displayName: '', schedule: valid)),
      {ReminderField.name, ReminderField.displayName},
    );
    expect(
      fieldsOf(
        validateReminder(
          name: 'ok',
          displayName: 'x' * (ReminderLimits.displayNameMaxLength + 1),
          schedule: valid,
        ),
      ),
      {ReminderField.displayName},
    );
  });

  test('weekly needs a weekday; end date not before start', () {
    expect(
      scheduleIssues(
        recurrence: const RepeatRecurrence(
          unit: RepeatUnit.week,
          startDate: LocalDate(2026, 11, 4),
          endDate: LocalDate(2026, 11, 3),
        ),
      ),
      {ReminderField.weekdays, ReminderField.endDate},
    );
  });

  test('repeat interval must be 1-99', () {
    expect(
      scheduleIssues(
        recurrence: const RepeatRecurrence(
          unit: RepeatUnit.day,
          every: 0,
          startDate: LocalDate(2026, 11, 4),
        ),
      ),
      {ReminderField.every},
    );
  });

  test('a range needs different start and end times', () {
    expect(
      scheduleIssues(
        timing: const RangeTiming(
          start: LocalTime(9, 0),
          end: LocalTime(9, 0),
          mode: RangeMode.interval,
        ),
      ),
      {ReminderField.timeRange},
    );
  });

  test('random mode needs a count that fits the range', () {
    expect(
      scheduleIssues(
        timing: const RangeTiming(
          start: LocalTime(9, 0),
          end: LocalTime(17, 0),
          mode: RangeMode.random,
        ),
      ),
      {ReminderField.activations},
    );
    expect(
      scheduleIssues(
        timing: const RangeTiming(
          start: LocalTime(9, 0),
          end: LocalTime(9, 5),
          mode: RangeMode.random,
          maxActivations: 6,
        ),
      ),
      {ReminderField.activations},
    );
  });

  test('interval mode limits are optional but checked', () {
    expect(
      scheduleIssues(
        timing: const RangeTiming(
          start: LocalTime(9, 0),
          end: LocalTime(17, 0),
          mode: RangeMode.interval,
          intervalMinutes: 0,
          maxActivations: 0,
        ),
      ),
      {ReminderField.interval, ReminderField.activations},
    );
  });
}
