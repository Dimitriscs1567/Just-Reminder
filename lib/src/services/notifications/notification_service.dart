import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_plan.dart';
import 'notification_scheduler.dart';

/// What the user allowed.
class NotificationPermissions {
  const NotificationPermissions({
    required this.enabled,
    required this.exactAlarms,
  });

  /// Notifications may be shown.
  final bool enabled;

  /// Android 12+: notifications can fire at the exact minute. Without it,
  /// Android may deliver them a few minutes late. Always true on iOS.
  final bool exactAlarms;
}

/// Wraps flutter_local_notifications for the app and background isolates.
class NotificationService {
  NotificationService(this._plugin)
    : scheduler = NotificationScheduler(_PluginGateway(_plugin));

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationScheduler scheduler;

  /// The Done button. Its id predates the "Done" wording; it stays, so
  /// notifications scheduled by older versions keep working.
  static const doneActionId = 'acknowledge';
  static const _iosCategoryId = 'reminder';
  static const _androidIcon = 'ic_stat_reminder';

  /// Must run in every isolate before use, always with the same background
  /// handler, so the stored handler is never cleared.
  Future<void> initialize({
    required DidReceiveBackgroundNotificationResponseCallback
    onBackgroundResponse,
    DidReceiveNotificationResponseCallback? onResponse,
  }) => _plugin.initialize(
    settings: InitializationSettings(
      android: const AndroidInitializationSettings(_androidIcon),
      iOS: DarwinInitializationSettings(
        // Permission is requested from the UI, at a moment that makes sense.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            _iosCategoryId,
            actions: [
              DarwinNotificationAction.plain(
                doneActionId,
                'Done',
              ),
            ],
          ),
        ],
      ),
    ),
    onDidReceiveNotificationResponse: onResponse,
    onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
  );

  NotificationBudget get budget => defaultTargetPlatform == TargetPlatform.iOS
      ? NotificationBudget.ios
      : NotificationBudget.android;

  /// The reminder whose notification launched the app, if any.
  Future<String?> launchReminderId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return decodeNotificationPayload(
      details.notificationResponse?.payload,
    )?.reminderId;
  }

  Future<NotificationPermissions> permissions() async {
    final android = _android;
    if (android != null) {
      return NotificationPermissions(
        enabled: await android.areNotificationsEnabled() ?? false,
        exactAlarms: await android.canScheduleExactNotifications() ?? false,
      );
    }
    final ios = _ios;
    if (ios != null) {
      final options = await ios.checkPermissions();
      return NotificationPermissions(
        enabled: options?.isEnabled ?? false,
        exactAlarms: true,
      );
    }
    return const NotificationPermissions(enabled: true, exactAlarms: true);
  }

  /// Shows the system permission prompt (Android 13+, iOS).
  Future<void> requestPermission() async {
    await _android?.requestNotificationsPermission();
    await _ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Android 12+: opens the "Alarms & reminders" setting.
  Future<void> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
  }

  Future<void> openSettings() async {
    await _plugin.openAppNotificationSettings();
  }

  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? true;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
}

/// How a planned notification looks on each platform.
NotificationDetails notificationDetailsFor(PlannedNotification notification) =>
    NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Alerts when a reminder is due',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        color: const Color(0xFF0F766E),
        // The tag groups a reminder's notifications so they can be removed
        // once it is done.
        tag: notification.reminderId,
        subText: notification.subtitle,
        timeoutAfter: notification.replacedAfter?.inMilliseconds,
        styleInformation: BigTextStyleInformation(notification.body),
        actions: const [
          AndroidNotificationAction(
            NotificationService.doneActionId,
            'Done',
          ),
        ],
      ),
      iOS: DarwinNotificationDetails(
        subtitle: notification.subtitle,
        threadIdentifier: notification.reminderId,
        categoryIdentifier: NotificationService._iosCategoryId,
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.active,
      ),
    );

class _PluginGateway implements NotificationGateway {
  _PluginGateway(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();

  @override
  Future<List<ActiveNotification>> active() => _plugin.getActiveNotifications();

  @override
  Future<void> cancel(int id, {String? tag}) => _plugin.cancel(id: id, tag: tag);

  @override
  Future<void> schedule(
    PlannedNotification notification, {
    required bool exact,
  }) => _plugin.zonedSchedule(
    id: notification.id,
    title: notification.title,
    body: notification.body,
    payload: notification.payloadFor(exact: exact),
    // Notification times are absolute instants, so UTC needs no time zone
    // database.
    scheduledDate: tz.TZDateTime.from(notification.at, tz.UTC),
    notificationDetails: notificationDetailsFor(notification),
    androidScheduleMode: exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
  );
}
