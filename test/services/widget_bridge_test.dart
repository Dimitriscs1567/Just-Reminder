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
      timing: FixedTiming(LocalTime(9, 0)),
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
        'a': ReminderRuntime.initial('a', now).copyWith(
          pendingAt: DateTime(2026, 11, 4, 7),
          missedCount: 1,
        ),
      },
      engine: engine,
      now: now,
    );

    final a = snapshot('a');
    expect(a['state'], 'live');
    expect(a['displayName'], 'Show a');
    expect(a['pendingAt'], DateTime(2026, 11, 4, 7).millisecondsSinceEpoch);
    expect(a['missedCount'], 1);
    expect(
      (a['upcoming']! as List<Object?>).first,
      DateTime(2026, 11, 4, 9).millisecondsSinceEpoch,
    );
    expect(snapshot('b')['state'], 'archived');
    expect(snapshot('b')['upcoming'], isEmpty);
    // A widget still showing the deleted reminder keeps its name.
    expect(snapshot('gone')['state'], 'deleted');
    expect(snapshot('gone')['displayName'], 'Old one');

    expect(
      [for (final entry in await bridge.readIndex()) (entry.id, entry.archived)],
      [('a', false), ('b', true)],
    );
    expect(callsTo('updateWidget'), hasLength(1));
    expect(
      (callsTo('updateWidget').single.arguments as Map<Object?, Object?>)['ios'],
      WidgetBridge.iosKind,
    );
  });

  test('Android redraws at the upcoming activations, soonest first', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await bridge.publish(
      reminders: [reminder('a')],
      runtimes: const {},
      engine: engine,
      now: now,
    );

    final arguments =
        callsTo('scheduleWidgetUpdates').single.arguments
            as Map<Object?, Object?>;
    expect(arguments['qualifiedAndroidName'], WidgetBridge.androidProvider);
    final times = (arguments['updateTimes']! as List<Object?>).cast<int>();
    expect(times.first, DateTime(2026, 11, 4, 9).millisecondsSinceEpoch);
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
    expect(callsTo('updateWidget'), hasLength(1));
  });

  test('a widget is assigned to a reminder and redrawn', () async {
    await bridge.assignAndroidWidget(7, 'a');
    expect(storage[WidgetStorageKeys.androidWidget(7)], 'a');
    expect(callsTo('updateWidget'), hasLength(1));
  });
}
