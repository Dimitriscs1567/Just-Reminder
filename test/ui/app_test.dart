import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/app.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/schedule.dart';
import 'package:just_reminder/src/services/app_events.dart';
import 'package:just_reminder/src/state/now.dart';
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
  times: [ReminderTime(start: LocalTime(9, 0))],
);

void main() {
  testWidgets('an empty list invites to create a reminder', (tester) async {
    final harness = await TestHarness.create(tester);
    await harness.pumpApp(tester);

    expect(find.text('No reminders yet'), findsOneWidget);
    expect(find.text('Create a reminder'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('a due reminder is marked done from the list', (
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

    expect(find.text('1 reminder is due'), findsOneWidget);
    expect(find.text('Due now · 1'), findsOneWidget);
    // Tests run with 12-hour times (a narrow no-break space before AM).
    expect(find.text('Due since 9:00 AM'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing due'), findsOneWidget);
    expect(find.text('“Drink water” done'), findsOneWidget);
    expect(find.text('Coming up · 1'), findsOneWidget);
    expect(
      find.text('Done 9:05 AM · next tomorrow 9:00 AM'),
      findsOneWidget,
    );
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
    expect(find.text('Next reminders'), findsNothing);
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
    expect(find.text('Nothing due'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('pausing stops reminders; resuming starts from now', (
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
    expect(find.text('It won’t remind you until you resume it.'), findsOneWidget);

    // 09:00 passes while it is paused.
    harness.now = DateTime(2026, 11, 4, 9, 5);
    await tester.runAsync(harness.service.syncAll);
    await tester.pumpAndSettle();
    expect(find.textContaining('Due since'), findsNothing);

    // Resuming does not catch up on 09:00.
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.text('Resumed'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('Nothing due'), findsOneWidget);
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
          times: [ReminderTime(start: LocalTime(9, 0))],
        ),
      );
      harness.now = DateTime(2026, 11, 4, 9, 5);
      await harness.service.markDone(reminder.id); // finished: archived
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
      find.text('This schedule never reminds you. Pick a later date or time.'),
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
    expect(find.text('Nothing due'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('each time is one reminder; a missed one counts that day', (
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
        schedule: const Schedule(
          recurrence: RepeatRecurrence(
            unit: RepeatUnit.day,
            startDate: LocalDate(2026, 11, 4),
          ),
          times: [
            ReminderTime(
              start: LocalTime(9, 0),
              end: LocalTime(10, 0),
              mode: NotifyMode.repeat,
              intervalMinutes: 15,
            ),
            ReminderTime(start: LocalTime(12, 0)),
          ],
        ),
      ),
    );

    // 09:00–10:00 passed without Done: missed, nothing due.
    harness.now = DateTime(2026, 11, 4, 11);
    await harness.pumpApp(tester);
    expect(find.text('Missed 9:00 AM · next 12:00 PM'), findsOneWidget);
    expect(find.text('1 missed'), findsOneWidget);
    expect(find.text('Nothing due'), findsOneWidget);

    // 12:00 is due, still showing the day's missed one.
    harness.now = DateTime(2026, 11, 4, 12, 1);
    await tester.runAsync(harness.service.syncAll);
    await tester.pumpAndSettle();
    expect(find.text('Due since 12:00 PM'), findsOneWidget);
    expect(find.text('1 missed'), findsOneWidget);

    // The history lists each time once.
    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('History'), 300);
    await tester.pumpAndSettle();
    // (Also among the chips of the next days.)
    expect(
      find.widgetWithText(ListTile, '9:00 AM – 10:00 AM'),
      findsOneWidget,
    );
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('12:00 PM'), findsWidgets);
    await harness.dispose(tester);
  });

  testWidgets('a change shown at the minute tick is recorded right away', (
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
        schedule: const Schedule(
          recurrence: RepeatRecurrence(
            unit: RepeatUnit.day,
            startDate: LocalDate(2026, 11, 4),
          ),
          times: [ReminderTime(start: LocalTime(9, 0), end: LocalTime(9, 30))],
        ),
      ),
    );
    harness.now = DateTime(2026, 11, 4, 9, 10);
    await harness.pumpApp(tester);
    expect(find.text('Due now · 1'), findsOneWidget);

    // The minute tick at 09:30 shows it missed before the sync timer
    // (09:30 + 1 s) fires; the app still records it then.
    harness.now = DateTime(2026, 11, 4, 9, 30);
    ProviderScope.containerOf(
      tester.element(find.byType(JustReminderApp)),
    ).read(nowProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('1 missed'), findsOneWidget);
    final runtime = await tester.runAsync(
      () => harness.repository.getRuntime(reminder!.id),
    );
    expect(runtime?.isFiring, isFalse);
    expect(runtime?.missedCount, 1);
    await harness.dispose(tester);
  });

  testWidgets('going back from a due reminder flies its icon home cleanly', (
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
    await harness.pumpApp(tester);
    expect(find.text('Due now · 1'), findsOneWidget);

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget);

    // The status icon flies back to the card, whose icon can be tapped for
    // Done; the flying copy must not need the card's Material.
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Due now · 1'), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('the editor adds a second time and saves both', (tester) async {
    final harness = await TestHarness.create(tester);
    await harness.pumpApp(tester);

    await tester.tap(find.text('Create a reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Stretch');
    await tester.pump();

    // Far down the editor: not built until scrolled to.
    await tester.scrollUntilVisible(
      find.text('Add time'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add time'));
    await tester.pumpAndSettle();
    // Added an hour after the first (10:00) and opened.
    expect(find.text('Remove this time'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('“Stretch” created'), findsOneWidget);
    expect(
      find.text('Every day · 10:00 AM, 11:00 AM'),
      findsOneWidget,
    );
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
