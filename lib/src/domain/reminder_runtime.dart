import '../core/local_date.dart';
import '../core/local_time.dart';
import 'occurrence.dart';
import 'occurrence_record.dart';
import 'schedule.dart';

/// The time of a reminder that is due right now (firing) until it is done
/// or missed.
class PendingOccurrence {
  const PendingOccurrence({
    required this.date,
    required this.time,
    required this.start,
    required this.dueAt,
    this.end,
  });

  factory PendingOccurrence.of(Occurrence occurrence) => PendingOccurrence(
    date: occurrence.date,
    time: occurrence.time,
    start: occurrence.start,
    dueAt: occurrence.dueAt,
    end: occurrence.end,
  );

  factory PendingOccurrence.fromJson(Map<String, Object?> json) {
    final end = json['end'] as int?;
    return PendingOccurrence(
      date: LocalDate.parse(json['date']! as String),
      time: ReminderTime.fromJson(
        (json['time']! as Map<Object?, Object?>).cast<String, Object?>(),
      ),
      start: _instant(json['start']! as int),
      dueAt: _instant(json['dueAt']! as int),
      end: end == null ? null : _instant(end),
    );
  }

  /// The day it belongs to.
  final LocalDate date;

  /// Its settings when it became due; editing the reminder doesn't change
  /// them.
  final ReminderTime time;

  final DateTime start;
  final DateTime dueAt;
  final DateTime? end;

  /// It as an [Occurrence] whose notifications stop when the reminder's
  /// next time starts at [nextStart].
  Occurrence toOccurrence(String reminderId, {DateTime? nextStart}) =>
      Occurrence(
        reminderId: reminderId,
        date: date,
        time: time,
        start: start,
        end: end,
        nextStart: nextStart,
      );

  Map<String, Object?> toJson() => {
    'date': date.toIso(),
    'time': time.toJson(),
    'start': start.millisecondsSinceEpoch,
    'dueAt': dueAt.millisecondsSinceEpoch,
    'end': end?.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is PendingOccurrence &&
      other.date == date &&
      other.time == time &&
      other.start == start &&
      other.dueAt == dueAt &&
      other.end == end;

  @override
  int get hashCode => Object.hash(date, time, start, dueAt, end);

  @override
  String toString() => 'PendingOccurrence($start, due $dueAt)';
}

/// How the latest finished time of a reminder ended.
class LastOutcome {
  const LastOutcome({
    required this.date,
    required this.start,
    required this.status,
    required this.at,
  });

  factory LastOutcome.fromJson(Map<String, Object?> json) => LastOutcome(
    date: LocalDate.parse(json['date']! as String),
    start: _instant(json['start']! as int),
    status: OccurrenceStatus.values.byName(json['status']! as String),
    at: _instant(json['at']! as int),
  );

  /// The day the time belongs to.
  final LocalDate date;

  /// When that time started.
  final DateTime start;

  /// [OccurrenceStatus.done] or [OccurrenceStatus.missed].
  final OccurrenceStatus status;

  /// When it was done or missed.
  final DateTime at;

  bool get isMissed => status == OccurrenceStatus.missed;

  Map<String, Object?> toJson() => {
    'date': date.toIso(),
    'start': start.millisecondsSinceEpoch,
    'status': status.name,
    'at': at.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is LastOutcome &&
      other.date == date &&
      other.start == start &&
      other.status == status &&
      other.at == at;

  @override
  int get hashCode => Object.hash(date, start, status, at);

  @override
  String toString() => 'LastOutcome(${status.name} $start at $at)';
}

/// Where a reminder stands.
///
/// It is derived from the history but stored on its own, so the list,
/// notifications and widgets never have to scan the history.
class ReminderRuntime {
  const ReminderRuntime({
    required this.reminderId,
    required this.processedUntil,
    required this.appliedAckUntil,
    this.pending,
    this.missedDate,
    this.missedCount = 0,
    this.last,
  });

  /// A fresh runtime: nothing processed before [since].
  factory ReminderRuntime.initial(String reminderId, DateTime since) =>
      ReminderRuntime(
        reminderId: reminderId,
        processedUntil: since,
        appliedAckUntil: since,
      );

  /// Also reads runtimes stored before 2026-11-05 (`pendingAt`, a running
  /// `missedCount`); their missed count starts over.
  factory ReminderRuntime.fromJson(Map<String, Object?> json) {
    final pending = json['pending'];
    final legacyPendingAt = json['pendingAt'] as int?;
    final missedDate = json['missedDate'] as String?;
    final last = json['last'];
    return ReminderRuntime(
      reminderId: json['reminderId']! as String,
      processedUntil: _instant(json['processedUntil']! as int),
      appliedAckUntil: _instant(json['appliedAckUntil']! as int),
      pending: switch (pending) {
        final Map<Object?, Object?> map => PendingOccurrence.fromJson(
          map.cast<String, Object?>(),
        ),
        _ when legacyPendingAt != null => _legacyPending(legacyPendingAt),
        _ => null,
      },
      missedDate: missedDate == null ? null : LocalDate.parse(missedDate),
      missedCount: missedDate == null ? 0 : json['missedCount']! as int,
      last: last is Map<Object?, Object?>
          ? LastOutcome.fromJson(last.cast<String, Object?>())
          : null,
    );
  }

  final String reminderId;

  /// Times that became due at or before this instant are in the history.
  final DateTime processedUntil;

  /// Done marks logged at or before this instant have been applied.
  final DateTime appliedAckUntil;

  /// The time that is due (firing), if any.
  final PendingOccurrence? pending;

  /// The day of the latest missed time; [missedCount] times of that day were
  /// missed.
  final LocalDate? missedDate;
  final int missedCount;

  /// How the latest finished time ended.
  final LastOutcome? last;

  /// Whether a time is due (firing).
  bool get isFiring => pending != null;

  /// How many of [date]'s times were missed.
  int missedOn(LocalDate date) => missedDate == date ? missedCount : 0;

  ReminderRuntime copyWith({
    DateTime? processedUntil,
    DateTime? appliedAckUntil,
    Object? pending = _unset,
    Object? missedDate = _unset,
    int? missedCount,
    Object? last = _unset,
  }) => ReminderRuntime(
    reminderId: reminderId,
    processedUntil: processedUntil ?? this.processedUntil,
    appliedAckUntil: appliedAckUntil ?? this.appliedAckUntil,
    pending: identical(pending, _unset)
        ? this.pending
        : pending as PendingOccurrence?,
    missedDate: identical(missedDate, _unset)
        ? this.missedDate
        : missedDate as LocalDate?,
    missedCount: missedCount ?? this.missedCount,
    last: identical(last, _unset) ? this.last : last as LastOutcome?,
  );

  Map<String, Object?> toJson() => {
    'reminderId': reminderId,
    'processedUntil': processedUntil.millisecondsSinceEpoch,
    'appliedAckUntil': appliedAckUntil.millisecondsSinceEpoch,
    'pending': pending?.toJson(),
    'missedDate': missedDate?.toIso(),
    'missedCount': missedCount,
    'last': last?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ReminderRuntime &&
      other.reminderId == reminderId &&
      other.processedUntil == processedUntil &&
      other.appliedAckUntil == appliedAckUntil &&
      other.pending == pending &&
      other.missedDate == missedDate &&
      other.missedCount == missedCount &&
      other.last == last;

  @override
  int get hashCode => Object.hash(
    reminderId,
    processedUntil,
    appliedAckUntil,
    pending,
    missedDate,
    missedCount,
    last,
  );

  @override
  String toString() =>
      'ReminderRuntime($reminderId, pending: $pending, '
      'missed: $missedCount on $missedDate, last: $last, '
      'processed: $processedUntil)';
}

/// An activation stored before 2026-11-05, as a time without an end.
PendingOccurrence _legacyPending(int millis) {
  final at = _instant(millis);
  return PendingOccurrence(
    date: LocalDate.fromDateTime(at),
    time: ReminderTime(start: LocalTime(at.hour, at.minute)),
    start: at,
    dueAt: at,
  );
}

DateTime _instant(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

const Object _unset = Object();
