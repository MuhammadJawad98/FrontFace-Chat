import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';

void main() {
  testWidgets('frontFaceWaitForNavigatorContext returns context once mounted',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const SizedBox(),
      ),
    );
    await tester.pump();

    final ctx = await frontFaceWaitForNavigatorContext(
      key,
      timeout: const Duration(seconds: 1),
    );
    expect(ctx, isNotNull);
    expect(ctx!.mounted, isTrue);
  });
}
