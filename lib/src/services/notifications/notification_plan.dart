import 'dart:convert';

import '../../core/stable_hash.dart';
import '../../domain/reminder.dart';
import '../../domain/reminder_runtime.dart';
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

  /// Every reminder gets at least its next few before the soonest
  /// activations of all reminders fill the rest of the budget.
  final int minPerReminder;
  final Duration horizon;
}

/// Shown when a reminder has no description.
const defaultNotificationBody = 'Tap Acknowledge once you’ve done it.';

/// One notification to schedule for one activation.
class PlannedNotification {
  const PlannedNotification({
    required this.reminderId,
    required this.at,
    required this.title,
    required this.body,
    required this.missedBefore,
    this.replacedAfter,
  });

  final String reminderId;
  final DateTime at;

  /// The reminder's display name.
  final String title;
  final String body;

  /// Activations that will have been missed before this one, if nothing is
  /// acknowledged meanwhile (shown as "2 missed").
  final int missedBefore;

  /// Android: dismiss this notification after this long, which is when the
  /// reminder's next notification (carrying the missed count) replaces it.
  final Duration? replacedAfter;

  int get id => notificationIdFor(reminderId, at);

  String? get subtitle => missedBefore == 0 ? null : '$missedBefore missed';

  /// Identifies the activation and fingerprints the content and how it is
  /// scheduled ([exact] alarm or not), so a change of either reschedules it
  /// and unchanged notifications are left alone. Android drops exact alarms
  /// when the permission is revoked, and keeps inexact ones inexact when it
  /// is granted, so the mode must count as a change.
  String payloadFor({required bool exact}) => jsonEncode({
    'r': reminderId,
    't': at.millisecondsSinceEpoch,
    'h': stableHash32(
      '$title|$body|$missedBefore|${replacedAfter?.inMilliseconds}|'
      '${exact ? 'exact' : 'inexact'}',
    ),
  });
}

/// The notification id of [reminderId]'s activation at [at].
int notificationIdFor(String reminderId, DateTime at) =>
    stableHash31('$reminderId@${at.millisecondsSinceEpoch}');

/// The reminder and activation a payload belongs to, or null.
({String reminderId, DateTime at})? decodeNotificationPayload(
  String? payload,
) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded case {'r': final String id, 't': final int at}) {
      return (reminderId: id, at: DateTime.fromMillisecondsSinceEpoch(at));
    }
  } on FormatException {
    // Not one of ours.
  }
  return null;
}

/// The notifications that should be scheduled after [now].
///
/// Each live reminder first gets up to [NotificationBudget.minPerReminder]
/// of its next activations (round-robin), then the soonest activations of
/// all reminders fill the budget. Per reminder the chosen activations are
/// always its next ones, without gaps.
List<PlannedNotification> planNotifications({
  required List<Reminder> reminders,
  required Map<String, ReminderRuntime> runtimes,
  required ScheduleEngine engine,
  required DateTime now,
  required NotificationBudget budget,
}) {
  final until = now.add(budget.horizon);
  final upcoming = <Reminder, List<DateTime>>{
    for (final reminder in reminders)
      if (reminder.isLive)
        reminder: engine.upcomingFor(
          reminder,
          now,
          count: budget.total,
          until: until,
        ),
  };

  final candidates = [
    for (final MapEntry(key: reminder, value: times) in upcoming.entries)
      for (var index = 0; index < times.length; index++)
        (reminder: reminder, index: index, at: times[index]),
  ];
  candidates.sort((a, b) {
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
  for (final candidate in candidates.take(budget.total)) {
    chosen.update(candidate.reminder, (count) => count + 1, ifAbsent: () => 1);
  }

  final plan = <PlannedNotification>[];
  for (final MapEntry(key: reminder, value: count) in chosen.entries) {
    final times = upcoming[reminder]!;
    final runtime = runtimes[reminder.id];
    final waiting = runtime?.pendingAt != null;
    final base = waiting ? 1 + runtime!.missedCount : 0;
    final description = reminder.description;
    for (var index = 0; index < count; index++) {
      plan.add(
        PlannedNotification(
          reminderId: reminder.id,
          at: times[index],
          title: reminder.displayName,
          body: description == null || description.isEmpty
              ? defaultNotificationBody
              : description,
          missedBefore: base + index,
          // Only when the next one is scheduled too, otherwise the reminder
          // would silently vanish from the tray.
          replacedAfter: index + 1 < count
              ? times[index + 1].difference(times[index])
              : null,
        ),
      );
    }
  }
  plan.sort((a, b) => a.at.compareTo(b.at));
  return plan;
}
