import 'dart:math' as math;

import '../core/local_date.dart';
import '../core/seeded_random.dart';
import '../core/stable_hash.dart';
import 'schedule.dart';

/// One [ReminderTime] of a reminder on one day — what the user sees as one
/// reminder, done or missed as a whole.
///
/// It becomes due at its first notification and stays due until it is
/// done; it is missed at its [end] or, without an end, when the reminder's
/// next time starts ([nextStart]).
class Occurrence {
  const Occurrence({
    required this.reminderId,
    required this.date,
    required this.time,
    required this.start,
    this.end,
    this.nextStart,
  });

  final String reminderId;

  /// The day it belongs to; a time that runs past midnight still belongs to
  /// the day it started on.
  final LocalDate date;

  /// Its settings (start, end, how it notifies).
  final ReminderTime time;

  final DateTime start;

  /// When it ends, if the time has an end.
  final DateTime? end;

  /// When the reminder's next time starts; `null` when no time follows.
  final DateTime? nextStart;

  /// When it counts as missed unless done: its end, or else when the next
  /// time starts. `null`: never — it stays due until done.
  DateTime? get missesAt => end ?? nextStart;

  /// When it becomes due: its first notification.
  DateTime get dueAt => notifications.first;

  /// When it notifies, oldest first. Repeating without an end, a next time
  /// or a limit, this never ends, so take what you need.
  ///
  /// - [NotifyMode.once]: the start.
  /// - [NotifyMode.repeat]: from the start every interval, before the end
  ///   (it is missed at the end, so a notification then could no longer be
  ///   done) or until the next time starts, at most `maxNotifications`
  ///   times.
  /// - [NotifyMode.random]: exactly `randomCount` whole minutes in
  ///   `[start, end)`, one in each equal part, the same every time they are
  ///   computed (seeded with the reminder, date and start time).
  ///
  /// Nothing is sent at or after [nextStart]: back-to-back times don't
  /// notify twice at the same moment.
  Iterable<DateTime> get notifications sync* {
    final end = this.end;
    final next = nextStart;
    switch (time.mode) {
      case NotifyMode.once:
        yield start;
      case NotifyMode.repeat:
        final step = Duration(minutes: math.max(1, time.intervalMinutes));
        final cap = time.maxNotifications;
        var count = 0;
        for (var at = start; ; at = at.add(step)) {
          // The first notification always comes, even for invalid data.
          if (count > 0) {
            if (cap != null && count >= cap) return;
            if (end != null && !at.isBefore(end)) return;
            if (next != null && !at.isBefore(next)) return;
          }
          yield at;
          count++;
        }
      case NotifyMode.random:
        if (end == null || !end.isAfter(start)) {
          yield start;
          return;
        }
        final minutes = end.difference(start).inMinutes;
        final count = math.max(1, math.min(time.randomCount, minutes));
        final random = SeededRandom(
          stableHash32('$reminderId|${date.toIso()}|${time.start.toIso()}'),
        );
        for (var i = 0; i < count; i++) {
          final slotStart = i * minutes ~/ count;
          final slotEnd = (i + 1) * minutes ~/ count;
          final offset = slotStart + random.nextInt(slotEnd - slotStart);
          yield start.add(Duration(minutes: offset));
        }
    }
  }

  /// The same occurrence ending its notifications when [nextStart] comes.
  Occurrence withNextStart(DateTime? nextStart) => Occurrence(
    reminderId: reminderId,
    date: date,
    time: time,
    start: start,
    end: end,
    nextStart: nextStart,
  );

  @override
  bool operator ==(Object other) =>
      other is Occurrence &&
      other.reminderId == reminderId &&
      other.date == date &&
      other.time == time &&
      other.start == start &&
      other.end == end &&
      other.nextStart == nextStart;

  @override
  int get hashCode =>
      Object.hash(reminderId, date, time, start, end, nextStart);

  @override
  String toString() =>
      'Occurrence($reminderId, $start${end == null ? '' : '–$end'}, '
      'next: $nextStart)';
}
