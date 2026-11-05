import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/app.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/services/app_events.dart';
import 'package:just_reminder/src/ui/routing/app_router.dart';
import 'package:just_reminder/src/ui/screens/details/reminder_details_screen.dart';
import 'package:just_reminder/src/ui/screens/home/home_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

const dailyAtNine = Schedule(
  recurrence: RepeatRecurrence(
    unit: RepeatUnit.day,
    startDate: LocalDate(2026, 11, 4),
  ),
  timing: FixedTiming(LocalTime(9, 0)),
);

void main() {
  testWidgets('an empty list invites to create a reminder', (tester) async {
    final harness = await TestHarness.create(tester);
    await harness.pumpApp(tester);

    expect(find.text('No reminders yet'), findsOneWidget);
    expect(find.text('Create a reminder'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('a waiting reminder is acknowledged from the list', (
    tester,
  ) async {
    final harness = await TestHarness.create(
      tester,
      now: DateTime(2026, 11, 4, 8),
    );
    await tester.runAsync(
      () => harness.service.create(
        name: 'Drink water',
        displayName: 'Water',
        schedule: dailyAtNine,
      ),
    );
    harness.now = DateTime(2026, 11, 4, 9, 5);
    await harness.pumpApp(tester); // the app syncs on start

    expect(find.text('1 reminder needs you'), findsOneWidget);
    expect(find.text('Needs attention · 1'), findsOneWidget);

    await tester.tap(find.text('Acknowledge'));
    await tester.pumpAndSettle();

    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('“Drink water” acknowledged'), findsOneWidget);
    expect(find.text('Coming up · 1'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('the editor validates, then creates the reminder', (
    tester,
  ) async {
    final harness = await TestHarness.create(tester);
    await harness.pumpApp(tester);

    await tester.tap(find.text('Create a reminder'));
    await tester.pumpAndSettle();
    expect(find.text('New reminder'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Stretch');
    await tester.pump();
    // The display name follows the name.
    expect(find.widgetWithText(TextField, 'Stretch'), findsNWidgets(2));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Back on the list (the editor's preview section is gone).
    expect(find.text('Next activations'), findsNothing);
    expect(find.text('“Stretch” created'), findsOneWidget);
    expect(find.text('Stretch'), findsOneWidget);
    expect(find.textContaining('Next: 10:00'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('editing saves changes; closing with changes asks first', (
    tester,
  ) async {
    final harness = await TestHarness.create(tester);
    await tester.runAsync(
      () => harness.service.create(
        name: 'Drink water',
        displayName: 'Water',
        schedule: dailyAtNine,
      ),
    );
    await harness.pumpApp(tester);
    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();

    // Close with unsaved changes -> confirmation -> discard.
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Drink water'),
      'Drink tea',
    );
    await tester.pump();
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Drink water'), findsOneWidget);

    // Edit and save.
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit reminder'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Drink water'),
      'Drink tea',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Changes saved'), findsOneWidget);
    expect(find.text('Drink tea'), findsOneWidget);
    // The display name was set explicitly, so it did not follow the name.
    expect(find.text('Water'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('a reminder can be archived and restored from its details', (
    tester,
  ) async {
    final harness = await TestHarness.create(tester);
    await tester.runAsync(
      () => harness.service.create(
        name: 'Drink water',
        displayName: 'Water',
        schedule: dailyAtNine,
      ),
    );
    await harness.pumpApp(tester);

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Moved to the archive'), findsOneWidget);
    expect(find.textContaining('Archived ·'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restored'), findsOneWidget);
    expect(find.text('All clear'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('pausing stops activations; resuming starts from now', (
    tester,
  ) async {
    final harness = await TestHarness.create(
      tester,
      now: DateTime(2026, 11, 4, 8),
    );
    await tester.runAsync(
      () => harness.service.create(
        name: 'Drink water',
        displayName: 'Water',
        schedule: dailyAtNine,
      ),
    );
    await harness.pumpApp(tester);
    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();

    // Below the fold of the 800×600 test screen; scrolling needs a frame.
    await tester.ensureVisible(find.text('Pause reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause reminder'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.text('It won’t activate until you resume it.'), findsOneWidget);

    // 09:00 passes while it is paused.
    harness.now = DateTime(2026, 11, 4, 9, 5);
    await tester.runAsync(harness.service.syncAll);
    await tester.pumpAndSettle();
    expect(find.textContaining('Waiting since'), findsNothing);

    // Resuming does not catch up on 09:00.
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.text('Resumed'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('All clear'), findsOneWidget);
    expect(find.textContaining('Next: Tomorrow'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('deleting asks first, then removes the reminder', (
    tester,
  ) async {
    final harness = await TestHarness.create(tester);
    final reminder = await tester.runAsync(
      () => harness.service.create(
        name: 'Drink water',
        displayName: 'Water',
        schedule: dailyAtNine,
      ),
    );
    await harness.pumpApp(tester);
    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();

    Future<void> chooseDelete() async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    await chooseDelete();
    expect(find.text('Delete “Drink water”?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget); // still on its details

    await chooseDelete();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('“Drink water” deleted'), findsOneWidget);
    expect(find.text('No reminders yet'), findsOneWidget);
    expect(
      await tester.runAsync(() => harness.repository.getReminder(reminder!.id)),
      isNull,
    );
    await harness.dispose(tester);
  });

  testWidgets('restoring a finished one-time reminder asks for a new date', (
    tester,
  ) async {
    final harness = await TestHarness.create(
      tester,
      now: DateTime(2026, 11, 4, 8),
    );
    await tester.runAsync(() async {
      final reminder = await harness.service.create(
        name: 'Call mom',
        displayName: 'Mom',
        schedule: const Schedule(
          recurrence: OnceRecurrence(LocalDate(2026, 11, 4)),
          timing: FixedTiming(LocalTime(9, 0)),
        ),
      );
      harness.now = DateTime(2026, 11, 4, 9, 5);
      await harness.service.acknowledge(reminder.id); // finished: archived
    });
    await harness.pumpApp(tester);

    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call mom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Restore reminder'), findsOneWidget);
    expect(find.textContaining('This reminder had finished.'), findsOneWidget);

    // Its date has passed, so it can't come back unchanged…
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(
      find.text('This schedule never activates. Pick a later date or time.'),
      findsOneWidget,
    );

    // …but it can as a repeating reminder.
    // (Scrolled up first: the snackbar covers the bottom of the screen.)
    await tester.ensureVisible(find.text('Repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('“Call mom” restored'), findsOneWidget);
    expect(find.text('All clear'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('a widget that launches the app opens its reminder at once', (
    tester,
  ) async {
    final harness = await TestHarness.create(
      tester,
      now: DateTime(2026, 11, 4, 8),
    );
    final reminder = await tester.runAsync(
      () => harness.service.create(
        name: 'Drink water',
        displayName: 'Water',
        schedule: dailyAtNine,
      ),
    );
    final events = AppEvents()..launchEvent = OpenReminder(reminder!.id);
    var startupReady = 0;
    await harness.pumpApp(
      tester,
      events: events,
      settle: false,
      onStartupReady: () => startupReady++,
    );

    // The very first frame is the reminder: no list, no router error page.
    final router = ProviderScope.containerOf(
      tester.element(find.byType(JustReminderApp)),
    ).read(routerProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/reminder/${reminder.id}',
    );
    expect(find.byType(ReminderDetailsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.pumpAndSettle();
    // Synced and loaded: main() lets the first frame through now.
    expect(startupReady, 1);
    expect(find.text('Drink water'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/reminder/${reminder.id}',
    );

    // Back leads to the list.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Coming up · 1'), findsOneWidget);
    await harness.dispose(tester);
  });
}
