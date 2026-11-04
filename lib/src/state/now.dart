import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The current time, refreshed at every minute boundary (and on demand), so
/// time-based labels and states stay current while the app is open.
final nowProvider = NotifierProvider<NowNotifier, DateTime>(NowNotifier.new);

class NowNotifier extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    final now = ref.watch(clockProvider)();
    _scheduleTick(now);
    return now;
  }

  /// Re-reads the clock, e.g. right after a sync.
  void refresh() {
    final now = ref.read(clockProvider)();
    state = now;
    _scheduleTick(now);
  }

  void _scheduleTick(DateTime now) {
    _timer?.cancel();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(nextMinute.difference(now), refresh);
  }
}
