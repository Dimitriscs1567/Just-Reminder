import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/validation.dart';

const nineAm = ReminderTime(start: LocalTime(9, 0));

const valid = Schedule(
  recurrence: OnceRecurrence(LocalDate(2026, 11, 5)),
  times: [nineAm],
);

LocalTime t(int hour, [int minute = 0]) => LocalTime(hour, minute);

Set<ReminderField> fieldsOf(List<ValidationIssue> issues) => {
  for (final issue in issues) issue.field,
};

List<ValidationIssue> timeIssues(List<ReminderTime> times) => validateSchedule(
  Schedule(
    recurrence: const OnceRecurrence(LocalDate(2026, 11, 5)),
    times: times,
  ),
);

/// `field@index` for each issue, to check which time it points at.
Set<String> located(List<ValidationIssue> issues) => {
  for (final issue in issues) '${issue.field.name}@${issue.timeIndex}',
};

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
      fieldsOf(
        validateSchedule(
          const Schedule(
            recurrence: RepeatRecurrence(
              unit: RepeatUnit.week,
              startDate: LocalDate(2026, 11, 4),
              endDate: LocalDate(2026, 11, 3),
            ),
            times: [nineAm],
          ),
        ),
      ),
      {ReminderField.weekdays, ReminderField.endDate},
    );
  });

  test('repeat every must be 1-99', () {
    expect(
      fieldsOf(
        validateSchedule(
          const Schedule(
            recurrence: RepeatRecurrence(
              unit: RepeatUnit.day,
              every: 0,
              startDate: LocalDate(2026, 11, 4),
            ),
            times: [nineAm],
          ),
        ),
      ),
      {ReminderField.every},
    );
  });

  test('at least one time, at most the limit', () {
    expect(fieldsOf(timeIssues(const [])), {ReminderField.times});
    expect(
      fieldsOf(
        timeIssues([
          for (var i = 0; i <= ReminderLimits.maxTimes; i++)
            ReminderTime(start: LocalTime.fromMinutes(i * 30)),
        ]),
      ),
      {ReminderField.times},
    );
  });

  test('a time with an end needs a different end', () {
    expect(located(timeIssues([ReminderTime(start: t(9), end: t(9))])), {
      'timeSpan@0',
    });
  });

  test('times may touch but not overlap', () {
    // Back to back is fine.
    expect(
      timeIssues([
        ReminderTime(start: t(9), end: t(12)),
        ReminderTime(start: t(12), end: t(15)),
        ReminderTime(start: t(15)),
      ]),
      isEmpty,
    );
    // Reported on the later one, by its index in the list.
    expect(
      located(
        timeIssues([
          ReminderTime(start: t(11)),
          ReminderTime(start: t(9), end: t(12)),
        ]),
      ),
      {'timeSpan@0'},
    );
    expect(
      located(timeIssues([ReminderTime(start: t(9)), ReminderTime(start: t(9))])),
      {'timeSpan@1'},
    );
  });

  test('all times together fit in one day', () {
    // 22:00–07:00 ends before the next day's 08:00.
    expect(
      timeIssues([
        ReminderTime(start: t(8)),
        ReminderTime(start: t(22), end: t(7)),
      ]),
      isEmpty,
    );
    // 22:00–09:00 runs into the next day's 08:00.
    expect(
      located(
        timeIssues([
          ReminderTime(start: t(8)),
          ReminderTime(start: t(22), end: t(9)),
        ]),
      ),
      {'timeSpan@1'},
    );
    // A range past midnight followed by another time overlaps it.
    expect(
      located(
        timeIssues([
          ReminderTime(start: t(22), end: t(2)),
          ReminderTime(start: t(23)),
        ]),
      ),
      {'timeSpan@1'},
    );
  });

  test('repeat interval and limit are checked', () {
    expect(
      located(
        timeIssues([
          ReminderTime(
            start: t(9),
            mode: NotifyMode.repeat,
            intervalMinutes: 0,
            maxNotifications: 0,
          ),
        ]),
      ),
      {'interval@0', 'notifications@0'},
    );
  });

  test('random needs an end and a count that fits', () {
    expect(
      located(timeIssues([ReminderTime(start: t(9), mode: NotifyMode.random)])),
      {'notifications@0'},
    );
    expect(
      located(
        timeIssues([
          ReminderTime(
            start: t(9),
            end: t(9, 5),
            mode: NotifyMode.random,
            randomCount: 6,
          ),
        ]),
      ),
      {'notifications@0'},
    );
    // Settings of other modes are not checked.
    expect(
      timeIssues([
        ReminderTime(
          start: t(9),
          end: t(17),
          mode: NotifyMode.random,
          intervalMinutes: 0,
        ),
      ]),
      isEmpty,
    );
  });
}
