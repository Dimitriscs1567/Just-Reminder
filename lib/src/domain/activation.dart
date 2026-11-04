/// What happened to an activation.
enum ActivationStatus {
  /// Fired and still waiting to be acknowledged.
  pending,

  /// Acknowledged by the user (see [ActivationRecord.acknowledgedAt]).
  acknowledged,

  /// A newer activation arrived (or the reminder was archived) before this
  /// one was acknowledged.
  missed,
}

/// One entry in a reminder's history.
class ActivationRecord {
  const ActivationRecord({
    required this.reminderId,
    required this.scheduledAt,
    required this.status,
    this.acknowledgedAt,
  });

  factory ActivationRecord.fromJson(Map<String, Object?> json) {
    final acknowledgedAt = json['acknowledgedAt'] as int?;
    return ActivationRecord(
      reminderId: json['reminderId']! as String,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(
        json['scheduledAt']! as int,
      ),
      status: ActivationStatus.values.byName(json['status']! as String),
      acknowledgedAt: acknowledgedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(acknowledgedAt),
    );
  }

  final String reminderId;

  /// When the activation happened.
  final DateTime scheduledAt;

  final ActivationStatus status;

  /// When it was acknowledged (only for [ActivationStatus.acknowledged]).
  final DateTime? acknowledgedAt;

  Map<String, Object?> toJson() => {
    'reminderId': reminderId,
    'scheduledAt': scheduledAt.millisecondsSinceEpoch,
    'status': status.name,
    'acknowledgedAt': acknowledgedAt?.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is ActivationRecord &&
      other.reminderId == reminderId &&
      other.scheduledAt == scheduledAt &&
      other.status == status &&
      other.acknowledgedAt == acknowledgedAt;

  @override
  int get hashCode =>
      Object.hash(reminderId, scheduledAt, status, acknowledgedAt);

  @override
  String toString() =>
      'ActivationRecord($reminderId, $scheduledAt, ${status.name}'
      '${acknowledgedAt == null ? '' : ', acknowledged $acknowledgedAt'})';
}
