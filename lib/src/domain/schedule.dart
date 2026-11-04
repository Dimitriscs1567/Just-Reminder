import '../core/local_date.dart';
import '../core/local_time.dart';

/// When a reminder activates: on which days ([recurrence]) and at what
/// time(s) of those days ([timing]).
class Schedule {
  const Schedule({required this.recurrence, required this.timing});

  factory Schedule.fromJson(Map<String, Object?> json) => Schedule(
    recurrence: Recurrence.fromJson(_map(json['recurrence'])),
    timing: Timing.fromJson(_map(json['timing'])),
  );

  final Recurrence recurrence;
  final Timing timing;

  Schedule copyWith({Recurrence? recurrence, Timing? timing}) => Schedule(
    recurrence: recurrence ?? this.recurrence,
    timing: timing ?? this.timing,
  );

  Map<String, Object?> toJson() => {
    'recurrence': recurrence.toJson(),
    'timing': timing.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Schedule &&
      other.recurrence == recurrence &&
      other.timing == timing;

  @override
  int get hashCode => Object.hash(recurrence, timing);
}

// ---------------------------------------------------------------------------
// Recurrence: which days
// ---------------------------------------------------------------------------

/// The unit of a repeating reminder: every N days, weeks or months.
enum RepeatUnit { day, week, month }

/// Which days a reminder's activation window starts on.
sealed class Recurrence {
  const Recurrence();

  factory Recurrence.fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'once' => OnceRecurrence.fromJson(json),
        'repeat' => RepeatRecurrence.fromJson(json),
        final type => throw FormatException('Unknown recurrence: $type'),
      };

  /// Whether an activation window starts on [date].
  bool occursOn(LocalDate date);

  /// The earliest date a window can start on.
  LocalDate get firstDate;

  /// The latest date a window can start on; `null` repeats forever.
  LocalDate? get lastDate;

  Map<String, Object?> toJson();
}

/// Activates on a single date.
final class OnceRecurrence extends Recurrence {
  const OnceRecurrence(this.date);

  factory OnceRecurrence.fromJson(Map<String, Object?> json) =>
      OnceRecurrence(LocalDate.parse(json['date']! as String));

  final LocalDate date;

  @override
  bool occursOn(LocalDate date) => date == this.date;

  @override
  LocalDate get firstDate => date;

  @override
  LocalDate get lastDate => date;

  @override
  Map<String, Object?> toJson() => {'type': 'once', 'date': date.toIso()};

  @override
  bool operator ==(Object other) =>
      other is OnceRecurrence && other.date == date;

  @override
  int get hashCode => date.hashCode;
}

/// Repeats every [every] days, weeks (on [weekdays]) or months (on
/// [dayOfMonth]), from [startDate] until the optional [endDate] (inclusive).
final class RepeatRecurrence extends Recurrence {
  const RepeatRecurrence({
    required this.unit,
    required this.startDate,
    this.every = 1,
    this.weekdays = const {},
    this.dayOfMonth = 1,
    this.endDate,
  });

  factory RepeatRecurrence.fromJson(Map<String, Object?> json) {
    final endDate = json['endDate'] as String?;
    return RepeatRecurrence(
      unit: RepeatUnit.values.byName(json['unit']! as String),
      every: json['every']! as int,
      startDate: LocalDate.parse(json['startDate']! as String),
      endDate: endDate == null ? null : LocalDate.parse(endDate),
      weekdays: {
        for (final day in json['weekdays']! as List<Object?>) day! as int,
      },
      dayOfMonth: json['dayOfMonth']! as int,
    );
  }

  final RepeatUnit unit;

  /// Repeat every N [unit]s (N >= 1).
  final int every;

  final LocalDate startDate;

  /// Last date a window may start on (inclusive); `null` = no end.
  final LocalDate? endDate;

  /// ISO weekdays (1 = Monday … 7 = Sunday). Used when [unit] is week.
  final Set<int> weekdays;

  /// Day of the month (1–31). Used when [unit] is month. Months without
  /// that day use their last day instead.
  final int dayOfMonth;

  @override
  bool occursOn(LocalDate date) {
    if (date.isBefore(startDate)) return false;
    final end = endDate;
    if (end != null && date.isAfter(end)) return false;
    switch (unit) {
      case RepeatUnit.day:
        return startDate.daysUntil(date) % every == 0;
      case RepeatUnit.week:
        if (!weekdays.contains(date.weekday)) return false;
        final weeks = startDate.startOfWeek.daysUntil(date.startOfWeek) ~/ 7;
        return weeks % every == 0;
      case RepeatUnit.month:
        if (startDate.monthsUntil(date) % every != 0) return false;
        final lastDay = LocalDate.daysInMonth(date.year, date.month);
        return date.day == (dayOfMonth < lastDay ? dayOfMonth : lastDay);
    }
  }

  @override
  LocalDate get firstDate => startDate;

  @override
  LocalDate? get lastDate => endDate;

  RepeatRecurrence copyWith({
    RepeatUnit? unit,
    int? every,
    LocalDate? startDate,
    Object? endDate = _unset,
    Set<int>? weekdays,
    int? dayOfMonth,
  }) => RepeatRecurrence(
    unit: unit ?? this.unit,
    every: every ?? this.every,
    startDate: startDate ?? this.startDate,
    endDate: identical(endDate, _unset) ? this.endDate : endDate as LocalDate?,
    weekdays: weekdays ?? this.weekdays,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
  );

  @override
  Map<String, Object?> toJson() => {
    'type': 'repeat',
    'unit': unit.name,
    'every': every,
    'startDate': startDate.toIso(),
    'endDate': endDate?.toIso(),
    'weekdays': (weekdays.toList()..sort()),
    'dayOfMonth': dayOfMonth,
  };

  /// Equality is semantic: [weekdays] only matter for weekly and
  /// [dayOfMonth] only for monthly recurrences.
  @override
  bool operator ==(Object other) =>
      other is RepeatRecurrence &&
      other.unit == unit &&
      other.every == every &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      (unit != RepeatUnit.week ||
          (other.weekdays.length == weekdays.length &&
              other.weekdays.containsAll(weekdays))) &&
      (unit != RepeatUnit.month || other.dayOfMonth == dayOfMonth);

  @override
  int get hashCode => Object.hash(
    unit,
    every,
    startDate,
    endDate,
    unit == RepeatUnit.week ? Object.hashAllUnordered(weekdays) : 0,
    unit == RepeatUnit.month ? dayOfMonth : 0,
  );
}

// ---------------------------------------------------------------------------
// Timing: what time(s) of the day
// ---------------------------------------------------------------------------

/// What time(s) a reminder activates on the days its recurrence selects.
sealed class Timing {
  const Timing();

  factory Timing.fromJson(Map<String, Object?> json) => switch (json['type']) {
    'fixed' => FixedTiming.fromJson(json),
    'range' => RangeTiming.fromJson(json),
    final type => throw FormatException('Unknown timing: $type'),
  };

  Map<String, Object?> toJson();
}

/// Activates once at [time].
final class FixedTiming extends Timing {
  const FixedTiming(this.time);

  factory FixedTiming.fromJson(Map<String, Object?> json) =>
      FixedTiming(LocalTime.parse(json['time']! as String));

  final LocalTime time;

  @override
  Map<String, Object?> toJson() => {'type': 'fixed', 'time': time.toIso()};

  @override
  bool operator ==(Object other) => other is FixedTiming && other.time == time;

  @override
  int get hashCode => time.hashCode;
}

/// How activations are placed inside a time range.
enum RangeMode {
  /// Every [RangeTiming.intervalMinutes] from the range start.
  interval,

  /// Exactly [RangeTiming.maxActivations] random times, one per equal slot.
  random,
}

/// Activates several times inside the window [start]–[end]. An [end] before
/// [start] means the window runs past midnight into the next day.
final class RangeTiming extends Timing {
  const RangeTiming({
    required this.start,
    required this.end,
    required this.mode,
    this.intervalMinutes = 60,
    this.maxActivations,
  });

  factory RangeTiming.fromJson(Map<String, Object?> json) => RangeTiming(
    start: LocalTime.parse(json['start']! as String),
    end: LocalTime.parse(json['end']! as String),
    mode: RangeMode.values.byName(json['mode']! as String),
    intervalMinutes: json['intervalMinutes']! as int,
    maxActivations: json['maxActivations'] as int?,
  );

  final LocalTime start;
  final LocalTime end;
  final RangeMode mode;

  /// Minutes between activations (interval mode).
  final int intervalMinutes;

  /// Interval mode: optional cap per window. Random mode: the exact number
  /// of activations per window (required).
  final int? maxActivations;

  /// Whether the window ends on the following day.
  bool get endsNextDay => end.minutesOfDay < start.minutesOfDay;

  /// Wall-clock length of the window in minutes (0 when start == end).
  int get windowMinutes => endsNextDay
      ? end.minutesOfDay + Duration.minutesPerDay - start.minutesOfDay
      : end.minutesOfDay - start.minutesOfDay;

  RangeTiming copyWith({
    LocalTime? start,
    LocalTime? end,
    RangeMode? mode,
    int? intervalMinutes,
    Object? maxActivations = _unset,
  }) => RangeTiming(
    start: start ?? this.start,
    end: end ?? this.end,
    mode: mode ?? this.mode,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    maxActivations: identical(maxActivations, _unset)
        ? this.maxActivations
        : maxActivations as int?,
  );

  @override
  Map<String, Object?> toJson() => {
    'type': 'range',
    'start': start.toIso(),
    'end': end.toIso(),
    'mode': mode.name,
    'intervalMinutes': intervalMinutes,
    'maxActivations': maxActivations,
  };

  /// Equality is semantic: [intervalMinutes] only matters in interval mode.
  @override
  bool operator ==(Object other) =>
      other is RangeTiming &&
      other.start == start &&
      other.end == end &&
      other.mode == mode &&
      (mode == RangeMode.random || other.intervalMinutes == intervalMinutes) &&
      other.maxActivations == maxActivations;

  @override
  int get hashCode => Object.hash(
    start,
    end,
    mode,
    mode == RangeMode.random ? 0 : intervalMinutes,
    maxActivations,
  );
}

const Object _unset = Object();

Map<String, Object?> _map(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();
