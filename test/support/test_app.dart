import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/app.dart';
import 'package:just_reminder/src/data/reminder_repository.dart';
import 'package:just_reminder/src/services/ack_inbox.dart';
import 'package:just_reminder/src/services/reminder_service.dart';
import 'package:just_reminder/src/state/now.dart';
import 'package:just_reminder/src/state/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sembast/sembast_memory.dart';

/// The real app on an in-memory database, an in-memory acknowledgment
/// inbox and a clock the test controls.
class TestHarness {
  TestHarness._(this.db, this.now);

  static Future<TestHarness> create(
    WidgetTester tester, {
    DateTime? now,
  }) async {
    final db = await tester.runAsync(
      () => newDatabaseFactoryMemory().openDatabase('test.db'),
    );
    return TestHarness._(db!, now ?? DateTime(2026, 11, 4, 9, 30));
  }

  final Database db;
  final inbox = MemoryAckInbox();

  /// The current time for the app and [service].
  DateTime now;

  late final repository = ReminderRepository(db);
  late final service = ReminderService(
    repository: repository,
    inbox: inbox,
    clock: () => now,
  );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ackInboxProvider.overrideWithValue(inbox),
          clockProvider.overrideWithValue(() => now),
          nowProvider.overrideWith(() => _TestNow(() => now)),
        ],
        child: const JustReminderApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Tears the app down (cancelling its timers) and closes the database.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  }
}

/// A [NowNotifier] without the minute timer.
class _TestNow extends NowNotifier {
  _TestNow(this._read);

  final DateTime Function() _read;

  @override
  DateTime build() => _read();

  @override
  void refresh() => state = _read();
}
