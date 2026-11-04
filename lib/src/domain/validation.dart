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
  timeRange,
  interval,
  activations,
}

/// A problem with a reminder being edited, with a message for the user.
class ValidationIssue {
  const ValidationIssue(this.field, this.message);

  final ReminderField field;
  final String message;

  @override
  String toString() => '${field.name}: $message';
}

/// Input limits shared by validation and the editor.
abstract final class ReminderLimits {
  static const nameMaxLength = 60;

  /// Kept short because it has to fit on a small home screen widget.
  static const displayNameMaxLength = 30;
  static const descriptionMaxLength = 500;
  static const maxEvery = 99;
  static const maxIntervalMinutes = Duration.minutesPerDay;
  static const maxActivationsPerWindow = 100;
}

/// Checks the user's input; an empty list means it can be saved.
///
/// Whether the schedule still has upcoming activations is checked
/// separately with `ScheduleEngine`, because it depends on "now".
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
List<ValidationIssue> validateSchedule(Schedule schedule) {
  final issues = <ValidationIssue>[];

  if (schedule.recurrence case final RepeatRecurrence repeat) {
    if (repeat.every < 1 || repeat.every > ReminderLimits.maxEvery) {
      issues.add(
        const ValidationIssue(
          ReminderField.every,
          'Choose a number from 1 to ${ReminderLimits.maxEvery}',
        ),
      );
    }
    if (repeat.unit == RepeatUnit.week &&
        (repeat.weekdays.isEmpty ||
            repeat.weekdays.any((day) => day < 1 || day > 7))) {
      issues.add(
        const ValidationIssue(
          ReminderField.weekdays,
          'Pick at least one weekday',
        ),
      );
    }
    if (repeat.unit == RepeatUnit.month &&
        (repeat.dayOfMonth < 1 || repeat.dayOfMonth > 31)) {
      issues.add(
        const ValidationIssue(
          ReminderField.dayOfMonth,
          'Choose a day from 1 to 31',
        ),
      );
    }
    final endDate = repeat.endDate;
    if (endDate != null && endDate.isBefore(repeat.startDate)) {
      issues.add(
        const ValidationIssue(
          ReminderField.endDate,
          'The end date can’t be before the start date',
        ),
      );
    }
  }

  if (schedule.timing case final RangeTiming range) {
    if (range.windowMinutes == 0) {
      issues.add(
        const ValidationIssue(
          ReminderField.timeRange,
          'Start and end time must be different',
        ),
      );
      return issues;
    }
    final count = range.maxActivations;
    switch (range.mode) {
      case RangeMode.interval:
        if (range.intervalMinutes < 1 ||
            range.intervalMinutes > ReminderLimits.maxIntervalMinutes) {
          issues.add(
            const ValidationIssue(
              ReminderField.interval,
              'Choose an interval from 1 minute to 24 hours',
            ),
          );
        }
        if (count != null &&
            (count < 1 || count > ReminderLimits.maxActivationsPerWindow)) {
          issues.add(
            const ValidationIssue(
              ReminderField.activations,
              'Choose a limit from 1 to '
              '${ReminderLimits.maxActivationsPerWindow}',
            ),
          );
        }
      case RangeMode.random:
        if (count == null ||
            count < 1 ||
            count > ReminderLimits.maxActivationsPerWindow) {
          issues.add(
            const ValidationIssue(
              ReminderField.activations,
              'Choose how many times, from 1 to '
              '${ReminderLimits.maxActivationsPerWindow}',
            ),
          );
        } else if (count > range.windowMinutes) {
          issues.add(
            ValidationIssue(
              ReminderField.activations,
              'At most ${range.windowMinutes} activations fit in this range',
            ),
          );
        }
    }
  }

  return issues;
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
