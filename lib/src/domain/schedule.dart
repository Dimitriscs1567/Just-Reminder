import '../core/local_date.dart';
import '../core/local_time.dart';

/// When a reminder reminds: on which days ([recurrence]) and at which
/// [times] of those days. Each time is one reminder that is done or missed
/// as a whole.
class Schedule {
  const Schedule({required this.recurrence, required this.times});

  factory Schedule.fromJson(Map<String, Object?> json) {
    final recurrence = Recurrence.fromJson(_map(json['recurrence']));
    final times = json['times'];
    return Schedule(
      recurrence: recurrence,
      times: times is List<Object?>
          ? [for (final time in times) ReminderTime.fromJson(_map(time))]
          // Stored before 2026-11-05: a single fixed time or time range.
          : [ReminderTime.fromLegacyTiming(_map(json['timing']))],
    );
  }

  final Recurrence recurrence;

  /// One or more times, in any order (see [orderedTimes]).
  final List<ReminderTime> times;

  /// [times] by start time.
  List<ReminderTime> get orderedTimes =>
      [...times]..sort((a, b) => a.start.compareTo(b.start));

  Schedule copyWith({Recurrence? recurrence, List<ReminderTime>? times}) =>
      Schedule(
        recurrence: recurrence ?? this.recurrence,
        times: times ?? this.times,
      );

  Map<String, Object?> toJson() => {
    'recurrence': recurrence.toJson(),
    'times': [for (final time in orderedTimes) time.toJson()],
  };

  /// The order of [times] doesn't matter.
  @override
  bool operator ==(Object other) {
    if (other is! Schedule || other.recurrence != recurrence) return false;
    final mine = orderedTimes;
    final theirs = other.orderedTimes;
    if (mine.length != theirs.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(recurrence, Object.hashAll(orderedTimes));
}

// ---------------------------------------------------------------------------
// Recurrence: which days
// ---------------------------------------------------------------------------

/// The unit of a repeating reminder: every N days, weeks or months.
enum RepeatUnit { day, week, month }

/// Which days a reminder reminds on.
sealed class Recurrence {
  const Recurrence();

  factory Recurrence.fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'once' => OnceRecurrence.fromJson(json),
        'repeat' => RepeatRecurrence.fromJson(json),
        final type => throw FormatException('Unknown recurrence: $type'),
      };

  /// Whether the reminder reminds on [date].
  bool occursOn(LocalDate date);

  /// The earliest date it can remind on.
  LocalDate get firstDate;

  /// The latest date it can remind on; `null` repeats forever.
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

  /// The last date it reminds on (inclusive); `null` = no end.
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
// Times: when in the day
// ---------------------------------------------------------------------------

/// How a time notifies.
enum NotifyMode {
  /// One notification, at the start.
  once,

  /// From the start every [ReminderTime.intervalMinutes], optionally at most
  /// [ReminderTime.maxNotifications] times.
  repeat,

  /// Exactly [ReminderTime.randomCount] notifications at random moments
  /// between start and end: the span is split into equal parts with one
  /// random minute in each. Needs an end.
  random,
}

/// One time of the day a reminder reminds at. Each day it is one reminder:
/// due from its first notification until it is done; missed at its [end],
/// or — without an end — when the reminder's next time starts.
///
/// An [end] before [start] runs past midnight into the next day.
final class ReminderTime {
  const ReminderTime({
    required this.start,
    this.end,
    this.mode = NotifyMode.once,
    this.intervalMinutes = 30,
    this.maxNotifications,
    this.randomCount = 3,
  });

  factory ReminderTime.fromJson(Map<String, Object?> json) {
    final end = json['end'] as String?;
    return ReminderTime(
      start: LocalTime.parse(json['start']! as String),
      end: end == null ? null : LocalTime.parse(end),
      mode: NotifyMode.values.byName(json['mode']! as String),
      intervalMinutes: json['intervalMinutes']! as int,
      maxNotifications: json['maxNotifications'] as int?,
      randomCount: json['randomCount']! as int,
    );
  }

  /// A time as stored before 2026-11-05: `{type: fixed, time}`, or
  /// `{type: range, start, end, mode: interval | random, intervalMinutes,
  /// maxActivations}` whose activations are now one time's notifications.
  factory ReminderTime.fromLegacyTiming(Map<String, Object?> json) {
    switch (json['type']) {
      case 'fixed':
        return ReminderTime(start: LocalTime.parse(json['time']! as String));
      case 'range':
        final random = json['mode'] == 'random';
        final max = json['maxActivations'] as int?;
        return ReminderTime(
          start: LocalTime.parse(json['start']! as String),
          end: LocalTime.parse(json['end']! as String),
          mode: random ? NotifyMode.random : NotifyMode.repeat,
          intervalMinutes: json['intervalMinutes'] as int? ?? 60,
          maxNotifications: random ? null : max,
          randomCount: random ? max ?? 1 : 3,
        );
      case final type:
        throw FormatException('Unknown timing: $type');
    }
  }

  final LocalTime start;

  /// When it is missed if not done; `null`: when the next time starts.
  final LocalTime? end;

  final NotifyMode mode;

  /// Minutes between notifications ([NotifyMode.repeat]).
  final int intervalMinutes;

  /// At most this many notifications ([NotifyMode.repeat]); `null` = no
  /// limit.
  final int? maxNotifications;

  /// How many random notifications ([NotifyMode.random]).
  final int randomCount;

  bool get hasEnd => end != null;

  /// Whether the end is on the following day.
  bool get endsNextDay {
    final end = this.end;
    return end != null && end.minutesOfDay < start.minutesOfDay;
  }

  /// Minutes from start to end (0 when they are equal); `null` without an
  /// end.
  int? get spanMinutes {
    final end = this.end;
    if (end == null) return null;
    return endsNextDay
        ? end.minutesOfDay + Duration.minutesPerDay - start.minutesOfDay
        : end.minutesOfDay - start.minutesOfDay;
  }

  ReminderTime copyWith({
    LocalTime? start,
    Object? end = _unset,
    NotifyMode? mode,
    int? intervalMinutes,
    Object? maxNotifications = _unset,
    int? randomCount,
  }) => ReminderTime(
    start: start ?? this.start,
    end: identical(end, _unset) ? this.end : end as LocalTime?,
    mode: mode ?? this.mode,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    maxNotifications: identical(maxNotifications, _unset)
        ? this.maxNotifications
        : maxNotifications as int?,
    randomCount: randomCount ?? this.randomCount,
  );

  Map<String, Object?> toJson() => {
    'start': start.toIso(),
    'end': end?.toIso(),
    'mode': mode.name,
    'intervalMinutes': intervalMinutes,
    'maxNotifications': maxNotifications,
    'randomCount': randomCount,
  };

  /// Equality is semantic: the interval and its limit only matter when
  /// repeating, the random count only for random times.
  @override
  bool operator ==(Object other) =>
      other is ReminderTime &&
      other.start == start &&
      other.end == end &&
      other.mode == mode &&
      (mode != NotifyMode.repeat ||
          (other.intervalMinutes == intervalMinutes &&
              other.maxNotifications == maxNotifications)) &&
      (mode != NotifyMode.random || other.randomCount == randomCount);

  @override
  int get hashCode => Object.hash(
    start,
    end,
    mode,
    mode == NotifyMode.repeat ? intervalMinutes : 0,
    mode == NotifyMode.repeat ? maxNotifications : 0,
    mode == NotifyMode.random ? randomCount : 0,
  );

  @override
  String toString() =>
      'ReminderTime($start${end == null ? '' : '–$end'}, ${mode.name})';
}

const Object _unset = Object();

Map<String, Object?> _map(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();
