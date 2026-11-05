import '../core/local_date.dart';
import 'reminder_runtime.dart';

/// What a reminder shows, in the app and on the widgets.
enum ReminderPhase {
  /// A time is due and not done yet.
  firing,

  /// The latest time today was missed and nothing is due.
  missed,

  /// Nothing is due: everything so far is done, or nothing happened yet
  /// today.
  done,
}

/// A reminder's phase and same-day missed count at one moment.
class ReminderStanding {
  const ReminderStanding({
    required this.phase,
    required this.missedCount,
    this.pending,
    this.last,
  });

  /// From [runtime] already brought forward to [now] (`advanceReminder`).
  ///
  /// Firing counts the missed times of the firing time's day — which may be
  /// yesterday, for a time still due past midnight. Otherwise the day
  /// starts clean: only today's times count, and only a time missed today
  /// shows as missed.
  factory ReminderStanding.at(ReminderRuntime runtime, DateTime now) {
    final pending = runtime.pending;
    if (pending != null) {
      return ReminderStanding(
        phase: ReminderPhase.firing,
        missedCount: runtime.missedOn(pending.date),
        pending: pending,
      );
    }
    final today = LocalDate.fromDateTime(now);
    final last = runtime.last;
    final lastToday = last != null && last.date == today ? last : null;
    return ReminderStanding(
      phase: lastToday != null && lastToday.isMissed
          ? ReminderPhase.missed
          : ReminderPhase.done,
      missedCount: runtime.missedOn(today),
      last: lastToday,
    );
  }

  final ReminderPhase phase;

  /// Missed times of the same day.
  final int missedCount;

  /// The time that is due (firing only).
  final PendingOccurrence? pending;

  /// Today's latest finished time, done or missed (not while firing).
  final LastOutcome? last;
}
