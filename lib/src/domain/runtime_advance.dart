import 'activation.dart';
import 'reminder_runtime.dart';

/// The outcome of moving a reminder's runtime forward in time.
class RuntimeAdvance {
  const RuntimeAdvance(this.runtime, this.records);

  final ReminderRuntime runtime;

  /// History records that were created or changed.
  final List<ActivationRecord> records;
}

/// Replays new [activations] and [acknowledgments] in time order:
///
/// - an activation becomes the waiting (pending) one; if another one was
///   still waiting, that one is recorded as **missed**;
/// - an acknowledgment acknowledges the waiting activation, if there is one,
///   and resets the missed count.
///
/// When an activation and an acknowledgment share an instant, the
/// activation goes first. [activations] must all be later than
/// `runtime.processedUntil`; afterwards `processedUntil` is [until].
RuntimeAdvance advanceRuntime({
  required ReminderRuntime runtime,
  required Iterable<DateTime> activations,
  required Iterable<DateTime> acknowledgments,
  required DateTime until,
}) {
  final events = <_Event>[
    for (final at in activations) _Event(at, isAcknowledgment: false),
    for (final at in acknowledgments) _Event(at, isAcknowledgment: true),
  ]..sort(_Event.compare);

  final reminderId = runtime.reminderId;
  final records = <DateTime, ActivationRecord>{};
  var pendingAt = runtime.pendingAt;
  var missedCount = runtime.missedCount;
  var lastAcknowledgedAt = runtime.lastAcknowledgedAt;
  var appliedAckUntil = runtime.appliedAckUntil;

  for (final event in events) {
    final pending = pendingAt;
    if (event.isAcknowledgment) {
      if (pending != null) {
        records[pending] = ActivationRecord(
          reminderId: reminderId,
          scheduledAt: pending,
          status: ActivationStatus.acknowledged,
          acknowledgedAt: event.at,
        );
        pendingAt = null;
        missedCount = 0;
        lastAcknowledgedAt = event.at;
      }
      if (event.at.isAfter(appliedAckUntil)) appliedAckUntil = event.at;
    } else {
      if (pending != null) {
        records[pending] = ActivationRecord(
          reminderId: reminderId,
          scheduledAt: pending,
          status: ActivationStatus.missed,
        );
        missedCount++;
      }
      records[event.at] = ActivationRecord(
        reminderId: reminderId,
        scheduledAt: event.at,
        status: ActivationStatus.pending,
      );
      pendingAt = event.at;
    }
  }

  return RuntimeAdvance(
    runtime.copyWith(
      processedUntil: until.isAfter(runtime.processedUntil)
          ? until
          : runtime.processedUntil,
      appliedAckUntil: appliedAckUntil,
      pendingAt: pendingAt,
      missedCount: missedCount,
      lastAcknowledgedAt: lastAcknowledgedAt,
    ),
    records.values.toList(),
  );
}

/// Records the waiting activation, if any, as missed. Used when a reminder
/// is archived while it is active.
RuntimeAdvance closePendingAsMissed(ReminderRuntime runtime) {
  final pending = runtime.pendingAt;
  if (pending == null) return RuntimeAdvance(runtime, const []);
  return RuntimeAdvance(
    runtime.copyWith(pendingAt: null, missedCount: runtime.missedCount + 1),
    [
      ActivationRecord(
        reminderId: runtime.reminderId,
        scheduledAt: pending,
        status: ActivationStatus.missed,
      ),
    ],
  );
}

class _Event {
  const _Event(this.at, {required this.isAcknowledgment});

  final DateTime at;
  final bool isAcknowledgment;

  static int compare(_Event a, _Event b) {
    final byTime = a.at.compareTo(b.at);
    if (byTime != 0) return byTime;
    if (a.isAcknowledgment == b.isAcknowledgment) return 0;
    return a.isAcknowledgment ? 1 : -1;
  }
}
