import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';

import '../core/app_constants.dart';
import '../domain/schedule_engine.dart';
import '../services/ack_inbox.dart';
import '../services/notifications/notification_plan.dart';
import '../services/notifications/notification_service.dart';
import '../services/widget/widget_bridge.dart';
import '../services/widget/widget_snapshot.dart';

// Entry points that run in background isolates: a tap on the Android
// widget's thumbs down, and the notification's Acknowledge button. They must
// never open the database (sembast is main-isolate only); they log the
// acknowledgment for the app's next sync and update widget + notifications
// right away.

/// home_widget interactivity callback (Android widget taps).
@pragma('vm:entry-point')
Future<void> widgetInteractionCallback(Uri? uri) async {
  final reminderId = reminderToAcknowledge(uri);
  if (reminderId != null) await acknowledgeInBackground(reminderId);
}

/// flutter_local_notifications background response (Acknowledge button).
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  if (response.actionId != NotificationService.acknowledgeActionId) return;
  final reminderId = decodeNotificationPayload(response.payload)?.reminderId;
  if (reminderId != null) await acknowledgeInBackground(reminderId);
}

/// The reminder a widget URI asks to acknowledge:
/// `justreminder://acknowledge?id=<reminder id>`.
String? reminderToAcknowledge(Uri? uri) {
  if (uri == null || uri.host != 'acknowledge') return null;
  final id = uri.queryParameters['id'];
  return id == null || id.isEmpty ? null : id;
}

/// Acknowledges [reminderId] without the database.
Future<void> acknowledgeInBackground(String reminderId) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await HomeWidget.setAppGroupId(iosAppGroupId);
  final now = DateTime.now();

  // 1. Log it; the app applies it to the history on its next sync.
  await const HomeWidgetAckInbox().add(reminderId, now);

  // 2. Flip the widget to thumbs up now.
  const widgets = WidgetBridge();
  final snapshot = await widgets.readSnapshot(reminderId);
  if (snapshot != null && widgetStatusAt(snapshot, now).isWaiting) {
    await widgets.writeSnapshot(
      reminderId,
      acknowledgedWidgetSnapshot(
        snapshot,
        at: now,
        engine: const ScheduleEngine(),
      ),
    );
    await widgets.updateWidgets();
  }

  // 3. Clear the tray and re-number the upcoming "N missed" texts.
  final notifications = NotificationService(FlutterLocalNotificationsPlugin());
  await notifications.initialize(
    onBackgroundResponse: notificationBackgroundHandler,
  );
  await notifications.scheduler.clearDelivered(reminderId);
  await notifications.scheduler.renumberAfterAcknowledgment(
    reminderId,
    now: now,
    exact: await notifications.canScheduleExact(),
  );
}
