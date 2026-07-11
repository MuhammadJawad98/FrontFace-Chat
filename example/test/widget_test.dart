import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat_example/main.dart';

void main() {
  testWidgets('example home shows credentials and language switcher', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Project ID'), findsOneWidget);
    expect(find.text('Publishable key'), findsOneWidget);
    expect(find.text('Open chat'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
  });

  testWidgets('switching to Arabic updates home copy', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    expect(find.text('فتح المحادثة'), findsOneWidget);
    expect(find.text('معرّف المشروع'), findsOneWidget);
  });
}
