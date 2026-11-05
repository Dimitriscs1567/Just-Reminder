import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../core/local_date.dart';
import '../core/local_time.dart';
import '../domain/schedule.dart';

/// ISO weekday (1–7) → short English name.
const weekdayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// ISO weekday (1–7) → full English name.
const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Formats times in the device's 12- or 24-hour style.
class TimeFormatter {
  const TimeFormatter({required this.use24Hour});

  factory TimeFormatter.of(BuildContext context) =>
      TimeFormatter(use24Hour: MediaQuery.alwaysUse24HourFormatOf(context));

  final bool use24Hour;

  String time(LocalTime time) =>
      instant(DateTime(2000, 1, 1, time.hour, time.minute));

  String instant(DateTime at) =>
      (use24Hour ? DateFormat.Hm() : DateFormat.jm()).format(at);
}

/// "Today", "Tomorrow", "Yesterday", "Wed, Nov 4" or, in another year,
/// "Wed, Nov 4, 2027".
String formatDay(LocalDate day, LocalDate today) {
  switch (today.daysUntil(day)) {
    case 0:
      return 'Today';
    case 1:
      return 'Tomorrow';
    case -1:
      return 'Yesterday';
  }
  final date = DateTime(day.year, day.month, day.day);
  return day.year == today.year
      ? DateFormat.MMMEd().format(date)
      : DateFormat.yMMMEd().format(date);
}

/// A full date such as "Wed, Nov 4, 2026".
String formatDate(LocalDate date) =>
    DateFormat.yMMMEd().format(DateTime(date.year, date.month, date.day));

/// "Today · 14:30", "Wed, Nov 4 · 9:00 AM", …
String formatMoment(DateTime at, DateTime now, TimeFormatter formatter) =>
    '${formatDay(LocalDate.fromDateTime(at), LocalDate.fromDateTime(now))}'
    ' · ${formatter.instant(at)}';

/// Like [formatMoment], but just the time when [at] is today: "14:30",
/// "Tomorrow · 8:30 AM".
String formatCompactMoment(
  DateTime at,
  DateTime now,
  TimeFormatter formatter,
) => LocalDate.fromDateTime(at) == LocalDate.fromDateTime(now)
    ? formatter.instant(at)
    : formatMoment(at, now, formatter);

/// For inside a sentence ("next …"): "16:00", "tomorrow 09:00",
/// "Tue, Nov 10, 09:00".
String formatInlineMoment(
  DateTime at,
  DateTime now,
  TimeFormatter formatter,
) {
  final day = LocalDate.fromDateTime(at);
  final today = LocalDate.fromDateTime(now);
  final time = formatter.instant(at);
  return switch (today.daysUntil(day)) {
    0 => time,
    1 => 'tomorrow $time',
    -1 => 'yesterday $time',
    _ => '${formatDay(day, today)}, $time',
  };
}

/// 1st, 2nd, 3rd, 4th, 11th, 21st, …
String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// "15 min", "1 h", "1 h 30 min".
String formatInterval(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

/// "Every weekday", "Every 2 weeks on Mon, Sat", "Monthly on the 15th", …
String describeRecurrence(Recurrence recurrence, {required LocalDate today}) {
  switch (recurrence) {
    case OnceRecurrence(:final date):
      return 'Once · ${formatDay(date, today)}';
    case final RepeatRecurrence repeat:
      final every = repeat.every;
      switch (repeat.unit) {
        case RepeatUnit.day:
          return every == 1 ? 'Every day' : 'Every $every days';
        case RepeatUnit.week:
          final days = repeat.weekdays.toList()..sort();
          final isWeekdays = _sameDays(days, const [1, 2, 3, 4, 5]);
          final isWeekend = _sameDays(days, const [6, 7]);
          final isDaily = days.length == 7;
          if (every == 1) {
            if (isWeekdays) return 'Every weekday';
            if (isWeekend) return 'Every weekend';
            if (isDaily) return 'Every day';
            return 'Every ${_dayList(days)}';
          }
          final which = isWeekdays
              ? 'weekdays'
              : isWeekend
              ? 'weekends'
              : isDaily
              ? 'every day'
              : _dayList(days);
          return 'Every $every weeks on $which';
        case RepeatUnit.month:
          final day = ordinal(repeat.dayOfMonth);
          final lastDayNote = repeat.dayOfMonth >= 29 ? ' (or last day)' : '';
          return every == 1
              ? 'Monthly on the $day$lastDayNote'
              : 'Every $every months on the $day$lastDayNote';
      }
  }
}

/// A time's span: "09:00", or "09:00 – 12:00" when it has an end.
String formatTimeSpan(ReminderTime time, TimeFormatter formatter) {
  final end = time.end;
  return end == null
      ? formatter.time(time.start)
      : '${formatter.time(time.start)} – ${formatter.time(end)}';
}

/// The same for one day's occurrence of a time: "09:00 – 12:00".
String formatOccurrenceSpan(
  DateTime start,
  DateTime? end,
  TimeFormatter formatter,
) => end == null
    ? formatter.instant(start)
    : '${formatter.instant(start)} – ${formatter.instant(end)}';

/// How a time notifies: "once", "every 30 min", "every hour, max 3",
/// "3 at random".
String describeNotify(ReminderTime time) {
  switch (time.mode) {
    case NotifyMode.once:
      return 'once';
    case NotifyMode.repeat:
      final every = time.intervalMinutes == 60
          ? 'every hour'
          : 'every ${formatInterval(time.intervalMinutes)}';
      final max = time.maxNotifications;
      return max == null ? every : '$every, max $max';
    case NotifyMode.random:
      return '${time.randomCount} at random';
  }
}

/// A time with how it notifies: "09:00 – 12:00 · every 30 min".
String describeTime(ReminderTime time, TimeFormatter formatter) =>
    '${formatTimeSpan(time, formatter)} · ${describeNotify(time)}';

/// One-line summary: "Every weekday · 09:00, 12:00 – 13:00". With
/// [includeOnceDate] false a one-time reminder is just "Once · 09:00"
/// (for places that show the date elsewhere).
String describeSchedule(
  Schedule schedule,
  TimeFormatter formatter, {
  required LocalDate today,
  bool includeOnceDate = true,
}) {
  final recurrence = schedule.recurrence;
  final when = recurrence is OnceRecurrence && !includeOnceDate
      ? 'Once'
      : describeRecurrence(recurrence, today: today);
  final times = [
    for (final time in schedule.orderedTimes) formatTimeSpan(time, formatter),
  ].join(', ');
  return '$when · $times';
}

bool _sameDays(List<int> a, List<int> b) =>
    a.length == b.length && a.every(b.contains);

String _dayList(List<int> days) =>
    days.map((day) => weekdayShortNames[day - 1]).join(', ');
