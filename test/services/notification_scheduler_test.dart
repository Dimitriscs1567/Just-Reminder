import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/services/notifications/notification_plan.dart';
import 'package:just_reminder/src/services/notifications/notification_scheduler.dart';

final now = DateTime(2026, 11, 4, 8);

DateTime nov(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute);

class FakeGateway implements NotificationGateway {
  final scheduled = <int, PlannedNotification>{};
  final exactById = <int, bool>{};
  final shown = <ActiveNotification>[];
  final cancelled = <int>[];
  var scheduleCalls = 0;

  @override
  Future<List<PendingNotificationRequest>> pending() async => [
    for (final n in scheduled.values)
      PendingNotificationRequest(
        n.id,
        n.title,
        n.body,
        n.payloadFor(exact: exactById[n.id] ?? true),
      ),
  ];

  @override
  Future<List<ActiveNotification>> active() async => List.of(shown);

  @override
  Future<void> schedule(
    PlannedNotification notification, {
    required bool exact,
  }) async {
    scheduleCalls++;
    scheduled[notification.id] = notification;
    exactById[notification.id] = exact;
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelled.add(id);
    scheduled.remove(id);
    shown.removeWhere((notification) => notification.id == id);
  }

  /// The pending notifications of [reminderId] by time.
  List<PlannedNotification> of(String reminderId) => [
    for (final n in scheduled.values)
      if (n.reminderId == reminderId) n,
  ]..sort((a, b) => a.at.compareTo(b.at));
}

/// A notification at [at] for the time that started at [start].
PlannedNotification planned(
  String reminderId,
  DateTime at, {
  DateTime? start,
  int missed = 0,
  String body = 'Body',
  Duration? replacedAfter,
}) => PlannedNotification(
  reminderId: reminderId,
  at: at,
  occurrenceStart: start ?? at,
  title: 'Title',
  body: body,
  missedBefore: missed,
  replacedAfter: replacedAfter,
);

ActiveNotification shownFor(PlannedNotification notification) =>
    ActiveNotification(
      id: notification.id,
      tag: notification.reminderId,
      payload: notification.payloadFor(exact: true),
    );

void main() {
  late FakeGateway gateway;
  late NotificationScheduler scheduler;

  setUp(() {
    gateway = FakeGateway();
    scheduler = NotificationScheduler(gateway);
  });

  Future<void> apply(
    List<PlannedNotification> plan, {
    Map<String, DateTime> dueStarts = const {},
    bool exact = true,
  }) => scheduler.apply(plan, now: now, dueStarts: dueStarts, exact: exact);

  test('a change between exact and inexact alarms reschedules all', () async {
    final plan = [planned('a', nov(4, 9)), planned('a', nov(4, 10), missed: 1)];
    await apply(plan, exact: false);
    expect(gateway.exactById.values, everyElement(isFalse));

    // E.g. the user just allowed "Alarms & reminders".
    await apply(plan);
    expect(gateway.scheduleCalls, 4);
    expect(gateway.exactById.values, everyElement(isTrue));
  });

  test('schedules the plan and leaves unchanged notifications alone', () async {
    final plan = [planned('a', nov(4, 9)), planned('a', nov(4, 10), missed: 1)];
    await apply(plan);
    expect(gateway.scheduled.keys, unorderedEquals(plan.map((n) => n.id)));
    expect(gateway.scheduleCalls, 2);

    await apply(plan);
    expect(gateway.scheduleCalls, 2);
    expect(gateway.cancelled, isEmpty);
  });

  test('changed content is rescheduled, dropped ones are cancelled', () async {
    await apply([planned('a', nov(4, 9)), planned('b', nov(4, 10))]);
    await apply([planned('a', nov(4, 9), body: 'New text')]);

    expect(gateway.scheduled.values.single.body, 'New text');
    expect(gateway.cancelled, contains(planned('b', nov(4, 10)).id));
  });

  test('a late notification of the due time is kept', () async {
    // 07:30, a repeat of the 07:00 time, still pending at 08:00.
    final late = planned('a', nov(4, 7, 30), start: nov(4, 7));
    gateway.scheduled[late.id] = late;

    await apply(const [], dueStarts: {'a': nov(4, 7)});
    expect(gateway.scheduled, contains(late.id));

    // Once it is done, it goes.
    await apply(const []);
    expect(gateway.scheduled, isNot(contains(late.id)));
  });

  test('shown notifications of reminders with nothing due are removed',
      () async {
    final a = planned('a', nov(4, 7));
    final b = planned('b', nov(4, 7));
    gateway.shown.addAll([shownFor(a), shownFor(b)]);

    await scheduler.clearDeliveredExcept({'a'});
    expect(gateway.shown.map((n) => n.id), [a.id]);

    await scheduler.clearDelivered('a');
    expect(gateway.shown, isEmpty);
  });

  test('Done outside the app stops the time and lowers the day’s counts',
      () async {
    await apply([
      // The 09:00 time repeats at 10:00 and 11:00…
      planned('a', nov(4, 10), start: nov(4, 9), missed: 1),
      planned('a', nov(4, 11), start: nov(4, 9), missed: 1),
      // …then 12:00 counted 09:00 as missed, tomorrow starts over.
      planned('a', nov(4, 12), missed: 2),
      planned('a', nov(5, 9)),
      planned('b', nov(4, 12), missed: 5),
    ]);
    await scheduler.afterDoneOutsideApp(
      'a',
      occurrenceStart: nov(4, 9),
      now: nov(4, 9, 30),
      exact: true,
    );

    final a = gateway.of('a');
    expect([for (final n in a) n.at], [nov(4, 12), nov(5, 9)]);
    expect([for (final n in a) n.missedBefore], [1, 0]);
    expect(a.first.replacedAfter, const Duration(hours: 21));
    // Other reminders are untouched.
    expect(gateway.of('b').single.missedBefore, 5);
  });
}
