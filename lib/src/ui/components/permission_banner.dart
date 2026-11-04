import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/providers.dart';

/// Asks for what reminders need to reach the user: permission to show
/// notifications, and (Android 12+) exact alarms so they arrive on time.
/// Shows nothing when everything is allowed.
class PermissionBanner extends ConsumerWidget {
  const PermissionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(notificationServiceProvider);
    final permissions = ref.watch(notificationPermissionsProvider).value;
    if (service == null || permissions == null) return const SizedBox.shrink();

    void recheck() => ref.invalidate(notificationPermissionsProvider);

    if (!permissions.enabled) {
      return _Banner(
        icon: Icons.notifications_off_outlined,
        title: 'Notifications are off',
        message: 'Reminders can’t alert you until you allow notifications.',
        action: 'Allow',
        onAction: () async {
          await service.requestPermission();
          if (!(await service.permissions()).enabled) {
            await service.openSettings();
          }
          recheck();
        },
      );
    }
    if (!permissions.exactAlarms) {
      return _Banner(
        icon: Icons.alarm_rounded,
        title: 'Allow on-time reminders',
        message:
            'Without “Alarms & reminders”, Android may deliver reminders a '
            'few minutes late.',
        action: 'Allow',
        onAction: () async {
          await service.requestExactAlarms();
          recheck();
        },
      );
    }
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: scheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(icon, color: scheme.onTertiaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onAction, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}
