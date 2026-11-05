import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/local_date.dart';
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
  /// running late) is kept while its time is still the reminder's due one
  /// ([dueStarts]: reminder id → start of its due time), so it is not lost.
  Future<void> apply(
    List<PlannedNotification> plan, {
    required DateTime now,
    required Map<String, DateTime> dueStarts,
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
          dueStarts[scheduled.reminderId] == scheduled.occurrenceStart) {
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

  /// Removes shown notifications of every reminder that has nothing due any
  /// more (done, missed, archived, deleted).
  Future<void> clearDeliveredExcept(Set<String> dueReminderIds) async {
    for (final notification in await _gateway.active()) {
      final reminderId = _reminderIdOf(notification);
      final id = notification.id;
      if (reminderId != null &&
          id != null &&
          !dueReminderIds.contains(reminderId)) {
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

  /// After [reminderId]'s time that started at [occurrenceStart] was marked
  /// done outside the app (widget, notification button): its remaining
  /// notifications are cancelled, and the later times of the same day no
  /// longer count it as missed, so their "N missed" goes down by one.
  Future<void> afterDoneOutsideApp(
    String reminderId, {
    required DateTime occurrenceStart,
    required DateTime now,
    required bool exact,
  }) async {
    final day = LocalDate.fromDateTime(occurrenceStart);
    final kept = <({PendingNotificationRequest request, NotificationPayload payload})>[];
    for (final request in await _gateway.pending()) {
      final payload = decodeNotificationPayload(request.payload);
      if (payload == null || payload.reminderId != reminderId) continue;
      if (payload.occurrenceStart == occurrenceStart) {
        await _gateway.cancel(request.id, tag: reminderId);
      } else if (payload.at.isAfter(now)) {
        kept.add((request: request, payload: payload));
      }
    }
    kept.sort((a, b) => a.payload.at.compareTo(b.payload.at));

    for (var index = 0; index < kept.length; index++) {
      final (:request, :payload) = kept[index];
      final sameDayLater =
          payload.occurrenceStart.isAfter(occurrenceStart) &&
          LocalDate.fromDateTime(payload.occurrenceStart) == day;
      final renumbered = PlannedNotification(
        reminderId: reminderId,
        at: payload.at,
        occurrenceStart: payload.occurrenceStart,
        title: request.title ?? '',
        body: request.body ?? defaultNotificationBody,
        missedBefore: sameDayLater && payload.missedBefore > 0
            ? payload.missedBefore - 1
            : payload.missedBefore,
        replacedAfter: index + 1 < kept.length
            ? kept[index + 1].payload.at.difference(payload.at)
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
