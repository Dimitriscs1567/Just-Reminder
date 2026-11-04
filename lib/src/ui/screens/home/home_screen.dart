import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/now.dart';
import '../../../state/reminder_views.dart';
import '../../components/empty_state.dart';
import '../../components/reminder_card.dart';
import '../../components/status_thumb.dart';
import '../../formatting.dart';
import '../../theme/app_theme.dart';

/// The reminder list: what needs attention first, then what's coming up,
/// then paused reminders.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewsAsync = ref.watch(reminderViewsProvider);
    final now = ref.watch(nowProvider);
    final live = [
      for (final view in viewsAsync.value ?? const <ReminderView>[])
        if (view.status != ReminderStatus.archived) view,
    ];

    return Scaffold(
      body: switch (viewsAsync) {
        AsyncData() => _HomeBody(views: live, now: now),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Something went wrong.\n$error'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: live.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New reminder'),
            ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.views, required this.now});

  final List<ReminderView> views;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final waiting = [
      for (final view in views)
        if (view.status == ReminderStatus.waiting) view,
    ]..sort((a, b) => a.runtime.pendingAt!.compareTo(b.runtime.pendingAt!));
    final upcoming = [
      for (final view in views)
        if (view.status == ReminderStatus.scheduled ||
            view.status == ReminderStatus.ended)
          view,
    ]..sort(_byNextActivation);
    final paused = [
      for (final view in views)
        if (view.status == ReminderStatus.paused) view,
    ]..sort((a, b) => a.reminder.name.compareTo(b.reminder.name));

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('Just Reminder'),
          actions: [
            IconButton(
              tooltip: 'Archive',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => context.push('/archive'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        if (views.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No reminders yet',
              message:
                  'Set one up and it will nudge you at the right time — '
                  'once, or on a schedule.',
              action: FilledButton.icon(
                onPressed: () => context.push('/new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a reminder'),
              ),
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _SummaryCard(
                waiting: waiting,
                next: upcoming.firstOrNull,
                now: now,
              ),
            ),
          ),
          ..._section(context, 'Needs attention', waiting),
          ..._section(context, 'Coming up', upcoming),
          ..._section(context, 'Paused', paused),
          const SliverToBoxAdapter(child: SizedBox(height: 104)),
        ],
      ],
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<ReminderView> items,
  ) {
    if (items.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Text(
            '$title · ${items.length}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => ReminderCard(
            key: ValueKey(items[index].id),
            view: items[index],
            now: now,
          ),
        ),
      ),
    ];
  }

  static int _byNextActivation(ReminderView a, ReminderView b) {
    final x = a.nextActivation;
    final y = b.nextActivation;
    if (x == null && y == null) return a.reminder.name.compareTo(b.reminder.name);
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }
}

/// The big "all clear" / "needs you" card at the top.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.waiting,
    required this.next,
    required this.now,
  });

  final List<ReminderView> waiting;
  final ReminderView? next;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final isWaiting = waiting.isNotEmpty;
    final background = isWaiting
        ? status.negativeContainer
        : status.positiveContainer;
    final foreground = isWaiting
        ? status.onNegativeContainer
        : status.onPositiveContainer;
    final next = this.next;
    final nextAt = next?.nextActivation;

    final title = switch (waiting.length) {
      0 => 'All clear',
      1 => '1 reminder needs you',
      final count => '$count reminders need you',
    };
    final subtitle = switch (waiting.length) {
      0 when next != null && nextAt != null =>
        'Next: ${next.reminder.displayName} · '
            '${formatCompactMoment(nextAt, now, TimeFormatter.of(context))}',
      0 => 'Nothing is scheduled right now.',
      1 => 'Acknowledge it once it’s done.',
      _ => 'Acknowledge them once they’re done.',
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          StatusThumb(waiting: isWaiting, size: 64),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
