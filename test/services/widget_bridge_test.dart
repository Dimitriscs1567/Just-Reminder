import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/domain/schedule_engine.dart';
import 'package:just_reminder/src/services/widget/widget_bridge.dart';
import 'package:just_reminder/src/services/widget_storage_keys.dart';

/// What the app writes for the native widgets (Kotlin / Swift read it), with
/// home_widget's platform channel replaced by an in-memory store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('home_widget');
  const bridge = WidgetBridge();
  const engine = ScheduleEngine();
  final now = DateTime(2026, 11, 4, 8);
  final storage = <String, Object?>{};
  final calls = <MethodCall>[];

  setUp(() {
    storage.clear();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final arguments = call.arguments as Map<Object?, Object?>?;
          switch (call.method) {
            case 'saveWidgetData':
              storage[arguments!['id']! as String] = arguments['data'];
              return true;
            case 'getWidgetData':
              return storage[arguments!['id']! as String] ??
                  arguments['defaultValue'];
            default:
              return true;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Reminder reminder(String id, {DateTime? archivedAt}) => Reminder(
    id: id,
    name: 'Name $id',
    displayName: 'Show $id',
    schedule: const Schedule(
      recurrence: RepeatRecurrence(
        unit: RepeatUnit.day,
        startDate: LocalDate(2026, 11, 4),
      ),
      times: [ReminderTime(start: LocalTime(9, 0))],
    ),
    createdAt: now,
    updatedAt: now,
    activeSince: now,
    archivedAt: archivedAt,
  );

  Map<String, Object?> snapshot(String id) =>
      jsonDecode(storage[WidgetStorageKeys.snapshot(id)]! as String)
          as Map<String, Object?>;

  Iterable<MethodCall> callsTo(String method) =>
      calls.where((call) => call.method == method);

  test('writes snapshots, the index and tombstones for deleted reminders', () async {
    // "gone" was published earlier and has been deleted since.
    storage[WidgetStorageKeys.index] = jsonEncode([
      {'id': 'gone', 'name': 'Old', 'displayName': 'Old one', 'archived': false},
    ]);

    await bridge.publish(
      reminders: [reminder('a'), reminder('b', archivedAt: now)],
      runtimes: {
        // 07:00 is due (until the next time, 09:00); one time was missed.
        'a': ReminderRuntime.initial('a', now).copyWith(
          pending: PendingOccurrence(
            date: const LocalDate(2026, 11, 4),
            time: const ReminderTime(start: LocalTime(7, 0)),
            start: DateTime(2026, 11, 4, 7),
            dueAt: DateTime(2026, 11, 4, 7),
          ),
          missedDate: const LocalDate(2026, 11, 4),
          missedCount: 1,
        ),
      },
      engine: engine,
      now: now,
    );

    final a = snapshot('a');
    expect(a['v'], 2);
    expect(a['state'], 'live');
    expect(a['displayName'], 'Show a');
    expect(a['pending'], {
      'date': '2026-11-04',
      'start': DateTime(2026, 11, 4, 7).millisecondsSinceEpoch,
      'due': DateTime(2026, 11, 4, 7).millisecondsSinceEpoch,
      'missesAt': DateTime(2026, 11, 4, 9).millisecondsSinceEpoch,
    });
    expect(a['missed'], {'date': '2026-11-04', 'count': 1});
    expect(
      ((a['occurrences']! as List<Object?>).first! as Map<Object?, Object?>)['due'],
      DateTime(2026, 11, 4, 9).millisecondsSinceEpoch,
    );
    expect(snapshot('b')['state'], 'archived');
    expect(snapshot('b')['occurrences'], isEmpty);
    // A widget still showing the deleted reminder keeps its name.
    expect(snapshot('gone')['state'], 'deleted');
    expect(snapshot('gone')['displayName'], 'Old one');

    expect(
      [for (final entry in await bridge.readIndex()) (entry.id, entry.archived)],
      [('a', false), ('b', true)],
    );
    // Both widgets: the one-reminder widget and the list widget.
    expect(
      [
        for (final call in callsTo('updateWidget'))
          (
            (call.arguments as Map<Object?, Object?>)['qualifiedAndroidName'],
            (call.arguments as Map<Object?, Object?>)['ios'],
          ),
      ],
      [
        (WidgetBridge.androidProvider, WidgetBridge.iosKind),
        (WidgetBridge.androidListProvider, WidgetBridge.iosListKind),
      ],
    );
  });

  test('Android redraws both widgets at the next changes, soonest first', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await bridge.publish(
      reminders: [reminder('a')],
      runtimes: const {},
      engine: engine,
      now: now,
    );

    final schedules = [
      for (final call in callsTo('scheduleWidgetUpdates'))
        call.arguments as Map<Object?, Object?>,
    ];
    expect([for (final arguments in schedules) arguments['qualifiedAndroidName']], [
      WidgetBridge.androidProvider,
      WidgetBridge.androidListProvider,
    ]);
    final times = (schedules.first['updateTimes']! as List<Object?>)
        .cast<int>();
    expect(schedules.last['updateTimes'], times);
    // 09:00 becomes due, then the day changes (09:00 is missed tomorrow).
    expect(times.take(2), [
      DateTime(2026, 11, 4, 9).millisecondsSinceEpoch,
      DateTime(2026, 11, 5).millisecondsSinceEpoch,
    ]);
    expect(times, orderedEquals([...times]..sort()));
  });

  test('iOS needs no scheduled redraws (the timeline has an entry per time)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await bridge.publish(
      reminders: [reminder('a')],
      runtimes: const {},
      engine: engine,
      now: now,
    );
    expect(callsTo('scheduleWidgetUpdates'), isEmpty);
    expect(callsTo('updateWidget'), hasLength(2));
  });

  test('a widget is assigned to a reminder and redrawn', () async {
    await bridge.assignAndroidWidget(7, 'a');
    expect(storage[WidgetStorageKeys.androidWidget(7)], 'a');
    expect(callsTo('updateWidget'), hasLength(2));
  });

  test('a list widget keeps its reminders in the order picked', () async {
    expect(await bridge.readAndroidList(8), isEmpty);
    await bridge.assignAndroidList(8, ['c', 'a', 'b']);
    expect(storage[WidgetStorageKeys.androidListWidget(8)], '["c","a","b"]');
    expect(await bridge.readAndroidList(8), ['c', 'a', 'b']);
    expect(callsTo('updateWidget'), hasLength(2));
  });
}
