import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:frontface_chat/src/services/frontface_api_service.dart';
import 'package:frontface_chat/src/services/frontface_realtime_bridge.dart';
import 'package:frontface_chat/src/services/frontface_visitor_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_api_manager.dart';
import 'fakes/fake_realtime_bridge.dart';

const _arabicStrings = FrontFaceChatStrings(
  talkToHuman: 'تحدث مع شخص',
  typeMessage: 'اكتب رسالة...',
  waitingForAgentWithPosition: 'في انتظار وكيل (الترتيب {position})',
);

FrontFaceChatProvider _buildProvider(
  FakeApiManager fake, {
  FrontFaceChatStrings strings = const FrontFaceChatStrings(),
  FrontFaceChatConfig? config,
  FrontFaceRealtimeBridge? realtime,
}) {
  final effectiveConfig = config ?? testConfig;
  final api = FrontFaceApiService(config: effectiveConfig, apiManager: fake);
  return FrontFaceChatProvider(
    config: effectiveConfig,
    strings: strings,
    api: api,
    store: FrontFaceVisitorStore(),
    realtime: realtime,
  );
}

Map<String, dynamic> _realtimeEmbedConfig() => {
      'enabled': true,
      'config': {
        'title': 'Chat with us',
        'greeting': 'Hi! How can I help you today?',
        'placeholder': '',
      },
      'leadCapture': {'enabled': false},
      'realtime': {
        'enabled': true,
        'supabaseUrl': 'https://example.supabase.co',
        'apiKey': 'sb_publishable_test',
        'tokenBased': true,
      },
    };

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
          'mode': 'live',
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
        'mode': 'live',
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
              'sessionToken': 'tok_refreshed',
            };
          }
          return {'response': 'Still here.', 'sessionId': 'sess_1'};
        };

        final provider = _buildProvider(fake);
        await provider.initialize();

        // initialize() already resolved the conversation via ensure-conversation
        expect(
          fake.calls.any((c) => c.path.contains('/ensure-conversation')),
          isTrue,
        );

        await provider.sendMessage('hello');
        await provider.sendMessage('second message');

        final messageCalls = fake.calls
            .where((c) => c.path.contains('/api/chat/message'))
            .toList();
        expect(messageCalls, hasLength(2));
        // Token from ensure-conversation on first continued message.
        expect(messageCalls[0].sessionToken, 'tok_1');
        // Refreshed token from first response is used on the follow-up.
        expect(messageCalls[1].sessionToken, 'tok_refreshed');
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
          'mode': 'live',
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

  group('typing and presence', () {
    test(
      'customer typing posts only while agent_active',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _realtimeEmbedConfig()
          ..handoffAvailabilityResponse = {
            'available': true,
            'showButton': true,
            'buttonText': '',
          }
          ..sendMessageResponder = (_) => {
                'response': 'Connecting…',
                'sessionId': 'sess_1',
                'sessionToken': 'tok_1',
                'handoff': {
                  'triggered': true,
                  'reason': 'agent_handling',
                },
              };
        final realtime = FakeRealtimeBridge();
        final provider = _buildProvider(fake, realtime: realtime);
        await provider.initialize();

        // Still AI — typing must be ignored.
        provider.onComposerChanged('hello');
        expect(
          fake.calls.where((c) => c.path.contains('/typing')),
          isEmpty,
        );

        await provider.sendMessage('talk to human');
        expect(provider.isAgentActive, isTrue);

        provider.onComposerChanged('a');
        final typingStarts = fake.calls
            .where((c) => c.path.contains('/typing'))
            .toList();
        expect(typingStarts, isNotEmpty);
        expect(typingStarts.last.body?['isTyping'], isTrue);
        expect(typingStarts.last.body?['participantType'], 'customer');

        provider.stopTyping();
        final typingStops = fake.calls
            .where((c) => c.path.contains('/typing'))
            .toList();
        expect(typingStops.last.body?['isTyping'], isFalse);
      },
    );

    test(
      'handoff starts presence online and connects Realtime with apiKey + JWT',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _realtimeEmbedConfig();
        final realtime = FakeRealtimeBridge();
        final provider = _buildProvider(fake, realtime: realtime);
        await provider.initialize();
        await provider.requestHuman();

        expect(provider.isInHandoff, isTrue);
        expect(
          fake.calls.where((c) => c.path.contains('/presence')),
          isNotEmpty,
        );
        expect(
          fake.calls
              .where((c) => c.path.contains('/presence'))
              .last
              .body?['status'],
          'online',
        );
        expect(
          fake.calls.where((c) => c.path.contains('/realtime-token')),
          isNotEmpty,
        );
        expect(realtime.connectCount, 1);
        expect(realtime.lastApiKey, 'sb_publishable_test');
        expect(realtime.lastJwt, 'jwt_test_token');
        expect(realtime.lastConversationId, 'sess_1');
      },
    );

    test(
      'agent typing:start/stop from Realtime updates agentTyping',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _realtimeEmbedConfig();
        final realtime = FakeRealtimeBridge();
        final provider = _buildProvider(fake, realtime: realtime);
        await provider.initialize();
        await provider.requestHuman();

        expect(provider.agentTyping, isFalse);
        realtime.emit('typing:start', {
          'payload': {
            'data': {
              'participant': {'type': 'agent', 'name': 'Sam'},
            },
          },
        });
        expect(provider.agentTyping, isTrue);
        expect(provider.agentName, 'Sam');

        realtime.emit('typing:stop', {
          'payload': {
            'data': {
              'participant': {'type': 'agent'},
            },
          },
        });
        expect(provider.agentTyping, isFalse);
      },
    );

    test(
      'Realtime disconnect clears a stuck agent typing indicator',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _realtimeEmbedConfig();
        final realtime = FakeRealtimeBridge();
        final provider = _buildProvider(fake, realtime: realtime);
        await provider.initialize();
        await provider.requestHuman();

        realtime.emit('typing:start', {
          'payload': {
            'data': {
              'participant': {'type': 'agent', 'name': 'Sam'},
            },
          },
        });
        expect(provider.agentTyping, isTrue);

        realtime.emitDisconnected();
        expect(provider.agentTyping, isFalse);
      },
    );

    test(
      'customer typing events from Realtime are ignored',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _realtimeEmbedConfig();
        final realtime = FakeRealtimeBridge();
        final provider = _buildProvider(fake, realtime: realtime);
        await provider.initialize();
        await provider.requestHuman();

        realtime.emit('typing:start', {
          'payload': {
            'data': {
              'participant': {'type': 'customer'},
            },
          },
        });
        expect(provider.agentTyping, isFalse);
      },
    );
  });

  group('handoff mode', () {
    test('standing button only when mode is live and showButton is true', () async {
      final fake = FakeApiManager(testConfig)
        ..handoffAvailabilityResponse = {
          'available': true,
          'showButton': true,
          'mode': 'live',
          'buttonText': 'Talk to a human',
        };
      final provider = _buildProvider(fake);
      await provider.initialize();
      expect(provider.showHandoffButton, isTrue);
    });

    test('no standing button when mode is ticket', () async {
      final fake = FakeApiManager(testConfig)
        ..handoffAvailabilityResponse = {
          'available': true,
          'showButton': true,
          'mode': 'ticket',
          'buttonText': 'Talk to a human',
        };
      final provider = _buildProvider(fake);
      await provider.initialize();
      expect(provider.showHandoffButton, isFalse);
    });
  });

  group('customer identify', () {
    test('identify posts JWT and returns verified identity', () async {
      final fake = FakeApiManager(testConfig);
      final provider = _buildProvider(fake);
      await provider.initialize();

      final result = await provider.identify('eyJ.test.token');

      expect(result.verifiedIdentity, isNotNull);
      expect(
        fake.calls.where((c) => c.path.contains('/customers/identify')),
        isNotEmpty,
      );
      expect(provider.identifyResult?.verifiedIdentity?['externalId'], 'user_1');
    });
  });

  group('chat history', () {
    test(
      'visitorId is stable across getOrCreate calls (persisted)',
      () async {
        final store = FrontFaceVisitorStore();
        final first = await store.getOrCreateVisitorId();
        final second = await store.getOrCreateVisitorId();
        expect(first, second);
        expect(first.startsWith('mob_'), isTrue);
      },
    );

    test(
      'setVisitorId persists account-keyed id used on initialize',
      () async {
        final fake = FakeApiManager(testConfig);
        final provider = _buildProvider(fake);
        await provider.setVisitorId('mob_account_user_42');
        await provider.initialize();

        expect(provider.visitorId, 'mob_account_user_42');
        final store = FrontFaceVisitorStore();
        expect(await store.peekVisitorId(), 'mob_account_user_42');
      },
    );

    test(
      'config.visitorId is applied on initialize',
      () async {
        const config = FrontFaceChatConfig(
          projectId: 'test-project',
          publishableKey: 'pk_test',
          visitorId: 'mob_from_config',
        );
        final fake = FakeApiManager(config);
        final provider = _buildProvider(fake, config: config);
        await provider.initialize();
        expect(provider.visitorId, 'mob_from_config');
      },
    );

    test(
      'missing local sessionId → ensure-conversation then hydrate history',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_visitor_id': 'mob_stable_visitor',
          'frontface_lead_completed_${testConfig.projectId}': true,
        });

        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = true
          ..messagesResponse = [
            {
              'id': 'm1',
              'senderType': 'customer',
              'content': 'I need help',
              'createdAt': '2026-08-01T10:00:00.000Z',
            },
            {
              'id': 'm2',
              'senderType': 'ai',
              'content': 'Sure — what happened?',
              'createdAt': '2026-08-01T10:00:01.000Z',
            },
          ];

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(provider.showLeadForm, isFalse);
        expect(provider.visitorId, 'mob_stable_visitor');
        expect(provider.sessionId, 'sess_1');
        expect(
          fake.calls.any((c) => c.path.contains('/ensure-conversation')),
          isTrue,
          reason: 'must resolve conversation when local sessionId is missing',
        );
        expect(
          fake.calls.any((c) => c.path.contains('/messages/public')),
          isTrue,
        );
        expect(provider.messages.length, 2);
        expect(provider.messages.first.content, 'I need help');
        expect(provider.messages.last.content, 'Sure — what happened?');
      },
    );

    test(
      'verified customer loads unified history across episodes',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_visitor_id': 'mob_stable_visitor',
          'frontface_lead_completed_${testConfig.projectId}': true,
        });

        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = true
          ..customerHistoryResponse = [
            {
              'id': 'm_new',
              'senderType': 'ai',
              'content': 'Welcome back!',
              'createdAt': '2026-09-02T12:00:01.000Z',
            },
            {
              'id': 'm_old',
              'senderType': 'customer',
              'content': 'From last week',
              'createdAt': '2026-08-25T10:00:00.000Z',
            },
          ]
          ..messagesResponse = [
            {
              'id': 'empty_thread',
              'senderType': 'ai',
              'content': 'Only this thread',
              'createdAt': '2026-09-02T12:00:00.000Z',
            },
          ];

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(
          fake.calls.any((c) => c.path.contains('/api/customers/history')),
          isTrue,
        );
        expect(
          fake.calls.any((c) => c.path.contains('/messages/public')),
          isFalse,
          reason: 'unified history should replace per-conversation read',
        );
        expect(provider.messages.length, 2);
        expect(provider.messages.first.content, 'From last week');
        expect(provider.messages.last.content, 'Welcome back!');
      },
    );

    test(
      'NOT_VERIFIED falls back to messages/public',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_visitor_id': 'mob_stable_visitor',
          'frontface_lead_completed_${testConfig.projectId}': true,
        });

        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = true
          ..customerHistoryNotVerified = true
          ..customerHistoryResponse = []
          ..messagesResponse = [
            {
              'id': 'm1',
              'senderType': 'customer',
              'content': 'Anonymous thread',
              'createdAt': '2026-09-02T12:00:00.000Z',
            },
          ];

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(
          fake.calls.any((c) => c.path.contains('/api/customers/history')),
          isTrue,
        );
        expect(
          fake.calls.any((c) => c.path.contains('/messages/public')),
          isTrue,
        );
        expect(provider.messages.single.content, 'Anonymous thread');
      },
    );

    test(
      'passes stored conversationId into ensure-conversation to resume',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_visitor_id': 'mob_stable_visitor',
          'frontface_lead_completed_${testConfig.projectId}': true,
          'frontface_session_id_${testConfig.projectId}': 'sess_existing',
          'frontface_session_token_${testConfig.projectId}': 'tok_existing',
        });

        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = true
          ..messagesResponse = [
            {
              'id': 'm1',
              'senderType': 'customer',
              'content': 'Prior message',
              'createdAt': '2026-09-01T10:00:00.000Z',
            },
          ];

        final provider = _buildProvider(fake);
        await provider.initialize();

        final ensure = fake.calls.firstWhere(
          (c) => c.path.contains('/ensure-conversation'),
        );
        expect(ensure.body?['conversationId'], 'sess_existing');
        expect(provider.sessionId, 'sess_existing');
        expect(provider.canChat, isTrue);
      },
    );

    test(
      'closed conversation with history auto-resumes without Start new chat',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_visitor_id': 'mob_stable_visitor',
          'frontface_lead_completed_${testConfig.projectId}': true,
          'frontface_session_id_${testConfig.projectId}': 'sess_closed',
          'frontface_session_token_${testConfig.projectId}': 'tok_closed',
        });

        var ensureCalls = 0;
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = true
          ..customerHistoryResponse = [
            {
              'id': 'm_old',
              'senderType': 'customer',
              'content': 'From yesterday',
              'createdAt': '2026-09-01T10:00:00.000Z',
            },
            {
              'id': 'm_ai',
              'senderType': 'ai',
              'content': 'Thanks — resolved.',
              'createdAt': '2026-09-01T10:01:00.000Z',
            },
          ]
          ..conversationStatusResponse = {'status': 'closed'}
          ..ensureConversationResponder = (body) {
            ensureCalls++;
            final passed = body?['conversationId']?.toString();
            if (ensureCalls == 1) {
              expect(passed, 'sess_closed');
              return {
                'conversationId': 'sess_closed',
                'sessionToken': 'tok_closed',
              };
            }
            // Resume path omits ended id → active thread.
            expect(passed, isNull);
            return {
              'conversationId': 'sess_active',
              'sessionToken': 'tok_active',
            };
          };

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(provider.messages.length, 2);
        expect(provider.messages.first.content, 'From yesterday');
        expect(provider.sessionId, 'sess_active');
        expect(provider.status, FrontFaceConversationStatus.aiActive);
        expect(provider.canChat, isTrue);
        expect(provider.statusBanner, isNull);
        expect(ensureCalls, 2);
      },
    );

    test(
      'unified history paginates with nextCursor and preserves metadata/parts',
      () async {
        SharedPreferences.setMockInitialValues({
          'frontface_visitor_id': 'mob_stable_visitor',
          'frontface_lead_completed_${testConfig.projectId}': true,
        });

        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = true
          ..customerHistoryResponse = [
            {
              'id': 'm2',
              'senderType': 'ai',
              'content': 'Newer page',
              'createdAt': '2026-09-02T12:00:01.000Z',
            },
          ]
          ..customerHistoryPage2 = [
            {
              'id': 'm1',
              'senderType': 'customer',
              'content': '',
              'createdAt': '2026-08-25T10:00:00.000Z',
              'metadata': {'ticketCard': {'status': 'open'}},
              'parts': [
                {
                  'type': 'location',
                  'payload': {
                    'latitude': 24.7,
                    'longitude': 46.6,
                    'label': 'Riyadh',
                  },
                },
              ],
            },
          ];

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(
          fake.calls.where((c) => c.path.contains('/api/customers/history')),
          hasLength(2),
        );
        expect(provider.messages.length, 2);
        expect(provider.messages.first.attachment?.kind,
            FrontFaceAttachmentKind.location);
        expect(provider.messages.first.attachment?.latitude, closeTo(24.7, 0.001));
        expect(provider.messages.last.content, 'Newer page');
      },
    );

    test(
      'no lead yet → does not ensure-conversation (form first)',
      () async {
        final fake = FakeApiManager(testConfig)
          ..embedConfigResponse = _leadCaptureEmailAfterConfig
          ..leadCaptureCompleted = false;

        final provider = _buildProvider(fake);
        await provider.initialize();

        expect(provider.showLeadForm, isTrue);
        expect(
          fake.calls.any((c) => c.path.contains('/ensure-conversation')),
          isFalse,
        );
        expect(
          fake.calls.any((c) => c.path.contains('/messages/public')),
          isFalse,
        );
      },
    );
  });

  group('attachments API', () {
    test('sendLocationAttachment keeps a visible customer location bubble', () async {
      final config = FrontFaceChatConfig(
        projectId: testConfig.projectId,
        publishableKey: testConfig.publishableKey,
        requireLeadCaptureBeforeChat: false,
        attachments: const FrontFaceAttachmentsConfig(
          enableLocation: true,
          googleMapsApiKey: 'AIza-test',
        ),
      );
      final fake = FakeApiManager(config);
      // Server history returns a location part with string coords (common JSON)
      // and empty content — previously this could wipe the local bubble.
      fake.messagesResponse = [
        {
          'id': 'msg_loc_1',
          'content': '',
          'senderType': 'customer',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'parts': [
            {
              'type': 'location',
              'payload': {
                'latitude': '24.7',
                'longitude': '46.6',
                'label': 'Riyadh',
              },
            },
          ],
        },
        {
          'id': 'msg_ai_1',
          'content': 'Got your location.',
          'senderType': 'ai',
          'createdAt': DateTime.now()
              .add(const Duration(seconds: 1))
              .toUtc()
              .toIso8601String(),
        },
      ];
      fake.sendMessageResponder = (_) => {
            'response': 'Got your location.',
            'sessionId': 'sess_1',
            'sessionToken': 'tok_1',
          };

      final provider = _buildProvider(fake, config: config);
      await provider.initialize();

      await provider.sendLocationAttachment(
        const FrontFaceAttachmentPayload(
          kind: FrontFaceAttachmentKind.location,
          latitude: 24.7,
          longitude: 46.6,
          label: 'Riyadh',
        ),
      );

      final customer = provider.messages.where(
        (m) => m.senderType == FrontFaceSenderType.customer,
      );
      expect(customer, isNotEmpty);
      expect(customer.every((m) => m.attachment != null), isTrue);
      expect(
        customer.first.attachment!.kind,
        FrontFaceAttachmentKind.location,
      );
      expect(customer.first.attachment!.latitude, closeTo(24.7, 0.001));
    });

    test('sendLocationAttachment posts location object', () async {
      final config = FrontFaceChatConfig(
        projectId: testConfig.projectId,
        publishableKey: testConfig.publishableKey,
        requireLeadCaptureBeforeChat: false,
        attachments: const FrontFaceAttachmentsConfig(
          enableLocation: true,
          googleMapsApiKey: 'AIza-test',
        ),
      );
      final fake = FakeApiManager(config);
      final provider = _buildProvider(fake, config: config);
      await provider.initialize();

      await provider.sendLocationAttachment(
        const FrontFaceAttachmentPayload(
          kind: FrontFaceAttachmentKind.location,
          latitude: 24.7,
          longitude: 46.6,
          accuracyMeters: 8,
          label: 'Riyadh',
        ),
      );

      final msgCall = fake.calls.lastWhere(
        (c) => c.path.contains('/api/chat/message'),
      );
      final location = msgCall.body?['location'] as Map<String, dynamic>?;
      expect(location?['latitude'], 24.7);
      expect(location?['longitude'], 46.6);
      expect(location?['accuracy_m'], 8);
      expect(location?['label'], 'Riyadh');
      expect(msgCall.body?['message'], '');
      final customer = provider.messages.lastWhere(
        (m) => m.senderType == FrontFaceSenderType.customer,
      );
      expect(customer.parts, isNotEmpty);
      expect(customer.parts.first.type, FrontFaceMessagePartType.location);
    });

    test('sendMediaAttachment reserves, PUTs, then sends parts', () async {
      final config = FrontFaceChatConfig(
        projectId: testConfig.projectId,
        publishableKey: testConfig.publishableKey,
        requireLeadCaptureBeforeChat: false,
        attachments: const FrontFaceAttachmentsConfig(enableImages: true),
      );
      final fake = FakeApiManager(config);
      final provider = _buildProvider(fake, config: config);
      await provider.initialize();

      final temp = await File(
        '${Directory.systemTemp.path}/ff_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ).create();
      await temp.writeAsBytes(List<int>.filled(64, 1));
      addTearDown(() => temp.deleteSync());

      await provider.sendMediaAttachment(
        FrontFacePendingAttachment(
          kind: FrontFaceAttachmentKind.image,
          path: temp.path,
          fileName: 'meal.jpg',
          mimeType: 'image/jpeg',
          byteLength: 64,
        ),
      );

      expect(
        fake.calls.any((c) => c.path.contains('/api/media/uploads')),
        isTrue,
      );
      expect(fake.putCalls, hasLength(1));
      expect(fake.putCalls.single.contentType, 'image/jpeg');
      expect(fake.putCalls.single.byteLength, 64);

      final msgCall = fake.calls.lastWhere(
        (c) => c.path.contains('/api/chat/message'),
      );
      final parts = msgCall.body?['parts'] as List?;
      expect(parts, isNotEmpty);
      expect(parts!.first['mediaAssetId'], 'asset_1');
    });

    test('optimistic media bubble shows uploading then clears', () async {
      final config = FrontFaceChatConfig(
        projectId: testConfig.projectId,
        publishableKey: testConfig.publishableKey,
        requireLeadCaptureBeforeChat: false,
        attachments: const FrontFaceAttachmentsConfig(enableAudio: true),
      );
      final fake = FakeApiManager(config)..delay = const Duration(milliseconds: 40);
      final provider = _buildProvider(fake, config: config);
      await provider.initialize();

      final temp = await File(
        '${Directory.systemTemp.path}/ff_aud_${DateTime.now().microsecondsSinceEpoch}.mp3',
      ).create();
      await temp.writeAsBytes(List<int>.filled(32, 2));
      addTearDown(() => temp.deleteSync());

      final future = provider.sendMediaAttachment(
        FrontFacePendingAttachment(
          kind: FrontFaceAttachmentKind.audio,
          path: temp.path,
          fileName: 'note.mp3',
          mimeType: 'audio/mpeg',
          byteLength: 32,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        provider.messages.any((m) => m.isAttachmentUploading),
        isTrue,
        reason: 'user bubble must appear immediately with upload loader',
      );
      expect(
        provider.showTypingIndicator,
        isFalse,
        reason: 'attachment upload uses bubble loader, not agent typing dots',
      );

      await future;
      expect(provider.messages.any((m) => m.isAttachmentUploading), isFalse);
      final customer = provider.messages.lastWhere(
        (m) => m.senderType == FrontFaceSenderType.customer,
      );
      expect(customer.attachment?.kind, FrontFaceAttachmentKind.audio);
    });
  });
}
