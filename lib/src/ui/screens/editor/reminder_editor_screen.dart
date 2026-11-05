import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/local_date.dart';
import '../../../core/local_time.dart';
import '../../../domain/reminder.dart';
import '../../../domain/schedule.dart';
import '../../../domain/validation.dart';
import '../../../state/now.dart';
import '../../../state/providers.dart';
import '../../components/empty_state.dart';
import '../../components/number_stepper.dart';
import '../../components/occurrence_times.dart';
import '../../components/picker_field.dart';
import '../../components/section_card.dart';
import '../../formatting.dart';
import 'editor_controller.dart';
import 'editor_draft.dart';

/// Create, edit or restore a reminder.
class ReminderEditorScreen extends ConsumerStatefulWidget {
  const ReminderEditorScreen({required this.target, super.key});

  final EditorTarget target;

  @override
  ConsumerState<ReminderEditorScreen> createState() =>
      _ReminderEditorScreenState();
}

typedef _ErrorLookup = String? Function(ReminderField field);

class _ReminderEditorScreenState extends ConsumerState<ReminderEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _displayName;
  late final TextEditingController _description;
  bool _showErrors = false;
  bool _saving = false;

  /// The key of the time row that is open; a new reminder starts with its
  /// only time open.
  int? _openTime;

  static const _intervalPresets = [5, 10, 15, 30, 45, 60, 90, 120, 180];

  EditorController get _controller =>
      ref.read(editorProvider(widget.target).notifier);

  @override
  void initState() {
    super.initState();
    final draft = ref.read(editorProvider(widget.target));
    _name = TextEditingController(text: draft.name);
    _displayName = TextEditingController(text: draft.displayName);
    _description = TextEditingController(text: draft.description);
    if (widget.target.mode == EditorMode.create) {
      _openTime = draft.times.first.key;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _displayName.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = editorProvider(widget.target);
    final draft = ref.watch(provider);
    final now = ref.watch(nowProvider);
    final mode = widget.target.mode;

    // The display name follows the name until the user types their own.
    ref.listen(provider.select((draft) => draft.displayName), (_, next) {
      if (_displayName.text != next) _displayName.text = next;
    });

    if (mode != EditorMode.create && _controller.original == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Reminder not found',
          message: 'It may have been deleted.',
        ),
      );
    }

    final issues = _showErrors
        ? _controller.validate()
        : const <ValidationIssue>[];
    String? error(ReminderField field) {
      for (final issue in issues) {
        if (issue.field == field) return issue.message;
      }
      return null;
    }

    return PopScope<Object?>(
      canPop: _saving || !_controller.isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(switch (mode) {
            EditorMode.create => 'New reminder',
            EditorMode.edit => 'Edit reminder',
            EditorMode.restore => 'Restore reminder',
          }),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(mode == EditorMode.restore ? 'Restore' : 'Save'),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            if (mode == EditorMode.restore) ...[
              const _RestoreHint(),
              const SizedBox(height: 16),
            ],
            _detailsSection(error),
            const SizedBox(height: 16),
            _whenSection(draft, error),
            const SizedBox(height: 16),
            _timesSection(draft, issues),
            const SizedBox(height: 16),
            _previewSection(draft, now),
          ],
        ),
      ),
    );
  }

  // Sections ----------------------------------------------------------------

  Widget _detailsSection(_ErrorLookup error) => SectionCard(
    icon: Icons.edit_note_rounded,
    title: 'Details',
    children: [
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        maxLength: ReminderLimits.nameMaxLength,
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Drink a glass of water',
          errorText: error(ReminderField.name),
          counterText: '',
        ),
        onChanged: _controller.setName,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _displayName,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        maxLength: ReminderLimits.displayNameMaxLength,
        decoration: InputDecoration(
          labelText: 'Display name',
          helperText: 'Shown on the widget and in notifications',
          helperMaxLines: 2,
          errorText: error(ReminderField.displayName),
        ),
        onChanged: _controller.setDisplayName,
      ),
      const SizedBox(height: 4),
      TextField(
        controller: _description,
        textCapitalization: TextCapitalization.sentences,
        minLines: 2,
        maxLines: 5,
        maxLength: ReminderLimits.descriptionMaxLength,
        decoration: InputDecoration(
          labelText: 'Description (optional)',
          helperText: 'Shown in the app and in notifications',
          alignLabelWithHint: true,
          errorText: error(ReminderField.description),
          counterText: '',
        ),
        onChanged: (value) =>
            _controller.edit((draft) => draft.copyWith(description: value)),
      ),
    ],
  );

  Widget _whenSection(EditorDraft draft, _ErrorLookup error) => SectionCard(
    icon: Icons.event_repeat_rounded,
    title: 'When',
    children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('Once'),
            icon: Icon(Icons.event_rounded),
          ),
          ButtonSegment(
            value: true,
            label: Text('Repeat'),
            icon: Icon(Icons.repeat_rounded),
          ),
        ],
        selected: {draft.repeats},
        onSelectionChanged: (selection) => _controller.edit(
          (draft) => draft.copyWith(repeats: selection.first),
        ),
      ),
      const SizedBox(height: 16),
      if (!draft.repeats)
        PickerField(
          label: 'Date',
          value: formatDate(draft.onceDate),
          icon: Icons.calendar_today_rounded,
          onTap: () async {
            final date = await _pickDate(draft.onceDate);
            if (date != null) {
              _controller.edit((draft) => draft.copyWith(onceDate: date));
            }
          },
        )
      else ...[
        SegmentedButton<RepeatUnit>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: RepeatUnit.day, label: Text('Daily')),
            ButtonSegment(value: RepeatUnit.week, label: Text('Weekly')),
            ButtonSegment(value: RepeatUnit.month, label: Text('Monthly')),
          ],
          selected: {draft.unit},
          onSelectionChanged: (selection) => _controller.edit(
            (draft) => draft.copyWith(unit: selection.first),
          ),
        ),
        const SizedBox(height: 16),
        _LabeledStepper(
          before: 'Every',
          after: _unitWord(draft.unit, draft.every),
          value: draft.every,
          min: 1,
          max: ReminderLimits.maxEvery,
          semanticLabel: 'Repeat every',
          onChanged: (value) =>
              _controller.edit((draft) => draft.copyWith(every: value)),
        ),
        _ErrorText(error(ReminderField.every)),
        if (draft.unit == RepeatUnit.week) ...[
          const SizedBox(height: 16),
          _WeekdayPicker(
            selected: draft.weekdays,
            onToggle: _controller.toggleWeekday,
            onPreset: (days) =>
                _controller.edit((draft) => draft.copyWith(weekdays: days)),
          ),
          _ErrorText(error(ReminderField.weekdays)),
        ],
        if (draft.unit == RepeatUnit.month) ...[
          const SizedBox(height: 16),
          _DayOfMonthPicker(
            day: draft.dayOfMonth,
            onChanged: (day) =>
                _controller.edit((draft) => draft.copyWith(dayOfMonth: day)),
          ),
        ],
        const SizedBox(height: 16),
        PickerField(
          label: 'Starts',
          value: formatDate(draft.startDate),
          icon: Icons.flag_outlined,
          onTap: () async {
            final date = await _pickDate(draft.startDate);
            if (date != null) {
              _controller.edit((draft) => draft.copyWith(startDate: date));
            }
          },
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('End date'),
          subtitle: Text(
            draft.endDate == null ? 'Repeats until you stop it' : 'Stops after the end date',
          ),
          value: draft.endDate != null,
          onChanged: (on) => _controller.edit(
            (draft) => draft.copyWith(
              endDate: on ? draft.startDate.addDays(30) : null,
            ),
          ),
        ),
        if (draft.endDate case final endDate?)
          PickerField(
            label: 'Ends',
            value: formatDate(endDate),
            icon: Icons.event_available_rounded,
            errorText: error(ReminderField.endDate),
            onTap: () async {
              final date = await _pickDate(endDate, notBefore: draft.startDate);
              if (date != null) {
                _controller.edit((draft) => draft.copyWith(endDate: date));
              }
            },
          ),
      ],
    ],
  );

  Widget _timesSection(EditorDraft draft, List<ValidationIssue> issues) {
    String? errorOf(int index) {
      for (final issue in issues) {
        if (issue.timeIndex == index) return issue.message;
      }
      return null;
    }

    String? listError;
    for (final issue in issues) {
      if (issue.field == ReminderField.times) listError ??= issue.message;
    }

    return SectionCard(
      icon: Icons.schedule_rounded,
      title: draft.times.length == 1 ? 'Time' : 'Times',
      children: [
        for (var index = 0; index < draft.times.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TimeTile(
              key: ValueKey(draft.times[index].key),
              time: draft.times[index],
              open: _openTime == draft.times[index].key,
              error: errorOf(index),
              canRemove: draft.times.length > 1,
              intervalPresets: _intervalPresets,
              onToggle: () {
                final key = draft.times[index].key;
                setState(() => _openTime = _openTime == key ? null : key);
              },
              onChanged: (change) =>
                  _controller.editTime(draft.times[index].key, change),
              onRemove: () {
                final key = draft.times[index].key;
                _controller.removeTime(key);
                if (_openTime == key) setState(() => _openTime = null);
              },
              pickTime: _pickTime,
              pickInterval: _pickCustomInterval,
            ),
          ),
        if (draft.times.length < ReminderLimits.maxTimes)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () {
                final key = _controller.addTime();
                setState(() => _openTime = key);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add time'),
            ),
          ),
        _ErrorText(listError),
      ],
    );
  }

  Widget _previewSection(EditorDraft draft, DateTime now) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = _controller.preview(now, count: 8);

    return SectionCard(
      icon: Icons.visibility_outlined,
      title: 'Next reminders',
      children: [
        if (preview.isEmpty)
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This schedule has no upcoming reminders.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          )
        else
          OccurrenceTimes(occurrences: preview, now: now),
        if (draft.times.any((time) => time.time.mode == NotifyMode.random)) ...[
          const SizedBox(height: 8),
          Text(
            'Random notifications are picked once per day and then stay put.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  // Actions -----------------------------------------------------------------

  Future<void> _save() async {
    final controller = _controller;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final mode = widget.target.mode;
    void tell(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    final issues = controller.validate();
    if (issues.isNotEmpty) {
      setState(() => _showErrors = true);
      tell(issues.first.message);
      return;
    }
    final mustActivate = mode != EditorMode.edit || controller.scheduleChanged;
    final now = ref.read(clockProvider)();
    if (mustActivate && controller.preview(now, count: 1).isEmpty) {
      setState(() => _showErrors = true);
      tell('This schedule never reminds you. Pick a later date or time.');
      return;
    }

    final notifications = ref.read(notificationServiceProvider);
    setState(() => _saving = true);
    final Reminder saved;
    try {
      saved = await controller.save();
    } on Object catch (error) {
      if (mounted) setState(() => _saving = false);
      tell('Couldn’t save: $error');
      return;
    }
    tell(switch (mode) {
      EditorMode.create => '“${saved.name}” created',
      EditorMode.edit => 'Changes saved',
      EditorMode.restore => '“${saved.name}” restored',
    });
    navigator.pop();

    // The natural moment to ask: right after a reminder is set up.
    if (notifications == null) return;
    try {
      if (!(await notifications.permissions()).enabled) {
        await notifications.requestPermission();
      }
    } on Object {
      // The home screen banner offers it again.
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your changes to this reminder will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<LocalDate?> _pickDate(LocalDate initial, {LocalDate? notBefore}) async {
    final today = LocalDate.fromDateTime(ref.read(clockProvider)());
    var first = notBefore ?? today;
    if (initial.isBefore(first)) first = initial;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.at(LocalTime.midnight),
      firstDate: first.at(LocalTime.midnight),
      lastDate: DateTime(today.year + 10, 12, 31),
    );
    return picked == null ? null : LocalDate.fromDateTime(picked);
  }

  Future<LocalTime?> _pickTime(LocalTime initial) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    return picked == null ? null : LocalTime(picked.hour, picked.minute);
  }

  Future<int?> _pickCustomInterval(int current) => showDialog<int>(
    context: context,
    builder: (context) => _CustomIntervalDialog(initialMinutes: current),
  );

  static String _unitWord(RepeatUnit unit, int every) {
    final word = switch (unit) {
      RepeatUnit.day => 'day',
      RepeatUnit.week => 'week',
      RepeatUnit.month => 'month',
    };
    return every == 1 ? word : '${word}s';
  }
}

// Building blocks -------------------------------------------------------------

class _RestoreHint extends StatelessWidget {
  const _RestoreHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.history_rounded, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This reminder had finished. Pick a new date or time to '
                'bring it back.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One time of the reminder: a summary row that opens its settings in place
/// (start, optional end, how it notifies).
class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.time,
    required this.open,
    required this.error,
    required this.canRemove,
    required this.intervalPresets,
    required this.onToggle,
    required this.onChanged,
    required this.onRemove,
    required this.pickTime,
    required this.pickInterval,
    super.key,
  });

  final TimeDraft time;
  final bool open;
  final String? error;
  final bool canRemove;
  final List<int> intervalPresets;
  final VoidCallback onToggle;
  final void Function(TimeDraft Function(TimeDraft time) change) onChanged;
  final VoidCallback onRemove;
  final Future<LocalTime?> Function(LocalTime initial) pickTime;
  final Future<int?> Function(int current) pickInterval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final formatter = TimeFormatter.of(context);
    final value = time.time;
    final error = this.error;
    final borderColor = error != null
        ? scheme.error
        : open
        ? scheme.primary
        : scheme.outlineVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: open || error != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatTimeSpan(value, formatter),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          TextSpan(
                            text: '   ${describeNotify(value)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (!open && error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _ErrorText(error, top: 0),
            ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _settings(context, value, formatter),
            ),
        ],
      ),
    );
  }

  Widget _settings(
    BuildContext context,
    ReminderTime value,
    TimeFormatter formatter,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final isPreset = intervalPresets.contains(time.intervalMinutes);
    final mode = value.mode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PickerField(
                label: 'Start',
                value: formatter.time(time.start),
                icon: Icons.alarm_rounded,
                onTap: () async {
                  final picked = await pickTime(time.start);
                  if (picked != null) {
                    onChanged((time) => time.copyWith(start: picked));
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PickerField(
                label: 'End',
                value: time.hasEnd
                    ? formatter.time(time.endOrDefault)
                    : 'None',
                icon: Icons.flag_outlined,
                helperText: time.hasEnd && value.endsNextDay
                    ? 'Next day'
                    : null,
                onTap: () async {
                  final picked = await pickTime(time.endOrDefault);
                  if (picked != null) {
                    onChanged(
                      (time) => time.copyWith(hasEnd: true, end: picked),
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                time.hasEnd
                    ? 'Missed at the end if it isn’t done.'
                    : 'Due until done; missed when the next time starts.',
                style: hint,
              ),
            ),
            if (time.hasEnd)
              TextButton(
                onPressed: () => onChanged(
                  (time) => time.copyWith(
                    hasEnd: false,
                    mode: time.mode == NotifyMode.random
                        ? NotifyMode.once
                        : null,
                  ),
                ),
                child: const Text('No end'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<NotifyMode>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: NotifyMode.once, label: Text('Once')),
            const ButtonSegment(
              value: NotifyMode.repeat,
              label: Text('Repeat'),
            ),
            ButtonSegment(
              value: NotifyMode.random,
              label: const Text('Random'),
              enabled: time.hasEnd,
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              onChanged((time) => time.copyWith(mode: selection.first)),
        ),
        const SizedBox(height: 6),
        Text(switch (mode) {
          NotifyMode.once => time.hasEnd
              ? 'One notification at the start.'
              : 'One notification at the start. Add an end time for random '
                    'notifications.',
          NotifyMode.repeat => 'Notifies again until it’s done.',
          NotifyMode.random =>
            'Start to end is split into equal parts with one random '
                'notification in each; it’s due from the first.',
        }, style: hint),
        if (mode == NotifyMode.repeat) ...[
          const SizedBox(height: 12),
          Text(
            'Every',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final minutes in intervalPresets)
                ChoiceChip(
                  label: Text(formatInterval(minutes)),
                  selected: time.intervalMinutes == minutes,
                  onSelected: (_) => onChanged(
                    (time) => time.copyWith(intervalMinutes: minutes),
                  ),
                ),
              ChoiceChip(
                label: Text(
                  isPreset
                      ? 'Custom…'
                      : 'Custom: ${formatInterval(time.intervalMinutes)}',
                ),
                selected: !isPreset,
                onSelected: (_) async {
                  final minutes = await pickInterval(time.intervalMinutes);
                  if (minutes != null) {
                    onChanged(
                      (time) => time.copyWith(intervalMinutes: minutes),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Limit notifications'),
            subtitle: Text(
              time.limitNotifications
                  ? 'At most ${time.maxNotifications}'
                  : 'Until it’s done',
            ),
            value: time.limitNotifications,
            onChanged: (on) =>
                onChanged((time) => time.copyWith(limitNotifications: on)),
          ),
          if (time.limitNotifications)
            _LabeledStepper(
              before: 'At most',
              after: 'notifications',
              value: time.maxNotifications,
              min: 1,
              max: ReminderLimits.maxNotifications,
              semanticLabel: 'Maximum notifications',
              onChanged: (count) =>
                  onChanged((time) => time.copyWith(maxNotifications: count)),
            ),
        ],
        if (mode == NotifyMode.random) ...[
          const SizedBox(height: 12),
          _LabeledStepper(
            before: 'Notify',
            after: 'times',
            value: math.min(time.randomCount, time.maxRandomCount),
            min: 1,
            max: time.maxRandomCount,
            semanticLabel: 'Random notifications',
            onChanged: (count) =>
                onChanged((time) => time.copyWith(randomCount: count)),
          ),
        ],
        _ErrorText(error),
        if (canRemove)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove this time'),
            ),
          ),
      ],
    );
  }
}

class _LabeledStepper extends StatelessWidget {
  const _LabeledStepper({
    required this.before,
    required this.after,
    required this.value,
    required this.min,
    required this.max,
    required this.semanticLabel,
    required this.onChanged,
  });

  final String before;
  final String after;
  final int value;
  final int min;
  final int max;
  final String semanticLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Row(
      children: [
        Flexible(child: Text(before, style: style)),
        const SizedBox(width: 12),
        NumberStepper(
          value: value,
          min: min,
          max: max,
          semanticLabel: semanticLabel,
          onChanged: onChanged,
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(after, style: style)),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message, {this.top = 8});

  final String? message;
  final double top;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({
    required this.selected,
    required this.onToggle,
    required this.onPreset,
  });

  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final ValueChanged<Set<int>> onPreset;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(44.0, (constraints.maxWidth - 6 * 6) / 7);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var day = 1; day <= 7; day++)
                  Tooltip(
                    message: weekdayNames[day - 1],
                    child: Semantics(
                      button: true,
                      selected: selected.contains(day),
                      label: weekdayNames[day - 1],
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: () => onToggle(day),
                        radius: size / 2 + 4,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: size,
                          height: size,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected.contains(day)
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                          ),
                          child: Text(
                            _letters[day - 1],
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: selected.contains(day)
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('Weekdays'),
              onPressed: () => onPreset({1, 2, 3, 4, 5}),
            ),
            ActionChip(
              label: const Text('Weekend'),
              onPressed: () => onPreset({6, 7}),
            ),
            ActionChip(
              label: const Text('Every day'),
              onPressed: () => onPreset({1, 2, 3, 4, 5, 6, 7}),
            ),
          ],
        ),
      ],
    );
  }
}

class _DayOfMonthPicker extends StatelessWidget {
  const _DayOfMonthPicker({required this.day, required this.onChanged});

  final int day;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('On the', style: theme.textTheme.bodyLarge),
            const SizedBox(width: 12),
            DropdownMenu<int>(
              width: 128,
              menuHeight: 320,
              initialSelection: day,
              requestFocusOnTap: false,
              dropdownMenuEntries: [
                for (var value = 1; value <= 31; value++)
                  DropdownMenuEntry(value: value, label: ordinal(value)),
              ],
              onSelected: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ],
        ),
        if (day >= 29) ...[
          const SizedBox(height: 8),
          Text(
            'Months without the ${ordinal(day)} use their last day.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CustomIntervalDialog extends StatefulWidget {
  const _CustomIntervalDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_CustomIntervalDialog> createState() => _CustomIntervalDialogState();
}

class _CustomIntervalDialogState extends State<_CustomIntervalDialog> {
  late final TextEditingController _minutes = TextEditingController(
    text: '${widget.initialMinutes}',
  );
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_minutes.text.trim());
    if (value == null ||
        value < 1 ||
        value > ReminderLimits.maxIntervalMinutes) {
      setState(() => _error = 'Enter 1 to ${ReminderLimits.maxIntervalMinutes}');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom interval'),
      content: TextField(
        controller: _minutes,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Minutes between notifications',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Set')),
      ],
    );
  }
}
