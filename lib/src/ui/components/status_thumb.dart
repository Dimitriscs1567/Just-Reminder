import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// The app's core signal: a red thumbs down while a reminder waits for
/// acknowledgment, a green thumbs up otherwise. [muted] (paused, archived)
/// shows a neutral thumb.
class StatusThumb extends StatelessWidget {
  const StatusThumb({
    required this.waiting,
    this.size = 48,
    this.muted = false,
    super.key,
  });

  final bool waiting;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    final scheme = Theme.of(context).colorScheme;
    final background = muted
        ? scheme.surfaceContainerHighest
        : waiting
        ? status.negative
        : status.positive;
    final foreground = muted
        ? scheme.onSurfaceVariant
        : waiting
        ? status.onNegative
        : status.onPositive;

    return Semantics(
      label: waiting ? 'Waiting for acknowledgment' : 'Nothing waiting',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          boxShadow: muted
              ? null
              : [
                  BoxShadow(
                    color: background.withValues(alpha: 0.35),
                    blurRadius: size / 4,
                    offset: Offset(0, size / 12),
                  ),
                ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: RotationTransition(
              turns: Tween<double>(begin: -0.1, end: 0).animate(animation),
              child: child,
            ),
          ),
          child: Icon(
            waiting ? Icons.thumb_down_rounded : Icons.thumb_up_rounded,
            key: ValueKey(waiting),
            size: size * 0.5,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
