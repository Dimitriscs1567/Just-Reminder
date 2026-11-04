/// A wall-clock time of day (hours and minutes), without a date.
class LocalTime implements Comparable<LocalTime> {
  const LocalTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24, 'hour must be 0-23'),
      assert(minute >= 0 && minute < 60, 'minute must be 0-59');

  /// Builds a time from minutes since midnight (0–1439).
  factory LocalTime.fromMinutes(int minutesOfDay) =>
      LocalTime(minutesOfDay ~/ 60, minutesOfDay % 60);

  /// Parses `HH:mm`.
  factory LocalTime.parse(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid time', value);
    }
    return LocalTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  final int hour;
  final int minute;

  static const midnight = LocalTime(0, 0);

  /// Minutes since midnight.
  int get minutesOfDay => hour * 60 + minute;

  String toIso() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalTime other) => minutesOfDay.compareTo(other.minutesOfDay);

  @override
  bool operator ==(Object other) =>
      other is LocalTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => toIso();
}
