import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';

void main() {
  Future<void> pumpIndicator(WidgetTester tester, TextDirection direction) {
    return tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: const Scaffold(
            body: FrontFaceTypingIndicator(theme: FrontFaceChatTheme()),
          ),
        ),
      ),
    );
  }

  testWidgets('renders three animated wave dots and animates without error', (
    tester,
  ) async {
    await pumpIndicator(tester, TextDirection.ltr);

    final indicator = find.byType(FrontFaceTypingIndicator);
    // Three dots, each driven by its own AnimatedBuilder + Transform.translate.
    expect(
      find.descendant(of: indicator, matching: find.byType(AnimatedBuilder)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: indicator, matching: find.byType(Transform)),
      findsNWidgets(3),
    );

    // Advance through a couple of animation cycles; must not throw.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  });

  testWidgets('renders correctly under an rtl ambient Directionality', (
    tester,
  ) async {
    await pumpIndicator(tester, TextDirection.rtl);

    expect(
      find.descendant(
        of: find.byType(FrontFaceTypingIndicator),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNWidgets(3),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
