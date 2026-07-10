import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:frontface_chat/src/services/frontface_api_service.dart';
import 'package:frontface_chat/src/services/frontface_visitor_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_manager.dart';

const _arabicStrings = FrontFaceChatStrings(
  textDirection: TextDirection.rtl,
  typeMessage: 'اكتب رسالة...',
);

Future<FrontFaceChatProvider> _pumpScreen(
  WidgetTester tester,
  FakeApiManager fake, {
  FrontFaceChatStrings strings = const FrontFaceChatStrings(),
}) async {
  final api = FrontFaceApiService(config: testConfig, apiManager: fake);
  final provider = FrontFaceChatProvider(
    config: testConfig,
    strings: strings,
    api: api,
    store: FrontFaceVisitorStore(),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider.value(
        value: provider,
        child: const FrontFaceChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

TextField _inputField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('placeholder fallback', () {
    testWidgets('English default is shown when the server sends none', (
      tester,
    ) async {
      final fake = FakeApiManager(testConfig);
      await _pumpScreen(tester, fake);

      expect(_inputField(tester).decoration?.hintText, 'Type a message...');
    });

    testWidgets('Arabic string is shown when the server sends none', (
      tester,
    ) async {
      final fake = FakeApiManager(testConfig);
      await _pumpScreen(tester, fake, strings: _arabicStrings);

      expect(_inputField(tester).decoration?.hintText, 'اكتب رسالة...');
    });

    testWidgets('server-provided placeholder overrides the local fallback', (
      tester,
    ) async {
      final fake = FakeApiManager(testConfig);
      fake.embedConfigResponse = {
        'enabled': true,
        'config': {'greeting': 'Hi!', 'placeholder': 'كيف نساعدك؟'},
        'leadCapture': {'enabled': false},
      };
      await _pumpScreen(tester, fake, strings: _arabicStrings);

      expect(_inputField(tester).decoration?.hintText, 'كيف نساعدك؟');
    });
  });

  group('title override', () {
    testWidgets('server-provided title is used when strings.title is null', (
      tester,
    ) async {
      final fake = FakeApiManager(testConfig);
      fake.embedConfigResponse = {
        'enabled': true,
        'config': {'greeting': 'Hi!', 'title': 'Support'},
        'leadCapture': {'enabled': false},
      };
      await _pumpScreen(tester, fake);

      expect(find.text('Support'), findsOneWidget);
    });

    testWidgets(
      'strings.title always overrides the dashboard title, even a non-empty one',
      (tester) async {
        final fake = FakeApiManager(testConfig);
        fake.embedConfigResponse = {
          'enabled': true,
          'config': {'greeting': 'مرحبا!', 'title': 'Support'},
          'leadCapture': {'enabled': false},
        };
        const strings = FrontFaceChatStrings(
          textDirection: TextDirection.rtl,
          title: 'الدعم',
        );
        await _pumpScreen(tester, fake, strings: strings);

        expect(find.text('الدعم'), findsOneWidget);
        expect(find.text('Support'), findsNothing);
      },
    );
  });

  group('loading state', () {
    testWidgets(
      'shows the English default loadingChat text while initializing',
      (tester) async {
        final fake = FakeApiManager(testConfig)
          ..delay = const Duration(milliseconds: 50);
        final api = FrontFaceApiService(config: testConfig, apiManager: fake);
        final provider = FrontFaceChatProvider(
          config: testConfig,
          api: api,
          store: FrontFaceVisitorStore(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider.value(
              value: provider,
              child: const FrontFaceChatScreen(),
            ),
          ),
        );
        // The fake API is deliberately delayed, so initialize() is still
        // in-flight here and the screen should be showing its loading state.
        await tester.pump();

        expect(find.text('Loading chat...'), findsOneWidget);

        await tester.pumpAndSettle();
      },
    );

    testWidgets('shows the Arabic loadingChat override while initializing', (
      tester,
    ) async {
      final fake = FakeApiManager(testConfig)
        ..delay = const Duration(milliseconds: 50);
      final api = FrontFaceApiService(config: testConfig, apiManager: fake);
      const strings = FrontFaceChatStrings(
        textDirection: TextDirection.rtl,
        loadingChat: 'جارٍ تحميل المحادثة...',
      );
      final provider = FrontFaceChatProvider(
        config: testConfig,
        strings: strings,
        api: api,
        store: FrontFaceVisitorStore(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: provider,
            child: const FrontFaceChatScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('جارٍ تحميل المحادثة...'), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });

  group(
    'input direction switches with content, in an Arabic-configured chat',
    () {
      testWidgets('starts rtl, matching the configured chat language', (
        tester,
      ) async {
        final fake = FakeApiManager(testConfig);
        await _pumpScreen(tester, fake, strings: _arabicStrings);

        expect(_inputField(tester).textDirection, TextDirection.rtl);
      });

      testWidgets('typing English switches the field to ltr', (tester) async {
        final fake = FakeApiManager(testConfig);
        await _pumpScreen(tester, fake, strings: _arabicStrings);

        await tester.enterText(find.byType(TextField), 'hello there');
        await tester.pump();

        expect(_inputField(tester).textDirection, TextDirection.ltr);
      });

      testWidgets('typing Arabic keeps the field rtl', (tester) async {
        final fake = FakeApiManager(testConfig);
        await _pumpScreen(tester, fake, strings: _arabicStrings);

        await tester.enterText(find.byType(TextField), 'مرحبا كيف حالك');
        await tester.pump();

        expect(_inputField(tester).textDirection, TextDirection.rtl);
      });

      testWidgets('clearing the field reverts to the chat language direction', (
        tester,
      ) async {
        final fake = FakeApiManager(testConfig);
        await _pumpScreen(tester, fake, strings: _arabicStrings);

        await tester.enterText(find.byType(TextField), 'hello');
        await tester.pump();
        expect(_inputField(tester).textDirection, TextDirection.ltr);

        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(_inputField(tester).textDirection, TextDirection.rtl);
      });
    },
  );

  group('greeting rendering end-to-end', () {
    testWidgets('English greeting appears exactly once', (tester) async {
      final fake = FakeApiManager(testConfig);
      fake.embedConfigResponse = {
        'enabled': true,
        'config': {
          'greeting': 'Hi! How can I help you today?',
          'greetingIntro': 'Hi there!',
          'placeholder': '',
        },
        'leadCapture': {'enabled': false},
      };
      await _pumpScreen(tester, fake);

      expect(find.text('Hi! How can I help you today?'), findsOneWidget);
      expect(find.textContaining('Hi there!'), findsNothing);
    });

    testWidgets('Arabic greeting appears exactly once', (tester) async {
      final fake = FakeApiManager(testConfig);
      fake.embedConfigResponse = {
        'enabled': true,
        'config': {
          'greeting': 'مرحبا! كيف يمكنني مساعدتك اليوم؟',
          'greetingIntro': 'أهلاً بك!',
          'placeholder': '',
        },
        'leadCapture': {'enabled': false},
      };
      await _pumpScreen(tester, fake, strings: _arabicStrings);

      expect(find.text('مرحبا! كيف يمكنني مساعدتك اليوم؟'), findsOneWidget);
      expect(find.textContaining('أهلاً بك!'), findsNothing);
    });
  });

  group('live language switching via updateStrings', () {
    testWidgets(
      'placeholder and input direction update without rebuilding the screen',
      (tester) async {
        final fake = FakeApiManager(testConfig);
        final provider = await _pumpScreen(tester, fake);

        expect(_inputField(tester).decoration?.hintText, 'Type a message...');
        expect(_inputField(tester).textDirection, TextDirection.ltr);

        provider.updateStrings(_arabicStrings);
        await tester.pump();

        expect(_inputField(tester).decoration?.hintText, 'اكتب رسالة...');
        expect(_inputField(tester).textDirection, TextDirection.rtl);
      },
    );

    testWidgets('title override applies immediately once set', (tester) async {
      final fake = FakeApiManager(testConfig);
      fake.embedConfigResponse = {
        'enabled': true,
        'config': {'greeting': 'Hi!', 'title': 'Support'},
        'leadCapture': {'enabled': false},
      };
      final provider = await _pumpScreen(tester, fake);

      expect(find.text('Support'), findsOneWidget);

      provider.updateStrings(const FrontFaceChatStrings(title: 'الدعم'));
      await tester.pump();

      expect(find.text('الدعم'), findsOneWidget);
      expect(find.text('Support'), findsNothing);
    });
  });
}
