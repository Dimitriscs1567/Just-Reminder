import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/validation.dart';
import 'package:just_reminder/src/state/providers.dart';
import 'package:just_reminder/src/ui/screens/editor/editor_controller.dart';
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

LocalTime t(int hour, [int minute = 0]) => LocalTime(hour, minute);

void main() {
  test('a new reminder repeats daily, once at the next full hour', () {
    final draft = EditorDraft.forNew(id: 'x', now: now);
    expect(
      draft.schedule,
      Schedule(
        recurrence: const RepeatRecurrence(
          unit: RepeatUnit.day,
          startDate: LocalDate(2026, 11, 4),
        ),
        times: [ReminderTime(start: t(10))],
      ),
    );
    expect(draft.weekdays, {DateTime.wednesday});
    expect(draft.displayNameEdited, isFalse);
  });

  test('an unchanged reminder gives back exactly its schedule', () {
    final schedules = [
      Schedule(
        recurrence: const OnceRecurrence(LocalDate(2026, 11, 5)),
        times: [ReminderTime(start: t(9))],
      ),
      Schedule(
        recurrence: const RepeatRecurrence(
          unit: RepeatUnit.week,
          every: 2,
          startDate: LocalDate(2026, 11, 2),
          endDate: LocalDate(2026, 12, 31),
          weekdays: {1, 5},
        ),
        times: [
          ReminderTime(
            start: t(9),
            end: t(12),
            mode: NotifyMode.repeat,
            intervalMinutes: 30,
            maxNotifications: 5,
          ),
          ReminderTime(start: t(15), mode: NotifyMode.repeat),
        ],
      ),
      Schedule(
        recurrence: const RepeatRecurrence(
          unit: RepeatUnit.month,
          startDate: LocalDate(2026, 11, 1),
          dayOfMonth: 31,
        ),
        times: [
          ReminderTime(start: t(8)),
          ReminderTime(
            start: t(22),
            end: t(2),
            mode: NotifyMode.random,
            randomCount: 3,
          ),
        ],
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

  test('a time saves only what its choice uses', () {
    final time = TimeDraft(
      key: 0,
      start: t(9),
      end: t(12),
      randomCount: 4,
      maxNotifications: 7,
    );
    // No end yet: the end is kept for later, random falls back to once.
    expect(time.time, ReminderTime(start: t(9)));
    expect(
      time.copyWith(mode: NotifyMode.random).time,
      ReminderTime(start: t(9)),
    );
    final ranged = time.copyWith(hasEnd: true);
    expect(
      ranged.copyWith(mode: NotifyMode.random).time,
      ReminderTime(
        start: t(9),
        end: t(12),
        mode: NotifyMode.random,
        randomCount: 4,
      ),
    );
    expect(
      ranged.copyWith(mode: NotifyMode.repeat).time.maxNotifications,
      isNull,
    );
    expect(
      ranged
          .copyWith(mode: NotifyMode.repeat, limitNotifications: true)
          .time
          .maxNotifications,
      7,
    );
    // Without an explicit end, the end defaults to an hour after the start.
    expect(
      TimeDraft(key: 1, start: t(23, 30), hasEnd: true).time.end,
      t(0, 30),
    );
  });

  test('times are added after the last one, kept in order, removed', () {
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    addTearDown(container.dispose);
    const target = (mode: EditorMode.create, reminderId: null);
    final controller = container.read(editorProvider(target).notifier);
    List<LocalTime> starts() => [
      for (final time in container.read(editorProvider(target)).times)
        time.start,
    ];
    final keep = container.listen(editorProvider(target), (_, _) {});
    addTearDown(keep.close);

    expect(starts(), [t(10)]);
    final added = controller.addTime();
    expect(starts(), [t(10), t(11)]);

    // A time with an end: the next one is added an hour after its end.
    controller.editTime(
      added,
      (time) => time.copyWith(hasEnd: true, end: t(13)),
    );
    controller.addTime();
    expect(starts(), [t(10), t(11), t(14)]);

    // Moving a start keeps the list in order.
    controller.editTime(added, (time) => time.copyWith(start: t(8)));
    expect(starts(), [t(8), t(10), t(14)]);

    controller.removeTime(added);
    expect(starts(), [t(10), t(14)]);
    expect(
      validateSchedule(container.read(editorProvider(target)).schedule),
      isEmpty,
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
