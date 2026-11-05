/// What happened to one of a reminder's times on one day.
enum OccurrenceStatus {
  /// Due and not done yet.
  pending,

  /// Done by the user (see [OccurrenceRecord.doneAt]).
  done,

  /// Not done in time: its end passed, the reminder's next time started, or
  /// the reminder was archived meanwhile.
  missed,
}

/// One entry in a reminder's history: one time on one day, done or not.
class OccurrenceRecord {
  const OccurrenceRecord({
    required this.reminderId,
    required this.start,
    required this.dueAt,
    required this.status,
    this.end,
    this.doneAt,
  });

  /// Also reads records stored before 2026-11-05 (`scheduledAt`, status
  /// `acknowledged`, `acknowledgedAt`).
  factory OccurrenceRecord.fromJson(Map<String, Object?> json) {
    final start = (json['start'] ?? json['scheduledAt'])! as int;
    final end = json['end'] as int?;
    final doneAt = (json['doneAt'] ?? json['acknowledgedAt']) as int?;
    return OccurrenceRecord(
      reminderId: json['reminderId']! as String,
      start: _instant(start),
      end: end == null ? null : _instant(end),
      dueAt: _instant(json['dueAt'] as int? ?? start),
      status: switch (json['status']) {
        'acknowledged' => OccurrenceStatus.done,
        final String name => OccurrenceStatus.values.byName(name),
        final status => throw FormatException('Unknown status: $status'),
      },
      doneAt: doneAt == null ? null : _instant(doneAt),
    );
  }

  final String reminderId;

  /// When the time started; also its key in the history.
  final DateTime start;

  /// When it ends, if the time has an end.
  final DateTime? end;

  /// When it became due (its first notification).
  final DateTime dueAt;

  final OccurrenceStatus status;

  /// When it was done (only for [OccurrenceStatus.done]).
  final DateTime? doneAt;

  Map<String, Object?> toJson() => {
    'reminderId': reminderId,
    'start': start.millisecondsSinceEpoch,
    'end': end?.millisecondsSinceEpoch,
    'dueAt': dueAt.millisecondsSinceEpoch,
    'status': status.name,
    'doneAt': doneAt?.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is OccurrenceRecord &&
      other.reminderId == reminderId &&
      other.start == start &&
      other.end == end &&
      other.dueAt == dueAt &&
      other.status == status &&
      other.doneAt == doneAt;

  @override
  int get hashCode =>
      Object.hash(reminderId, start, end, dueAt, status, doneAt);

  @override
  String toString() =>
      'OccurrenceRecord($reminderId, $start${end == null ? '' : '–$end'}, '
      '${status.name}${doneAt == null ? '' : ' $doneAt'})';
}

DateTime _instant(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);
