import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/services/notifications/notification_plan.dart';
import 'package:just_reminder/src/services/notifications/notification_service.dart';

void main() {
  PlannedNotification planned({int missed = 0, Duration? replacedAfter}) =>
      PlannedNotification(
        reminderId: 'water',
        at: DateTime(2026, 11, 4, 9),
        title: 'Water',
        body: 'A full glass.',
        missedBefore: missed,
        replacedAfter: replacedAfter,
      );

  test('Android: Acknowledge button, grouped by reminder, "N missed"', () {
    final android = notificationDetailsFor(
      planned(missed: 2, replacedAfter: const Duration(hours: 1)),
    ).android!;
    expect(android.channelId, 'reminders');
    expect(android.importance, Importance.high);
    expect(android.tag, 'water');
    expect(android.subText, '2 missed');
    // Replaced by the reminder's next notification.
    expect(android.timeoutAfter, const Duration(hours: 1).inMilliseconds);

    final action = android.actions!.single;
    expect(action.id, NotificationService.acknowledgeActionId);
    expect(action.title, 'Acknowledge');
    // Acknowledging happens in the background, without opening the app.
    expect(action.showsUserInterface, isFalse);
  });

  test('iOS: Acknowledge category, one thread per reminder, "N missed"', () {
    final ios = notificationDetailsFor(planned(missed: 2)).iOS!;
    expect(ios.categoryIdentifier, 'reminder');
    expect(ios.threadIdentifier, 'water');
    expect(ios.subtitle, '2 missed');
  });

  test('without missed ones there is no missed line, and the last one stays', () {
    final details = notificationDetailsFor(planned());
    expect(details.android!.subText, isNull);
    expect(details.android!.timeoutAfter, isNull);
    expect(details.iOS!.subtitle, isNull);
  });
}
