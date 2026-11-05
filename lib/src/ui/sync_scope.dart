import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../services/app_events.dart';
import '../state/now.dart';
import '../state/providers.dart';
import '../state/reminder_views.dart';
import 'routing/app_router.dart';

/// Keeps the app current while it runs:
/// - syncs on start, whenever the app comes back to the foreground
///   (acknowledgments made on a widget or notification are applied then)
///   and exactly when the next activation is due;
/// - handles [AppEvent]s: notification and widget taps open the reminder,
///   the notification's Acknowledge button (while the app runs)
///   acknowledges it.
class SyncScope extends ConsumerStatefulWidget {
  const SyncScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope> {
  late final AppLifecycleListener _lifecycle;
  ProviderSubscription<DateTime?>? _nextActivation;
  StreamSubscription<AppEvent>? _events;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _nextActivation = ref.listenManual(
      nextActivationProvider,
      (_, next) => _scheduleSyncAt(next),
      fireImmediately: true,
    );
    final events = ref.read(appEventsProvider);
    _events = events.stream.listen(_handle);
    unawaited(_startup());
    final launch = events.takeLaunchEvent();
    if (launch != null) {
      // After the first frame, so the router is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) => _handle(launch));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nextActivation?.close();
    unawaited(_events?.cancel());
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    ref.invalidate(notificationPermissionsProvider);
    unawaited(_sync());
  }

  /// The first sync. The launch screen stays up until it is done and the
  /// reminders are loaded, so no blank (loading) or outdated frame shows —
  /// e.g. a widget's reminder opens already showing it is waiting.
  Future<void> _startup() async {
    final ready = ref.read(startupReadyProvider);
    try {
      await _sync();
      if (mounted) {
        await Future.wait([
          ref.read(remindersProvider.future),
          ref.read(runtimesProvider.future),
        ]);
      }
    } finally {
      ready?.call();
    }
  }

  Future<void> _sync() async {
    try {
      await ref.read(reminderServiceProvider).syncAll();
    } finally {
      if (mounted) ref.read(nowProvider.notifier).refresh();
    }
  }

  void _scheduleSyncAt(DateTime? at) {
    _timer?.cancel();
    if (at == null) return;
    final delay = at.difference(ref.read(clockProvider)());
    // A second late, so the activation is safely in the past.
    _timer = Timer(
      (delay.isNegative ? Duration.zero : delay) + const Duration(seconds: 1),
      _sync,
    );
  }

  Future<void> _handle(AppEvent event) async {
    if (!mounted) return;
    final router = ref.read(routerProvider);
    switch (event) {
      case OpenReminder(:final reminderId):
        // Make sure a just-fired activation shows as waiting.
        await _sync();
        final location = reminderLocation(reminderId);
        // When this event launched the app, the router started there.
        if (router.routerDelegate.currentConfiguration.uri.path != location) {
          router.go(location);
        }
      case AcknowledgeReminder(:final reminderId):
        await ref.read(reminderServiceProvider).acknowledge(reminderId);
      case ExplainWidgetEditing():
        final context = router.routerDelegate.navigatorKey.currentContext;
        if (context == null || !context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.widgets_outlined),
            title: const Text('Choose another reminder'),
            content: const Text(
              'This widget’s reminder was archived or deleted. Long-press the '
              'widget, tap Edit Widget and pick another reminder.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
