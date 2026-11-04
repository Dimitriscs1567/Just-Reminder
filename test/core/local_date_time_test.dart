import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';

void main() {
  group('LocalDate', () {
    test('adds days across month, year and leap-day boundaries', () {
      expect(
        const LocalDate(2026, 12, 31).addDays(1),
        const LocalDate(2027, 1, 1),
      );
      expect(
        const LocalDate(2028, 2, 28).addDays(1),
        const LocalDate(2028, 2, 29),
      );
      expect(
        const LocalDate(2027, 3, 1).addDays(-1),
        const LocalDate(2027, 2, 28),
      );
    });

    test('counts whole days between dates, ignoring DST', () {
      // Spans the European and US DST changes in March.
      expect(
        const LocalDate(2026, 3, 1).daysUntil(const LocalDate(2026, 4, 1)),
        31,
      );
      expect(
        const LocalDate(2026, 11, 10).daysUntil(const LocalDate(2026, 11, 4)),
        -6,
      );
    });

    test('knows ISO weekdays and the Monday of the week', () {
      const wednesday = LocalDate(2026, 11, 4);
      expect(wednesday.weekday, DateTime.wednesday);
      expect(wednesday.startOfWeek, const LocalDate(2026, 11, 2));
      expect(
        const LocalDate(2026, 11, 8).startOfWeek, // Sunday
        const LocalDate(2026, 11, 2),
      );
    });

    test('knows month lengths, including leap years', () {
      expect(LocalDate.daysInMonth(2027, 2), 28);
      expect(LocalDate.daysInMonth(2028, 2), 29);
      expect(LocalDate.daysInMonth(2026, 4), 30);
      expect(LocalDate.daysInMonth(2026, 12), 31);
    });

    test('counts calendar months', () {
      expect(
        const LocalDate(2026, 11, 20).monthsUntil(const LocalDate(2027, 1, 1)),
        2,
      );
    });

    test('parses, formats and compares', () {
      const date = LocalDate(2026, 3, 7);
      expect(date.toIso(), '2026-03-07');
      expect(LocalDate.parse('2026-03-07'), date);
      expect(date.isBefore(const LocalDate(2026, 3, 8)), isTrue);
      expect(date.isAfter(const LocalDate(2025, 12, 31)), isTrue);
    });

    test('combines with a time in local time', () {
      expect(
        const LocalDate(2026, 11, 4).at(const LocalTime(9, 30)),
        DateTime(2026, 11, 4, 9, 30),
      );
    });
  });

  group('LocalTime', () {
    test('parses, formats and converts minutes', () {
      expect(LocalTime.parse('07:05'), const LocalTime(7, 5));
      expect(const LocalTime(7, 5).toIso(), '07:05');
      expect(const LocalTime(13, 45).minutesOfDay, 825);
      expect(LocalTime.fromMinutes(825), const LocalTime(13, 45));
    });
  });
}
