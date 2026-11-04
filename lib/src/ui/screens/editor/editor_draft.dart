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
    required this.useRange,
    required this.fixedTime,
    required this.rangeStart,
    required this.rangeEnd,
    required this.rangeMode,
    required this.intervalMinutes,
    required this.limitActivations,
    required this.maxActivations,
    required this.randomCount,
  });

  /// Defaults for a new reminder: repeating daily at the next full hour.
  factory EditorDraft.forNew({required String id, required DateTime now}) {
    final today = LocalDate.fromDateTime(now);
    final nextHour = LocalTime((now.hour + 1) % 24, 0);
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
      useRange: false,
      fixedTime: nextHour,
      rangeStart: const LocalTime(9, 0),
      rangeEnd: const LocalTime(17, 0),
      rangeMode: RangeMode.interval,
      intervalMinutes: 60,
      limitActivations: false,
      maxActivations: 5,
      randomCount: 3,
    );
  }

  /// The form for an existing reminder; fields its schedule doesn't use get
  /// the same defaults as a new reminder.
  factory EditorDraft.fromReminder(Reminder reminder, {required DateTime now}) {
    final base = EditorDraft.forNew(id: reminder.id, now: now);
    var draft = base.copyWith(
      name: reminder.name,
      displayName: reminder.displayName,
      displayNameEdited: true,
      description: reminder.description ?? '',
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
    switch (reminder.schedule.timing) {
      case FixedTiming(:final time):
        draft = draft.copyWith(useRange: false, fixedTime: time);
      case final RangeTiming range:
        final max = range.maxActivations;
        draft = draft.copyWith(
          useRange: true,
          rangeStart: range.start,
          rangeEnd: range.end,
          rangeMode: range.mode,
          intervalMinutes: range.intervalMinutes,
          limitActivations: range.mode == RangeMode.interval && max != null,
          maxActivations: range.mode == RangeMode.interval && max != null
              ? max
              : null,
          randomCount: range.mode == RangeMode.random && max != null
              ? max
              : null,
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

  final bool useRange;
  final LocalTime fixedTime;
  final LocalTime rangeStart;
  final LocalTime rangeEnd;
  final RangeMode rangeMode;
  final int intervalMinutes;
  final bool limitActivations;
  final int maxActivations;
  final int randomCount;

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
    timing: useRange
        ? RangeTiming(
            start: rangeStart,
            end: rangeEnd,
            mode: rangeMode,
            intervalMinutes: intervalMinutes,
            maxActivations: switch (rangeMode) {
              RangeMode.interval => limitActivations ? maxActivations : null,
              RangeMode.random => randomCount,
            },
          )
        : FixedTiming(fixedTime),
  );

  /// Minutes in the current time range (0 when start == end).
  int get rangeMinutes => RangeTiming(
    start: rangeStart,
    end: rangeEnd,
    mode: rangeMode,
  ).windowMinutes;

  /// The largest random count the current range allows.
  int get maxRandomCount =>
      math.max(1, math.min(ReminderLimits.maxActivationsPerWindow, rangeMinutes));

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
    bool? useRange,
    LocalTime? fixedTime,
    LocalTime? rangeStart,
    LocalTime? rangeEnd,
    RangeMode? rangeMode,
    int? intervalMinutes,
    bool? limitActivations,
    int? maxActivations,
    int? randomCount,
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
    useRange: useRange ?? this.useRange,
    fixedTime: fixedTime ?? this.fixedTime,
    rangeStart: rangeStart ?? this.rangeStart,
    rangeEnd: rangeEnd ?? this.rangeEnd,
    rangeMode: rangeMode ?? this.rangeMode,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    limitActivations: limitActivations ?? this.limitActivations,
    maxActivations: maxActivations ?? this.maxActivations,
    randomCount: randomCount ?? this.randomCount,
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
      other.useRange == useRange &&
      other.fixedTime == fixedTime &&
      other.rangeStart == rangeStart &&
      other.rangeEnd == rangeEnd &&
      other.rangeMode == rangeMode &&
      other.intervalMinutes == intervalMinutes &&
      other.limitActivations == limitActivations &&
      other.maxActivations == maxActivations &&
      other.randomCount == randomCount;

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
    useRange,
    fixedTime,
    rangeStart,
    rangeEnd,
    rangeMode,
    intervalMinutes,
    limitActivations,
    maxActivations,
    randomCount,
  ]);
}

const Object _unset = Object();
