import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/now.dart';
import '../../../state/reminder_views.dart';
import '../../components/empty_state.dart';
import '../../components/reminder_card.dart';

/// Archived reminders, most recently archived first. Open one to restore or
/// delete it.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final viewsAsync = ref.watch(reminderViewsProvider);
    final archived = [
      for (final view in viewsAsync.value ?? const <ReminderView>[])
        if (view.status == ReminderStatus.archived) view,
    ]..sort((a, b) => b.reminder.archivedAt!.compareTo(a.reminder.archivedAt!));

    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: switch (viewsAsync) {
        AsyncData() when archived.isEmpty => const EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'Nothing archived',
          message:
              'Finished reminders move here automatically. You can also '
              'archive a reminder from its details.',
        ),
        AsyncData() => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: archived.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => index == 0
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Archived reminders never remind you. Open one to restore '
                    'or delete it — its history is kept.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ReminderCard(view: archived[index - 1], now: now),
        ),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
