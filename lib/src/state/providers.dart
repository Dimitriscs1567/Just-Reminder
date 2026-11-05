import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import '../core/clock.dart';
import '../data/reminder_repository.dart';
import '../domain/activation.dart';
import '../domain/reminder.dart';
import '../domain/reminder_runtime.dart';
import '../domain/schedule_engine.dart';
import '../services/ack_inbox.dart';
import '../services/app_events.dart';
import '../services/app_side_effects.dart';
import '../services/notifications/notification_service.dart';
import '../services/reminder_service.dart';
import '../services/widget/widget_bridge.dart';

/// The current time; overridden in tests.
final clockProvider = Provider<Clock>((ref) => systemClock);

/// The opened sembast database. Overridden in `main()` once it is open.
final databaseProvider = Provider<Database>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final reminderRepositoryProvider = Provider<ReminderRepository>(
  (ref) => ReminderRepository(ref.watch(databaseProvider)),
);

final scheduleEngineProvider = Provider<ScheduleEngine>(
  (ref) => const ScheduleEngine(),
);

final ackInboxProvider = Provider<AckInbox>(
  (ref) => const HomeWidgetAckInbox(),
);

/// The notification plugin wrapper. `null` until `main()` provides one (and
/// in tests), which turns notifications and widget updates off.
final notificationServiceProvider = Provider<NotificationService?>(
  (ref) => null,
);

final widgetBridgeProvider = Provider<WidgetBridge>(
  (ref) => const WidgetBridge(),
);

/// Called once the first sync is done and the reminders are loaded. `main()`
/// keeps the launch screen up until then, so the first frame already shows
/// the right screen and states. `null` in tests.
final startupReadyProvider = Provider<void Function()?>((ref) => null);

/// Notification taps, widget clicks and other outside requests.
final appEventsProvider = Provider<AppEvents>((ref) {
  final events = AppEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// What the user allowed; `null` without a notification service.
final notificationPermissionsProvider =
    FutureProvider.autoDispose<NotificationPermissions?>(
      (ref) async => ref.watch(notificationServiceProvider)?.permissions(),
    );

/// Keeps notifications and home screen widgets in line with the data.
final sideEffectsProvider = Provider<ReminderSideEffects>((ref) {
  final notifications = ref.watch(notificationServiceProvider);
  if (notifications == null) return const NoSideEffects();
  return AppSideEffects(
    repository: ref.watch(reminderRepositoryProvider),
    engine: ref.watch(scheduleEngineProvider),
    clock: ref.watch(clockProvider),
    widgets: ref.watch(widgetBridgeProvider),
    notifications: notifications,
  );
});

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(
    repository: ref.watch(reminderRepositoryProvider),
    inbox: ref.watch(ackInboxProvider),
    engine: ref.watch(scheduleEngineProvider),
    clock: ref.watch(clockProvider),
    sideEffects: ref.watch(sideEffectsProvider),
  ),
);

/// All reminders, including archived ones.
final remindersProvider = StreamProvider<List<Reminder>>(
  (ref) => ref.watch(reminderRepositoryProvider).watchReminders(),
);

/// Runtime state of every reminder, by reminder id.
final runtimesProvider = StreamProvider<Map<String, ReminderRuntime>>(
  (ref) => ref.watch(reminderRepositoryProvider).watchRuntimes(),
);

/// One reminder; `null` once it has been deleted.
final reminderProvider = StreamProvider.autoDispose.family<Reminder?, String>(
  (ref, id) => ref.watch(reminderRepositoryProvider).watchReminder(id),
);

/// A reminder's most recent [HistoryQuery.limit] history entries, newest
/// first.
final historyProvider = StreamProvider.autoDispose
    .family<List<ActivationRecord>, HistoryQuery>(
      (ref, query) => ref
          .watch(reminderRepositoryProvider)
          .watchHistory(query.reminderId, limit: query.limit),
    );

typedef HistoryQuery = ({String reminderId, int limit});
