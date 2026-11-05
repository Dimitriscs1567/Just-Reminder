import 'dart:math' as math;

import '../../../core/local_date.dart';
import '../../../core/local_time.dart';
import '../../../domain/reminder.dart';
import '../../../domain/schedule.dart';
import '../../../domain/validation.dart';

/// Everything the editor form holds, flat, so switching e.g. between
/// "Once" and "Repeat" keeps the values of the other choice.
class EditorDraft {
  const EditorDraft({
    required this.id,
    required this.name,
    required this.displayName,
    required this.displayNameEdited,
    required this.description,
    required this.repeats,
    required this.onceDate,
    required this.unit,
    required this.every,
    required this.weekdays,
    required this.dayOfMonth,
    required this.startDate,
    required this.endDate,
    required this.times,
  });

  /// Defaults for a new reminder: repeating daily, once at the next full
  /// hour.
  factory EditorDraft.forNew({required String id, required DateTime now}) {
    final today = LocalDate.fromDateTime(now);
    return EditorDraft(
      id: id,
      name: '',
      displayName: '',
      displayNameEdited: false,
      description: '',
      repeats: true,
      onceDate: now.hour == 23 ? today.addDays(1) : today,
      unit: RepeatUnit.day,
      every: 1,
      weekdays: {today.weekday},
      dayOfMonth: today.day,
      startDate: today,
      endDate: null,
      times: [TimeDraft(key: 0, start: LocalTime((now.hour + 1) % 24, 0))],
    );
  }

  /// The form for an existing reminder; fields its schedule doesn't use get
  /// the same defaults as a new reminder.
  factory EditorDraft.fromReminder(Reminder reminder, {required DateTime now}) {
    final base = EditorDraft.forNew(id: reminder.id, now: now);
    final times = reminder.schedule.orderedTimes;
    var draft = base.copyWith(
      name: reminder.name,
      displayName: reminder.displayName,
      displayNameEdited: true,
      description: reminder.description ?? '',
      times: [
        for (var key = 0; key < times.length; key++)
          TimeDraft.of(times[key], key: key),
      ],
    );
    switch (reminder.schedule.recurrence) {
      case OnceRecurrence(:final date):
        draft = draft.copyWith(repeats: false, onceDate: date);
      case final RepeatRecurrence repeat:
        draft = draft.copyWith(
          repeats: true,
          unit: repeat.unit,
          every: repeat.every,
          weekdays: repeat.weekdays.isEmpty ? null : repeat.weekdays,
          dayOfMonth: repeat.dayOfMonth,
          startDate: repeat.startDate,
          endDate: repeat.endDate,
        );
    }
    return draft;
  }

  /// Reminder id; for new reminders it is generated up front so the
  /// preview shows the same random times that will be saved.
  final String id;
  final String name;
  final String displayName;

  /// Until the user types a display name, it follows the name.
  final bool displayNameEdited;
  final String description;

  final bool repeats;
  final LocalDate onceDate;
  final RepeatUnit unit;
  final int every;
  final Set<int> weekdays;
  final int dayOfMonth;
  final LocalDate startDate;
  final LocalDate? endDate;

  /// The reminder's times, by start.
  final List<TimeDraft> times;

  /// The display name to suggest while the user hasn't typed one.
  static String suggestDisplayName(String name) {
    final trimmed = name.trim();
    return trimmed.length <= ReminderLimits.displayNameMaxLength
        ? trimmed
        : trimmed.substring(0, ReminderLimits.displayNameMaxLength).trim();
  }

  /// The schedule the form describes. Values that only matter for another
  /// choice (e.g. weekdays of a daily reminder) are left out.
  Schedule get schedule => Schedule(
    recurrence: repeats
        ? RepeatRecurrence(
            unit: unit,
            every: every,
            startDate: startDate,
            endDate: endDate,
            weekdays: unit == RepeatUnit.week ? weekdays : const {},
            dayOfMonth: unit == RepeatUnit.month ? dayOfMonth : 1,
          )
        : OnceRecurrence(onceDate),
    times: [for (final time in times) time.time],
  );

  EditorDraft copyWith({
    String? name,
    String? displayName,
    bool? displayNameEdited,
    String? description,
    bool? repeats,
    LocalDate? onceDate,
    RepeatUnit? unit,
    int? every,
    Set<int>? weekdays,
    int? dayOfMonth,
    LocalDate? startDate,
    Object? endDate = _unset,
    List<TimeDraft>? times,
  }) => EditorDraft(
    id: id,
    name: name ?? this.name,
    displayName: displayName ?? this.displayName,
    displayNameEdited: displayNameEdited ?? this.displayNameEdited,
    description: description ?? this.description,
    repeats: repeats ?? this.repeats,
    onceDate: onceDate ?? this.onceDate,
    unit: unit ?? this.unit,
    every: every ?? this.every,
    weekdays: weekdays ?? this.weekdays,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    startDate: startDate ?? this.startDate,
    endDate: identical(endDate, _unset) ? this.endDate : endDate as LocalDate?,
    times: times ?? this.times,
  );

  @override
  bool operator ==(Object other) =>
      other is EditorDraft &&
      other.id == id &&
      other.name == name &&
      other.displayName == displayName &&
      other.displayNameEdited == displayNameEdited &&
      other.description == description &&
      other.repeats == repeats &&
      other.onceDate == onceDate &&
      other.unit == unit &&
      other.every == every &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.dayOfMonth == dayOfMonth &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      _sameTimes(other.times, times);

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    displayName,
    displayNameEdited,
    description,
    repeats,
    onceDate,
    unit,
    every,
    Object.hashAllUnordered(weekdays),
    dayOfMonth,
    startDate,
    endDate,
    Object.hashAll(times),
  ]);

  static bool _sameTimes(List<TimeDraft> a, List<TimeDraft> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One time in the editor, flat, so switching e.g. between "Repeat" and
/// "Random" keeps the values of the other choice.
class TimeDraft {
  const TimeDraft({
    required this.key,
    required this.start,
    this.hasEnd = false,
    this.end,
    this.mode = NotifyMode.once,
    this.intervalMinutes = 30,
    this.limitNotifications = false,
    this.maxNotifications = 5,
    this.randomCount = 3,
  });

  factory TimeDraft.of(ReminderTime time, {required int key}) {
    final max = time.maxNotifications;
    return TimeDraft(
      key: key,
      start: time.start,
      hasEnd: time.end != null,
      end: time.end,
      mode: time.mode,
      intervalMinutes: time.intervalMinutes,
      limitNotifications: time.mode == NotifyMode.repeat && max != null,
      maxNotifications: max ?? 5,
      randomCount: time.randomCount,
    );
  }

  /// Identifies it in the editor while the times re-sort; not saved.
  final int key;

  final LocalTime start;
  final bool hasEnd;

  /// The end while [hasEnd] (kept when switched off); defaults to an hour
  /// after the start.
  final LocalTime? end;

  final NotifyMode mode;
  final int intervalMinutes;
  final bool limitNotifications;
  final int maxNotifications;
  final int randomCount;

  /// The end to show and save.
  LocalTime get endOrDefault =>
      end ?? LocalTime.fromMinutes((start.minutesOfDay + 60) % 1440);

  /// The time it describes. Random without an end isn't offered, so it
  /// falls back to a single notification.
  ReminderTime get time => ReminderTime(
    start: start,
    end: hasEnd ? endOrDefault : null,
    mode: mode == NotifyMode.random && !hasEnd ? NotifyMode.once : mode,
    intervalMinutes: intervalMinutes,
    maxNotifications: limitNotifications ? maxNotifications : null,
    randomCount: randomCount,
  );

  /// Minutes from start to end (0 when they are equal).
  int get spanMinutes =>
      ReminderTime(start: start, end: endOrDefault).spanMinutes ?? 0;

  /// The largest random count start–end allows.
  int get maxRandomCount =>
      math.max(1, math.min(ReminderLimits.maxNotifications, spanMinutes));

  TimeDraft copyWith({
    LocalTime? start,
    bool? hasEnd,
    LocalTime? end,
    NotifyMode? mode,
    int? intervalMinutes,
    bool? limitNotifications,
    int? maxNotifications,
    int? randomCount,
  }) => TimeDraft(
    key: key,
    start: start ?? this.start,
    hasEnd: hasEnd ?? this.hasEnd,
    end: end ?? this.end,
    mode: mode ?? this.mode,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    limitNotifications: limitNotifications ?? this.limitNotifications,
    maxNotifications: maxNotifications ?? this.maxNotifications,
    randomCount: randomCount ?? this.randomCount,
  );

  /// Compares what the user entered; the [key] is ignored.
  @override
  bool operator ==(Object other) =>
      other is TimeDraft &&
      other.start == start &&
      other.hasEnd == hasEnd &&
      other.end == end &&
      other.mode == mode &&
      other.intervalMinutes == intervalMinutes &&
      other.limitNotifications == limitNotifications &&
      other.maxNotifications == maxNotifications &&
      other.randomCount == randomCount;

  @override
  int get hashCode => Object.hash(
    start,
    hasEnd,
    end,
    mode,
    intervalMinutes,
    limitNotifications,
    maxNotifications,
    randomCount,
  );
}

const Object _unset = Object();
