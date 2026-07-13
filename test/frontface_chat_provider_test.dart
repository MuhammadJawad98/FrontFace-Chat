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

  group('handoff message de-dupe', () {
    test(
      'chat-triggered handoff merges server history without duplicating confirmation',
      () async {
        const confirmation =
            "I'm connecting you with a human agent now. Please hold on.";
        final fake = FakeApiManager(testConfig);
        fake.sendMessageResponder = (_) => {
              'response': confirmation,
              'sessionId': 'sess_1',
              'sessionToken': 'tok_1',
              'handoff': {
                'triggered': true,
                'reason': 'in_queue',
                'queuePosition': 2,
              },
            };
        fake.messagesResponse = [
          {
            'id': 'cust_1',
            'senderType': 'customer',
            'content': 'can I talk to a human',
            'createdAt': DateTime(2024, 1, 1, 12, 0, 0).toIso8601String(),
          },
          {
            'id': 'ai_handoff_1',
            'senderType': 'ai',
            'content': confirmation,
            'createdAt': DateTime(2024, 1, 1, 12, 0, 1).toIso8601String(),
          },
        ];

        final provider = _buildProvider(fake);
        await provider.initialize();
        await provider.sendMessage('can I talk to a human');

        final connecting = provider.messages
            .where((m) => m.content == confirmation)
            .toList();
        expect(
          connecting,
          hasLength(1),
          reason:
              'HTTP response + messages/public must not both render the '
              'handoff confirmation',
        );
        expect(connecting.single.id, 'ai_handoff_1');
        expect(
          provider.messages.where((m) => m.content == 'can I talk to a human'),
          hasLength(1),
          reason: 'visitor message must stay visible after handoff merge',
        );
        expect(provider.isInHandoff, isTrue);
        expect(
          fake.calls.where((c) => c.path.contains('/messages/public')),
          isNotEmpty,
          reason: 'entering handoff must fetch full server history',
        );
      },
    );

    test(
      'keeps the visitor bubble when server history has not indexed it yet',
      () async {
        const confirmation =
            "I'm connecting you with a human agent now. Please hold on.";
        final fake = FakeApiManager(testConfig);
        fake.sendMessageResponder = (_) => {
              'response': confirmation,
              'sessionId': 'sess_1',
              'sessionToken': 'tok_1',
              'handoff': {
                'triggered': true,
                'reason': 'in_queue',
                'queuePosition': 1,
              },
            };
        // Read-after-write lag: confirmation is on the server, but the just-
        // posted visitor message is not in this GET yet.
        fake.messagesResponse = [
          {
            'id': 'ai_handoff_1',
            'senderType': 'ai',
            'content': confirmation,
            'createdAt': DateTime(2024, 1, 1, 12, 0, 1).toIso8601String(),
          },
        ];

        final provider = _buildProvider(fake);
        await provider.initialize();
        await provider.sendMessage('talk to human');

        expect(
          provider.messages
              .where((m) => m.content == 'talk to human')
              .single
              .senderType,
          FrontFaceSenderType.customer,
          reason:
              'clearing local transcript on handoff would drop this message '
              'when the GET races ahead of the server write',
        );
        expect(
          provider.messages.where((m) => m.content == confirmation),
          hasLength(1),
        );
      },
    );

    test(
      'polling a server copy drops the matching local provisional bubble',
      () async {
        const reply =
            "I'm connecting you with a human agent now. Please hold on.";
        final fake = FakeApiManager(testConfig);
        fake.sendMessageResponder = (_) => {
              'response': reply,
              'sessionId': 'sess_1',
              'sessionToken': 'tok_1',
              'handoff': {
                'triggered': true,
                'reason': 'in_queue',
              },
            };

        final provider = _buildProvider(fake);
        await provider.initialize();

        // History replace fails on enter-handoff — keep the provisional
        // local_* bubble so a later poll can exercise content reconciliation.
        fake.forcedErrorPathContains = '/messages/public';
        fake.forcedError = const FrontFaceApiException(
          code: 'NETWORK',
          message: 'offline',
        );

        await provider.sendMessage('can I talk to a human');

        expect(
          provider.messages.where((m) => m.content == reply).single.id,
          startsWith('local_'),
        );

        // Polls succeed with the server copy of the same text.
        fake.forcedErrorPathContains = null;
        fake.forcedError = null;
        fake.messagesResponse = [
          {
            'id': 'ai_server_1',
            'senderType': 'ai',
            'content': reply,
            'createdAt': DateTime(2024, 1, 1, 12, 0, 1).toIso8601String(),
          },
        ];

        await Future<void>.delayed(const Duration(seconds: 3));

        final copies =
            provider.messages.where((m) => m.content == reply).toList();
        expect(
          copies,
          hasLength(1),
          reason: 'local provisional + polled server copy must collapse to one',
        );
        expect(copies.single.id, 'ai_server_1');
      },
    );

    test(
      'messages without an id stay stable across fromJson so polls do not duplicate',
      () {
        final json = {
          'senderType': 'ai',
          'content': 'Hello from the bot',
          'createdAt': '2024-01-01T12:00:00.000Z',
        };
        final a = FrontFaceChatMessage.fromJson(json);
        final b = FrontFaceChatMessage.fromJson(json);
        expect(a.id, isNot(startsWith('local_')));
        expect(a.id, b.id);
        expect(a.id, startsWith('srv_'));
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
