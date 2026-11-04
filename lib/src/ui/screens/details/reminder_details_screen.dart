import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/local_date.dart';
import '../../../domain/activation.dart';
import '../../../domain/schedule.dart';
import '../../../state/now.dart';
import '../../../state/providers.dart';
import '../../../state/reminder_views.dart';
import '../../components/activation_times.dart';
import '../../components/empty_state.dart';
import '../../components/reminder_card.dart';
import '../../components/section_card.dart';
import '../../components/status_thumb.dart';
import '../../formatting.dart';
import '../../reminder_actions.dart';
import '../../theme/app_theme.dart';

/// Everything about one reminder: status, schedule, history and actions.
class ReminderDetailsScreen extends ConsumerWidget {
  const ReminderDetailsScreen({required this.reminderId, super.key});

  final String reminderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    return switch (ref.watch(reminderViewProvider(reminderId))) {
      AsyncData(value: final view?) => _Details(view: view, now: now),
      AsyncData() => Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Reminder not found',
          message: 'It may have been deleted.',
        ),
      ),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Something went wrong.\n$error')),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

enum _MenuAction { archive, restore, delete }

class _Details extends ConsumerWidget {
  const _Details({required this.view, required this.now});

  final ReminderView view;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = view.reminder.isArchived;
    final upcoming = ref
        .watch(scheduleEngineProvider)
        .upcomingFor(view.reminder, now, count: 6);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!archived)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/reminder/${view.id}/edit'),
            ),
          PopupMenuButton<_MenuAction>(
            tooltip: 'More',
            onSelected: (action) => _onMenu(context, ref, action),
            itemBuilder: (context) => [
              if (archived)
                const PopupMenuItem(
                  value: _MenuAction.restore,
                  child: ListTile(
                    leading: Icon(Icons.unarchive_outlined),
                    title: Text('Restore'),
                  ),
                )
              else
                const PopupMenuItem(
                  value: _MenuAction.archive,
                  child: ListTile(
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('Archive'),
                  ),
                ),
              PopupMenuItem(
                value: _MenuAction.delete,
                child: ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          _Header(view: view),
          const SizedBox(height: 24),
          _StatusPanel(view: view, now: now),
          const SizedBox(height: 16),
          _ScheduleCard(view: view, now: now),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 16),
            _UpcomingCard(upcoming: upcoming, now: now),
          ],
          const SizedBox(height: 24),
          _HistorySection(reminderId: view.id, now: now),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.archive:
        await archiveReminder(context, ref, view);
      case _MenuAction.restore:
        await restoreReminder(context, ref, view);
      case _MenuAction.delete:
        final router = GoRouter.of(context);
        await deleteReminder(
          context,
          ref,
          view,
          beforeDelete: () => router.canPop() ? router.pop() : router.go('/'),
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view});

  final ReminderView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final description = view.reminder.description;
    final muted =
        !view.isWaiting && view.status != ReminderStatus.scheduled;

    return Column(
      children: [
        Hero(
          tag: 'thumb-${view.id}',
          child: StatusThumb(waiting: view.isWaiting, muted: muted, size: 96),
        ),
        const SizedBox(height: 20),
        Text(
          view.reminder.name,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Tooltip(
          message: 'Display name: shown on the widget and in notifications',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.widgets_outlined,
                  size: 16,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    view.reminder.displayName,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 14),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// The colored panel saying where the reminder stands, with the one action
/// that matters most right now.
class _StatusPanel extends ConsumerWidget {
  const _StatusPanel({required this.view, required this.now});

  final ReminderView view;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final formatter = TimeFormatter.of(context);
    final today = LocalDate.fromDateTime(now);

    Widget panel({
      required Color background,
      required Color foreground,
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      List<Widget> actions = const [],
    }) => AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (actions.isNotEmpty) ...[const SizedBox(height: 16), ...actions],
        ],
      ),
    );

    switch (view.status) {
      case ReminderStatus.waiting:
        return panel(
          background: status.negativeContainer,
          foreground: status.onNegativeContainer,
          icon: Icons.notifications_active_rounded,
          title:
              'Waiting since '
              '${formatCompactMoment(view.runtime.pendingAt!, now, formatter)}',
          subtitle: view.reminder.paused
              ? 'Paused — no new activations until you resume it.'
              : null,
          trailing: view.missedCount > 0
              ? MissedBadge(count: view.missedCount)
              : null,
          actions: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: status.negative,
                foregroundColor: status.onNegative,
                minimumSize: const Size.fromHeight(56),
                textStyle: theme.textTheme.titleMedium,
              ),
              onPressed: () => acknowledgeReminder(context, ref, view),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Acknowledge'),
            ),
          ],
        );
      case ReminderStatus.scheduled:
        return panel(
          background: status.positiveContainer,
          foreground: status.onPositiveContainer,
          icon: Icons.check_circle_rounded,
          title: 'All clear',
          subtitle:
              'Next: ${formatMoment(view.nextActivation!, now, formatter)}',
        );
      case ReminderStatus.paused:
        return panel(
          background: scheme.surfaceContainerHigh,
          foreground: scheme.onSurface,
          icon: Icons.pause_circle_rounded,
          title: 'Paused',
          subtitle: 'It won’t activate until you resume it.',
          actions: [
            FilledButton.tonalIcon(
              onPressed: () =>
                  setReminderPaused(context, ref, view, paused: false),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume'),
            ),
          ],
        );
      case ReminderStatus.ended:
        return panel(
          background: scheme.surfaceContainerHigh,
          foreground: scheme.onSurface,
          icon: Icons.event_busy_rounded,
          title: 'No more activations',
          subtitle: 'It moves to the archive automatically.',
        );
      case ReminderStatus.archived:
        return panel(
          background: scheme.surfaceContainerHigh,
          foreground: scheme.onSurface,
          icon: Icons.inventory_2_rounded,
          title:
              'Archived · ${formatDay(LocalDate.fromDateTime(view.reminder.archivedAt!), today)}',
          subtitle: 'Archived reminders never activate.',
          actions: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => restoreReminder(context, ref, view),
                    icon: const Icon(Icons.unarchive_outlined),
                    label: const Text('Restore'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      deleteReminder(
                        context,
                        ref,
                        view,
                        beforeDelete: () =>
                            router.canPop() ? router.pop() : router.go('/'),
                      );
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.view, required this.now});

  final ReminderView view;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = view.reminder.schedule;
    final formatter = TimeFormatter.of(context);
    final today = LocalDate.fromDateTime(now);
    final repeat = switch (schedule.recurrence) {
      final RepeatRecurrence repeat => repeat,
      OnceRecurrence() => null,
    };

    return SectionCard(
      icon: Icons.event_repeat_rounded,
      title: 'Schedule',
      children: [
        _InfoRow(
          icon: Icons.repeat_rounded,
          label: 'When',
          value: describeRecurrence(schedule.recurrence, today: today),
        ),
        _InfoRow(
          icon: Icons.schedule_rounded,
          label: 'Time',
          value: describeTiming(schedule.timing, formatter),
        ),
        if (repeat != null) ...[
          _InfoRow(
            icon: Icons.flag_outlined,
            label: 'Starts',
            value: formatDate(repeat.startDate),
          ),
          _InfoRow(
            icon: Icons.event_available_rounded,
            label: 'Ends',
            value: switch (repeat.endDate) {
              final endDate? => formatDate(endDate),
              null => 'Never',
            },
          ),
        ],
        if (!view.reminder.isArchived) ...[
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.pause_circle_outline_rounded),
            title: const Text('Pause reminder'),
            subtitle: const Text('No activations while paused'),
            value: view.reminder.paused,
            onChanged: (paused) =>
                setReminderPaused(context, ref, view, paused: paused),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.upcoming, required this.now});

  final List<DateTime> upcoming;
  final DateTime now;

  @override
  Widget build(BuildContext context) => SectionCard(
    icon: Icons.notifications_none_rounded,
    title: 'Coming up',
    children: [ActivationTimes(times: upcoming, now: now)],
  );
}

/// The reminder's history, newest first, grouped by day, loaded in pages.
class _HistorySection extends ConsumerStatefulWidget {
  const _HistorySection({required this.reminderId, required this.now});

  final String reminderId;
  final DateTime now;

  @override
  ConsumerState<_HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends ConsumerState<_HistorySection> {
  static const _pageSize = 30;
  int _limit = _pageSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final historyAsync = ref.watch(
      historyProvider((reminderId: widget.reminderId, limit: _limit)),
    );
    final records = historyAsync.value ?? const <ActivationRecord>[];
    final today = LocalDate.fromDateTime(widget.now);

    final tiles = <Widget>[];
    LocalDate? currentDay;
    for (final record in records) {
      final day = LocalDate.fromDateTime(record.scheduledAt);
      if (day != currentDay) {
        currentDay = day;
        tiles.add(
          Padding(
            padding: EdgeInsets.fromLTRB(16, tiles.isEmpty ? 14 : 18, 16, 4),
            child: Text(
              formatDay(day, today),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      tiles.add(_HistoryTile(record: record, now: widget.now));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('History', style: theme.textTheme.titleMedium),
        ),
        if (records.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                historyAsync.isLoading
                    ? 'Loading…'
                    : 'Nothing yet — every activation will be listed here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: tiles,
              ),
            ),
          ),
        if (records.length >= _limit)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () => setState(() => _limit += _pageSize),
              child: const Text('Show more'),
            ),
          ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record, required this.now});

  final ActivationRecord record;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    final formatter = TimeFormatter.of(context);
    final acknowledgedAt = record.acknowledgedAt;

    final (icon, color, label) = switch (record.status) {
      ActivationStatus.acknowledged => (
        Icons.check_circle_rounded,
        status.positive,
        acknowledgedAt == null
            ? 'Acknowledged'
            : 'Acknowledged ${_when(acknowledgedAt, formatter)}',
      ),
      ActivationStatus.missed => (
        Icons.cancel_rounded,
        status.negative,
        'Missed',
      ),
      ActivationStatus.pending => (
        Icons.hourglass_top_rounded,
        status.negative,
        'Waiting for acknowledgment',
      ),
    };

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: color),
      title: Text(
        formatter.instant(record.scheduledAt),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      subtitle: Text(label),
    );
  }

  String _when(DateTime at, TimeFormatter formatter) {
    final sameDay =
        LocalDate.fromDateTime(at) == LocalDate.fromDateTime(record.scheduledAt);
    return sameDay
        ? 'at ${formatter.instant(at)}'
        : formatMoment(at, now, formatter);
  }
}
