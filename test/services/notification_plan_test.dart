import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';
import 'package:just_reminder/src/services/notifications/notification_plan.dart';

final now = DateTime(2026, 11, 4, 8);
const engine = ScheduleEngine();

/// Every hour from 09:00 to 17:00, every day.
const hourly = Schedule(
  recurrence: RepeatRecurrence(
    unit: RepeatUnit.day,
    startDate: LocalDate(2026, 11, 4),
  ),
  timing: RangeTiming(
    start: LocalTime(9, 0),
    end: LocalTime(17, 0),
    mode: RangeMode.interval,
  ),
);

const daily = Schedule(
  recurrence: RepeatRecurrence(
    unit: RepeatUnit.day,
    startDate: LocalDate(2026, 11, 4),
  ),
  timing: FixedTiming(LocalTime(12, 0)),
);

Reminder reminder(
  String id,
  Schedule schedule, {
  String? description,
  bool paused = false,
  DateTime? archivedAt,
}) => Reminder(
  id: id,
  name: 'Name $id',
  displayName: 'Show $id',
  description: description,
  schedule: schedule,
  createdAt: now,
  updatedAt: now,
  activeSince: now,
  paused: paused,
  archivedAt: archivedAt,
);

List<PlannedNotification> plan(
  List<Reminder> reminders, {
  Map<String, ReminderRuntime> runtimes = const {},
  NotificationBudget budget = const NotificationBudget(total: 50),
}) => planNotifications(
  reminders: reminders,
  runtimes: runtimes,
  engine: engine,
  now: now,
  budget: budget,
);

void main() {
  test('one notification per upcoming activation, soonest first', () {
    final result = plan([reminder('a', daily)]);
    expect(result.first.at, DateTime(2026, 11, 4, 12));
    expect(result.first.title, 'Show a');
    expect(result.first.body, defaultNotificationBody);
    expect(
      [for (final n in result) n.at],
      orderedEquals([...result.map((n) => n.at)]..sort()),
    );
    // 14 days ahead by default.
    expect(result, hasLength(14));
  });

  test('the description becomes the text', () {
    expect(
      plan([reminder('a', daily, description: 'A full glass')]).first.body,
      'A full glass',
    );
  });

  test('later notifications count the ones that would be missed', () {
    final result = plan([reminder('a', hourly)]).take(3).toList();
    expect([for (final n in result) n.missedBefore], [0, 1, 2]);
    expect(result[0].subtitle, isNull);
    expect(result[1].subtitle, '1 missed');
  });

  test('a waiting reminder starts counting from its missed activations', () {
    final runtime = ReminderRuntime.initial('a', now).copyWith(
      pendingAt: DateTime(2026, 11, 4, 7),
      missedCount: 2,
    );
    final result = plan([reminder('a', hourly)], runtimes: {'a': runtime});
    expect(result.first.missedBefore, 3); // 2 missed + the waiting one
  });

  test('a notification is replaced when the next one arrives', () {
    final result = plan(
      [reminder('a', hourly)],
      budget: const NotificationBudget(total: 2),
    );
    expect(result[0].replacedAfter, const Duration(hours: 1));
    // The last scheduled one stays until acknowledged.
    expect(result[1].replacedAfter, isNull);
  });

  test('paused and archived reminders get nothing', () {
    expect(
      plan([
        reminder('p', daily, paused: true),
        reminder('x', daily, archivedAt: now),
      ]),
      isEmpty,
    );
  });

  test('the budget is shared fairly, then by time', () {
    final result = plan(
      [reminder('busy', hourly), reminder('calm', daily)],
      budget: const NotificationBudget(total: 8, minPerReminder: 3),
    );
    expect(result, hasLength(8));
    final calm = result.where((n) => n.reminderId == 'calm').toList();
    final busy = result.where((n) => n.reminderId == 'busy').toList();
    // "calm" keeps its next 3 although "busy" fires far more often…
    expect(calm, hasLength(3));
    // …and each reminder gets its next activations without gaps.
    expect(busy.first.at, DateTime(2026, 11, 4, 9));
    expect(
      [for (final n in busy) n.missedBefore],
      [for (var i = 0; i < busy.length; i++) i],
    );
  });

  test('ids and payloads are stable and decodable', () {
    final first = plan([reminder('a', daily)]).first;
    final again = plan([reminder('a', daily)]).first;
    expect(first.id, again.id);
    expect(first.payloadFor(exact: true), again.payloadFor(exact: true));
    expect(first.id, notificationIdFor('a', DateTime(2026, 11, 4, 12)));
    final decoded = decodeNotificationPayload(first.payloadFor(exact: true));
    expect(decoded?.reminderId, 'a');
    expect(decoded?.at, DateTime(2026, 11, 4, 12));
    expect(decodeNotificationPayload('not json'), isNull);
    expect(decodeNotificationPayload(null), isNull);
  });

  test('changed content changes the payload', () {
    final plain = plan([reminder('a', daily)]).first;
    final described = plan([reminder('a', daily, description: 'x')]).first;
    expect(described.id, plain.id);
    expect(described.payloadFor(exact: true), isNot(plain.payloadFor(exact: true)));
  });
}
