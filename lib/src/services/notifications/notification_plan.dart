import 'dart:convert';

import '../../core/local_date.dart';
import '../../core/stable_hash.dart';
import '../../domain/occurrence.dart';
import '../../domain/reminder.dart';
import '../../domain/reminder_runtime.dart';
import '../../domain/runtime_advance.dart';
import '../../domain/schedule_engine.dart';

/// How many notifications may be scheduled ahead, and how far.
class NotificationBudget {
  const NotificationBudget({
    required this.total,
    this.minPerReminder = 3,
    this.horizon = const Duration(days: 14),
  });

  /// iOS keeps at most 64 pending notifications per app.
  static const ios = NotificationBudget(total: 60);

  /// Some Android OEMs cap apps at 500 alarms; stay well below that.
  static const android = NotificationBudget(total: 200);

  final int total;

  /// Every reminder gets at least its next few notifications before the
  /// soonest ones of all reminders fill the rest of the budget.
  final int minPerReminder;
  final Duration horizon;
}

/// Shown when a reminder has no description.
const defaultNotificationBody = 'Tap Done once you’ve done it.';

/// One notification to schedule. A time with repeats or random
/// notifications has several, all for the same [occurrenceStart].
class PlannedNotification {
  const PlannedNotification({
    required this.reminderId,
    required this.at,
    required this.occurrenceStart,
    required this.title,
    required this.body,
    required this.missedBefore,
    this.replacedAfter,
  });

  final String reminderId;
  final DateTime at;

  /// The start of the time it reminds of.
  final DateTime occurrenceStart;

  /// The reminder's display name.
  final String title;
  final String body;

  /// Times of the same day missed by then, if nothing is done meanwhile
  /// (shown as "2 missed").
  final int missedBefore;

  /// Android: dismiss this notification after this long, which is when the
  /// reminder's next notification replaces it.
  final Duration? replacedAfter;

  int get id => notificationIdFor(reminderId, at);

  String? get subtitle => missedBefore == 0 ? null : '$missedBefore missed';

  /// Says which reminder, time and moment it is for and what "N missed" it
  /// shows (`r`, `s`, `t`, `m`; the widget extension reads them too), and
  /// fingerprints the content and how it is scheduled ([exact] alarm or
  /// not), so a change of either reschedules it and unchanged notifications
  /// are left alone. Android drops exact alarms when the permission is
  /// revoked, and keeps inexact ones inexact when it is granted, so the mode
  /// must count as a change.
  String payloadFor({required bool exact}) => jsonEncode({
    'r': reminderId,
    't': at.millisecondsSinceEpoch,
    's': occurrenceStart.millisecondsSinceEpoch,
    'm': missedBefore,
    'h': stableHash32(
      '$title|$body|$missedBefore|${replacedAfter?.inMilliseconds}|'
      '${exact ? 'exact' : 'inexact'}',
    ),
  });
}

/// The notification id of [reminderId]'s notification at [at].
int notificationIdFor(String reminderId, DateTime at) =>
    stableHash31('$reminderId@${at.millisecondsSinceEpoch}');

/// What a notification's payload says.
typedef NotificationPayload = ({
  String reminderId,
  DateTime at,
  DateTime occurrenceStart,
  int missedBefore,
});

/// Decodes a payload of [PlannedNotification.payloadFor], or null. Payloads
/// from before 2026-11-05 (no `s`, `m`) were one notification per time.
NotificationPayload? decodeNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded case {'r': final String id, 't': final int at}) {
      final start = decoded['s'];
      final missed = decoded['m'];
      return (
        reminderId: id,
        at: DateTime.fromMillisecondsSinceEpoch(at),
        occurrenceStart: DateTime.fromMillisecondsSinceEpoch(
          start is int ? start : at,
        ),
        missedBefore: missed is int ? missed : 0,
      );
    }
  } on FormatException {
    // Not one of ours.
  }
  return null;
}

/// The notifications that should be scheduled after [now].
///
/// For every live reminder: the remaining notifications of its due time
/// (none once it is done or missed), then those of its next times. Each
/// reminder first gets up to [NotificationBudget.minPerReminder] of them
/// (round-robin), then the soonest of all reminders fill the budget. Per
/// reminder the chosen ones are always its next ones, without gaps.
List<PlannedNotification> planNotifications({
  required List<Reminder> reminders,
  required Map<String, ReminderRuntime> runtimes,
  required ScheduleEngine engine,
  required DateTime now,
  required NotificationBudget budget,
}) {
  final until = now.add(budget.horizon);
  final candidates = <Reminder, List<_Candidate>>{
    for (final reminder in reminders)
      if (reminder.isLive)
        reminder: _candidates(
          reminder,
          runtimes[reminder.id] ??
              ReminderRuntime.initial(reminder.id, reminder.activeSince),
          engine,
          now,
          until,
          budget.total,
        ),
  };

  final ranked = [
    for (final MapEntry(key: reminder, value: list) in candidates.entries)
      for (var index = 0; index < list.length; index++)
        (reminder: reminder, index: index, at: list[index].at),
  ];
  ranked.sort((a, b) {
    final aGuaranteed = a.index < budget.minPerReminder;
    final bGuaranteed = b.index < budget.minPerReminder;
    if (aGuaranteed != bGuaranteed) return aGuaranteed ? -1 : 1;
    if (aGuaranteed) {
      final byIndex = a.index.compareTo(b.index);
      if (byIndex != 0) return byIndex;
    }
    return a.at.compareTo(b.at);
  });

  final chosen = <Reminder, int>{};
  for (final item in ranked.take(budget.total)) {
    chosen.update(item.reminder, (count) => count + 1, ifAbsent: () => 1);
  }

  final plan = <PlannedNotification>[];
  for (final MapEntry(key: reminder, value: count) in chosen.entries) {
    final list = candidates[reminder]!;
    final description = reminder.description;
    for (var index = 0; index < count; index++) {
      final candidate = list[index];
      plan.add(
        PlannedNotification(
          reminderId: reminder.id,
          at: candidate.at,
          occurrenceStart: candidate.occurrenceStart,
          title: reminder.displayName,
          body: description == null || description.isEmpty
              ? defaultNotificationBody
              : description,
          missedBefore: candidate.missedBefore,
          // Only when the next one is scheduled too, otherwise the reminder
          // would silently vanish from the tray.
          replacedAfter: index + 1 < count
              ? list[index + 1].at.difference(candidate.at)
              : null,
        ),
      );
    }
  }
  plan.sort((a, b) => a.at.compareTo(b.at));
  return plan;
}

/// [reminder]'s notifications in `(now, until]`, at most [max], in order.
List<_Candidate> _candidates(
  Reminder reminder,
  ReminderRuntime stored,
  ScheduleEngine engine,
  DateTime now,
  DateTime until,
  int max,
) {
  final runtime = advanceReminder(
    reminder: reminder,
    runtime: stored,
    engine: engine,
    now: now,
  ).runtime;
  final result = <_Candidate>[];
  // Missed per day so far, assuming every time not done yet will be missed.
  final missed = <LocalDate, int>{};

  void add(Occurrence occurrence) {
    final before = missed[occurrence.date] ?? runtime.missedOn(occurrence.date);
    for (final at in occurrence.notifications
        .skipWhile((at) => !at.isAfter(now))
        .takeWhile((at) => !at.isAfter(until))
        .take(max - result.length)) {
      result.add(_Candidate(at, occurrence.start, before));
    }
    missed[occurrence.date] = before + 1;
  }

  final pending = runtime.pending;
  if (pending != null) {
    add(
      pending.toOccurrence(
        reminder.id,
        nextStart: engine.nextStartAfter(reminder, pending.start),
      ),
    );
  }
  for (final occurrence in engine.upcomingFor(
    reminder,
    now,
    count: max,
    until: until,
  )) {
    if (result.length >= max) break;
    add(occurrence);
  }
  return result;
}

class _Candidate {
  const _Candidate(this.at, this.occurrenceStart, this.missedBefore);

  final DateTime at;
  final DateTime occurrenceStart;
  final int missedBefore;
}
