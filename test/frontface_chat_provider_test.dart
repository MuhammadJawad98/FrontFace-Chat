import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:frontface_chat/src/services/frontface_api_service.dart';
import 'package:frontface_chat/src/services/frontface_visitor_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_api_manager.dart';

const _arabicStrings = FrontFaceChatStrings(
  talkToHuman: 'تحدث مع شخص',
  typeMessage: 'اكتب رسالة...',
  waitingForAgentWithPosition: 'في انتظار وكيل (الترتيب {position})',
);

FrontFaceChatProvider _buildProvider(
  FakeApiManager fake, {
  FrontFaceChatStrings strings = const FrontFaceChatStrings(),
}) {
  final api = FrontFaceApiService(config: testConfig, apiManager: fake);
  return FrontFaceChatProvider(
    config: testConfig,
    strings: strings,
    api: api,
    store: FrontFaceVisitorStore(),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('greeting — no duplication', () {
    test('English: only the greeting is shown, not greeting + intro', () async {
      final fake = FakeApiManager(testConfig);
      fake.embedConfigResponse = {
        'enabled': true,
        'config': {
          'title': 'Chat with us',
          'greeting':
              "Hi, I'm OneGo Bot from One Go. Thanks for stopping by. How can I make things easier for you today?",
          'greetingIntro':
              "Hi, I'm OneGo Bot from One Go. Thanks for stopping by.",
          'placeholder': '',
        },
        'leadCapture': {'enabled': false},
      };

      final provider = _buildProvider(fake);
      await provider.initialize();

      expect(provider.messages.length, 1);
      expect(
        provider.messages.single.content,
        "Hi, I'm OneGo Bot from One Go. Thanks for stopping by. How can I make things easier for you today?",
      );
    });

    test('Arabic: only the greeting is shown, not greeting + intro', () async {
      final fake = FakeApiManager(testConfig);
      fake.embedConfigResponse = {
        'enabled': true,
        'config': {
          'title': 'الدردشة معنا',
          'greeting': 'مرحبا! كيف يمكنني مساعدتك اليوم؟',
          'greetingIntro': 'أهلاً بك!',
          'placeholder': '',
        },
        'leadCapture': {'enabled': false},
      };

      final provider = _buildProvider(fake, strings: _arabicStrings);
      await provider.initialize();

      expect(provider.messages.length, 1);
      expect(
        provider.messages.single.content,
        'مرحبا! كيف يمكنني مساعدتك اليوم؟',
      );
    });
  });

  group('handoff button text — localized fallback', () {
    test(
      'English default is used when the server sends no buttonText',
      () async {
        final fake = FakeApiManager(testConfig);
        fake.handoffAvailabilityResponse = {
          'available': true,
          'showButton': true,
          'buttonText': '',
        };

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(provider.handoffButtonText, 'Talk to a human');
      },
    );

    test('Arabic string is used when the server sends no buttonText', () async {
      final fake = FakeApiManager(testConfig);
      fake.handoffAvailabilityResponse = {
        'available': true,
        'showButton': true,
        'buttonText': '',
      };

      final provider = _buildProvider(fake, strings: _arabicStrings);
      await provider.initialize();

      expect(provider.handoffButtonText, 'تحدث مع شخص');
    });

    test(
      'server-provided buttonText always wins over the local fallback',
      () async {
        final fake = FakeApiManager(testConfig);
        fake.handoffAvailabilityResponse = {
          'available': true,
          'showButton': true,
          'buttonText': 'Chat now',
        };

        final provider = _buildProvider(fake, strings: _arabicStrings);
        await provider.initialize();

        expect(provider.handoffButtonText, 'Chat now');
      },
    );
  });

  group('placeholder — model no longer hardcodes English', () {
    test('empty when the server omits it, regardless of language', () async {
      final fake = FakeApiManager(testConfig);
      // embedConfigResponse.config.placeholder already omitted/empty.
      final provider = _buildProvider(fake, strings: _arabicStrings);
      await provider.initialize();

      expect(provider.config.placeholder, '');
    });

    test('server value is preserved when present', () async {
      final fake = FakeApiManager(testConfig);
      fake.embedConfigResponse = {
        'enabled': true,
        'config': {'greeting': 'Hi!', 'placeholder': 'اكتب هنا...'},
        'leadCapture': {'enabled': false},
      };
      final provider = _buildProvider(fake);
      await provider.initialize();

      expect(provider.config.placeholder, 'اكتب هنا...');
    });
  });

  group('session token', () {
    test(
      'persists across messages and is sent on the follow-up request',
      () async {
        final fake = FakeApiManager(testConfig);
        var call = 0;
        fake.sendMessageResponder = (body) {
          call++;
          if (call == 1) {
            return {
              'response': 'Hello!',
              'sessionId': 'sess_1',
              'sessionToken': 'tok_1',
            };
          }
          return {'response': 'Still here.', 'sessionId': 'sess_1'};
        };

        final provider = _buildProvider(fake);
        await provider.initialize();

        await provider.sendMessage('hello');
        await provider.sendMessage('second message');

        final messageCalls = fake.calls
            .where((c) => c.path.contains('/api/chat/message'))
            .toList();
        expect(messageCalls, hasLength(2));
        expect(messageCalls[0].sessionToken, isNull);
        expect(messageCalls[1].sessionToken, 'tok_1');
      },
    );
  });

  group('updateStrings — runtime language switching', () {
    test('swaps the active strings and notifies listeners', () async {
      final fake = FakeApiManager(testConfig);
      final provider = _buildProvider(fake);
      await provider.initialize();

      expect(provider.strings.talkToHuman, 'Talk to a human');

      var notified = false;
      provider.addListener(() => notified = true);

      provider.updateStrings(_arabicStrings);

      expect(provider.strings.talkToHuman, 'تحدث مع شخص');
      expect(provider.handoffButtonText, 'تحدث مع شخص');
      expect(notified, isTrue);
    });

    test(
      'recomputes an already-shown status banner in the new language',
      () async {
        final fake = FakeApiManager(testConfig);
        fake.handoffAvailabilityResponse = {
          'available': true,
          'showButton': true,
          'buttonText': '',
        };
        final provider = _buildProvider(fake);
        await provider.initialize();

        await provider.requestHuman();
        expect(provider.statusBanner, 'Waiting for an agent (position 1)');

        provider.updateStrings(_arabicStrings);

        expect(
          provider.statusBanner,
          contains('انتظار'),
          reason: 'status banner should be rebuilt in the new language',
        );
      },
    );
  });
}
