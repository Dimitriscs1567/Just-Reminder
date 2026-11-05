import '../../core/local_date.dart';
import '../../domain/occurrence.dart';
import '../../domain/reminder.dart';
import '../../domain/reminder_runtime.dart';
import '../../domain/runtime_advance.dart';
import '../../domain/schedule_engine.dart';

/// The snapshot format: 2 has the three states (`missed`, `last`, dates).
const widgetSnapshotVersion = 2;

/// How far ahead a snapshot lists times, and at most how many. The widget
/// changes state at those times without the app running.
const widgetSnapshotHorizon = Duration(days: 14);
const widgetSnapshotMaxUpcoming = 200;

/// The JSON a home screen widget renders a reminder from.
///
/// ```json
/// {
///   "v": 2, "id": "…", "name": "Drink water", "displayName": "Water",
///   "state": "live" | "paused" | "archived" | "deleted",
///   "asOf": 1767225600000,   // when it was taken (epoch ms)
///   "pending": {"date": "2026-11-05", "start": …, "due": …,
///               "missesAt": … | null} | null,   // the due time
///   "missed": {"date": "2026-11-05", "count": 2} | null,
///   "last": {"date": "2026-11-05", "start": …, "at": …,
///            "status": "done" | "missed"} | null,  // latest finished time
///   "occurrences": [{"date": …, "start": …, "due": …, "missesAt": …}, …],
///   "reminder": { … }        // full Reminder JSON (for background isolates
///                            // that recompute the times)
/// }
/// ```
///
/// `pending`, `missed` and `last` are the reminder's runtime at `asOf`;
/// `occurrences` are its next times (due after `asOf`, up to 14 days
/// ahead). A widget replays them up to the moment it draws and shows the
/// same state as the app ([widgetStatusAt], mirrored in `WidgetStore.kt`
/// and `WidgetStore.swift` — change them together). Dates are local
/// (`YYYY-MM-DD`); a time without one belongs to the day it starts on.
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
  final missedDate = current.missedDate;
  final last = current.last;
  return {
    'v': widgetSnapshotVersion,
    'id': reminder.id,
    'name': reminder.name,
    'displayName': reminder.displayName,
    'state': reminder.isArchived
        ? 'archived'
        : reminder.paused
        ? 'paused'
        : 'live',
    'asOf': now.millisecondsSinceEpoch,
    'pending': pending == null
        ? null
        : _WidgetTime(
            date: pending.date.toIso(),
            start: pending.start.millisecondsSinceEpoch,
            due: pending.dueAt.millisecondsSinceEpoch,
            missesAt: engine
                .missesAt(reminder, pending)
                ?.millisecondsSinceEpoch,
          ).toJson(),
    'missed': missedDate == null || current.missedCount <= 0
        ? null
        : {'date': missedDate.toIso(), 'count': current.missedCount},
    'last': last == null
        ? null
        : {
            'date': last.date.toIso(),
            'start': last.start.millisecondsSinceEpoch,
            'status': last.isMissed ? 'missed' : 'done',
            'at': last.at.millisecondsSinceEpoch,
          },
    'occurrences': _occurrences(reminder, engine, now),
    'reminder': reminder.toJson(),
  };
}

/// What is left of a deleted reminder, so its widgets can say "Deleted".
Map<String, Object?> deletedWidgetSnapshot({
  required String id,
  required String name,
  required String displayName,
}) => {
  'v': widgetSnapshotVersion,
  'id': id,
  'name': name,
  'displayName': displayName,
  'state': 'deleted',
};

/// The snapshot after the reminder was marked done at [at] outside the app
/// (widget tap, notification button): brought forward to [at], the due
/// time done (the day's missed count stays), the next times recomputed.
Map<String, Object?> doneWidgetSnapshot(
  Map<String, Object?> snapshot, {
  required DateTime at,
  required ScheduleEngine engine,
}) {
  final now = at.millisecondsSinceEpoch;
  final replay = _WidgetReplay.of(snapshot, until: now)..done(now);
  final reminder = switch (snapshot['reminder']) {
    final Map<Object?, Object?> json => Reminder.fromJson(
      json.cast<String, Object?>(),
    ),
    _ => null,
  };
  return {
    // Version 1 fields, replaced by the ones below.
    for (final MapEntry(:key, :value) in snapshot.entries)
      if (!const {'pendingAt', 'missedCount', 'upcoming'}.contains(key))
        key: value,
    'v': widgetSnapshotVersion,
    'asOf': now,
    ...replay.toJson(),
    'occurrences': reminder != null
        ? _occurrences(reminder, engine, at)
        : [
            for (final time in _WidgetTime.listOf(snapshot['occurrences']))
              if (time.due > now) time.toJson(),
          ],
  };
}

/// The start of the time a Done at [at] finishes: the one due then, if
/// any.
DateTime? dueOccurrenceStartAt(Map<String, Object?> snapshot, DateTime at) {
  final start = _WidgetReplay.of(
    snapshot,
    until: at.millisecondsSinceEpoch,
  ).pending?.start;
  return start == null ? null : DateTime.fromMillisecondsSinceEpoch(start);
}

/// What a widget shows for a reminder.
enum WidgetStatusKind {
  /// A time is due: teal ring with a thumbs-up, tap for Done.
  firing,

  /// Today's latest time was missed and nothing is due.
  missed,

  /// Nothing is due (all done, or nothing happened yet today).
  done,

  /// Paused and nothing due.
  paused,

  archived,
  deleted,
}

class WidgetStatus {
  const WidgetStatus(this.kind, {this.missed = 0});

  final WidgetStatusKind kind;

  /// The day's missed times (while firing: of the due time's day).
  final int missed;

  bool get isFiring => kind == WidgetStatusKind.firing;

  @override
  bool operator ==(Object other) =>
      other is WidgetStatus && other.kind == kind && other.missed == missed;

  @override
  int get hashCode => Object.hash(kind, missed);

  @override
  String toString() => 'WidgetStatus(${kind.name}, missed: $missed)';
}

/// The widget's state at [at] for [snapshot] (null = nothing stored, shown
/// as deleted): the snapshot's runtime with the times due or missed since
/// it was taken, shown like `ReminderStanding` (a new day starts clean).
/// Mirrors `WidgetStore.kt` and `WidgetStore.swift`.
WidgetStatus widgetStatusAt(Map<String, Object?>? snapshot, DateTime at) {
  if (snapshot == null) return const WidgetStatus(WidgetStatusKind.deleted);
  final state = snapshot['state'];
  switch (state) {
    case 'deleted':
      return const WidgetStatus(WidgetStatusKind.deleted);
    case 'archived':
      return const WidgetStatus(WidgetStatusKind.archived);
  }
  final replay = _WidgetReplay.of(snapshot, until: at.millisecondsSinceEpoch);
  final pending = replay.pending;
  if (pending != null) {
    return WidgetStatus(
      WidgetStatusKind.firing,
      missed: replay.missedOn(pending.date),
    );
  }
  final today = LocalDate.fromDateTime(at).toIso();
  final missed = replay.missedOn(today);
  if (state == 'paused') {
    return WidgetStatus(WidgetStatusKind.paused, missed: missed);
  }
  return WidgetStatus(
    replay.lastDate == today && replay.lastMissed
        ? WidgetStatusKind.missed
        : WidgetStatusKind.done,
    missed: missed,
  );
}

/// When [snapshot]'s widget may change without the app running: its times
/// becoming due or being missed, and every midnight (a new day starts
/// clean), up to the end of the snapshot's horizon. Android schedules
/// redraws at these instants; the iOS timeline has an entry for each.
List<DateTime> widgetChangeTimes(Map<String, Object?> snapshot) {
  if (snapshot['state'] case 'archived' || 'deleted') return const [];
  final asOf = snapshot['asOf'] as int? ?? 0;
  final times = <int>{};
  void add(int? time) {
    if (time != null && time > asOf) times.add(time);
  }

  add(_WidgetTime.of(snapshot['pending'])?.missesAt);
  for (final time in _WidgetTime.listOf(snapshot['occurrences'])) {
    add(time.due);
    add(time.missesAt);
  }
  final day = DateTime.fromMillisecondsSinceEpoch(asOf);
  for (var days = 1; days <= widgetSnapshotHorizon.inDays + 1; days++) {
    add(DateTime(day.year, day.month, day.day + days).millisecondsSinceEpoch);
  }
  return [for (final time in times.toList()..sort()) _instant(time)];
}

/// [reminder]'s next times as snapshot JSON.
List<Map<String, Object?>> _occurrences(
  Reminder reminder,
  ScheduleEngine engine,
  DateTime now,
) => [
  for (final occurrence in engine.upcomingFor(
    reminder,
    now,
    count: widgetSnapshotMaxUpcoming,
    until: now.add(widgetSnapshotHorizon),
  ))
    _WidgetTime.ofOccurrence(occurrence).toJson(),
];

DateTime _instant(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

/// One time of a reminder as a snapshot stores it.
class _WidgetTime {
  const _WidgetTime({
    required this.date,
    required this.start,
    required this.due,
    this.missesAt,
  });

  factory _WidgetTime.ofOccurrence(Occurrence occurrence) => _WidgetTime(
    date: occurrence.date.toIso(),
    start: occurrence.start.millisecondsSinceEpoch,
    due: occurrence.dueAt.millisecondsSinceEpoch,
    missesAt: occurrence.missesAt?.millisecondsSinceEpoch,
  );

  static _WidgetTime? of(Object? json) {
    if (json is! Map<Object?, Object?>) return null;
    final start = json['start'];
    final due = json['due'];
    if (start is! int || due is! int) return null;
    final date = json['date'];
    final missesAt = json['missesAt'];
    return _WidgetTime(
      // Version 1 snapshots have no dates: a time belongs to the day it
      // starts on.
      date: date is String
          ? date
          : LocalDate.fromDateTime(_instant(start)).toIso(),
      start: start,
      due: due,
      missesAt: missesAt is int ? missesAt : null,
    );
  }

  static List<_WidgetTime> listOf(Object? json) => [
    if (json is List<Object?>)
      for (final item in json) ?_WidgetTime.of(item),
  ];

  final String date;
  final int start;
  final int due;
  final int? missesAt;

  Map<String, Object?> toJson() => {
    'date': date,
    'start': start,
    'due': due,
    'missesAt': missesAt,
  };
}

/// A snapshot's runtime brought forward in time without the app: the
/// widget's version of `advanceRuntime` (times becoming due, misses at
/// their `missesAt`, in time order, a miss first at the same instant; a due
/// time replacing a still pending one misses that one).
class _WidgetReplay {
  _WidgetReplay._(Map<String, Object?> snapshot)
    : pending = _WidgetTime.of(snapshot['pending']) {
    if (snapshot['missed'] case {
      'date': final String date,
      'count': final int count,
    }) {
      missedDate = date;
      missedCount = count;
    }
    if (snapshot['last'] case final Map<Object?, Object?> last) {
      lastDate = last['date'] as String?;
      lastStart = last['start'] as int?;
      lastMissed = last['status'] == 'missed';
      lastAt = last['at'] as int?;
    }
  }

  /// [snapshot]'s runtime as it is at [until] (epoch ms).
  factory _WidgetReplay.of(Map<String, Object?> snapshot, {required int until}) {
    final replay = _WidgetReplay._(snapshot);
    final asOf = snapshot['asOf'] as int? ?? 0;
    // (instant, 0 = missed / 1 = due, time)
    final events = <(int, int, _WidgetTime)>[
      if (replay.pending case final pending?)
        if (pending.missesAt case final missesAt? when missesAt <= until)
          (missesAt, 0, pending),
      for (final time in _WidgetTime.listOf(snapshot['occurrences']))
        if (time.due > asOf && time.due <= until) ...[
          (time.due, 1, time),
          if (time.missesAt case final missesAt? when missesAt <= until)
            (missesAt, 0, time),
        ],
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    for (final (at, kind, time) in events) {
      if (kind == 0) {
        if (replay.pending?.start == time.start) replay._miss(at);
      } else {
        if (replay.pending != null) replay._miss(at);
        replay.pending = time;
      }
    }
    return replay;
  }

  _WidgetTime? pending;
  String? missedDate;
  int missedCount = 0;
  String? lastDate;
  int? lastStart;
  bool lastMissed = false;
  int? lastAt;

  int missedOn(String date) => missedDate == date ? missedCount : 0;

  void _miss(int at) {
    final missed = pending!;
    final counted = missedDate;
    if (counted == missed.date) {
      missedCount++;
    } else if (counted == null || missed.date.compareTo(counted) > 0) {
      missedDate = missed.date;
      missedCount = 1;
    }
    _finish(missed, missed: true, at: at);
  }

  /// Done at [at]: finishes the due time, if any.
  void done(int at) {
    final due = pending;
    if (due != null && due.due <= at) _finish(due, missed: false, at: at);
  }

  void _finish(_WidgetTime time, {required bool missed, required int at}) {
    lastDate = time.date;
    lastStart = time.start;
    lastMissed = missed;
    lastAt = at;
    pending = null;
  }

  Map<String, Object?> toJson() => {
    'pending': pending?.toJson(),
    'missed': missedDate == null || missedCount <= 0
        ? null
        : {'date': missedDate, 'count': missedCount},
    'last': lastDate == null
        ? null
        : {
            'date': lastDate,
            'start': lastStart,
            'status': lastMissed ? 'missed' : 'done',
            'at': lastAt,
          },
  };
}
