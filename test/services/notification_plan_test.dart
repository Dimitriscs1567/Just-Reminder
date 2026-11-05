import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/runtime_advance.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';
import 'package:just_reminder/src/services/notifications/notification_plan.dart';

final now = DateTime(2026, 11, 4, 8);
const engine = ScheduleEngine();
const recurrence = RepeatRecurrence(
  unit: RepeatUnit.day,
  startDate: LocalDate(2026, 11, 4),
);

DateTime nov(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute);

/// One time a day, 09:00–12:00, notifying every hour until done.
const hourly = Schedule(
  recurrence: recurrence,
  times: [
    ReminderTime(
      start: LocalTime(9, 0),
      end: LocalTime(12, 0),
      mode: NotifyMode.repeat,
      intervalMinutes: 60,
    ),
  ],
);

/// Three times a day, once each.
const threeTimes = Schedule(
  recurrence: recurrence,
  times: [
    ReminderTime(start: LocalTime(9, 0)),
    ReminderTime(start: LocalTime(12, 0)),
    ReminderTime(start: LocalTime(15, 0)),
  ],
);

const noon = Schedule(
  recurrence: recurrence,
  times: [ReminderTime(start: LocalTime(12, 0))],
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
  DateTime? at,
}) => planNotifications(
  reminders: reminders,
  runtimes: runtimes,
  engine: engine,
  now: at ?? now,
  budget: budget,
);

void main() {
  test('one notification per time, soonest first', () {
    final result = plan([reminder('a', noon)]);
    expect(result.first.at, nov(4, 12));
    expect(result.first.occurrenceStart, nov(4, 12));
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
      plan([reminder('a', noon, description: 'A full glass')]).first.body,
      'A full glass',
    );
  });

  test('a repeating time notifies several times for the same time', () {
    final day = plan([reminder('a', hourly)]).take(3).toList();
    // Before the end (12:00), when it is missed.
    expect([for (final n in day) n.at], [nov(4, 9), nov(4, 10), nov(4, 11)]);
    expect({for (final n in day) n.occurrenceStart}, {nov(4, 9)});
    // Repeats of one time never count as missed.
    expect([for (final n in day) n.missedBefore], [0, 0, 0]);
  });

  test('later times of a day count the earlier ones as missed', () {
    final result = plan([reminder('a', threeTimes)]).take(4).toList();
    expect([for (final n in result) n.missedBefore], [0, 1, 2, 0]);
    expect(result[1].subtitle, '1 missed');
    expect(result[3].at, nov(5, 9)); // a new day starts at 0
  });

  test('the due time notifies until done; nothing more once done', () {
    final created = reminder('a', hourly);
    final due = advanceReminder(
      reminder: created,
      runtime: ReminderRuntime.initial('a', now),
      engine: engine,
      now: nov(4, 9, 30),
    ).runtime;
    final firing = plan([created], runtimes: {'a': due}, at: nov(4, 9, 30));
    expect([for (final n in firing.take(3)) n.at], [
      nov(4, 10),
      nov(4, 11),
      nov(5, 9),
    ]);

    final done = advanceReminder(
      reminder: created,
      runtime: due,
      engine: engine,
      now: nov(4, 9, 30),
      acknowledgments: [nov(4, 9, 20)],
    ).runtime;
    final afterDone = plan([created], runtimes: {'a': done}, at: nov(4, 9, 30));
    expect(afterDone.first.at, nov(5, 9));
  });

  test('missed times of the day so far count too', () {
    final created = reminder('a', threeTimes);
    final runtime = advanceReminder(
      reminder: created,
      runtime: ReminderRuntime.initial('a', now),
      engine: engine,
      now: nov(4, 12, 30),
    ).runtime; // 09:00 missed, 12:00 due
    final result = plan([created], runtimes: {'a': runtime}, at: nov(4, 12, 30));
    expect(result.first.at, nov(4, 15));
    expect(result.first.missedBefore, 2); // 09:00 + the due 12:00
  });

  test('a notification is replaced when the next one arrives', () {
    final result = plan(
      [reminder('a', hourly)],
      budget: const NotificationBudget(total: 2),
    );
    expect(result[0].replacedAfter, const Duration(hours: 1));
    // The last scheduled one stays until it is done.
    expect(result[1].replacedAfter, isNull);
  });

  test('paused and archived reminders get nothing', () {
    expect(
      plan([
        reminder('p', noon, paused: true),
        reminder('x', noon, archivedAt: now),
      ]),
      isEmpty,
    );
  });

  test('the budget is shared fairly, then by time', () {
    final result = plan(
      [reminder('busy', hourly), reminder('calm', noon)],
      budget: const NotificationBudget(total: 8, minPerReminder: 3),
    );
    expect(result, hasLength(8));
    final calm = result.where((n) => n.reminderId == 'calm').toList();
    final busy = result.where((n) => n.reminderId == 'busy').toList();
    // "calm" keeps its next 3 although "busy" notifies far more often…
    expect(calm, hasLength(3));
    // …and each reminder gets its next ones without gaps.
    expect([for (final n in busy) n.at], [
      nov(4, 9),
      nov(4, 10),
      nov(4, 11),
      nov(5, 9),
      nov(5, 10),
    ]);
  });

  test('ids and payloads are stable and decodable', () {
    final first = plan([reminder('a', noon)]).first;
    final again = plan([reminder('a', noon)]).first;
    expect(first.id, again.id);
    expect(first.payloadFor(exact: true), again.payloadFor(exact: true));
    expect(first.id, notificationIdFor('a', nov(4, 12)));
    final decoded = decodeNotificationPayload(first.payloadFor(exact: true));
    expect(decoded?.reminderId, 'a');
    expect(decoded?.at, nov(4, 12));
    expect(decoded?.occurrenceStart, nov(4, 12));
    expect(decoded?.missedBefore, 0);
    expect(decodeNotificationPayload('not json'), isNull);
    expect(decodeNotificationPayload(null), isNull);
    // Payloads of older versions: one notification per time.
    final old = decodeNotificationPayload('{"r":"a","t":1,"h":2}');
    expect(old?.occurrenceStart, old?.at);
  });

  test('changed content changes the payload', () {
    final plain = plan([reminder('a', noon)]).first;
    final described = plan([reminder('a', noon, description: 'x')]).first;
    expect(described.id, plain.id);
    expect(
      described.payloadFor(exact: true),
      isNot(plain.payloadFor(exact: true)),
    );
  });
}
