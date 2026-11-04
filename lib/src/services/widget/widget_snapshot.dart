import '../../domain/reminder.dart';
import '../../domain/reminder_runtime.dart';
import '../../domain/schedule_engine.dart';

/// How far ahead a snapshot lists activations, and at most how many. The
/// widget flips to thumbs down at those times without the app running.
const widgetSnapshotHorizon = Duration(days: 14);
const widgetSnapshotMaxUpcoming = 200;

/// The JSON a home screen widget renders a reminder from.
///
/// ```json
/// {
///   "v": 1, "id": "…", "name": "Drink water", "displayName": "Water",
///   "state": "live" | "paused" | "archived" | "deleted",
///   "asOf": 1767225600000,          // when the snapshot was taken (ms)
///   "pendingAt": 1767225000000,     // waiting activation, or null
///   "missedCount": 2,               // missed before the waiting one
///   "upcoming": [1767229200000],    // activations after asOf (ms)
///   "reminder": { … }               // full Reminder JSON (for background
///                                   // isolates that recompute "upcoming")
/// }
/// ```
///
/// The waiting state at time `t` is computed the same way in Dart
/// ([widgetStatusAt]), Kotlin and Swift:
/// `total = (pendingAt != null ? 1 + missedCount : 0)
///        + count(upcoming in (asOf, t])`; waiting when `total > 0`,
/// with `total - 1` missed.
Map<String, Object?> buildWidgetSnapshot({
  required Reminder reminder,
  required ReminderRuntime runtime,
  required ScheduleEngine engine,
  required DateTime now,
}) => {
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
  'pendingAt': runtime.pendingAt?.millisecondsSinceEpoch,
  'missedCount': runtime.missedCount,
  'upcoming': _upcoming(reminder, engine, now),
  'reminder': reminder.toJson(),
};

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

/// The snapshot after the reminder was acknowledged at [at] outside the
/// app (widget tap, notification button): nothing waiting any more, and the
/// upcoming activations recomputed from [at].
Map<String, Object?> acknowledgedWidgetSnapshot(
  Map<String, Object?> snapshot, {
  required DateTime at,
  required ScheduleEngine engine,
}) {
  final upcoming = switch (snapshot['reminder']) {
    final Map<Object?, Object?> json => _upcoming(
      Reminder.fromJson(json.cast<String, Object?>()),
      engine,
      at,
    ),
    _ => [
      for (final time in _times(snapshot['upcoming']))
        if (time > at.millisecondsSinceEpoch) time,
    ],
  };
  return {
    ...snapshot,
    'asOf': at.millisecondsSinceEpoch,
    'pendingAt': null,
    'missedCount': 0,
    'upcoming': upcoming,
  };
}

/// What a widget shows.
enum WidgetStatusKind { waiting, clear, archived, deleted }

class WidgetStatus {
  const WidgetStatus(this.kind, {this.missed = 0});

  final WidgetStatusKind kind;

  /// Missed activations before the waiting one (only when waiting).
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
  final due = _times(
    snapshot['upcoming'],
  ).where((time) => time > asOf && time <= now).length;
  final total = base + due;
  return total > 0
      ? WidgetStatus(WidgetStatusKind.waiting, missed: total - 1)
      : const WidgetStatus(WidgetStatusKind.clear);
}

List<int> _upcoming(Reminder reminder, ScheduleEngine engine, DateTime now) => [
  for (final at in engine.upcomingFor(
    reminder,
    now,
    count: widgetSnapshotMaxUpcoming,
    until: now.add(widgetSnapshotHorizon),
  ))
    at.millisecondsSinceEpoch,
];

Iterable<int> _times(Object? value) =>
    value is List<Object?> ? value.whereType<int>() : const <int>[];
