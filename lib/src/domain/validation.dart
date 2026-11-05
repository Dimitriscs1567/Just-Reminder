import 'schedule.dart';

/// The editor field a [ValidationIssue] belongs to.
enum ReminderField {
  name,
  displayName,
  description,
  every,
  weekdays,
  dayOfMonth,
  endDate,

  /// The list of times as a whole (none, too many).
  times,

  /// One time ([ValidationIssue.timeIndex]): its start, end or place among
  /// the others (overlaps, more than a day).
  timeSpan,

  /// One time's repeat interval.
  interval,

  /// One time's notification limit or random count.
  notifications,
}

/// A problem with a reminder being edited, with a message for the user.
class ValidationIssue {
  const ValidationIssue(this.field, this.message, {this.timeIndex});

  final ReminderField field;
  final String message;

  /// The time it is about: an index into `Schedule.times`.
  final int? timeIndex;

  @override
  String toString() =>
      '${field.name}${timeIndex == null ? '' : '[$timeIndex]'}: $message';
}

/// Input limits shared by validation and the editor.
abstract final class ReminderLimits {
  static const nameMaxLength = 60;

  /// Kept short because it has to fit on a small home screen widget.
  static const displayNameMaxLength = 30;
  static const descriptionMaxLength = 500;
  static const maxEvery = 99;
  static const maxTimes = 24;
  static const maxIntervalMinutes = Duration.minutesPerDay;

  /// Largest notification limit and random count of one time.
  static const maxNotifications = 100;
}

/// Checks the user's input; an empty list means it can be saved.
///
/// Whether the schedule still comes up again is checked separately with
/// `ScheduleEngine`, because it depends on "now".
List<ValidationIssue> validateReminder({
  required String name,
  required String displayName,
  required Schedule schedule,
  String? description,
}) => [
  ..._validateText(
    ReminderField.name,
    name,
    label: 'a name',
    maxLength: ReminderLimits.nameMaxLength,
  ),
  ..._validateText(
    ReminderField.displayName,
    displayName,
    label: 'a display name',
    maxLength: ReminderLimits.displayNameMaxLength,
  ),
  if ((description?.trim().length ?? 0) > ReminderLimits.descriptionMaxLength)
    const ValidationIssue(
      ReminderField.description,
      'Use at most ${ReminderLimits.descriptionMaxLength} characters',
    ),
  ...validateSchedule(schedule),
];

/// Checks a schedule's own consistency.
List<ValidationIssue> validateSchedule(Schedule schedule) => [
  ..._validateRecurrence(schedule.recurrence),
  ..._validateTimes(schedule.times),
];

Iterable<ValidationIssue> _validateRecurrence(Recurrence recurrence) sync* {
  if (recurrence is! RepeatRecurrence) return;
  if (recurrence.every < 1 || recurrence.every > ReminderLimits.maxEvery) {
    yield const ValidationIssue(
      ReminderField.every,
      'Choose a number from 1 to ${ReminderLimits.maxEvery}',
    );
  }
  if (recurrence.unit == RepeatUnit.week &&
      (recurrence.weekdays.isEmpty ||
          recurrence.weekdays.any((day) => day < 1 || day > 7))) {
    yield const ValidationIssue(
      ReminderField.weekdays,
      'Pick at least one weekday',
    );
  }
  if (recurrence.unit == RepeatUnit.month &&
      (recurrence.dayOfMonth < 1 || recurrence.dayOfMonth > 31)) {
    yield const ValidationIssue(
      ReminderField.dayOfMonth,
      'Choose a day from 1 to 31',
    );
  }
  final endDate = recurrence.endDate;
  if (endDate != null && endDate.isBefore(recurrence.startDate)) {
    yield const ValidationIssue(
      ReminderField.endDate,
      'The end date can’t be before the start date',
    );
  }
}

/// Each time on its own, then the times together: they may not overlap
/// (one may start exactly when the previous one ends) and must fit in one
/// day, so a day's times never run into the next day's.
Iterable<ValidationIssue> _validateTimes(List<ReminderTime> times) sync* {
  if (times.isEmpty) {
    yield const ValidationIssue(ReminderField.times, 'Add at least one time');
    return;
  }
  if (times.length > ReminderLimits.maxTimes) {
    yield const ValidationIssue(
      ReminderField.times,
      'Use at most ${ReminderLimits.maxTimes} times',
    );
  }

  final spanIssues = <int>{};
  for (var index = 0; index < times.length; index++) {
    final issues = _validateTime(times[index], index).toList();
    spanIssues.addAll([
      for (final issue in issues)
        if (issue.field == ReminderField.timeSpan) index,
    ]);
    yield* issues;
  }

  // Minutes from the start of the day, with ends past midnight above 1440.
  final order = [for (var i = 0; i < times.length; i++) i]
    ..sort((a, b) => times[a].start.compareTo(times[b].start));
  int startOf(int index) => times[index].start.minutesOfDay;
  int endOf(int index) => startOf(index) + (times[index].spanMinutes ?? 0);

  for (var k = 1; k < order.length; k++) {
    final previous = order[k - 1];
    final current = order[k];
    if (spanIssues.contains(current)) continue;
    if (startOf(current) == startOf(previous)) {
      yield ValidationIssue(
        ReminderField.timeSpan,
        'Another time starts at the same minute',
        timeIndex: current,
      );
    } else if (endOf(previous) > startOf(current)) {
      yield ValidationIssue(
        ReminderField.timeSpan,
        'Overlaps the time before it',
        timeIndex: current,
      );
    }
  }
  final last = order.last;
  if (order.length > 1 &&
      !spanIssues.contains(last) &&
      endOf(last) > startOf(order.first) + Duration.minutesPerDay) {
    yield ValidationIssue(
      ReminderField.timeSpan,
      'All times must fit in one day: this one runs into the next day’s '
      'first time',
      timeIndex: last,
    );
  }
}

Iterable<ValidationIssue> _validateTime(ReminderTime time, int index) sync* {
  final span = time.spanMinutes;
  if (span == 0) {
    yield ValidationIssue(
      ReminderField.timeSpan,
      'Start and end must be different',
      timeIndex: index,
    );
  }
  switch (time.mode) {
    case NotifyMode.once:
      break;
    case NotifyMode.repeat:
      if (time.intervalMinutes < 1 ||
          time.intervalMinutes > ReminderLimits.maxIntervalMinutes) {
        yield ValidationIssue(
          ReminderField.interval,
          'Choose an interval from 1 minute to 24 hours',
          timeIndex: index,
        );
      }
      final max = time.maxNotifications;
      if (max != null && (max < 1 || max > ReminderLimits.maxNotifications)) {
        yield ValidationIssue(
          ReminderField.notifications,
          'Choose a limit from 1 to ${ReminderLimits.maxNotifications}',
          timeIndex: index,
        );
      }
    case NotifyMode.random:
      final count = time.randomCount;
      if (span == null) {
        yield ValidationIssue(
          ReminderField.notifications,
          'Random notifications need an end time',
          timeIndex: index,
        );
      } else if (count < 1 || count > ReminderLimits.maxNotifications) {
        yield ValidationIssue(
          ReminderField.notifications,
          'Choose how many, from 1 to ${ReminderLimits.maxNotifications}',
          timeIndex: index,
        );
      } else if (span > 0 && count > span) {
        yield ValidationIssue(
          ReminderField.notifications,
          'At most $span fit between start and end',
          timeIndex: index,
        );
      }
  }
}

Iterable<ValidationIssue> _validateText(
  ReminderField field,
  String value, {
  required String label,
  required int maxLength,
}) sync* {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    yield ValidationIssue(field, 'Enter $label');
  } else if (trimmed.length > maxLength) {
    yield ValidationIssue(field, 'Use at most $maxLength characters');
  }
}
