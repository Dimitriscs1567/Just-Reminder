import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/app.dart';

void main() {
  testWidgets('app shell starts on the home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustReminderApp()));
    await tester.pumpAndSettle();

    expect(find.text('Just Reminder'), findsOneWidget);
  });
}
