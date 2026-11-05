import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../state/reminder_views.dart';
import '../theme/app_theme.dart';

/// What a [StatusIcon] shows.
enum StatusIconKind {
  /// A teal ring with a thumbs-up: due, tap it for Done.
  firing,

  /// A gray dashed ring with a thumbs-up crossed by a dashed line.
  missed,

  /// A faint check: nothing due.
  done,

  /// A faint pause sign.
  paused,

  /// A faint check for reminders that are over (ended, archived).
  muted;

  static StatusIconKind of(ReminderStatus status) => switch (status) {
    ReminderStatus.firing => firing,
    ReminderStatus.missed => missed,
    ReminderStatus.done => done,
    ReminderStatus.paused => paused,
    ReminderStatus.ended || ReminderStatus.archived => muted,
  };
}

/// The [StatusIcon.heroTag] of a reminder's icon (list card ↔ details).
String statusHeroTag(String reminderId) => 'status-$reminderId';

/// A reminder's state at a glance (Product decisions → Look). Calm on
/// purpose: teal while due, neutral gray otherwise — never red.
class StatusIcon extends StatelessWidget {
  const StatusIcon({
    required this.kind,
    this.size = 48,
    this.surface,
    this.onTap,
    this.tooltip,
    this.heroTag,
    super.key,
  });

  final StatusIconKind kind;
  final double size;

  /// The color behind the icon; the missed sign's slash is cut out of the
  /// thumb with it. Defaults to the card color.
  final Color? surface;

  /// Makes it a button (the firing ring marks the reminder done).
  final VoidCallback? onTap;
  final String? tooltip;

  /// Flies the icon between screens (list card ↔ details). Only the drawing
  /// flies: the button around it needs the card's `Material`, which the
  /// flight's overlay doesn't have.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    Widget icon = Semantics(
      label: tooltip ?? _label,
      button: onTap != null,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        // Drawn for the size it really gets, which changes during a flight.
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: KeyedSubtree(
              key: ValueKey(kind),
              child: _drawing(context, constraints.biggest.shortestSide),
            ),
          ),
        ),
      ),
    );
    final heroTag = this.heroTag;
    if (heroTag != null) icon = Hero(tag: heroTag, child: icon);
    if (onTap == null) return icon;
    return Tooltip(
      message: tooltip ?? _label,
      child: InkResponse(
        onTap: onTap,
        radius: size / 2 + 6,
        child: icon,
      ),
    );
  }

  Widget _drawing(BuildContext context, double size) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final due = context.statusColors.due;
    final faint = scheme.outline;
    final stroke = math.max(2.0, size * 0.07);
    final background =
        surface ?? theme.cardTheme.color ?? scheme.surfaceContainerLow;

    return switch (kind) {
      StatusIconKind.firing => CustomPaint(
        painter: _RingPainter(color: due, strokeWidth: stroke),
        child: Center(
          child: Icon(Icons.thumb_up_rounded, size: size * 0.46, color: due),
        ),
      ),
      StatusIconKind.missed => CustomPaint(
        painter: _RingPainter(color: faint, strokeWidth: stroke, dashed: true),
        foregroundPainter: _SlashPainter(
          color: faint,
          gapColor: background,
          strokeWidth: stroke * 0.8,
        ),
        child: Center(
          child: Icon(
            Icons.thumb_up_outlined,
            size: size * 0.44,
            color: faint,
          ),
        ),
      ),
      StatusIconKind.done || StatusIconKind.muted => Center(
        child: Icon(Icons.check_rounded, size: size * 0.6, color: faint),
      ),
      StatusIconKind.paused => Center(
        child: Icon(Icons.pause_rounded, size: size * 0.6, color: faint),
      ),
    };
  }

  String get _label => switch (kind) {
    StatusIconKind.firing => 'Due',
    StatusIconKind.missed => 'Missed',
    StatusIconKind.done => 'Nothing due',
    StatusIconKind.paused => 'Paused',
    StatusIconKind.muted => 'Over',
  };
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.color,
    required this.strokeWidth,
    this.dashed = false,
  });

  final Color color;
  final double strokeWidth;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - strokeWidth / 2;
    if (!dashed) {
      canvas.drawCircle(center, radius, paint);
      return;
    }
    const dashes = 14;
    const sweep = 2 * math.pi / dashes;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep - math.pi / 2, sweep * 0.5, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashed != dashed;
}

/// A dashed line from bottom left to top right, cut out of what is below.
class _SlashPainter extends CustomPainter {
  const _SlashPainter({
    required this.color,
    required this.gapColor,
    required this.strokeWidth,
  });

  final Color color;
  final Color gapColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final reach = size.shortestSide * 0.3;
    final from = center + Offset(-reach, reach);
    final to = center + Offset(reach, -reach);
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = gapColor
        ..strokeWidth = strokeWidth * 2.2
        ..strokeCap = StrokeCap.round,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    const dashes = 4;
    final step = (to - from) / (dashes * 2 - 1);
    for (var i = 0; i < dashes; i++) {
      final start = from + step * (i * 2.0);
      canvas.drawLine(start, start + step, paint);
    }
  }

  @override
  bool shouldRepaint(_SlashPainter old) =>
      old.color != color ||
      old.gapColor != gapColor ||
      old.strokeWidth != strokeWidth;
}
