import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import '../core/clock.dart';
import '../data/reminder_repository.dart';
import '../domain/activation.dart';
import '../domain/reminder.dart';
import '../domain/reminder_runtime.dart';
import '../domain/schedule_engine.dart';
import '../services/ack_inbox.dart';
import '../services/reminder_service.dart';

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

/// Keeps notifications and widgets up to date (wired up in a later step).
final sideEffectsProvider = Provider<ReminderSideEffects>(
  (ref) => const NoSideEffects(),
);

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
