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
  FrontFaceChatConfig? config,
}) {
  final effectiveConfig = config ?? testConfig;
  final api = FrontFaceApiService(config: effectiveConfig, apiManager: fake);
  return FrontFaceChatProvider(
    config: effectiveConfig,
    strings: strings,
    api: api,
    store: FrontFaceVisitorStore(),
  );
}

final _leadCaptureEmailAfterConfig = {
  'enabled': true,
  'config': {'greeting': 'Hi! How can I help you today?', 'placeholder': ''},
  'leadCapture': {
    'enabled': true,
    'capture_mode': 'email_after',
    'formFields': {
      'email': {'required': true},
    },
  },
};

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

  group('requireLeadCaptureBeforeChat override', () {
    test(
      'forces the lead form before chat even when the dashboard mode is email_after',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig;
        const overrideConfig = FrontFaceChatConfig(
          projectId: 'test-project',
          publishableKey: 'pk_test',
          requireLeadCaptureBeforeChat: true,
        );

        final provider = _buildProvider(fake, config: overrideConfig);
        await provider.initialize();

        expect(provider.showLeadForm, isTrue);
        expect(
          provider.messages,
          isEmpty,
          reason: 'no greeting should show until the lead form is submitted',
        );
      },
    );

    test(
      'has no effect when lead capture itself is disabled on the dashboard',
      () async {
        final fake = FakeApiManager(testConfig);
        // Default embedConfigResponse has leadCapture.enabled == false.
        const overrideConfig = FrontFaceChatConfig(
          projectId: 'test-project',
          publishableKey: 'pk_test',
          requireLeadCaptureBeforeChat: true,
        );

        final provider = _buildProvider(fake, config: overrideConfig);
        await provider.initialize();

        expect(provider.showLeadForm, isFalse);
        expect(provider.messages, isNotEmpty);
      },
    );

    test(
      'dashboard email_after mode still applies when the override is off',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig;

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(
          provider.showLeadForm,
          isFalse,
          reason:
              'email_after shows the form after the first exchange, not before',
        );
        expect(provider.messages, isNotEmpty, reason: 'greeting shows first');
      },
    );
  });

  group('session expiry', () {
    test(
      'sendMessage recovers: clears the session and re-shows the lead form',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..forcedErrorPathContains = '/api/chat/message'
          ..forcedError = const FrontFaceApiException(
            code: 'SESSION_INVALID',
            message: 'Session invalid',
            statusCode: 403,
          );

        final provider = _buildProvider(fake);
        await provider.initialize();

        await provider.sendMessage('hi');

        expect(
          provider.messages.any(
            (m) => m.content == provider.strings.sessionExpired,
          ),
          isTrue,
        );
        expect(
          provider.showLeadForm,
          isTrue,
          reason: 'lead capture is enabled, so it must be asked again',
        );
        expect(provider.error, isNull);
      },
    );

    test(
      'sendMessage recovers with the greeting when lead capture is disabled',
      () async {
        // default embedConfigResponse has leadCapture disabled.
        final fake = FakeApiManager(testConfig)
          ..forcedErrorPathContains = '/api/chat/message'
          ..forcedError = const FrontFaceApiException(
            code: 'SESSION_INVALID',
            message: 'Session invalid',
            statusCode: 403,
          );

        final provider = _buildProvider(fake);
        await provider.initialize();

        await provider.sendMessage('are you still there');

        expect(provider.showLeadForm, isFalse);
        expect(
          provider.messages.any(
            (m) => m.content == 'Hi! How can I help you today?',
          ),
          isTrue,
          reason: 'greeting should be re-shown after recovery',
        );
      },
    );

    test(
      'initialize() recovers when hydrating an already-expired stored session',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_session_id_${testConfig.projectId}': 'sess_old',
          'frontface_session_token_${testConfig.projectId}': 'tok_old',
        });

        final fake = FakeApiManager(testConfig)
          ..forcedErrorPathContains = '/messages/public'
          ..forcedError = const FrontFaceApiException(
            code: 'SESSION_INVALID',
            message: 'Session invalid',
            statusCode: 403,
          );

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(
          provider.messages.any(
            (m) => m.content == provider.strings.sessionExpired,
          ),
          isTrue,
        );
        expect(
          provider.messages.any(
            (m) => m.content == 'Hi! How can I help you today?',
          ),
          isTrue,
        );
        expect(provider.error, isNull);
      },
    );
  });
}
