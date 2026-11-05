import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/services/widget/widget_snapshot.dart';
import 'package:just_reminder/src/services/widget_storage_keys.dart';
import 'package:just_reminder/src/ui/screens/widget_config/list_widget_configuration_app.dart';
import 'package:just_reminder/src/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// The list widget's setup screen (Android), on home_widget storage
/// replaced by an in-memory map.
void main() {
  const channel = MethodChannel('home_widget');
  final storage = <String, Object?>{};

  setUp(() {
    storage
      ..clear()
      ..[WidgetStorageKeys.index] = jsonEncode([
        for (final (id, archived) in [('a', false), ('b', false), ('c', true)])
          {
            'id': id,
            'name': 'Name $id',
            'displayName': 'Show $id',
            'archived': archived,
          },
      ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = call.arguments as Map<Object?, Object?>?;
          switch (call.method) {
            case 'saveWidgetData':
              storage[arguments!['id']! as String] = arguments['data'];
              return true;
            case 'getWidgetData':
              return storage[arguments!['id']! as String] ??
                  arguments['defaultValue'];
            default:
              return true;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<List<bool>> pumpScreen(WidgetTester tester) async {
    final finished = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackColorScheme(Brightness.light)),
        home: ListWidgetConfigurationScreen(
          appWidgetId: 8,
          onFinished: () async => finished.add(true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return finished;
  }

  List<String> savedList() =>
      (jsonDecode(storage[WidgetStorageKeys.androidListWidget(8)]! as String)
              as List<Object?>)
          .cast<String>();

  Finder title(String text) =>
      find.descendant(of: find.byType(ListTile), matching: find.text(text));

  testWidgets('lists the reminders in the order they are ticked', (
    tester,
  ) async {
    final finished = await pumpScreen(tester);
    // Archived reminders can't be picked.
    expect(find.text('Show c'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(title('Show b'));
    await tester.pumpAndSettle();
    await tester.tap(title('Show a'));
    await tester.pumpAndSettle();
    expect(find.text('On the widget'), findsOneWidget);
    // b (ticked first) above a.
    expect(
      tester.getTopLeft(title('Show b')).dy,
      lessThan(tester.getTopLeft(title('Show a')).dy),
    );

    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    expect(savedList(), ['b', 'a']);
    expect(finished, [true]);
  });

  testWidgets('drag to change the order', (tester) async {
    storage[WidgetStorageKeys.androidListWidget(8)] = jsonEncode(['a', 'b']);
    await pumpScreen(tester);
    expect(find.text('Save'), findsOneWidget);

    final handle = find.byIcon(Icons.drag_handle_rounded).first;
    final rowHeight = tester.getSize(find.byType(ListTile).first).height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(Offset(0, rowHeight / 4));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(savedList(), ['b', 'a']);
  });

  testWidgets('a deleted reminder keeps its place until it is unticked', (
    tester,
  ) async {
    storage[WidgetStorageKeys.androidListWidget(8)] = jsonEncode(['gone', 'a']);
    storage[WidgetStorageKeys.snapshot('gone')] = jsonEncode(
      deletedWidgetSnapshot(id: 'gone', name: 'Old', displayName: 'Old one'),
    );
    await pumpScreen(tester);
    expect(title('Old one'), findsOneWidget);
    expect(find.text('Deleted'), findsOneWidget);

    await tester.tap(title('Old one'));
    await tester.pumpAndSettle();
    // Unticked: gone for good (it can't be picked again).
    expect(find.text('Old one'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(savedList(), ['a']);
  });
}
