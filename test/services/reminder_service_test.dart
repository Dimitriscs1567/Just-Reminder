import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/data/reminder_repository.dart';
import 'package:just_reminder/src/domain/activation.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/services/ack_inbox.dart';
import 'package:just_reminder/src/services/reminder_service.dart';
import 'package:sembast/sembast_memory.dart';

const nov4 = LocalDate(2026, 11, 4);

const dailyAtNine = Schedule(
  recurrence: RepeatRecurrence(unit: RepeatUnit.day, startDate: nov4),
  timing: FixedTiming(LocalTime(9, 0)),
);

/// 09:00, 10:00, 11:00 and 12:00 every day.
const hourlyNineToNoon = Schedule(
  recurrence: RepeatRecurrence(unit: RepeatUnit.day, startDate: nov4),
  timing: RangeTiming(
    start: LocalTime(9, 0),
    end: LocalTime(12, 0),
    mode: RangeMode.interval,
  ),
);

Schedule onceAtNine(LocalDate date) => Schedule(
  recurrence: OnceRecurrence(date),
  timing: const FixedTiming(LocalTime(9, 0)),
);

DateTime nov(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute);

void main() {
  late Database db;
  late ReminderRepository repository;
  late MemoryAckInbox inbox;
  late DateTime now;
  late ReminderService service;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
    repository = ReminderRepository(db);
    inbox = MemoryAckInbox();
    now = nov(4, 8);
    service = ReminderService(
      repository: repository,
      inbox: inbox,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  Future<Reminder> create(Schedule schedule) => service.create(
    name: 'Drink water',
    displayName: 'Water',
    schedule: schedule,
  );

  Future<List<ActivationRecord>> history(String id) =>
      repository.getHistory(id);

  ActivationRecord rec(
    String id,
    DateTime scheduledAt,
    ActivationStatus status, [
    DateTime? acknowledgedAt,
  ]) => ActivationRecord(
    reminderId: id,
    scheduledAt: scheduledAt,
    status: status,
    acknowledgedAt: acknowledgedAt,
  );

  test('create trims text and drops an empty description', () async {
    final reminder = await service.create(
      name: '  Drink water ',
      displayName: ' Water ',
      description: '   ',
      schedule: dailyAtNine,
    );
    expect(reminder.name, 'Drink water');
    expect(reminder.displayName, 'Water');
    expect(reminder.description, isNull);
    expect((await repository.getRuntime(reminder.id))?.isActive, isFalse);
  });

  test('an activation makes the reminder active', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 1);
    await service.syncAll();

    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.pendingAt, nov(4, 9));
    expect(await history(reminder.id), [
      rec(reminder.id, nov(4, 9), ActivationStatus.pending),
    ]);
  });

  test('acknowledging clears it and records when', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 5);
    await service.acknowledge(reminder.id);

    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.isActive, isFalse);
    expect(runtime?.lastAcknowledgedAt, nov(4, 9, 5));
    expect(await history(reminder.id), [
      rec(reminder.id, nov(4, 9), ActivationStatus.acknowledged, nov(4, 9, 5)),
    ]);
  });

  test('a new activation while waiting marks the previous one missed', () async {
    final reminder = await create(hourlyNineToNoon);
    now = nov(4, 10, 1);
    await service.syncAll();
    expect((await repository.getRuntime(reminder.id))?.missedCount, 1);

    now = nov(4, 10, 2);
    await service.acknowledge(reminder.id);
    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.isActive, isFalse);
    expect(runtime?.missedCount, 0);
    expect(await history(reminder.id), [
      rec(reminder.id, nov(4, 10), ActivationStatus.acknowledged, nov(4, 10, 2)),
      rec(reminder.id, nov(4, 9), ActivationStatus.missed),
    ]);
  });

  test('acknowledgments logged elsewhere are applied in time order', () async {
    final reminder = await create(hourlyNineToNoon);
    // E.g. tapped on the widget while the app was closed.
    await inbox.add(reminder.id, nov(4, 9, 30));
    now = nov(4, 10, 30);
    await service.syncAll();

    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.pendingAt, nov(4, 10));
    expect(runtime?.missedCount, 0);
    expect(await history(reminder.id), [
      rec(reminder.id, nov(4, 10), ActivationStatus.pending),
      rec(reminder.id, nov(4, 9), ActivationStatus.acknowledged, nov(4, 9, 30)),
    ]);
  });

  test('syncing twice changes nothing the second time', () async {
    final reminder = await create(hourlyNineToNoon);
    now = nov(4, 10, 1);
    await service.syncAll();
    await service.syncAll();
    expect(await history(reminder.id), hasLength(2));
    expect((await repository.getRuntime(reminder.id))?.missedCount, 1);
  });

  test('editing keeps a waiting activation and the new schedule starts now', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 30);
    await service.syncAll();

    // 09:15 today is already in the past, so it does not happen.
    await service.update(
      reminder.copyWith(
        schedule: dailyAtNine.copyWith(
          timing: const FixedTiming(LocalTime(9, 15)),
        ),
      ),
    );
    expect((await repository.getRuntime(reminder.id))?.pendingAt, nov(4, 9));

    now = nov(5, 9, 20);
    await service.syncAll();
    expect(await history(reminder.id), [
      rec(reminder.id, nov(5, 9, 15), ActivationStatus.pending),
      rec(reminder.id, nov(4, 9), ActivationStatus.missed),
    ]);
  });

  test('pausing stops activations; resuming does not catch up', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 8, 30);
    await service.setPaused(reminder.id, paused: true);

    now = nov(6, 10);
    await service.syncAll();
    expect(await history(reminder.id), isEmpty);

    await service.setPaused(reminder.id, paused: false);
    now = nov(7, 9, 1);
    await service.syncAll();
    expect(await history(reminder.id), [
      rec(reminder.id, nov(7, 9), ActivationStatus.pending),
    ]);
  });

  test('pausing keeps a waiting activation waiting', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 10);
    await service.syncAll();
    await service.setPaused(reminder.id, paused: true);
    expect((await repository.getRuntime(reminder.id))?.pendingAt, nov(4, 9));
  });

  test('archiving records a waiting activation as missed', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 10);
    await service.syncAll();
    await service.archive(reminder.id);

    expect((await repository.getReminder(reminder.id))?.isArchived, isTrue);
    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.isActive, isFalse);
    expect(await history(reminder.id), [
      rec(reminder.id, nov(4, 9), ActivationStatus.missed),
    ]);

    // Archived reminders never activate.
    now = nov(6, 12);
    await service.syncAll();
    expect(await history(reminder.id), hasLength(1));
  });

  test('restoring brings it back without replaying the archived time', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 10);
    await service.syncAll();
    await service.archive(reminder.id);

    now = nov(6, 8);
    final restored = await service.restore(reminder.id);
    expect(restored.isArchived, isFalse);
    expect((await repository.getRuntime(reminder.id))?.missedCount, 0);

    now = nov(6, 9, 1);
    await service.syncAll();
    expect(await history(reminder.id), [
      rec(reminder.id, nov(6, 9), ActivationStatus.pending),
      rec(reminder.id, nov(4, 9), ActivationStatus.missed),
    ]);
  });

  test('a finished one-time reminder is archived once acknowledged', () async {
    final reminder = await create(onceAtNine(nov4));
    now = nov(5, 12);
    await service.syncAll();
    // Still waiting, so it stays in the list even after its date.
    var stored = await repository.getReminder(reminder.id);
    expect(stored?.isArchived, isFalse);

    await service.acknowledge(reminder.id);
    stored = await repository.getReminder(reminder.id);
    expect(stored?.isArchived, isTrue);
    expect(await history(reminder.id), [
      rec(reminder.id, nov(4, 9), ActivationStatus.acknowledged, nov(5, 12)),
    ]);
  });

  test('a repeating reminder past its end date is archived', () async {
    final reminder = await create(
      const Schedule(
        recurrence: RepeatRecurrence(
          unit: RepeatUnit.day,
          startDate: nov4,
          endDate: nov4,
        ),
        timing: FixedTiming(LocalTime(9, 0)),
      ),
    );
    now = nov(4, 9, 5);
    await service.acknowledge(reminder.id);
    expect((await repository.getReminder(reminder.id))?.isArchived, isTrue);
  });

  test('a paused one-time reminder whose date passed is archived', () async {
    final reminder = await create(onceAtNine(const LocalDate(2026, 11, 5)));
    await service.setPaused(reminder.id, paused: true);
    now = nov(5, 10);
    await service.syncAll();

    expect((await repository.getReminder(reminder.id))?.isArchived, isTrue);
    // It was paused at 09:00, so it never activated.
    expect(await history(reminder.id), isEmpty);
  });

  test('restoring with edits uses the new schedule', () async {
    final reminder = await create(onceAtNine(nov4));
    now = nov(4, 9, 5);
    await service.acknowledge(reminder.id); // finished -> archived

    now = nov(10, 8);
    await service.restore(
      reminder.id,
      edited: reminder.copyWith(schedule: onceAtNine(const LocalDate(2026, 11, 11))),
    );
    now = nov(11, 9, 1);
    await service.syncAll();
    expect((await repository.getRuntime(reminder.id))?.pendingAt, nov(11, 9));
  });

  test('deleting removes the reminder, its runtime, history and log', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 5);
    await service.acknowledge(reminder.id);
    await service.delete(reminder.id);

    expect(await repository.getReminder(reminder.id), isNull);
    expect(await repository.getRuntime(reminder.id), isNull);
    expect(await history(reminder.id), isEmpty);
    expect(await inbox.read(reminder.id), isEmpty);
  });
}
