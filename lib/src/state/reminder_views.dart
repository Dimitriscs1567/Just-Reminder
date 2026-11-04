import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reminder.dart';
import '../domain/reminder_runtime.dart';
import 'now.dart';
import 'providers.dart';

/// Where a reminder stands, as shown in the UI.
enum ReminderStatus {
  /// An activation is waiting for acknowledgment (thumbs down).
  waiting,

  /// Nothing waiting; it will activate again (thumbs up).
  scheduled,

  /// Switched off by the user.
  paused,

  /// Nothing waiting and nothing upcoming; the next sync archives it.
  ended,

  /// In the archive.
  archived,
}

/// A reminder together with its runtime state and next activation.
class ReminderView {
  const ReminderView({
    required this.reminder,
    required this.runtime,
    required this.nextActivation,
  });

  final Reminder reminder;
  final ReminderRuntime runtime;

  /// The next activation, or `null` when none is coming (paused, archived,
  /// finished).
  final DateTime? nextActivation;

  String get id => reminder.id;

  bool get isWaiting => !reminder.isArchived && runtime.isActive;

  /// Missed activations to show next to the waiting one.
  int get missedCount => isWaiting ? runtime.missedCount : 0;

  ReminderStatus get status {
    if (reminder.isArchived) return ReminderStatus.archived;
    if (runtime.isActive) return ReminderStatus.waiting;
    if (reminder.paused) return ReminderStatus.paused;
    if (nextActivation == null) return ReminderStatus.ended;
    return ReminderStatus.scheduled;
  }
}

/// Every reminder (archived ones included) as a [ReminderView].
final reminderViewsProvider = Provider<AsyncValue<List<ReminderView>>>((ref) {
  final remindersAsync = ref.watch(remindersProvider);
  final runtimesAsync = ref.watch(runtimesProvider);
  final now = ref.watch(nowProvider);
  final engine = ref.watch(scheduleEngineProvider);

  for (final async in [remindersAsync, runtimesAsync]) {
    if (async case AsyncError(:final error, :final stackTrace)) {
      return AsyncError(error, stackTrace);
    }
  }
  final reminders = remindersAsync.value;
  final runtimes = runtimesAsync.value;
  if (reminders == null || runtimes == null) return const AsyncLoading();

  return AsyncData([
    for (final reminder in reminders)
      ReminderView(
        reminder: reminder,
        runtime:
            runtimes[reminder.id] ??
            ReminderRuntime.initial(reminder.id, reminder.activeSince),
        nextActivation: engine.upcomingFor(reminder, now).firstOrNull,
      ),
  ]);
});

/// One reminder's view; `null` once it has been deleted.
final reminderViewProvider = Provider.autoDispose
    .family<AsyncValue<ReminderView?>, String>(
      (ref, id) => ref.watch(reminderViewsProvider).whenData((views) {
        for (final view in views) {
          if (view.id == id) return view;
        }
        return null;
      }),
    );

/// The soonest upcoming activation of any reminder, used to refresh the app
/// exactly when something activates.
final nextActivationProvider = Provider<DateTime?>((ref) {
  DateTime? earliest;
  final views = ref.watch(reminderViewsProvider).value ?? const <ReminderView>[];
  for (final view in views) {
    final next = view.nextActivation;
    if (next != null && (earliest == null || next.isBefore(earliest))) {
      earliest = next;
    }
  }
  return earliest;
});
