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

// Entry points that run in background isolates: a tap on an Android
// widget's thumbs-up, and the notification's Done button. They must never open
// the database (sembast is main-isolate only); they log the Done mark for
// the app's next sync and update widget + notifications right away.

/// home_widget interactivity callback (Android widget taps on the
/// thumbs-up, in either widget).
@pragma('vm:entry-point')
Future<void> widgetInteractionCallback(Uri? uri) async {
  final reminderId = reminderToMarkDone(uri);
  if (reminderId != null) await markDoneInBackground(reminderId);
}

/// flutter_local_notifications background response (Done button).
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  if (response.actionId != NotificationService.doneActionId) return;
  final reminderId = decodeNotificationPayload(response.payload)?.reminderId;
  if (reminderId != null) await markDoneInBackground(reminderId);
}

/// The reminder a widget URI asks to mark done:
/// `justreminder://acknowledge?id=<reminder id>` (the host predates the
/// "Done" wording).
String? reminderToMarkDone(Uri? uri) {
  if (uri == null || uri.host != 'acknowledge') return null;
  final id = uri.queryParameters['id'];
  return id == null || id.isEmpty ? null : id;
}

/// Marks [reminderId]'s due time done without the database.
Future<void> markDoneInBackground(String reminderId) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await HomeWidget.setAppGroupId(iosAppGroupId);
  final now = DateTime.now();

  // 1. Log it; the app applies it to the history on its next sync.
  await const HomeWidgetAckInbox().add(reminderId, now);

  // 2. Update the widget now.
  const widgets = WidgetBridge();
  final snapshot = await widgets.readSnapshot(reminderId);
  final doneStart = snapshot == null
      ? null
      : dueOccurrenceStartAt(snapshot, now);
  if (snapshot != null && widgetStatusAt(snapshot, now).isFiring) {
    await widgets.writeSnapshot(
      reminderId,
      doneWidgetSnapshot(snapshot, at: now, engine: const ScheduleEngine()),
    );
    await widgets.updateWidgets();
  }

  // 3. Clear the tray, stop the time's remaining notifications and lower
  //    "N missed" on the day's later ones.
  final notifications = NotificationService(FlutterLocalNotificationsPlugin());
  await notifications.initialize(
    onBackgroundResponse: notificationBackgroundHandler,
  );
  await notifications.scheduler.clearDelivered(reminderId);
  if (doneStart != null) {
    await notifications.scheduler.afterDoneOutsideApp(
      reminderId,
      occurrenceStart: doneStart,
      now: now,
      exact: await notifications.canScheduleExact(),
    );
  }
}
