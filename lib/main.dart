import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/background/background_handlers.dart';
import 'src/core/app_constants.dart';
import 'src/data/app_database.dart';
import 'src/services/app_events.dart';
import 'src/services/notifications/notification_plan.dart';
import 'src/services/notifications/notification_service.dart';
import 'src/state/providers.dart';
import 'src/ui/screens/widget_config/widget_configuration_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS: widget data lives in the App Group shared with the widget.
  await HomeWidget.setAppGroupId(iosAppGroupId);

  final events = AppEvents();
  final notifications = NotificationService(FlutterLocalNotificationsPlugin());
  await notifications.initialize(
    onBackgroundResponse: notificationBackgroundHandler,
    onResponse: (response) {
      final reminderId = decodeNotificationPayload(
        response.payload,
      )?.reminderId;
      if (reminderId == null) return;
      events.add(
        response.actionId == NotificationService.acknowledgeActionId
            ? AcknowledgeReminder(reminderId)
            : OpenReminder(reminderId),
      );
    },
  );
  // Android widget taps (thumbs down) run Dart in the background. Android
  // only: the iOS widget acknowledges in Swift, and home_widget throws on
  // iOS < 17 (and starts an unused engine on iOS 17+).
  if (defaultTargetPlatform == TargetPlatform.android) {
    await HomeWidget.registerInteractivityCallback(widgetInteractionCallback);
  }

  final launchedFor = await notifications.launchReminderId();
  events.launchEvent = launchedFor != null
      ? OpenReminder(launchedFor)
      : appEventForWidgetUri(await HomeWidget.initiallyLaunchedFromHomeWidget());
  HomeWidget.widgetClicked.listen((uri) {
    if (appEventForWidgetUri(uri) case final event?) events.add(event);
  });

  final database = await openAppDatabase();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        notificationServiceProvider.overrideWithValue(notifications),
        appEventsProvider.overrideWithValue(events),
      ],
      child: const JustReminderApp(),
    ),
  );
}

/// Android: entry point of `WidgetConfigurationActivity`, which the
/// launcher opens to pick the reminder a new widget shows. It only reads
/// widget storage; the database stays with the main app.
@pragma('vm:entry-point')
Future<void> widgetConfigurationMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appWidgetId = int.tryParse(
    await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure() ?? '',
  );
  if (appWidgetId == null) return main();
  runApp(WidgetConfigurationApp(appWidgetId: appWidgetId));
}
