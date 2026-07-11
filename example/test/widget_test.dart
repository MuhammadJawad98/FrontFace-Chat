import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat_example/main.dart';

void main() {
  testWidgets('example home shows credential fields', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Project ID'), findsOneWidget);
    expect(find.text('Publishable key'), findsOneWidget);
    expect(find.text('Open chat'), findsOneWidget);
    expect(find.text('Corrupt stored session token'), findsOneWidget);
  });
}
