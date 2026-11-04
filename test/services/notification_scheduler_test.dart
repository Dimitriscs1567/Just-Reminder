import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/services/notifications/notification_plan.dart';
import 'package:just_reminder/src/services/notifications/notification_scheduler.dart';

final now = DateTime(2026, 11, 4, 8);

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
}

PlannedNotification planned(
  String reminderId,
  int hour, {
  int missed = 0,
  String body = 'Body',
}) => PlannedNotification(
  reminderId: reminderId,
  at: DateTime(2026, 11, 4, hour),
  title: 'Title',
  body: body,
  missedBefore: missed,
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
    Map<String, DateTime> waitingSince = const {},
    bool exact = true,
  }) => scheduler.apply(
    plan,
    now: now,
    waitingSince: waitingSince,
    exact: exact,
  );

  test('a change between exact and inexact alarms reschedules all', () async {
    final plan = [planned('a', 9), planned('a', 10, missed: 1)];
    await apply(plan, exact: false);
    expect(gateway.exactById.values, everyElement(isFalse));

    // E.g. the user just allowed "Alarms & reminders".
    await apply(plan);
    expect(gateway.scheduleCalls, 4);
    expect(gateway.exactById.values, everyElement(isTrue));
  });

  test('schedules the plan and leaves unchanged notifications alone', () async {
    final plan = [planned('a', 9), planned('a', 10, missed: 1)];
    await apply(plan);
    expect(gateway.scheduled.keys, unorderedEquals(plan.map((n) => n.id)));
    expect(gateway.scheduleCalls, 2);

    await apply(plan);
    expect(gateway.scheduleCalls, 2);
    expect(gateway.cancelled, isEmpty);
  });

  test('changed content is rescheduled, dropped ones are cancelled', () async {
    await apply([planned('a', 9), planned('b', 10)]);
    await apply([planned('a', 9, body: 'New text')]);

    expect(gateway.scheduled.values.single.body, 'New text');
    expect(gateway.cancelled, contains(planned('b', 10).id));
  });

  test('a late notification of the waiting activation is kept', () async {
    final late = planned('a', 7); // 07:00, still pending at 08:00
    gateway.scheduled[late.id] = late;

    await apply(const [], waitingSince: {'a': DateTime(2026, 11, 4, 7)});
    expect(gateway.scheduled, contains(late.id));

    // Once acknowledged, it goes.
    await apply(const []);
    expect(gateway.scheduled, isNot(contains(late.id)));
  });

  test('shown notifications of reminders that are not waiting are removed', () async {
    final a = planned('a', 7);
    final b = planned('b', 7);
    gateway.shown.addAll([shownFor(a), shownFor(b)]);

    await scheduler.clearDeliveredExcept({'a'});
    expect(gateway.shown.map((n) => n.id), [a.id]);

    await scheduler.clearDelivered('a');
    expect(gateway.shown, isEmpty);
  });

  test('after an acknowledgment the missed counts start over', () async {
    await apply([
      planned('a', 9, missed: 2),
      planned('a', 10, missed: 3),
      planned('b', 9, missed: 5),
    ]);
    await scheduler.renumberAfterAcknowledgment('a', now: now, exact: true);

    final a = gateway.scheduled.values.where((n) => n.reminderId == 'a').toList()
      ..sort((x, y) => x.at.compareTo(y.at));
    expect([for (final n in a) n.missedBefore], [0, 1]);
    expect(a.first.replacedAfter, const Duration(hours: 1));
    // Other reminders are untouched.
    expect(
      gateway.scheduled.values.singleWhere((n) => n.reminderId == 'b').missedBefore,
      5,
    );
  });
}
