import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../data/reminder_repository.dart';
import '../domain/schedule_engine.dart';
import 'notifications/notification_plan.dart';
import 'notifications/notification_service.dart';
import 'reminder_service.dart';
import 'widget/widget_bridge.dart';

/// After every change: publish widget snapshots and reschedule
/// notifications, so both match the database.
class AppSideEffects implements ReminderSideEffects {
  AppSideEffects({
    required this._repository,
    required this._engine,
    required this._clock,
    required this._widgets,
    required this._notifications,
  });

  final ReminderRepository _repository;
  final ScheduleEngine _engine;
  final Clock _clock;
  final WidgetBridge _widgets;
  final NotificationService _notifications;

  @override
  Future<void> onRemindersChanged() async {
    final now = _clock();
    final reminders = await _repository.getReminders();
    final runtimes = await _repository.getRuntimes();

    // Side effects must never break the data change that triggered them.
    try {
      await _widgets.publish(
        reminders: reminders,
        runtimes: runtimes,
        engine: _engine,
        now: now,
      );
    } on Object catch (error, stack) {
      debugPrint('Widget update failed: $error\n$stack');
    }

    try {
      final dueStarts = {
        for (final MapEntry(key: id, value: runtime) in runtimes.entries)
          id: ?runtime.pending?.start,
      };
      await _notifications.scheduler.apply(
        planNotifications(
          reminders: reminders,
          runtimes: runtimes,
          engine: _engine,
          now: now,
          budget: _notifications.budget,
        ),
        now: now,
        dueStarts: dueStarts,
        exact: await _notifications.canScheduleExact(),
      );
      await _notifications.scheduler.clearDeliveredExcept(
        dueStarts.keys.toSet(),
      );
    } on Object catch (error, stack) {
      debugPrint('Notification update failed: $error\n$stack');
    }
  }
}
