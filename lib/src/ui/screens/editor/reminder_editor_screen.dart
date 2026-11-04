import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/local_date.dart';
import '../../../core/local_time.dart';
import '../../../domain/schedule.dart';
import '../../../domain/validation.dart';
import '../../../state/now.dart';
import '../../../state/providers.dart';
import '../../components/activation_times.dart';
import '../../components/empty_state.dart';
import '../../components/number_stepper.dart';
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
            _timeSection(draft, error),
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

  Widget _timeSection(EditorDraft draft, _ErrorLookup error) {
    final formatter = TimeFormatter.of(context);
    final endsNextDay =
        draft.rangeEnd.minutesOfDay < draft.rangeStart.minutesOfDay;
    final isPreset = _intervalPresets.contains(draft.intervalMinutes);

    return SectionCard(
      icon: Icons.schedule_rounded,
      title: 'Time',
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Fixed time'),
              icon: Icon(Icons.alarm_rounded),
            ),
            ButtonSegment(
              value: true,
              label: Text('Time range'),
              icon: Icon(Icons.timelapse_rounded),
            ),
          ],
          selected: {draft.useRange},
          onSelectionChanged: (selection) => _controller.edit(
            (draft) => draft.copyWith(useRange: selection.first),
          ),
        ),
        const SizedBox(height: 16),
        if (!draft.useRange)
          PickerField(
            label: 'At',
            value: formatter.time(draft.fixedTime),
            icon: Icons.alarm_rounded,
            onTap: () async {
              final time = await _pickTime(draft.fixedTime);
              if (time != null) {
                _controller.edit((draft) => draft.copyWith(fixedTime: time));
              }
            },
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PickerField(
                  label: 'From',
                  value: formatter.time(draft.rangeStart),
                  icon: Icons.wb_twilight_rounded,
                  onTap: () async {
                    final time = await _pickTime(draft.rangeStart);
                    if (time != null) {
                      _controller.edit(
                        (draft) => draft.copyWith(rangeStart: time),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PickerField(
                  label: 'To',
                  value: formatter.time(draft.rangeEnd),
                  icon: Icons.nights_stay_outlined,
                  helperText: endsNextDay ? 'Next day' : null,
                  errorText: error(ReminderField.timeRange),
                  onTap: () async {
                    final time = await _pickTime(draft.rangeEnd);
                    if (time != null) {
                      _controller.edit((draft) => draft.copyWith(rangeEnd: time));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<RangeMode>(
            segments: const [
              ButtonSegment(
                value: RangeMode.interval,
                label: Text('Interval'),
                icon: Icon(Icons.av_timer_rounded),
              ),
              ButtonSegment(
                value: RangeMode.random,
                label: Text('Random'),
                icon: Icon(Icons.shuffle_rounded),
              ),
            ],
            selected: {draft.rangeMode},
            onSelectionChanged: (selection) => _controller.edit(
              (draft) => draft.copyWith(rangeMode: selection.first),
            ),
          ),
          const SizedBox(height: 16),
          if (draft.rangeMode == RangeMode.interval) ...[
            Text(
              'Every',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in _intervalPresets)
                  ChoiceChip(
                    label: Text(formatInterval(minutes)),
                    selected: draft.intervalMinutes == minutes,
                    onSelected: (_) => _controller.edit(
                      (draft) => draft.copyWith(intervalMinutes: minutes),
                    ),
                  ),
                ChoiceChip(
                  label: Text(
                    isPreset
                        ? 'Custom…'
                        : 'Custom: ${formatInterval(draft.intervalMinutes)}',
                  ),
                  selected: !isPreset,
                  onSelected: (_) => _pickCustomInterval(draft.intervalMinutes),
                ),
              ],
            ),
            _ErrorText(error(ReminderField.interval)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Limit activations'),
              subtitle: Text(
                draft.limitActivations
                    ? 'At most ${draft.maxActivations} per day'
                    : 'Until the range ends',
              ),
              value: draft.limitActivations,
              onChanged: (on) => _controller.edit(
                (draft) => draft.copyWith(limitActivations: on),
              ),
            ),
            if (draft.limitActivations)
              _LabeledStepper(
                before: 'At most',
                after: 'per day',
                value: draft.maxActivations,
                min: 1,
                max: ReminderLimits.maxActivationsPerWindow,
                semanticLabel: 'Maximum activations per day',
                onChanged: (value) => _controller.edit(
                  (draft) => draft.copyWith(maxActivations: value),
                ),
              ),
          ] else ...[
            _LabeledStepper(
              before: 'Times',
              after: 'per day',
              value: math.min(draft.randomCount, draft.maxRandomCount),
              min: 1,
              max: draft.maxRandomCount,
              semanticLabel: 'Random activations per day',
              onChanged: (value) => _controller.edit(
                (draft) => draft.copyWith(randomCount: value),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The range is split into equal parts with one random time in '
              'each, so they never bunch up.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          _ErrorText(error(ReminderField.activations)),
        ],
      ],
    );
  }

  Widget _previewSection(EditorDraft draft, DateTime now) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = _controller.preview(now, count: 8);

    return SectionCard(
      icon: Icons.visibility_outlined,
      title: 'Next activations',
      children: [
        if (preview.isEmpty)
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This schedule has no upcoming activations.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          )
        else
          ActivationTimes(times: preview, now: now),
        if (draft.useRange && draft.rangeMode == RangeMode.random) ...[
          const SizedBox(height: 8),
          Text(
            'Random times are picked once per day and then stay put.',
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
      tell('This schedule never activates. Pick a later date or time.');
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await controller.save();
      tell(switch (mode) {
        EditorMode.create => '“${saved.name}” created',
        EditorMode.edit => 'Changes saved',
        EditorMode.restore => '“${saved.name}” restored',
      });
      navigator.pop();
    } on Object catch (error) {
      if (mounted) setState(() => _saving = false);
      tell('Couldn’t save: $error');
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

  Future<void> _pickCustomInterval(int current) async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => _CustomIntervalDialog(initialMinutes: current),
    );
    if (minutes != null) {
      _controller.edit((draft) => draft.copyWith(intervalMinutes: minutes));
    }
  }

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
  const _ErrorText(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
          labelText: 'Minutes between activations',
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
