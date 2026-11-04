import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/local_date.dart';
import 'package:just_reminder/src/core/local_time.dart';
import 'package:just_reminder/src/domain/schedule.dart';
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
}
