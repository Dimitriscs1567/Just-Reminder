import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/local_date.dart';
import '../../domain/occurrence_record.dart';
import '../../state/reminder_views.dart';
import '../formatting.dart';
import '../reminder_actions.dart';
import '../theme/app_theme.dart';
import 'status_icon.dart';

/// A reminder in a list: status icon, name, schedule and status. A due
/// reminder gets a soft teal tint and a Done button.
class ReminderCard extends ConsumerWidget {
  const ReminderCard({required this.view, required this.now, super.key});

  final ReminderView view;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final firing = view.isFiring;
    final background = firing
        ? status.dueContainer
        : theme.cardTheme.color ?? scheme.surfaceContainerLow;

    return Card(
      color: background,
      child: InkWell(
        onTap: () => context.push('/reminder/${view.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  StatusIcon(
                    kind: StatusIconKind.of(view.status),
                    size: 44,
                    surface: background,
                    heroTag: statusHeroTag(view.id),
                    onTap: firing
                        ? () => markReminderDone(context, ref, view)
                        : null,
                    tooltip: firing ? 'Done' : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.reminder.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: firing ? status.onDueContainer : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          describeSchedule(
                            view.reminder.schedule,
                            TimeFormatter.of(context),
                            today: LocalDate.fromDateTime(now),
                            // The status line already shows the next date.
                            includeOnceDate:
                                view.status == ReminderStatus.archived,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: firing
                                ? status.onDueContainer
                                : scheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        ReminderStatusLine(view: view, now: now),
                      ],
                    ),
                  ),
                ],
              ),
              if (firing) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: status.due,
                    foregroundColor: status.onDue,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => markReminderDone(context, ref, view),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Done'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line saying where a reminder stands: "Due since 12:00",
/// "Missed 12:00 · next tomorrow 09:00", "Done 11:04 · next 16:00", …
class ReminderStatusLine extends StatelessWidget {
  const ReminderStatusLine({required this.view, required this.now, super.key});

  final ReminderView view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final formatter = TimeFormatter.of(context);
    final today = LocalDate.fromDateTime(now);
    final nextAt = view.next?.start;
    String next() => nextAt == null
        ? ''
        : ' · next ${formatInlineMoment(nextAt, now, formatter)}';
    final last = view.lastToday;

    final (icon, text, color) = switch (view.status) {
      ReminderStatus.firing => (
        Icons.notifications_active_outlined,
        'Due since '
            '${formatCompactMoment(view.due!.dueAt, now, formatter)}',
        status.onDueContainer,
      ),
      ReminderStatus.missed => (
        Icons.schedule_rounded,
        'Missed ${formatter.instant(last!.start)}${next()}',
        scheme.onSurfaceVariant,
      ),
      ReminderStatus.done when last?.status == OccurrenceStatus.done => (
        Icons.schedule_rounded,
        'Done ${formatter.instant(last!.at)}${next()}',
        scheme.onSurfaceVariant,
      ),
      ReminderStatus.done => (
        Icons.schedule_rounded,
        'Next: ${formatCompactMoment(nextAt!, now, formatter)}',
        scheme.onSurfaceVariant,
      ),
      ReminderStatus.paused => (
        Icons.pause_circle_outline_rounded,
        'Paused',
        scheme.onSurfaceVariant,
      ),
      ReminderStatus.ended => (
        Icons.event_busy_rounded,
        'No more reminders',
        scheme.onSurfaceVariant,
      ),
      ReminderStatus.archived => (
        Icons.inventory_2_outlined,
        'Archived · '
            '${formatDay(LocalDate.fromDateTime(view.reminder.archivedAt!), today)}',
        scheme.onSurfaceVariant,
      ),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (view.missedCount > 0) ...[
          const SizedBox(width: 8),
          MissedBadge(count: view.missedCount, onDue: view.isFiring),
        ],
      ],
    );
  }
}

/// "2 missed" pill, always neutral (never red). [onDue] adapts it to the
/// teal background of a due reminder.
class MissedBadge extends StatelessWidget {
  const MissedBadge({required this.count, this.onDue = false, super.key});

  final int count;
  final bool onDue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.statusColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onDue
            ? status.due.withValues(alpha: 0.16)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count missed',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: onDue ? status.onDueContainer : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
