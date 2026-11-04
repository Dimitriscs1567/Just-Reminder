import 'local_time.dart';

/// A calendar date without a time of day or time zone.
///
/// Date arithmetic runs on UTC dates internally, so daylight-saving changes
/// can never shift a day.
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate(dateTime.year, dateTime.month, dateTime.day);

  /// Parses an ISO-8601 calendar date (`yyyy-MM-dd`).
  factory LocalDate.parse(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      throw FormatException('Invalid date', value);
    }
    return LocalDate(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  /// Number of days in [month] of [year].
  static int daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// ISO weekday: 1 = Monday … 7 = Sunday.
  int get weekday => _utc.weekday;

  /// The Monday of the week this date belongs to.
  LocalDate get startOfWeek => addDays(DateTime.monday - weekday);

  LocalDate addDays(int days) {
    final utc = DateTime.utc(year, month, day + days);
    return LocalDate(utc.year, utc.month, utc.day);
  }

  /// Whole days from this date to [other]; negative when [other] is earlier.
  int daysUntil(LocalDate other) => other._utc.difference(_utc).inDays;

  /// Calendar months from this date's month to [other]'s month.
  int monthsUntil(LocalDate other) =>
      (other.year - year) * 12 + (other.month - month);

  /// This date at [time] in the device's local time zone.
  DateTime at(LocalTime time) =>
      DateTime(year, month, day, time.hour, time.minute);

  bool isBefore(LocalDate other) => compareTo(other) < 0;

  bool isAfter(LocalDate other) => compareTo(other) > 0;

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
