import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ids.dart';
import '../../../core/local_time.dart';
import '../../../domain/occurrence.dart';
import '../../../domain/reminder.dart';
import '../../../domain/validation.dart';
import '../../../state/providers.dart';
import '../../../state/reminder_views.dart';
import 'editor_draft.dart';

/// What the editor is doing.
enum EditorMode {
  /// A new reminder.
  create,

  /// Changing an existing reminder.
  edit,

  /// Bringing an archived reminder back with changes (e.g. a new date).
  restore,
}

typedef EditorTarget = ({EditorMode mode, String? reminderId});

final editorProvider = NotifierProvider.autoDispose
    .family<EditorController, EditorDraft, EditorTarget>(EditorController.new);

/// Holds the editor form and saves it.
class EditorController extends Notifier<EditorDraft> {
  EditorController(this.target);

  final EditorTarget target;

  late EditorDraft _initial;
  Reminder? _original;

  @override
  EditorDraft build() {
    final now = ref.read(clockProvider)();
    _original = _findReminder(target.reminderId);
    final original = _original;
    _initial = original == null
        ? EditorDraft.forNew(id: newId(), now: now)
        : EditorDraft.fromReminder(original, now: now);
    return _initial;
  }

  /// The reminder being edited or restored (`null` when creating, or when it
  /// no longer exists).
  Reminder? get original => _original;

  /// Whether the form differs from what it started with.
  bool get isDirty => state != _initial;

  /// Whether the schedule differs from the saved one (always true when
  /// creating).
  bool get scheduleChanged =>
      _original == null || _original!.schedule != state.schedule;

  void edit(EditorDraft Function(EditorDraft draft) change) =>
      state = change(state);

  void setName(String name) => state = state.copyWith(
    name: name,
    displayName: state.displayNameEdited
        ? null
        : EditorDraft.suggestDisplayName(name),
  );

  void setDisplayName(String displayName) => state = state.copyWith(
    displayName: displayName,
    displayNameEdited: displayName.trim().isNotEmpty,
  );

  void toggleWeekday(int weekday) {
    final days = {...state.weekdays};
    if (!days.remove(weekday)) days.add(weekday);
    state = state.copyWith(weekdays: days);
  }

  /// Changes the time with [key]; the times stay in start order.
  void editTime(int key, TimeDraft Function(TimeDraft time) change) =>
      state = state.copyWith(
        times: _ordered([
          for (final time in state.times)
            time.key == key ? change(time) : time,
        ]),
      );

  /// Adds a time an hour after the last one (after its end, if it has one)
  /// and returns its key.
  int addTime() {
    final times = state.times;
    final key = times.fold(-1, (max, time) => time.key > max ? time.key : max) + 1;
    final last = times.lastOrNull;
    final after = last == null
        ? const LocalTime(8, 0)
        : last.hasEnd
        ? last.endOrDefault
        : last.start;
    state = state.copyWith(
      times: _ordered([
        ...times,
        TimeDraft(
          key: key,
          start: LocalTime.fromMinutes((after.minutesOfDay + 60) % 1440),
        ),
      ]),
    );
    return key;
  }

  /// Removes the time with [key], unless it is the only one.
  void removeTime(int key) {
    if (state.times.length <= 1) return;
    state = state.copyWith(
      times: [
        for (final time in state.times)
          if (time.key != key) time,
      ],
    );
  }

  List<ValidationIssue> validate() => validateReminder(
    name: state.name,
    displayName: state.displayName,
    description: state.description,
    schedule: state.schedule,
  );

  /// The next times of the form's schedule that become due after [now].
  List<Occurrence> preview(DateTime now, {int count = 5}) => ref
      .read(scheduleEngineProvider)
      .upcoming(state.id, state.schedule, now, count: count);

  static List<TimeDraft> _ordered(List<TimeDraft> times) =>
      times..sort((a, b) => a.start.compareTo(b.start));

  /// Saves the form (create, update or restore) and returns the reminder.
  /// Call [validate] first.
  Future<Reminder> save() async {
    final service = ref.read(reminderServiceProvider);
    final draft = state;
    final description = draft.description.trim().isEmpty
        ? null
        : draft.description;
    final original = _original;

    final Reminder saved;
    if (original == null || target.mode == EditorMode.create) {
      saved = await service.create(
        id: draft.id,
        name: draft.name,
        displayName: draft.displayName,
        description: description,
        schedule: draft.schedule,
      );
    } else {
      final edited = original.copyWith(
        name: draft.name,
        displayName: draft.displayName,
        description: description,
        schedule: draft.schedule,
      );
      saved = target.mode == EditorMode.restore
          ? await service.restore(original.id, edited: edited)
          : await service.update(edited);
    }
    _initial = state;
    return saved;
  }

  Reminder? _findReminder(String? id) {
    if (id == null) return null;
    final views =
        ref.read(reminderViewsProvider).value ?? const <ReminderView>[];
    for (final view in views) {
      if (view.id == id) return view.reminder;
    }
    return null;
  }
}
