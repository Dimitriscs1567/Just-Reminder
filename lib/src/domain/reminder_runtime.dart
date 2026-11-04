/// Where a reminder stands right now.
///
/// It is derived from the history but stored on its own, so the list,
/// notifications and widgets never have to scan the history.
class ReminderRuntime {
  const ReminderRuntime({
    required this.reminderId,
    required this.processedUntil,
    required this.appliedAckUntil,
    this.pendingAt,
    this.missedCount = 0,
    this.lastAcknowledgedAt,
  });

  /// A fresh runtime: nothing processed before [since].
  factory ReminderRuntime.initial(String reminderId, DateTime since) =>
      ReminderRuntime(
        reminderId: reminderId,
        processedUntil: since,
        appliedAckUntil: since,
      );

  factory ReminderRuntime.fromJson(Map<String, Object?> json) {
    final pendingAt = json['pendingAt'] as int?;
    final lastAcknowledgedAt = json['lastAcknowledgedAt'] as int?;
    return ReminderRuntime(
      reminderId: json['reminderId']! as String,
      processedUntil: DateTime.fromMillisecondsSinceEpoch(
        json['processedUntil']! as int,
      ),
      appliedAckUntil: DateTime.fromMillisecondsSinceEpoch(
        json['appliedAckUntil']! as int,
      ),
      pendingAt: pendingAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(pendingAt),
      missedCount: json['missedCount']! as int,
      lastAcknowledgedAt: lastAcknowledgedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastAcknowledgedAt),
    );
  }

  final String reminderId;

  /// Activations at or before this instant are already in the history.
  final DateTime processedUntil;

  /// Acknowledgments logged at or before this instant have been applied.
  final DateTime appliedAckUntil;

  /// The activation waiting for acknowledgment, if any.
  final DateTime? pendingAt;

  /// Activations missed since the last acknowledgment. Shown next to the
  /// waiting activation until it is acknowledged.
  final int missedCount;

  final DateTime? lastAcknowledgedAt;

  /// Whether an activation is waiting for acknowledgment (thumbs down).
  bool get isActive => pendingAt != null;

  ReminderRuntime copyWith({
    DateTime? processedUntil,
    DateTime? appliedAckUntil,
    Object? pendingAt = _unset,
    int? missedCount,
    Object? lastAcknowledgedAt = _unset,
  }) => ReminderRuntime(
    reminderId: reminderId,
    processedUntil: processedUntil ?? this.processedUntil,
    appliedAckUntil: appliedAckUntil ?? this.appliedAckUntil,
    pendingAt: identical(pendingAt, _unset)
        ? this.pendingAt
        : pendingAt as DateTime?,
    missedCount: missedCount ?? this.missedCount,
    lastAcknowledgedAt: identical(lastAcknowledgedAt, _unset)
        ? this.lastAcknowledgedAt
        : lastAcknowledgedAt as DateTime?,
  );

  Map<String, Object?> toJson() => {
    'reminderId': reminderId,
    'processedUntil': processedUntil.millisecondsSinceEpoch,
    'appliedAckUntil': appliedAckUntil.millisecondsSinceEpoch,
    'pendingAt': pendingAt?.millisecondsSinceEpoch,
    'missedCount': missedCount,
    'lastAcknowledgedAt': lastAcknowledgedAt?.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is ReminderRuntime &&
      other.reminderId == reminderId &&
      other.processedUntil == processedUntil &&
      other.appliedAckUntil == appliedAckUntil &&
      other.pendingAt == pendingAt &&
      other.missedCount == missedCount &&
      other.lastAcknowledgedAt == lastAcknowledgedAt;

  @override
  int get hashCode => Object.hash(
    reminderId,
    processedUntil,
    appliedAckUntil,
    pendingAt,
    missedCount,
    lastAcknowledgedAt,
  );

  @override
  String toString() =>
      'ReminderRuntime($reminderId, pending: $pendingAt, '
      'missed: $missedCount, processed: $processedUntil)';
}

const Object _unset = Object();
