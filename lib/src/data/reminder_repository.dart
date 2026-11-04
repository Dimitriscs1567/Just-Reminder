import 'package:sembast/sembast.dart';

import '../domain/activation.dart';
import '../domain/reminder.dart';
import '../domain/reminder_runtime.dart';

/// Reads and writes reminders, their runtime state and their history.
///
/// Stores:
/// - `reminders`: [Reminder] by id
/// - `runtimes`: [ReminderRuntime] by reminder id
/// - `history/<reminder id>`: [ActivationRecord] by activation time (epoch
///   ms). One store per reminder keeps history queries from scanning the
///   history of every other reminder, and makes deleting it cheap.
class ReminderRepository {
  ReminderRepository(this._db);

  final Database _db;

  static final _reminders = stringMapStoreFactory.store('reminders');
  static final _runtimes = stringMapStoreFactory.store('runtimes');

  static StoreRef<int, Map<String, Object?>> _history(String reminderId) =>
      intMapStoreFactory.store('history/$reminderId');

  // Reminders ---------------------------------------------------------------

  Stream<List<Reminder>> watchReminders() =>
      _reminders.query().onSnapshots(_db).map(_toReminders);

  Future<List<Reminder>> getReminders() async =>
      _toReminders(await _reminders.find(_db));

  Stream<Reminder?> watchReminder(String id) => _reminders
      .record(id)
      .onSnapshot(_db)
      .map((snapshot) => snapshot == null ? null : _toReminder(snapshot.value));

  Future<Reminder?> getReminder(String id) async {
    final value = await _reminders.record(id).get(_db);
    return value == null ? null : _toReminder(value);
  }

  // Runtimes ----------------------------------------------------------------

  Stream<Map<String, ReminderRuntime>> watchRuntimes() =>
      _runtimes.query().onSnapshots(_db).map(
        (snapshots) => {
          for (final snapshot in snapshots)
            snapshot.key: ReminderRuntime.fromJson(snapshot.value),
        },
      );

  Future<ReminderRuntime?> getRuntime(String reminderId) async {
    final value = await _runtimes.record(reminderId).get(_db);
    return value == null ? null : ReminderRuntime.fromJson(value);
  }

  // History -----------------------------------------------------------------

  /// The reminder's history, newest first.
  Stream<List<ActivationRecord>> watchHistory(String reminderId, {int? limit}) =>
      _history(reminderId)
          .query(finder: _newestFirst(limit))
          .onSnapshots(_db)
          .map(_toRecords);

  /// The reminder's history, newest first.
  Future<List<ActivationRecord>> getHistory(
    String reminderId, {
    int? limit,
  }) async => _toRecords(
    await _history(reminderId).find(_db, finder: _newestFirst(limit)),
  );

  // Writes ------------------------------------------------------------------

  /// Writes any of [reminder], [runtime] and history [records] in one
  /// transaction, so the three never disagree.
  Future<void> save({
    Reminder? reminder,
    ReminderRuntime? runtime,
    List<ActivationRecord> records = const [],
  }) => _db.transaction((txn) async {
    if (reminder != null) {
      await _reminders.record(reminder.id).put(txn, reminder.toJson());
    }
    if (runtime != null) {
      await _runtimes.record(runtime.reminderId).put(txn, runtime.toJson());
    }
    for (final record in records) {
      await _history(record.reminderId)
          .record(record.scheduledAt.millisecondsSinceEpoch)
          .put(txn, record.toJson());
    }
  });

  /// Deletes the reminder together with its runtime and whole history.
  Future<void> delete(String reminderId) => _db.transaction((txn) async {
    await _reminders.record(reminderId).delete(txn);
    await _runtimes.record(reminderId).delete(txn);
    await _history(reminderId).drop(txn);
  });

  // Mapping -----------------------------------------------------------------

  static Finder _newestFirst(int? limit) =>
      Finder(sortOrders: [SortOrder(Field.key, false)], limit: limit);

  static Reminder _toReminder(Map<String, Object?> value) =>
      Reminder.fromJson(value);

  static List<Reminder> _toReminders(
    List<RecordSnapshot<String, Map<String, Object?>>> snapshots,
  ) => [for (final snapshot in snapshots) _toReminder(snapshot.value)];

  static List<ActivationRecord> _toRecords(
    List<RecordSnapshot<int, Map<String, Object?>>> snapshots,
  ) => [
    for (final snapshot in snapshots) ActivationRecord.fromJson(snapshot.value),
  ];
}
