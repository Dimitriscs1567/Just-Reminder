import 'dart:math' as math;

import '../core/local_date.dart';
import '../core/seeded_random.dart';
import '../core/stable_hash.dart';
import 'reminder.dart';
import 'schedule.dart';

/// Computes when reminders activate.
///
/// Pure and deterministic: the same reminder id, schedule and date always
/// give the same instants, including random times. All instants are in the
/// device's local time zone, so reminders follow the wall clock (e.g. when
/// travelling).
class ScheduleEngine {
  const ScheduleEngine({this.searchLimitDays = 3700});

  /// How far ahead [upcoming] looks for the next activation. Enough for the
  /// sparsest schedule the editor allows ("every 99 months").
  final int searchLimitDays;

  /// Activations in the half-open interval `(from, to]`, oldest first.
  List<DateTime> between(
    String reminderId,
    Schedule schedule,
    DateTime from,
    DateTime to,
  ) {
    if (!to.isAfter(from)) return const [];
    return upcoming(reminderId, schedule, from, count: 1 << 30, until: to);
  }

  /// Up to [count] activations strictly after [after] (and not later than
  /// [until], when given), oldest first.
  List<DateTime> upcoming(
    String reminderId,
    Schedule schedule,
    DateTime after, {
    int count = 1,
    DateTime? until,
  }) {
    if (count <= 0) return const [];
    final recurrence = schedule.recurrence;
    final afterDate = LocalDate.fromDateTime(after);

    // A window that runs past midnight may have started the day before.
    var date = afterDate.addDays(-1);
    if (date.isBefore(recurrence.firstDate)) date = recurrence.firstDate;

    var lastDate = until == null
        ? afterDate.addDays(searchLimitDays)
        : LocalDate.fromDateTime(until);
    final recurrenceEnd = recurrence.lastDate;
    if (recurrenceEnd != null && recurrenceEnd.isBefore(lastDate)) {
      lastDate = recurrenceEnd;
    }

    final result = <DateTime>[];
    while (!date.isAfter(lastDate) && result.length < count) {
      if (recurrence.occursOn(date)) {
        for (final at in windowActivations(reminderId, schedule.timing, date)) {
          if (at.isAfter(after) && (until == null || !at.isAfter(until))) {
            result.add(at);
          }
        }
      }
      date = date.addDays(1);
    }
    // Windows never overlap, so this is already sorted; keep it robust.
    result.sort();
    return result.length > count ? result.sublist(0, count) : result;
  }

  /// Like [upcoming], for a whole reminder: nothing while it is paused or
  /// archived, and nothing at or before its `activeSince`.
  List<DateTime> upcomingFor(
    Reminder reminder,
    DateTime after, {
    int count = 1,
    DateTime? until,
  }) {
    if (!reminder.isLive) return const [];
    final from = after.isAfter(reminder.activeSince)
        ? after
        : reminder.activeSince;
    return upcoming(
      reminder.id,
      reminder.schedule,
      from,
      count: count,
      until: until,
    );
  }

  /// Whether [reminder]'s schedule can never activate again after [after]
  /// (a past one-time reminder, or a repeating one past its end date).
  /// Paused state is ignored: a paused reminder that could still activate
  /// after being resumed is not finished.
  bool isFinished(Reminder reminder, DateTime after) {
    final from = after.isAfter(reminder.activeSince)
        ? after
        : reminder.activeSince;
    return upcoming(reminder.id, reminder.schedule, from).isEmpty;
  }

  /// Activations of the window that starts on [date], ignoring whether the
  /// recurrence selects that date.
  List<DateTime> windowActivations(
    String reminderId,
    Timing timing,
    LocalDate date,
  ) {
    switch (timing) {
      case FixedTiming(:final time):
        return [date.at(time)];
      case final RangeTiming range:
        final start = date.at(range.start);
        final end = (range.endsNextDay ? date.addDays(1) : date).at(range.end);
        if (!end.isAfter(start)) return const [];
        return switch (range.mode) {
          RangeMode.interval => _intervalActivations(range, start, end),
          RangeMode.random => _randomActivations(
            range,
            start,
            end,
            SeededRandom(stableHash32('$reminderId|${date.toIso()}')),
          ),
        };
    }
  }

  /// From the range start, every interval, up to and including the end,
  /// capped at `maxActivations` when set.
  static List<DateTime> _intervalActivations(
    RangeTiming range,
    DateTime start,
    DateTime end,
  ) {
    final step = Duration(minutes: math.max(1, range.intervalMinutes));
    final cap = range.maxActivations;
    final result = <DateTime>[];
    for (var at = start; !at.isAfter(end); at = at.add(step)) {
      if (cap != null && result.length >= cap) break;
      result.add(at);
    }
    return result;
  }

  /// Exactly N times: the window is split into N equal slots (whole minutes)
  /// and each slot gets one random minute, so times never bunch up.
  static List<DateTime> _randomActivations(
    RangeTiming range,
    DateTime start,
    DateTime end,
    SeededRandom random,
  ) {
    final minutes = end.difference(start).inMinutes;
    final count = math.min(math.max(1, range.maxActivations ?? 1), minutes);
    final result = <DateTime>[];
    for (var i = 0; i < count; i++) {
      final slotStart = i * minutes ~/ count;
      final slotEnd = (i + 1) * minutes ~/ count;
      final offset = slotStart + random.nextInt(slotEnd - slotStart);
      result.add(start.add(Duration(minutes: offset)));
    }
    return result;
  }
}
