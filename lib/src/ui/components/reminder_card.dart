import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/local_date.dart';
import '../../state/reminder_views.dart';
import '../formatting.dart';
import '../reminder_actions.dart';
import '../theme/app_theme.dart';
import 'status_thumb.dart';

/// A reminder in a list: thumb, name, schedule and status. Waiting reminders
/// get a red tint and a big Acknowledge button.
class ReminderCard extends ConsumerWidget {
  const ReminderCard({required this.view, required this.now, super.key});

  final ReminderView view;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final waiting = view.isWaiting;

    return Card(
      color: waiting
          ? Color.alphaBlend(
              status.negativeContainer.withValues(alpha: 0.55),
              theme.cardTheme.color ?? scheme.surfaceContainerLow,
            )
          : null,
      child: InkWell(
        onTap: () => context.push('/reminder/${view.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Hero(
                    tag: 'thumb-${view.id}',
                    child: StatusThumb(
                      waiting: waiting,
                      muted: !waiting && view.status != ReminderStatus.scheduled,
                      size: 44,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.reminder.name,
                          style: theme.textTheme.titleMedium,
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
                            color: scheme.onSurfaceVariant,
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
              if (waiting) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: status.negative,
                    foregroundColor: status.onNegative,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => acknowledgeReminder(context, ref, view),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Acknowledge'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line saying where a reminder stands ("Next: Today · 14:30", …).
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

    final (icon, text, color) = switch (view.status) {
      ReminderStatus.waiting => (
        Icons.notifications_active_rounded,
        'Since ${formatCompactMoment(view.runtime.pendingAt!, now, formatter)}',
        status.onNegativeContainer,
      ),
      ReminderStatus.scheduled => (
        Icons.schedule_rounded,
        'Next: ${formatCompactMoment(view.nextActivation!, now, formatter)}',
        scheme.primary,
      ),
      ReminderStatus.paused => (
        Icons.pause_circle_outline_rounded,
        'Paused',
        scheme.onSurfaceVariant,
      ),
      ReminderStatus.ended => (
        Icons.event_busy_rounded,
        'No more activations',
        scheme.onSurfaceVariant,
      ),
      ReminderStatus.archived => (
        Icons.inventory_2_outlined,
        'Archived · ${formatDay(LocalDate.fromDateTime(view.reminder.archivedAt!), LocalDate.fromDateTime(now))}',
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (view.missedCount > 0) ...[
          const SizedBox(width: 8),
          MissedBadge(count: view.missedCount),
        ],
      ],
    );
  }
}

/// "2 missed" pill.
class MissedBadge extends StatelessWidget {
  const MissedBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.negative,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count missed',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: status.onNegative,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
