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
      'default config shows lead form before greeting even for email_after',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig;

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(
          provider.showLeadForm,
          isTrue,
          reason:
              'requireLeadCaptureBeforeChat defaults to true — form first',
        );
        expect(
          provider.messages,
          isEmpty,
          reason: 'no greeting until the lead form is submitted',
        );
      },
    );

    test(
      'dashboard email_after mode applies when requireLeadCaptureBeforeChat is false',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig;
        const afterConfig = FrontFaceChatConfig(
          projectId: 'test-project',
          publishableKey: 'pk_test',
          requireLeadCaptureBeforeChat: false,
        );

        final provider = _buildProvider(fake, config: afterConfig);
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

    test(
      'wins over an already-stored session that has not completed lead capture',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_session_id_${testConfig.projectId}': 'sess_old',
          'frontface_session_token_${testConfig.projectId}': 'tok_old',
        });

        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = false
          ..messagesResponse = [
            {
              'id': 'old_msg',
              'senderType': 'ai',
              'content': 'Welcome back!',
              'createdAt': DateTime(2024, 1, 1).toIso8601String(),
            },
          ];
        const overrideConfig = FrontFaceChatConfig(
          projectId: 'test-project',
          publishableKey: 'pk_test',
          requireLeadCaptureBeforeChat: true,
        );

        final provider = _buildProvider(fake, config: overrideConfig);
        await provider.initialize();

        expect(
          provider.showLeadForm,
          isTrue,
          reason:
              'a stored session should not bypass a still-required lead form',
        );
        expect(
          provider.messages,
          isEmpty,
          reason: 'should not hydrate history before lead capture is done',
        );
      },
    );

    test(
      'does not re-show the form for a returning session that already completed it',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_session_id_${testConfig.projectId}': 'sess_old',
          'frontface_session_token_${testConfig.projectId}': 'tok_old',
          'frontface_lead_completed_${testConfig.projectId}': true,
        });

        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..messagesResponse = [
            {
              'id': 'old_msg',
              'senderType': 'ai',
              'content': 'Welcome back!',
              'createdAt': DateTime(2024, 1, 1).toIso8601String(),
            },
          ];
        const overrideConfig = FrontFaceChatConfig(
          projectId: 'test-project',
          publishableKey: 'pk_test',
          requireLeadCaptureBeforeChat: true,
        );

        final provider = _buildProvider(fake, config: overrideConfig);
        await provider.initialize();

        expect(provider.showLeadForm, isFalse);
        expect(
          provider.messages.any((m) => m.content == 'Welcome back!'),
          isTrue,
          reason: 'existing session history should hydrate normally',
        );
      },
    );
  });

  group('session expiry', () {
    test(
      'sendMessage on SESSION_INVALID clears chat and shows the lead form',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..forcedErrorPathContains = '/api/chat/message'
          ..forcedErrorRemaining = 1
          ..forcedError = const FrontFaceApiException(
            code: 'SESSION_INVALID',
            message: 'Session invalid',
            statusCode: 403,
          );

        SharedPreferences.setMockInitialValues({
          'frontface_session_id_${testConfig.projectId}': 'sess_old',
          'frontface_session_token_${testConfig.projectId}': 'tok_old',
          'frontface_lead_completed_${testConfig.projectId}': true,
        });

        // Allow chat without form so we can hit sendMessage first.
        const afterConfig = FrontFaceChatConfig(
          projectId: 'test-project',
          publishableKey: 'pk_test',
          requireLeadCaptureBeforeChat: false,
        );

        final provider = _buildProvider(fake, config: afterConfig);
        await provider.initialize();
        await provider.sendMessage('hi');

        expect(provider.error, isNull);
        expect(
          provider.messages,
          isEmpty,
          reason: 'chat must be cleared on session expiry',
        );
        expect(
          provider.showLeadForm,
          isTrue,
          reason: 'lead form must show before a new session is created',
        );
        expect(
          provider.messages.any(
            (m) => m.content == provider.strings.sessionExpired,
          ),
          isFalse,
        );
      },
    );

    test(
      'sendMessage without lead capture shows greeting after clear, not an error',
      () async {
        final fake = FakeApiManager(testConfig)
          ..forcedErrorPathContains = '/api/chat/message'
          ..forcedErrorRemaining = 1
          ..forcedError = const FrontFaceApiException(
            code: 'SESSION_INVALID',
            message: 'Session invalid',
            statusCode: 403,
          );

        final provider = _buildProvider(fake);
        await provider.initialize();
        await provider.sendMessage('are you still there');

        expect(provider.error, isNull);
        expect(provider.showLeadForm, isFalse);
        expect(
          provider.messages.any(
            (m) => m.content == 'Hi! How can I help you today?',
          ),
          isTrue,
        );
      },
    );

    test(
      'initialize() on expired session clears chat and shows the lead form',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_session_id_${testConfig.projectId}': 'sess_old',
          'frontface_session_token_${testConfig.projectId}': 'tok_old',
          'frontface_lead_completed_${testConfig.projectId}': true,
        });

        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..forcedErrorPathContains = '/messages/public'
          ..forcedErrorRemaining = 1
          ..forcedError = const FrontFaceApiException(
            code: 'SESSION_INVALID',
            message: 'Session invalid',
            statusCode: 403,
          );

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(provider.error, isNull);
        expect(provider.messages, isEmpty);
        expect(provider.showLeadForm, isTrue);
        expect(
          provider.messages.any(
            (m) => m.content == provider.strings.sessionExpired,
          ),
          isFalse,
        );
      },
    );

    test(
      'startNewChat shows lead form with empty messages when lead capture is on',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = true;

        SharedPreferences.setMockInitialValues({
          'frontface_lead_completed_${testConfig.projectId}': true,
        });

        final provider = _buildProvider(fake);
        await provider.initialize();
        await provider.startNewChat();

        expect(provider.showLeadForm, isTrue);
        expect(provider.messages, isEmpty);
      },
    );
  });
}
