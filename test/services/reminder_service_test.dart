import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/data/reminder_repository.dart';
import 'package:just_reminder/src/domain/occurrence_record.dart';
import 'package:just_reminder/src/domain/reminder.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/services/ack_inbox.dart';
import 'package:just_reminder/src/services/reminder_service.dart';
import 'package:sembast/sembast_memory.dart';

const nov4 = LocalDate(2026, 11, 4);
const daily = RepeatRecurrence(unit: RepeatUnit.day, startDate: nov4);
const nineAm = ReminderTime(start: LocalTime(9, 0));

const dailyAtNine = Schedule(recurrence: daily, times: [nineAm]);

/// 09:00 (until the next time) and 12:00–13:00 every 30 minutes.
const nineAndNoon = Schedule(
  recurrence: daily,
  times: [
    nineAm,
    ReminderTime(
      start: LocalTime(12, 0),
      end: LocalTime(13, 0),
      mode: NotifyMode.repeat,
      intervalMinutes: 30,
    ),
  ],
);

Schedule onceAtNine(LocalDate date) =>
    Schedule(recurrence: OnceRecurrence(date), times: const [nineAm]);

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

  /// The history as `HH:mm status` (plus the done time), newest first.
  Future<List<String>> history(String id) async => [
    for (final record in await repository.getHistory(id))
      '${record.start.day}/${_hm(record.start)} ${record.status.name}'
          '${record.doneAt == null ? '' : ' ${_hm(record.doneAt!)}'}',
  ];

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
    expect((await repository.getRuntime(reminder.id))?.isFiring, isFalse);
  });

  test('a time becomes due', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 1);
    await service.syncAll();

    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.pending?.start, nov(4, 9));
    expect(await history(reminder.id), ['4/09:00 pending']);
  });

  test('Done finishes it and records when', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 5);
    await service.markDone(reminder.id);

    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.isFiring, isFalse);
    expect(runtime?.last?.status, OccurrenceStatus.done);
    expect(await history(reminder.id), ['4/09:00 done 09:05']);
  });

  test('missed when the next time starts, or at its end', () async {
    final reminder = await create(nineAndNoon);
    now = nov(4, 12, 10);
    await service.syncAll();
    expect(await history(reminder.id), ['4/12:00 pending', '4/09:00 missed']);

    now = nov(4, 13, 5);
    await service.syncAll();
    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.isFiring, isFalse);
    expect(runtime?.missedOn(nov4), 2);
    expect(await history(reminder.id), ['4/12:00 missed', '4/09:00 missed']);
  });

  test('Done marks logged elsewhere are applied in time order', () async {
    final reminder = await create(nineAndNoon);
    // E.g. tapped on the widget while the app was closed.
    await inbox.add(reminder.id, nov(4, 9, 30));
    now = nov(4, 12, 10);
    await service.syncAll();

    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.pending?.start, nov(4, 12));
    expect(runtime?.missedOn(nov4), 0);
    expect(await history(reminder.id), ['4/12:00 pending', '4/09:00 done 09:30']);
  });

  test('syncing twice changes nothing the second time', () async {
    final reminder = await create(nineAndNoon);
    now = nov(4, 12, 10);
    await service.syncAll();
    await service.syncAll();
    expect(await history(reminder.id), hasLength(2));
    expect((await repository.getRuntime(reminder.id))?.missedOn(nov4), 1);
  });

  test('editing keeps a due time due until the new schedule’s next time',
      () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 30);
    await service.syncAll();

    // 09:15 today is already in the past, so it does not happen.
    await service.update(
      reminder.copyWith(
        schedule: dailyAtNine.copyWith(
          times: const [ReminderTime(start: LocalTime(9, 15))],
        ),
      ),
    );
    expect(
      (await repository.getRuntime(reminder.id))?.pending?.start,
      nov(4, 9),
    );

    now = nov(5, 9, 20);
    await service.syncAll();
    expect(await history(reminder.id), ['5/09:15 pending', '4/09:00 missed']);
  });

  test('pausing stops new times; resuming does not catch up', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 8, 30);
    await service.setPaused(reminder.id, paused: true);

    now = nov(6, 10);
    await service.syncAll();
    expect(await history(reminder.id), isEmpty);

    await service.setPaused(reminder.id, paused: false);
    now = nov(7, 9, 1);
    await service.syncAll();
    expect(await history(reminder.id), ['7/09:00 pending']);
  });

  test('pausing keeps a due time due, past the next time', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 10);
    await service.syncAll();
    await service.setPaused(reminder.id, paused: true);

    now = nov(6, 12);
    await service.syncAll();
    expect(
      (await repository.getRuntime(reminder.id))?.pending?.start,
      nov(4, 9),
    );
  });

  test('archiving records a due time as missed', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 10);
    await service.syncAll();
    await service.archive(reminder.id);

    expect((await repository.getReminder(reminder.id))?.isArchived, isTrue);
    expect((await repository.getRuntime(reminder.id))?.isFiring, isFalse);
    expect(await history(reminder.id), ['4/09:00 missed']);

    // Archived reminders never remind.
    now = nov(6, 12);
    await service.syncAll();
    expect(await history(reminder.id), hasLength(1));
  });

  test('restoring brings it back without replaying the archived time',
      () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 10);
    await service.syncAll();
    await service.archive(reminder.id);

    now = nov(6, 8);
    final restored = await service.restore(reminder.id);
    expect(restored.isArchived, isFalse);
    final runtime = await repository.getRuntime(reminder.id);
    expect(runtime?.missedCount, 0);
    expect(runtime?.last, isNull);

    now = nov(6, 9, 1);
    await service.syncAll();
    expect(await history(reminder.id), ['6/09:00 pending', '4/09:00 missed']);
  });

  test('a finished one-time reminder is archived once done', () async {
    final reminder = await create(onceAtNine(nov4));
    now = nov(5, 12);
    await service.syncAll();
    // Its only time has no next time, so it stays due after its date.
    expect((await repository.getReminder(reminder.id))?.isArchived, isFalse);

    await service.markDone(reminder.id);
    expect((await repository.getReminder(reminder.id))?.isArchived, isTrue);
    expect(await history(reminder.id), ['4/09:00 done 12:00']);
  });

  test('a one-time reminder whose last time has an end is archived', () async {
    final reminder = await create(
      const Schedule(
        recurrence: OnceRecurrence(nov4),
        times: [ReminderTime(start: LocalTime(9, 0), end: LocalTime(10, 0))],
      ),
    );
    now = nov(4, 10, 1);
    await service.syncAll();
    expect((await repository.getReminder(reminder.id))?.isArchived, isTrue);
    expect(await history(reminder.id), ['4/09:00 missed']);
  });

  test('a repeating reminder past its end date is archived', () async {
    final reminder = await create(
      const Schedule(
        recurrence: RepeatRecurrence(
          unit: RepeatUnit.day,
          startDate: nov4,
          endDate: nov4,
        ),
        times: [nineAm],
      ),
    );
    now = nov(4, 9, 5);
    await service.markDone(reminder.id);
    expect((await repository.getReminder(reminder.id))?.isArchived, isTrue);
  });

  test('a paused one-time reminder whose date passed is archived', () async {
    final reminder = await create(onceAtNine(const LocalDate(2026, 11, 5)));
    await service.setPaused(reminder.id, paused: true);
    now = nov(5, 10);
    await service.syncAll();

    expect((await repository.getReminder(reminder.id))?.isArchived, isTrue);
    // It was paused at 09:00, so it never became due.
    expect(await history(reminder.id), isEmpty);
  });

  test('restoring with edits uses the new schedule', () async {
    final reminder = await create(onceAtNine(nov4));
    now = nov(4, 9, 5);
    await service.markDone(reminder.id); // finished -> archived

    now = nov(10, 8);
    await service.restore(
      reminder.id,
      edited: reminder.copyWith(
        schedule: onceAtNine(const LocalDate(2026, 11, 11)),
      ),
    );
    now = nov(11, 9, 1);
    await service.syncAll();
    expect(
      (await repository.getRuntime(reminder.id))?.pending?.start,
      nov(11, 9),
    );
  });

  test('deleting removes the reminder, its runtime, history and log', () async {
    final reminder = await create(dailyAtNine);
    now = nov(4, 9, 5);
    await service.markDone(reminder.id);
    await service.delete(reminder.id);

    expect(await repository.getReminder(reminder.id), isNull);
    expect(await repository.getRuntime(reminder.id), isNull);
    expect(await repository.getHistory(reminder.id), isEmpty);
    expect(await inbox.read(reminder.id), isEmpty);
  });
}

String _hm(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
