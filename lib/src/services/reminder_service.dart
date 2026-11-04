import 'dart:async';

import '../core/clock.dart';
import '../core/ids.dart';
import '../data/reminder_repository.dart';
import '../domain/reminder.dart';
import '../domain/reminder_runtime.dart';
import '../domain/runtime_advance.dart';
import '../domain/schedule.dart';
import '../domain/schedule_engine.dart';
import 'ack_inbox.dart';

/// Work that keeps notifications and home screen widgets in line with the
/// data. Called after every change.
abstract interface class ReminderSideEffects {
  Future<void> onRemindersChanged();
}

/// [ReminderSideEffects] that do nothing (tests, and until notifications and
/// widgets are wired up).
class NoSideEffects implements ReminderSideEffects {
  const NoSideEffects();

  @override
  Future<void> onRemindersChanged() async {}
}

/// Every change to reminders goes through this service. It runs in the main
/// isolate only and serializes its operations, so a sync never interleaves
/// with an edit.
class ReminderService {
  ReminderService({
    required this._repository,
    required this._inbox,
    this._engine = const ScheduleEngine(),
    this._clock = systemClock,
    this._sideEffects = const NoSideEffects(),
  });

  final ReminderRepository _repository;
  final AckInbox _inbox;
  final ScheduleEngine _engine;
  final Clock _clock;
  final ReminderSideEffects _sideEffects;

  Future<void> _queue = Future<void>.value();

  /// Creates a reminder. Pass the [id] the editor already used for its
  /// schedule preview, so the saved random times match what was shown.
  Future<Reminder> create({
    required String name,
    required String displayName,
    required Schedule schedule,
    String? description,
    String? id,
  }) => _serialized(() async {
    final now = _clock();
    final reminder = Reminder(
      id: id ?? newId(),
      name: name.trim(),
      displayName: displayName.trim(),
      description: _clean(description),
      schedule: schedule,
      createdAt: now,
      updatedAt: now,
      activeSince: now,
    );
    await _repository.save(
      reminder: reminder,
      runtime: ReminderRuntime.initial(reminder.id, now),
    );
    await _sideEffects.onRemindersChanged();
    return reminder;
  });

  /// Saves the user's edits. History is first brought up to date under the
  /// old schedule; a waiting activation stays waiting until acknowledged.
  Future<Reminder> update(Reminder edited) => _serialized(() async {
    final now = _clock();
    final current = await _sync(
      await _require(edited.id),
      now,
      allowArchive: false,
    );
    final scheduleChanged = edited.schedule != current.schedule;
    final updated = current.copyWith(
      name: edited.name.trim(),
      displayName: edited.displayName.trim(),
      description: _clean(edited.description),
      schedule: edited.schedule,
      updatedAt: now,
      activeSince: scheduleChanged ? now : null,
    );
    await _repository.save(reminder: updated);
    await _sideEffects.onRemindersChanged();
    return updated;
  });

  /// Pauses or resumes. A waiting activation stays waiting; resuming never
  /// catches up on activations that fell inside the pause.
  Future<void> setPaused(String id, {required bool paused}) =>
      _serialized(() async {
        final now = _clock();
        final reminder = await _sync(
          await _require(id),
          now,
          allowArchive: false,
        );
        if (reminder.paused == paused) return;
        await _repository.save(
          reminder: reminder.copyWith(
            paused: paused,
            updatedAt: now,
            activeSince: paused ? null : now,
          ),
        );
        await _sideEffects.onRemindersChanged();
      });

  /// Moves the reminder to the archive; a waiting activation is recorded as
  /// missed. Its history is kept.
  Future<void> archive(String id) => _serialized(() async {
    final now = _clock();
    final current = await _require(id);
    if (current.isArchived) return;
    final reminder = await _sync(current, now, allowArchive: false);
    final closed = closePendingAsMissed(await _runtimeOf(reminder));
    await _repository.save(
      reminder: reminder.copyWith(archivedAt: now, updatedAt: now),
      runtime: closed.runtime,
      records: closed.records,
    );
    await _sideEffects.onRemindersChanged();
  });

  /// Brings an archived reminder back to the list, optionally with the
  /// user's [edited] details (e.g. a new date for a finished one-time
  /// reminder). Nothing that would have happened while archived is replayed.
  Future<Reminder> restore(String id, {Reminder? edited}) =>
      _serialized(() async {
        final now = _clock();
        final current = await _require(id);
        final source = edited ?? current;
        final restored = current.copyWith(
          name: source.name.trim(),
          displayName: source.displayName.trim(),
          description: _clean(source.description),
          schedule: source.schedule,
          archivedAt: null,
          updatedAt: now,
          activeSince: now,
        );
        final runtime = (await _runtimeOf(current)).copyWith(
          processedUntil: now,
          appliedAckUntil: now,
          pendingAt: null,
          missedCount: 0,
        );
        await _repository.save(reminder: restored, runtime: runtime);
        await _sideEffects.onRemindersChanged();
        return restored;
      });

  /// Deletes the reminder and its whole history.
  Future<void> delete(String id) => _serialized(() async {
    await _repository.delete(id);
    await _inbox.clear(id);
    await _sideEffects.onRemindersChanged();
  });

  /// Acknowledges the reminder's waiting activation (from inside the app).
  Future<void> acknowledge(String id) => _serialized(() async {
    final now = _clock();
    await _inbox.add(id, now);
    final reminder = await _repository.getReminder(id);
    if (reminder != null) await _sync(reminder, now);
    await _sideEffects.onRemindersChanged();
  });

  /// Brings every reminder up to "now": records activations that happened,
  /// applies acknowledgments logged elsewhere (widget, notification) and
  /// archives finished reminders.
  Future<void> syncAll() => _serialized(() async {
    final now = _clock();
    for (final reminder in await _repository.getReminders()) {
      await _sync(reminder, now);
    }
    await _sideEffects.onRemindersChanged();
  });

  // -------------------------------------------------------------------------

  /// Runs [action] after every earlier operation has finished.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Reminder> _require(String id) async {
    final reminder = await _repository.getReminder(id);
    if (reminder == null) throw StateError('Reminder $id not found');
    return reminder;
  }

  Future<ReminderRuntime> _runtimeOf(Reminder reminder) async =>
      await _repository.getRuntime(reminder.id) ??
      ReminderRuntime.initial(reminder.id, reminder.activeSince);

  /// Brings one reminder up to [now] and returns it — archived when it is
  /// finished and nothing is waiting (unless [allowArchive] is false).
  Future<Reminder> _sync(
    Reminder reminder,
    DateTime now, {
    bool allowArchive = true,
  }) async {
    if (reminder.isArchived) return reminder;
    final runtime = await _runtimeOf(reminder);
    final acknowledgments = [
      for (final at in await _inbox.read(reminder.id))
        if (at.isAfter(runtime.appliedAckUntil)) at,
    ];
    final from = runtime.processedUntil.isAfter(reminder.activeSince)
        ? runtime.processedUntil
        : reminder.activeSince;
    final activations = reminder.isLive
        ? _engine.between(reminder.id, reminder.schedule, from, now)
        : const <DateTime>[];

    final advance = advanceRuntime(
      runtime: runtime,
      activations: activations,
      acknowledgments: acknowledgments,
      until: now,
    );
    final archive =
        allowArchive &&
        !advance.runtime.isActive &&
        _engine.isFinished(reminder, now);
    final result = archive
        ? reminder.copyWith(archivedAt: now, updatedAt: now)
        : reminder;

    // Without new activations or acknowledgments only `processedUntil`
    // would change; skipping that write is safe because the next sync
    // re-scans the same (empty) span.
    if (archive || activations.isNotEmpty || acknowledgments.isNotEmpty) {
      await _repository.save(
        reminder: archive ? result : null,
        runtime: advance.runtime,
        records: advance.records,
      );
    }
    return result;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
