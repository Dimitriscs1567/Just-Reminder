import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../state/providers.dart';
import '../state/reminder_views.dart';

/// User-facing reminder actions with their feedback (snackbars, dialogs),
/// shared by all screens.

Future<void> acknowledgeReminder(
  BuildContext context,
  WidgetRef ref,
  ReminderView view,
) async {
  unawaited(HapticFeedback.mediumImpact());
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(reminderServiceProvider).acknowledge(view.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('“${view.reminder.name}” acknowledged')),
    );
}

Future<void> setReminderPaused(
  BuildContext context,
  WidgetRef ref,
  ReminderView view, {
  required bool paused,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  await ref
      .read(reminderServiceProvider)
      .setPaused(view.id, paused: paused);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(paused ? 'Paused' : 'Resumed')),
    );
}

Future<void> archiveReminder(
  BuildContext context,
  WidgetRef ref,
  ReminderView view,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(reminderServiceProvider);
  // Undo restores cleanly only when nothing was waiting (archiving records
  // a waiting activation as missed).
  final canUndo = !view.isWaiting;
  await service.archive(view.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Moved to the archive'),
        action: canUndo
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () => unawaited(service.restore(view.id)),
              )
            : null,
      ),
    );
}

/// Restores [view]; when its schedule could never activate again (e.g. a
/// finished one-time reminder), the editor opens first to pick a new date.
Future<void> restoreReminder(
  BuildContext context,
  WidgetRef ref,
  ReminderView view,
) async {
  final now = ref.read(clockProvider)();
  final asRestored = view.reminder.copyWith(archivedAt: null, activeSince: now);
  if (ref.read(scheduleEngineProvider).isFinished(asRestored, now)) {
    await context.push('/reminder/${view.id}/edit?mode=restore');
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(reminderServiceProvider).restore(view.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Restored')));
}

/// Asks for confirmation, then deletes [view] and its history. Returns
/// whether it was deleted. [beforeDelete] runs after confirmation, e.g. to
/// leave the reminder's screen first.
Future<bool> deleteReminder(
  BuildContext context,
  WidgetRef ref,
  ReminderView view, {
  VoidCallback? beforeDelete,
}) async {
  final service = ref.read(reminderServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text('Delete “${view.reminder.name}”?'),
        content: const Text(
          'The reminder and its whole history will be deleted. '
          'This can’t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return false;
  beforeDelete?.call();
  await service.delete(view.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('“${view.reminder.name}” deleted')),
    );
  return true;
}
