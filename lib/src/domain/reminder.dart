import 'schedule.dart';

/// A reminder as the user set it up.
class Reminder {
  const Reminder({
    required this.id,
    required this.name,
    required this.displayName,
    required this.schedule,
    required this.createdAt,
    required this.updatedAt,
    required this.activeSince,
    this.description,
    this.paused = false,
    this.archivedAt,
  });

  factory Reminder.fromJson(Map<String, Object?> json) {
    final archivedAt = json['archivedAt'] as int?;
    return Reminder(
      id: json['id']! as String,
      name: json['name']! as String,
      displayName: json['displayName']! as String,
      description: json['description'] as String?,
      schedule: Schedule.fromJson(
        (json['schedule']! as Map<Object?, Object?>).cast<String, Object?>(),
      ),
      paused: json['paused']! as bool,
      archivedAt: archivedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(archivedAt),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt']! as int),
      activeSince: DateTime.fromMillisecondsSinceEpoch(
        json['activeSince']! as int,
      ),
    );
  }

  final String id;

  /// Full name, shown in the app.
  final String name;

  /// Short name, shown on the home screen widget and as notification title.
  final String displayName;

  /// Optional details, shown in the app and as notification text.
  final String? description;

  final Schedule schedule;

  /// Paused reminders do not activate.
  final bool paused;

  /// When the reminder was archived; `null` while it is in the main list.
  final DateTime? archivedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Activations at or before this instant never happen. Set on creation and
  /// moved to "now" whenever the schedule is edited, or the reminder is
  /// resumed or restored, so no activations are invented for the past.
  final DateTime activeSince;

  bool get isArchived => archivedAt != null;

  /// Whether the reminder can activate (not paused, not archived).
  bool get isLive => !paused && archivedAt == null;

  Reminder copyWith({
    String? name,
    String? displayName,
    Object? description = _unset,
    Schedule? schedule,
    bool? paused,
    Object? archivedAt = _unset,
    DateTime? updatedAt,
    DateTime? activeSince,
  }) => Reminder(
    id: id,
    name: name ?? this.name,
    displayName: displayName ?? this.displayName,
    description: identical(description, _unset)
        ? this.description
        : description as String?,
    schedule: schedule ?? this.schedule,
    paused: paused ?? this.paused,
    archivedAt: identical(archivedAt, _unset)
        ? this.archivedAt
        : archivedAt as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    activeSince: activeSince ?? this.activeSince,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'displayName': displayName,
    'description': description,
    'schedule': schedule.toJson(),
    'paused': paused,
    'archivedAt': archivedAt?.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'activeSince': activeSince.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.name == name &&
      other.displayName == displayName &&
      other.description == description &&
      other.schedule == schedule &&
      other.paused == paused &&
      other.archivedAt == archivedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.activeSince == activeSince;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    displayName,
    description,
    schedule,
    paused,
    archivedAt,
    createdAt,
    updatedAt,
    activeSince,
  );
}

const Object _unset = Object();
