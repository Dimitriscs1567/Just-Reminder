import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_plan.dart';

/// The notification operations the scheduler needs; implemented with the
/// plugin in the app and with a fake in tests.
abstract interface class NotificationGateway {
  /// Scheduled notifications that have not been shown yet.
  Future<List<PendingNotificationRequest>> pending();

  /// Notifications currently shown in the tray.
  Future<List<ActiveNotification>> active();

  /// Schedules [notification]; one with the same id is replaced.
  Future<void> schedule(PlannedNotification notification, {required bool exact});

  /// Cancels a pending notification or removes a shown one.
  Future<void> cancel(int id, {String? tag});
}

/// Keeps the scheduled and shown notifications in line with the data.
class NotificationScheduler {
  NotificationScheduler(this._gateway);

  final NotificationGateway _gateway;

  /// Makes the pending notifications match [plan]: unchanged ones stay,
  /// changed or missing ones are (re)scheduled, others are cancelled.
  ///
  /// A pending notification whose time has passed (an inexact alarm that is
  /// running late) is kept while its activation is the reminder's waiting
  /// one ([waitingSince]), so a late notification is not lost.
  Future<void> apply(
    List<PlannedNotification> plan, {
    required DateTime now,
    required Map<String, DateTime> waitingSince,
    required bool exact,
  }) async {
    final desired = {for (final notification in plan) notification.id: notification};
    final unchanged = <int>{};
    for (final request in await _gateway.pending()) {
      final wanted = desired[request.id];
      if (wanted != null && wanted.payloadFor(exact: exact) == request.payload) {
        unchanged.add(request.id);
        continue;
      }
      final scheduled = decodeNotificationPayload(request.payload);
      if (scheduled != null &&
          !scheduled.at.isAfter(now) &&
          waitingSince[scheduled.reminderId] == scheduled.at) {
        continue;
      }
      await _gateway.cancel(request.id, tag: scheduled?.reminderId);
    }
    for (final notification in plan) {
      if (!unchanged.contains(notification.id)) {
        await _gateway.schedule(notification, exact: exact);
      }
    }
  }

  /// Removes shown notifications of every reminder that is not waiting any
  /// more (acknowledged, archived, deleted).
  Future<void> clearDeliveredExcept(Set<String> waitingReminderIds) async {
    for (final notification in await _gateway.active()) {
      final reminderId = _reminderIdOf(notification);
      final id = notification.id;
      if (reminderId != null &&
          id != null &&
          !waitingReminderIds.contains(reminderId)) {
        await _gateway.cancel(id, tag: notification.tag);
      }
    }
  }

  /// Removes the shown notifications of [reminderId].
  Future<void> clearDelivered(String reminderId) async {
    for (final notification in await _gateway.active()) {
      final id = notification.id;
      if (id != null && _reminderIdOf(notification) == reminderId) {
        await _gateway.cancel(id, tag: notification.tag);
      }
    }
  }

  /// After [reminderId] was acknowledged outside the app: its upcoming
  /// notifications no longer count earlier missed activations, so they are
  /// re-numbered 0, 1, 2… missed.
  Future<void> renumberAfterAcknowledgment(
    String reminderId, {
    required DateTime now,
    required bool exact,
  }) async {
    final mine = [
      for (final request in await _gateway.pending())
        if (decodeNotificationPayload(request.payload) case final scheduled?
            when scheduled.reminderId == reminderId &&
                scheduled.at.isAfter(now))
          (request: request, at: scheduled.at),
    ]..sort((a, b) => a.at.compareTo(b.at));

    for (var index = 0; index < mine.length; index++) {
      final (:request, :at) = mine[index];
      final renumbered = PlannedNotification(
        reminderId: reminderId,
        at: at,
        title: request.title ?? '',
        body: request.body ?? defaultNotificationBody,
        missedBefore: index,
        replacedAfter: index + 1 < mine.length
            ? mine[index + 1].at.difference(at)
            : null,
      );
      if (renumbered.payloadFor(exact: exact) != request.payload) {
        await _gateway.schedule(renumbered, exact: exact);
      }
    }
  }

  static String? _reminderIdOf(ActiveNotification notification) =>
      decodeNotificationPayload(notification.payload)?.reminderId ??
      notification.tag ??
      notification.groupKey;
}
