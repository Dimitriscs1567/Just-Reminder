import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/now.dart';
import '../state/providers.dart';
import '../state/reminder_views.dart';

/// Keeps the data current while the app runs: syncs on start, whenever the
/// app comes back to the foreground (acknowledgments made on the widget or a
/// notification are applied then), and exactly when the next activation is
/// due.
class SyncScope extends ConsumerStatefulWidget {
  const SyncScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope> {
  late final AppLifecycleListener _lifecycle;
  ProviderSubscription<DateTime?>? _nextActivation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _sync);
    _nextActivation = ref.listenManual(
      nextActivationProvider,
      (_, next) => _scheduleSyncAt(next),
      fireImmediately: true,
    );
    unawaited(_sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nextActivation?.close();
    _lifecycle.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) => widget.child;
}
