import '../core/local_date.dart';
import 'occurrence.dart';
import 'reminder.dart';
import 'reminder_runtime.dart';
import 'schedule.dart';

/// Computes when reminders remind.
///
/// Pure and deterministic: the same reminder id, schedule and date always
/// give the same occurrences and notification times, random ones included.
/// All instants are in the device's local time zone, so reminders follow
/// the wall clock (e.g. when travelling).
class ScheduleEngine {
  const ScheduleEngine({this.searchLimitDays = 3700});

  /// How far ahead the engine looks for the next occurrence. Enough for the
  /// sparsest schedule the editor allows ("every 99 months").
  final int searchLimitDays;

  /// Occurrences that become due in the half-open interval `(from, to]`,
  /// oldest first.
  List<Occurrence> dueBetween(
    String reminderId,
    Schedule schedule,
    DateTime from,
    DateTime to,
  ) {
    if (!to.isAfter(from)) return const [];
    return upcoming(reminderId, schedule, from, count: 1 << 30, until: to);
  }

  /// Up to [count] occurrences that become due strictly after [after] (and
  /// not after [until], when given), oldest first.
  List<Occurrence> upcoming(
    String reminderId,
    Schedule schedule,
    DateTime after, {
    int count = 1,
    DateTime? until,
  }) {
    if (count <= 0) return const [];
    final result = <Occurrence>[];
    // A time that runs past midnight may have started the day before.
    for (final occurrence in occurrencesFrom(
      reminderId,
      schedule,
      LocalDate.fromDateTime(after).addDays(-1),
    )) {
      if (until != null && occurrence.start.isAfter(until)) break;
      final due = occurrence.dueAt;
      if (!due.isAfter(after) || (until != null && due.isAfter(until))) {
        continue;
      }
      result.add(occurrence);
      if (result.length >= count) break;
    }
    // Times never overlap, so this is already sorted; keep it robust.
    return result..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  /// Like [upcoming], for a whole reminder: nothing while it is paused or
  /// archived, and nothing due at or before its `activeSince`.
  List<Occurrence> upcomingFor(
    Reminder reminder,
    DateTime after, {
    int count = 1,
    DateTime? until,
  }) {
    if (!reminder.isLive) return const [];
    return upcoming(
      reminder.id,
      reminder.schedule,
      _later(after, reminder.activeSince),
      count: count,
      until: until,
    );
  }

  /// Whether [reminder] can never become due again after [after] (a past
  /// one-time reminder, or a repeating one past its end date). Paused state
  /// is ignored: a paused reminder that could still remind after being
  /// resumed is not finished.
  bool isFinished(Reminder reminder, DateTime after) => upcoming(
    reminder.id,
    reminder.schedule,
    _later(after, reminder.activeSince),
  ).isEmpty;

  /// When [pending] counts as missed unless it is done: at its end, or else
  /// when [reminder]'s next time starts. `null`: it stays due until done.
  DateTime? missesAt(Reminder reminder, PendingOccurrence pending) =>
      pending.end ?? nextStartAfter(reminder, pending.start);

  /// The start of [reminder]'s first time after [start] that will really
  /// come (it becomes due after `activeSince`); `null` while the reminder is
  /// paused or archived, or when no time follows.
  DateTime? nextStartAfter(Reminder reminder, DateTime start) {
    if (!reminder.isLive) return null;
    for (final occurrence in occurrencesFrom(
      reminder.id,
      reminder.schedule,
      LocalDate.fromDateTime(start).addDays(-1),
    )) {
      if (!occurrence.start.isAfter(start)) continue;
      if (!occurrence.dueAt.isAfter(reminder.activeSince)) continue;
      return occurrence.start;
    }
    return null;
  }

  /// Every occurrence of [schedule] from [fromDate] on, in start order, each
  /// knowing when the next one starts. It ends with the recurrence, or
  /// [searchLimitDays] after [fromDate].
  Iterable<Occurrence> occurrencesFrom(
    String reminderId,
    Schedule schedule,
    LocalDate fromDate,
  ) sync* {
    Occurrence? previous;
    for (final occurrence in _slots(reminderId, schedule, fromDate)) {
      if (previous != null) yield previous.withNextStart(occurrence.start);
      previous = occurrence;
    }
    if (previous != null) yield previous;
  }

  /// The occurrences without their next start.
  Iterable<Occurrence> _slots(
    String reminderId,
    Schedule schedule,
    LocalDate fromDate,
  ) sync* {
    final recurrence = schedule.recurrence;
    final times = schedule.orderedTimes;
    if (times.isEmpty) return;
    var date = fromDate.isBefore(recurrence.firstDate)
        ? recurrence.firstDate
        : fromDate;
    var last = date.addDays(searchLimitDays);
    final recurrenceEnd = recurrence.lastDate;
    if (recurrenceEnd != null && recurrenceEnd.isBefore(last)) {
      last = recurrenceEnd;
    }
    while (!date.isAfter(last)) {
      if (recurrence.occursOn(date)) {
        for (final time in times) {
          final end = time.end;
          yield Occurrence(
            reminderId: reminderId,
            date: date,
            time: time,
            start: date.at(time.start),
            end: end == null
                ? null
                : (time.endsNextDay ? date.addDays(1) : date).at(end),
          );
        }
      }
      date = date.addDays(1);
    }
  }

  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
}
