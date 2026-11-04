import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/validation.dart';
import 'package:just_reminder/src/ui/screens/editor/editor_draft.dart';

final now = DateTime(2026, 11, 4, 9, 30); // a Wednesday

Reminder reminderWith(Schedule schedule) => Reminder(
  id: 'r1',
  name: 'Drink water',
  displayName: 'Water',
  description: 'A full glass',
  schedule: schedule,
  createdAt: now,
  updatedAt: now,
  activeSince: now,
);

void main() {
  test('a new reminder repeats daily at the next full hour', () {
    final draft = EditorDraft.forNew(id: 'x', now: now);
    expect(draft.schedule, const Schedule(
      recurrence: RepeatRecurrence(
        unit: RepeatUnit.day,
        startDate: LocalDate(2026, 11, 4),
      ),
      timing: FixedTiming(LocalTime(10, 0)),
    ));
    expect(draft.weekdays, {DateTime.wednesday});
    expect(draft.displayNameEdited, isFalse);
  });

  test('an unchanged reminder gives back exactly its schedule', () {
    final schedules = [
      const Schedule(
        recurrence: OnceRecurrence(LocalDate(2026, 11, 5)),
        timing: FixedTiming(LocalTime(9, 0)),
      ),
      const Schedule(
        recurrence: RepeatRecurrence(
          unit: RepeatUnit.week,
          every: 2,
          startDate: LocalDate(2026, 11, 2),
          endDate: LocalDate(2026, 12, 31),
          weekdays: {1, 5},
        ),
        timing: RangeTiming(
          start: LocalTime(9, 0),
          end: LocalTime(17, 0),
          mode: RangeMode.interval,
          intervalMinutes: 30,
          maxActivations: 5,
        ),
      ),
      const Schedule(
        recurrence: RepeatRecurrence(
          unit: RepeatUnit.month,
          startDate: LocalDate(2026, 11, 1),
          dayOfMonth: 31,
        ),
        timing: RangeTiming(
          start: LocalTime(22, 0),
          end: LocalTime(2, 0),
          mode: RangeMode.random,
          maxActivations: 3,
        ),
      ),
      const Schedule(
        recurrence: RepeatRecurrence(
          unit: RepeatUnit.day,
          startDate: LocalDate(2026, 11, 1),
        ),
        timing: RangeTiming(
          start: LocalTime(8, 0),
          end: LocalTime(20, 0),
          mode: RangeMode.interval,
        ),
      ),
    ];
    for (final schedule in schedules) {
      final draft = EditorDraft.fromReminder(reminderWith(schedule), now: now);
      expect(draft.schedule, schedule);
      expect(draft.name, 'Drink water');
      expect(draft.displayNameEdited, isTrue);
    }
  });

  test('values of other choices are kept but not saved', () {
    final draft = EditorDraft.forNew(id: 'x', now: now).copyWith(
      unit: RepeatUnit.week,
      weekdays: {1, 2},
    );
    final daily = draft.copyWith(unit: RepeatUnit.day);
    expect(daily.weekdays, {1, 2}); // remembered for switching back
    expect((daily.schedule.recurrence as RepeatRecurrence).weekdays, isEmpty);
  });

  test('random mode saves the count, interval mode the optional limit', () {
    final range = EditorDraft.forNew(id: 'x', now: now).copyWith(
      useRange: true,
      randomCount: 4,
      maxActivations: 7,
    );
    expect(
      (range.copyWith(rangeMode: RangeMode.random).schedule.timing as RangeTiming)
          .maxActivations,
      4,
    );
    expect((range.schedule.timing as RangeTiming).maxActivations, isNull);
    expect(
      (range.copyWith(limitActivations: true).schedule.timing as RangeTiming)
          .maxActivations,
      7,
    );
  });

  test('the suggested display name fits the widget', () {
    expect(EditorDraft.suggestDisplayName('  Water  '), 'Water');
    expect(
      EditorDraft.suggestDisplayName('x' * 40).length,
      ReminderLimits.displayNameMaxLength,
    );
  });
}
