import '../../domain/occurrence.dart';
import '../../domain/reminder.dart';
import '../../domain/reminder_runtime.dart';
import '../../domain/runtime_advance.dart';
import '../../domain/schedule_engine.dart';

/// How far ahead a snapshot lists times, and at most how many. The widget
/// changes state at those times without the app running.
const widgetSnapshotHorizon = Duration(days: 14);
const widgetSnapshotMaxUpcoming = 200;

/// The JSON a home screen widget renders a reminder from.
///
/// ```json
/// {
///   "v": 1, "id": "…", "name": "Drink water", "displayName": "Water",
///   "state": "live" | "paused" | "archived" | "deleted",
///   "asOf": 1767225600000,          // when the snapshot was taken (ms)
///   "pendingAt": 1767225000000,     // when the due time became due, or null
///   "missedCount": 2,               // its day's missed times
///   "upcoming": [1767229200000],    // when the next times become due (ms)
///   "pending": {"start": …, "due": …, "missesAt": … | null} | null,
///   "occurrences": [{"start": …, "due": …, "missesAt": … | null}, …],
///   "reminder": { … }               // full Reminder JSON (for background
///                                   // isolates that recompute the times)
/// }
/// ```
///
/// The widgets read `pendingAt`, `missedCount` and `upcoming`: the state at
/// time `t` is computed the same way in Dart ([widgetStatusAt]), Kotlin and
/// Swift: `total = (pendingAt != null ? 1 + missedCount : 0)
///        + count(upcoming in (asOf, t])`; waiting when `total > 0`, with
/// `total - 1` missed. `pending` and `occurrences` (the due time and the
/// next ones, with when they are missed) tell a Done made outside the app
/// which time it finishes ([dueOccurrenceStartAt]).
Map<String, Object?> buildWidgetSnapshot({
  required Reminder reminder,
  required ReminderRuntime runtime,
  required ScheduleEngine engine,
  required DateTime now,
}) {
  final current = reminder.isArchived
      ? runtime
      : advanceReminder(
          reminder: reminder,
          runtime: runtime,
          engine: engine,
          now: now,
        ).runtime;
  final pending = current.pending;
  return {
    'v': 1,
    'id': reminder.id,
    'name': reminder.name,
    'displayName': reminder.displayName,
    'state': reminder.isArchived
        ? 'archived'
        : reminder.paused
        ? 'paused'
        : 'live',
    'asOf': now.millisecondsSinceEpoch,
    'pendingAt': pending?.dueAt.millisecondsSinceEpoch,
    'missedCount': pending == null ? 0 : current.missedOn(pending.date),
    ..._times(reminder, engine, now),
    'pending': pending == null
        ? null
        : _occurrenceJson(
            start: pending.start,
            due: pending.dueAt,
            missesAt: engine.missesAt(reminder, pending),
          ),
    'reminder': reminder.toJson(),
  };
}

/// What is left of a deleted reminder, so its widgets can say "Deleted".
Map<String, Object?> deletedWidgetSnapshot({
  required String id,
  required String name,
  required String displayName,
}) => {
  'v': 1,
  'id': id,
  'name': name,
  'displayName': displayName,
  'state': 'deleted',
};

/// The snapshot after the reminder was marked done at [at] outside the app
/// (widget tap, notification button): nothing due any more, and the next
/// times recomputed from [at].
Map<String, Object?> doneWidgetSnapshot(
  Map<String, Object?> snapshot, {
  required DateTime at,
  required ScheduleEngine engine,
}) {
  final reminder = switch (snapshot['reminder']) {
    final Map<Object?, Object?> json => Reminder.fromJson(
      json.cast<String, Object?>(),
    ),
    _ => null,
  };
  final now = at.millisecondsSinceEpoch;
  return {
    ...snapshot,
    'asOf': now,
    'pendingAt': null,
    'missedCount': 0,
    'pending': null,
    if (reminder != null)
      ..._times(reminder, engine, at)
    else ...{
      'upcoming': [
        for (final time in _ints(snapshot['upcoming']))
          if (time > now) time,
      ],
      'occurrences': [
        for (final occurrence in _maps(snapshot['occurrences']))
          if ((occurrence['due'] as int? ?? 0) > now) occurrence,
      ],
    },
  };
}

/// The start of the time a Done at [at] finishes: the latest time due by
/// then (the snapshot's due one, or one of its next times), unless it was
/// already missed. `null` when nothing is due.
DateTime? dueOccurrenceStartAt(Map<String, Object?> snapshot, DateTime at) {
  final now = at.millisecondsSinceEpoch;
  Map<String, Object?>? latest;
  for (final occurrence in [
    ..._maps([snapshot['pending']]),
    ..._maps(snapshot['occurrences']),
  ]) {
    final due = occurrence['due'] as int?;
    if (due == null || due > now) continue;
    if (latest == null || due > (latest['due']! as int)) latest = occurrence;
  }
  if (latest == null) return null;
  final missesAt = latest['missesAt'] as int?;
  if (missesAt != null && missesAt <= now) return null;
  final start = latest['start'] as int?;
  return start == null ? null : DateTime.fromMillisecondsSinceEpoch(start);
}

/// What a widget shows.
enum WidgetStatusKind { waiting, clear, archived, deleted }

class WidgetStatus {
  const WidgetStatus(this.kind, {this.missed = 0});

  final WidgetStatusKind kind;

  /// Missed times shown while waiting.
  final int missed;

  bool get isWaiting => kind == WidgetStatusKind.waiting;
}

/// The widget's state at [at] for [snapshot] (null = nothing stored, shown
/// as deleted). Mirrors `WidgetStore.kt` and `WidgetStore.swift`.
WidgetStatus widgetStatusAt(Map<String, Object?>? snapshot, DateTime at) {
  if (snapshot == null) return const WidgetStatus(WidgetStatusKind.deleted);
  switch (snapshot['state']) {
    case 'deleted':
      return const WidgetStatus(WidgetStatusKind.deleted);
    case 'archived':
      return const WidgetStatus(WidgetStatusKind.archived);
  }
  final asOf = snapshot['asOf'] as int? ?? 0;
  final now = at.millisecondsSinceEpoch;
  final base = snapshot['pendingAt'] == null
      ? 0
      : 1 + (snapshot['missedCount'] as int? ?? 0);
  final due = _ints(
    snapshot['upcoming'],
  ).where((time) => time > asOf && time <= now).length;
  final total = base + due;
  return total > 0
      ? WidgetStatus(WidgetStatusKind.waiting, missed: total - 1)
      : const WidgetStatus(WidgetStatusKind.clear);
}

/// `upcoming` (due times) and `occurrences` of [reminder]'s next times.
Map<String, Object?> _times(
  Reminder reminder,
  ScheduleEngine engine,
  DateTime now,
) {
  final next = engine.upcomingFor(
    reminder,
    now,
    count: widgetSnapshotMaxUpcoming,
    until: now.add(widgetSnapshotHorizon),
  );
  return {
    'upcoming': [
      for (final occurrence in next) occurrence.dueAt.millisecondsSinceEpoch,
    ],
    'occurrences': [
      for (final occurrence in next) _ofOccurrence(occurrence),
    ],
  };
}

Map<String, Object?> _ofOccurrence(Occurrence occurrence) => _occurrenceJson(
  start: occurrence.start,
  due: occurrence.dueAt,
  missesAt: occurrence.missesAt,
);

Map<String, Object?> _occurrenceJson({
  required DateTime start,
  required DateTime due,
  required DateTime? missesAt,
}) => {
  'start': start.millisecondsSinceEpoch,
  'due': due.millisecondsSinceEpoch,
  'missesAt': missesAt?.millisecondsSinceEpoch,
};

Iterable<int> _ints(Object? value) =>
    value is List<Object?> ? value.whereType<int>() : const <int>[];

Iterable<Map<String, Object?>> _maps(Object? value) => value is List<Object?>
    ? value.whereType<Map<Object?, Object?>>().map(
        (map) => map.cast<String, Object?>(),
      )
    : const [];
