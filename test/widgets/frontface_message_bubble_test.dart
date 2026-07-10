import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';

const _arabicStrings = FrontFaceChatStrings(
  textDirection: TextDirection.rtl,
  messageCopied: 'تم النسخ',
);

Future<void> _pump(
  WidgetTester tester,
  FrontFaceChatMessage message, {
  FrontFaceChatStrings strings = const FrontFaceChatStrings(),
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: strings.textDirection,
        child: Scaffold(
          body: FrontFaceMessageBubble(
            message: message,
            theme: const FrontFaceChatTheme(),
            strings: strings,
          ),
        ),
      ),
    ),
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Fake the clipboard platform channel so Clipboard.setData doesn't
    // throw MissingPluginException in widget tests.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') return null;
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  group('text direction — customer bubble', () {
    testWidgets('English customer message renders ltr', (tester) async {
      await _pump(
        tester,
        FrontFaceChatMessage.local(
          content: 'I want to sell my Mazda',
          senderType: FrontFaceSenderType.customer,
        ),
      );

      final text = tester.widget<Text>(find.text('I want to sell my Mazda'));
      expect(text.textDirection, TextDirection.ltr);
    });

    testWidgets('Arabic customer message renders rtl', (tester) async {
      await _pump(
        tester,
        FrontFaceChatMessage.local(
          content: 'أريد أن أبيع سيارتي',
          senderType: FrontFaceSenderType.customer,
        ),
        strings: _arabicStrings,
      );

      final text = tester.widget<Text>(find.text('أريد أن أبيع سيارتي'));
      expect(text.textDirection, TextDirection.rtl);
    });

    testWidgets(
      'English text stays ltr even inside an Arabic-configured chat',
      (tester) async {
        await _pump(
          tester,
          FrontFaceChatMessage.local(
            content: 'i want to sell my mazda',
            senderType: FrontFaceSenderType.customer,
          ),
          strings: _arabicStrings,
        );

        final text = tester.widget<Text>(find.text('i want to sell my mazda'));
        expect(text.textDirection, TextDirection.ltr);
      },
    );
  });

  group('markdown rendering — assistant bubble', () {
    testWidgets('bold markdown renders without literal asterisks', (
      tester,
    ) async {
      await _pump(
        tester,
        FrontFaceChatMessage.local(
          content: '- **Make and Model**: Mazda',
          senderType: FrontFaceSenderType.ai,
        ),
      );
      await tester.pump();

      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('Make and Model'), findsOneWidget);
    });

    testWidgets('Arabic assistant markdown wraps in rtl Directionality', (
      tester,
    ) async {
      await _pump(
        tester,
        FrontFaceChatMessage.local(
          content: 'مرحبا! **كيف يمكنني مساعدتك؟**',
          senderType: FrontFaceSenderType.ai,
        ),
      );
      await tester.pump();

      // The MarkdownBody itself is wrapped in a Directionality matching the
      // message's own detected direction, independent of the app shell.
      final directionalities = tester.widgetList<Directionality>(
        find.byType(Directionality),
      );
      expect(
        directionalities.any((d) => d.textDirection == TextDirection.rtl),
        isTrue,
      );
    });
  });

  group('copy to clipboard', () {
    testWidgets(
      'long-press copies English message and shows English snackbar',
      (tester) async {
        Object? copiedText;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = (call.arguments as Map)['text'];
            }
            return null;
          },
        );

        await _pump(
          tester,
          FrontFaceChatMessage.local(
            content: 'Hello there',
            senderType: FrontFaceSenderType.ai,
          ),
        );
        await tester.pump();

        await tester.longPress(find.textContaining('Hello there'));
        await tester.pump();

        expect(copiedText, 'Hello there');
        expect(find.text('Copied to clipboard'), findsOneWidget);
      },
    );

    testWidgets('long-press shows the Arabic copied confirmation', (
      tester,
    ) async {
      await _pump(
        tester,
        FrontFaceChatMessage.local(
          content: 'مرحبا',
          senderType: FrontFaceSenderType.customer,
        ),
        strings: _arabicStrings,
      );
      await tester.pump();

      await tester.longPress(find.text('مرحبا'));
      await tester.pump();

      expect(find.text('تم النسخ'), findsOneWidget);
    });
  });

  group('system messages', () {
    testWidgets('Arabic system message renders rtl and centered', (
      tester,
    ) async {
      await _pump(
        tester,
        FrontFaceChatMessage.local(
          content: 'انتهت المحادثة',
          senderType: FrontFaceSenderType.system,
        ),
        strings: _arabicStrings,
      );

      final text = tester.widget<Text>(find.text('انتهت المحادثة'));
      expect(text.textDirection, TextDirection.rtl);
      expect(text.textAlign, TextAlign.center);
    });
  });

  group('emoji', () {
    testWidgets(
      'emoji + Arabic customer message renders without error and stays rtl',
      (tester) async {
        await _pump(
          tester,
          FrontFaceChatMessage.local(
            content: '😀 مرحبا كيف حالك؟',
            senderType: FrontFaceSenderType.customer,
          ),
          strings: _arabicStrings,
        );

        expect(tester.takeException(), isNull);
        final text = tester.widget<Text>(find.textContaining('مرحبا'));
        expect(text.textDirection, TextDirection.rtl);
      },
    );

    testWidgets('emoji + markdown bold in an assistant message renders both', (
      tester,
    ) async {
      await _pump(
        tester,
        FrontFaceChatMessage.local(
          content: '🎉 **Congrats!** Your listing is live.',
          senderType: FrontFaceSenderType.ai,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('Congrats!'), findsOneWidget);
    });
  });
}
