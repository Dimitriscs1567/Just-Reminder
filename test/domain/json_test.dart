import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/occurrence_record.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/schedule.dart';

/// Round-trips through a JSON string, like storage does.
Map<String, Object?> viaJson(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  final schedules = <String, Schedule>{
    'once, one time': const Schedule(
      recurrence: OnceRecurrence(LocalDate(2026, 11, 5)),
      times: [ReminderTime(start: LocalTime(9, 0))],
    ),
    'weekly, several times': const Schedule(
      recurrence: RepeatRecurrence(
        unit: RepeatUnit.week,
        every: 2,
        startDate: LocalDate(2026, 11, 4),
        endDate: LocalDate(2027, 1, 31),
        weekdays: {5, 1, 3},
      ),
      times: [
        ReminderTime(
          start: LocalTime(9, 0),
          end: LocalTime(12, 0),
          mode: NotifyMode.repeat,
          intervalMinutes: 30,
          maxNotifications: 5,
        ),
        ReminderTime(start: LocalTime(14, 0), mode: NotifyMode.repeat),
      ],
    ),
    'monthly, random past midnight': const Schedule(
      recurrence: RepeatRecurrence(
        unit: RepeatUnit.month,
        startDate: LocalDate(2026, 11, 4),
        dayOfMonth: 31,
      ),
      times: [
        ReminderTime(
          start: LocalTime(22, 0),
          end: LocalTime(2, 0),
          mode: NotifyMode.random,
          randomCount: 3,
        ),
      ],
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

  test('the order of times does not matter', () {
    const a = ReminderTime(start: LocalTime(9, 0));
    const b = ReminderTime(start: LocalTime(15, 0));
    const recurrence = OnceRecurrence(LocalDate(2026, 11, 5));
    expect(
      const Schedule(recurrence: recurrence, times: [a, b]),
      const Schedule(recurrence: recurrence, times: [b, a]),
    );
  });

  test('runtime and history records survive a JSON round trip', () {
    final runtime = ReminderRuntime(
      reminderId: 'abc',
      processedUntil: DateTime(2026, 11, 4, 10),
      appliedAckUntil: DateTime(2026, 11, 4, 9, 30),
      pending: PendingOccurrence(
        date: const LocalDate(2026, 11, 4),
        time: const ReminderTime(
          start: LocalTime(9, 0),
          end: LocalTime(12, 0),
          mode: NotifyMode.random,
        ),
        start: DateTime(2026, 11, 4, 9),
        dueAt: DateTime(2026, 11, 4, 9, 47),
        end: DateTime(2026, 11, 4, 12),
      ),
      missedDate: const LocalDate(2026, 11, 4),
      missedCount: 2,
      last: LastOutcome(
        date: const LocalDate(2026, 11, 4),
        start: DateTime(2026, 11, 4, 8),
        status: OccurrenceStatus.done,
        at: DateTime(2026, 11, 4, 8, 15),
      ),
    );
    expect(ReminderRuntime.fromJson(viaJson(runtime.toJson())), runtime);

    final record = OccurrenceRecord(
      reminderId: 'abc',
      start: DateTime(2026, 11, 4, 9),
      end: DateTime(2026, 11, 4, 12),
      dueAt: DateTime(2026, 11, 4, 9, 47),
      status: OccurrenceStatus.done,
      doneAt: DateTime(2026, 11, 4, 10),
    );
    expect(OccurrenceRecord.fromJson(viaJson(record.toJson())), record);
  });

  group('data stored before several times per reminder', () {
    final ms = DateTime(2026, 11, 4, 9).millisecondsSinceEpoch;

    test('a fixed time or a range becomes one time', () {
      Schedule read(Map<String, Object?> timing) => Schedule.fromJson({
        'recurrence': {'type': 'once', 'date': '2026-11-05'},
        'timing': timing,
      });
      expect(read({'type': 'fixed', 'time': '09:00'}).times, const [
        ReminderTime(start: LocalTime(9, 0)),
      ]);
      expect(
        read({
          'type': 'range',
          'start': '09:00',
          'end': '17:00',
          'mode': 'interval',
          'intervalMinutes': 30,
          'maxActivations': 4,
        }).times,
        const [
          ReminderTime(
            start: LocalTime(9, 0),
            end: LocalTime(17, 0),
            mode: NotifyMode.repeat,
            intervalMinutes: 30,
            maxNotifications: 4,
          ),
        ],
      );
      expect(
        read({
          'type': 'range',
          'start': '22:00',
          'end': '02:00',
          'mode': 'random',
          'intervalMinutes': 60,
          'maxActivations': 3,
        }).times,
        const [
          ReminderTime(
            start: LocalTime(22, 0),
            end: LocalTime(2, 0),
            mode: NotifyMode.random,
            randomCount: 3,
          ),
        ],
      );
    });

    test('a waiting activation stays due; the missed count starts over', () {
      final runtime = ReminderRuntime.fromJson({
        'reminderId': 'abc',
        'processedUntil': ms,
        'appliedAckUntil': ms,
        'pendingAt': ms,
        'missedCount': 3,
        'lastAcknowledgedAt': null,
      });
      expect(runtime.pending?.start, DateTime(2026, 11, 4, 9));
      expect(runtime.pending?.dueAt, DateTime(2026, 11, 4, 9));
      expect(runtime.pending?.date, const LocalDate(2026, 11, 4));
      expect(runtime.missedCount, 0);
    });

    test('acknowledged history entries read as done', () {
      final record = OccurrenceRecord.fromJson({
        'reminderId': 'abc',
        'scheduledAt': ms,
        'status': 'acknowledged',
        'acknowledgedAt': ms + 60000,
      });
      expect(record.start, DateTime(2026, 11, 4, 9));
      expect(record.dueAt, DateTime(2026, 11, 4, 9));
      expect(record.end, isNull);
      expect(record.status, OccurrenceStatus.done);
      expect(record.doneAt, DateTime(2026, 11, 4, 9, 1));
    });
  });
}
