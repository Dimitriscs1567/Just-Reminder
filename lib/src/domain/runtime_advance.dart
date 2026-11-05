import '../core/local_date.dart';
import 'occurrence.dart';
import 'occurrence_record.dart';
import 'reminder.dart';
import 'reminder_runtime.dart';
import 'schedule_engine.dart';

/// The outcome of moving a reminder's runtime forward in time.
class RuntimeAdvance {
  const RuntimeAdvance(this.runtime, this.records);

  final ReminderRuntime runtime;

  /// History records that were created or changed.
  final List<OccurrenceRecord> records;
}

/// Replays, in time order:
///
/// - [occurrences] becoming due: each becomes the pending (firing) one. They
///   must become due after `runtime.processedUntil` and at or before
///   [until]. Should another one still be pending (only possible after the
///   schedule was edited), it is recorded as missed right then;
/// - pending times being missed at their end, or when the next time starts
///   (`Occurrence.missesAt`, and [pendingMissesAt] for the runtime's own
///   pending time). Each miss counts for the day its time belongs to;
/// - [acknowledgments] (Done): the pending time is done. Done doesn't reset
///   the missed count; only a new day does.
///
/// At the same instant a miss comes first, then a time becoming due, then a
/// Done mark. Afterwards `processedUntil` is [until].
RuntimeAdvance advanceRuntime({
  required ReminderRuntime runtime,
  required Iterable<Occurrence> occurrences,
  required DateTime? pendingMissesAt,
  required Iterable<DateTime> acknowledgments,
  required DateTime until,
}) {
  final events = <_Event>[
    if (runtime.pending case final pending?
        when pendingMissesAt != null && !pendingMissesAt.isAfter(until))
      _Event(pendingMissesAt, _Kind.miss, start: pending.start),
    for (final occurrence in occurrences) ...[
      _Event(occurrence.dueAt, _Kind.due, occurrence: occurrence),
      if (occurrence.missesAt case final missesAt? when !missesAt.isAfter(until))
        _Event(missesAt, _Kind.miss, start: occurrence.start),
    ],
    for (final at in acknowledgments) _Event(at, _Kind.ack),
  ]..sort(_Event.compare);

  final state = _State(runtime);
  for (final event in events) {
    switch (event.kind) {
      case _Kind.miss:
        if (state.pending?.start == event.start) state.miss(event.at);
      case _Kind.due:
        if (state.pending != null) state.miss(event.at);
        state.becomeDue(event.occurrence!);
      case _Kind.ack:
        state.done(event.at);
    }
  }

  return RuntimeAdvance(
    runtime.copyWith(
      processedUntil: until.isAfter(runtime.processedUntil)
          ? until
          : runtime.processedUntil,
      appliedAckUntil: state.appliedAckUntil,
      pending: state.pending,
      missedDate: state.missedDate,
      missedCount: state.missedCount,
      last: state.last,
    ),
    state.records.values.toList(),
  );
}

/// [reminder]'s [runtime] brought forward to [now]: the times that became
/// due since `processedUntil` (none while paused or archived, none due at
/// or before `activeSince`), the misses and the Done marks in
/// [acknowledgments]. Without acknowledgments this is what the app shows
/// between syncs; a sync then records the same.
RuntimeAdvance advanceReminder({
  required Reminder reminder,
  required ReminderRuntime runtime,
  required ScheduleEngine engine,
  required DateTime now,
  Iterable<DateTime> acknowledgments = const [],
}) {
  final from = runtime.processedUntil.isAfter(reminder.activeSince)
      ? runtime.processedUntil
      : reminder.activeSince;
  final pending = runtime.pending;
  return advanceRuntime(
    runtime: runtime,
    occurrences: reminder.isLive
        ? engine.dueBetween(reminder.id, reminder.schedule, from, now)
        : const [],
    pendingMissesAt: pending == null
        ? null
        : engine.missesAt(reminder, pending),
    acknowledgments: acknowledgments,
    until: now,
  );
}

/// Records the pending time, if any, as missed at [at]. Used when a
/// reminder is archived while a time is due.
RuntimeAdvance closePendingAsMissed(ReminderRuntime runtime, DateTime at) =>
    advanceRuntime(
      runtime: runtime,
      occurrences: const [],
      pendingMissesAt: at,
      acknowledgments: const [],
      until: at,
    );

class _State {
  _State(ReminderRuntime runtime)
    : reminderId = runtime.reminderId,
      pending = runtime.pending,
      missedDate = runtime.missedDate,
      missedCount = runtime.missedCount,
      last = runtime.last,
      appliedAckUntil = runtime.appliedAckUntil;

  final String reminderId;
  final records = <DateTime, OccurrenceRecord>{};
  PendingOccurrence? pending;
  LocalDate? missedDate;
  int missedCount;
  LastOutcome? last;
  DateTime appliedAckUntil;

  void becomeDue(Occurrence occurrence) {
    final due = PendingOccurrence.of(occurrence);
    pending = due;
    records[due.start] = _record(due, OccurrenceStatus.pending);
  }

  void miss(DateTime at) {
    final missed = pending!;
    records[missed.start] = _record(missed, OccurrenceStatus.missed);
    final countedDate = missedDate;
    if (countedDate == missed.date) {
      missedCount++;
    } else if (countedDate == null || missed.date.isAfter(countedDate)) {
      missedDate = missed.date;
      missedCount = 1;
    }
    last = LastOutcome(
      date: missed.date,
      start: missed.start,
      status: OccurrenceStatus.missed,
      at: at,
    );
    pending = null;
  }

  void done(DateTime at) {
    final due = pending;
    if (due != null && !due.dueAt.isAfter(at)) {
      records[due.start] = _record(due, OccurrenceStatus.done, doneAt: at);
      last = LastOutcome(
        date: due.date,
        start: due.start,
        status: OccurrenceStatus.done,
        at: at,
      );
      pending = null;
    }
    if (at.isAfter(appliedAckUntil)) appliedAckUntil = at;
  }

  OccurrenceRecord _record(
    PendingOccurrence occurrence,
    OccurrenceStatus status, {
    DateTime? doneAt,
  }) => OccurrenceRecord(
    reminderId: reminderId,
    start: occurrence.start,
    end: occurrence.end,
    dueAt: occurrence.dueAt,
    status: status,
    doneAt: doneAt,
  );
}

/// Event kinds in the order they are handled at the same instant.
enum _Kind { miss, due, ack }

class _Event {
  const _Event(this.at, this.kind, {this.start, this.occurrence});

  final DateTime at;
  final _Kind kind;

  /// The start of the time a miss is about.
  final DateTime? start;

  /// The time that becomes due.
  final Occurrence? occurrence;

  static int compare(_Event a, _Event b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.kind.index.compareTo(b.kind.index);
  }
}
