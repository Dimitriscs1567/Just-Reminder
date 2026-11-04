import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/activation.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/schedule.dart';

/// Round-trips through a JSON string, like storage does.
Map<String, Object?> viaJson(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  final schedules = <String, Schedule>{
    'once, fixed': const Schedule(
      recurrence: OnceRecurrence(LocalDate(2026, 11, 5)),
      timing: FixedTiming(LocalTime(9, 0)),
    ),
    'weekly, interval with max': const Schedule(
      recurrence: RepeatRecurrence(
        unit: RepeatUnit.week,
        every: 2,
        startDate: LocalDate(2026, 11, 4),
        endDate: LocalDate(2027, 1, 31),
        weekdays: {5, 1, 3},
      ),
      timing: RangeTiming(
        start: LocalTime(9, 0),
        end: LocalTime(17, 0),
        mode: RangeMode.interval,
        intervalMinutes: 30,
        maxActivations: 5,
      ),
    ),
    'monthly, random past midnight': const Schedule(
      recurrence: RepeatRecurrence(
        unit: RepeatUnit.month,
        startDate: LocalDate(2026, 11, 4),
        dayOfMonth: 31,
      ),
      timing: RangeTiming(
        start: LocalTime(22, 0),
        end: LocalTime(2, 0),
        mode: RangeMode.random,
        maxActivations: 3,
      ),
    ),
  };

  for (final MapEntry(key: name, value: schedule) in schedules.entries) {
    test('reminder with $name survives a JSON round trip', () {
      final reminder = Reminder(
        id: 'abc',
        name: 'Drink water',
        displayName: 'Water',
        description: 'A full glass',
        schedule: schedule,
        createdAt: DateTime(2026, 11, 4, 8),
        updatedAt: DateTime(2026, 11, 4, 8, 30),
        activeSince: DateTime(2026, 11, 4, 8, 30),
        paused: true,
        archivedAt: DateTime(2026, 11, 6),
      );
      expect(Reminder.fromJson(viaJson(reminder.toJson())), reminder);
    });
  }

  test('runtime and history records survive a JSON round trip', () {
    final runtime = ReminderRuntime(
      reminderId: 'abc',
      processedUntil: DateTime(2026, 11, 4, 10),
      appliedAckUntil: DateTime(2026, 11, 4, 9, 30),
      pendingAt: DateTime(2026, 11, 4, 10),
      missedCount: 2,
      lastAcknowledgedAt: DateTime(2026, 11, 4, 9, 30),
    );
    expect(ReminderRuntime.fromJson(viaJson(runtime.toJson())), runtime);

    final record = ActivationRecord(
      reminderId: 'abc',
      scheduledAt: DateTime(2026, 11, 4, 9),
      status: ActivationStatus.acknowledged,
      acknowledgedAt: DateTime(2026, 11, 4, 9, 30),
    );
    expect(ActivationRecord.fromJson(viaJson(record.toJson())), record);
  });
}
