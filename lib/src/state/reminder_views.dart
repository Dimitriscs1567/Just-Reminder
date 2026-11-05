import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/occurrence.dart';
import '../domain/reminder.dart';
import '../domain/reminder_runtime.dart';
import '../domain/reminder_standing.dart';
import '../domain/runtime_advance.dart';
import 'now.dart';
import 'providers.dart';

/// Where a reminder stands, as shown in the UI.
enum ReminderStatus {
  /// A time is due (also while paused, until it is done or missed).
  firing,

  /// Today's latest time was missed; nothing is due. It reminds again.
  missed,

  /// Nothing is due; it reminds again.
  done,

  /// Switched off by the user.
  paused,

  /// Nothing due and nothing to come; the next sync archives it.
  ended,

  /// In the archive.
  archived,
}

/// A reminder with its state at "now".
class ReminderView {
  const ReminderView({
    required this.reminder,
    required this.runtime,
    required this.standing,
    required this.next,
    required this.dueMissesAt,
  });

  final Reminder reminder;

  /// The runtime brought forward to "now" (what the next sync records).
  final ReminderRuntime runtime;

  final ReminderStanding standing;

  /// The next time that will become due, or `null` when none is coming
  /// (paused, archived, finished).
  final Occurrence? next;

  /// When the due time counts as missed, if one is due and that is known.
  final DateTime? dueMissesAt;

  String get id => reminder.id;

  bool get isFiring => status == ReminderStatus.firing;

  /// The time that is due.
  PendingOccurrence? get due => isFiring ? standing.pending : null;

  /// Missed times of the same day (none for archived reminders).
  int get missedCount => reminder.isArchived ? 0 : standing.missedCount;

  /// Today's latest finished time (done or missed), if any.
  LastOutcome? get lastToday => standing.last;

  ReminderStatus get status {
    if (reminder.isArchived) return ReminderStatus.archived;
    if (standing.phase == ReminderPhase.firing) return ReminderStatus.firing;
    if (reminder.paused) return ReminderStatus.paused;
    if (next == null) return ReminderStatus.ended;
    return standing.phase == ReminderPhase.missed
        ? ReminderStatus.missed
        : ReminderStatus.done;
  }

  /// When its state next changes on its own: its next time becomes due, or
  /// the due one is missed.
  DateTime? get nextChange {
    if (reminder.isArchived) return null;
    final due = next?.dueAt;
    final missesAt = dueMissesAt;
    if (due == null) return missesAt;
    if (missesAt == null) return due;
    return due.isBefore(missesAt) ? due : missesAt;
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
      () {
        final stored =
            runtimes[reminder.id] ??
            ReminderRuntime.initial(reminder.id, reminder.activeSince);
        final runtime = reminder.isArchived
            ? stored
            : advanceReminder(
                reminder: reminder,
                runtime: stored,
                engine: engine,
                now: now,
              ).runtime;
        final pending = runtime.pending;
        return ReminderView(
          reminder: reminder,
          runtime: runtime,
          standing: ReminderStanding.at(runtime, now),
          next: engine.upcomingFor(reminder, now).firstOrNull,
          dueMissesAt: pending == null || reminder.isArchived
              ? null
              : engine.missesAt(reminder, pending),
        );
      }(),
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

/// The soonest moment any reminder changes state on its own, used to sync
/// (history, notifications, widgets) exactly then.
final nextChangeProvider = Provider<DateTime?>((ref) {
  DateTime? earliest;
  final views = ref.watch(reminderViewsProvider).value ?? const <ReminderView>[];
  for (final view in views) {
    final next = view.nextChange;
    if (next != null && (earliest == null || next.isBefore(earliest))) {
      earliest = next;
    }
  }
  return earliest;
});
