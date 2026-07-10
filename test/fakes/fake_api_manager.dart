import 'package:frontface_chat/src/config/frontface_chat_config.dart';
import 'package:frontface_chat/src/services/frontface_api_manager.dart';

class RecordedCall {
  final String path;
  final String? sessionToken;
  final Map<String, dynamic>? body;

  RecordedCall({required this.path, required this.sessionToken, this.body});
}

/// Test double for [FrontFaceApiManager] that returns canned responses
/// instead of making real HTTP calls, and records every call so tests can
/// assert on paths/headers/bodies sent by the provider.
class FakeApiManager extends FrontFaceApiManager {
  FakeApiManager(super.config);

  final List<RecordedCall> calls = [];

  /// Artificial delay applied to every call, so tests can observe transient
  /// loading states that would otherwise resolve within a single pump.
  Duration delay = Duration.zero;

  Map<String, dynamic> embedConfigResponse = {
    'enabled': true,
    'config': {
      'title': 'Chat with us',
      'greeting': 'Hi! How can I help you today?',
      'greetingIntro': '',
      'placeholder': '',
      'primaryColor': '#0a0a0a',
    },
    'leadCapture': {'enabled': false},
  };

  Map<String, dynamic> handoffAvailabilityResponse = {
    'available': true,
    'showButton': true,
    'buttonText': '',
  };

  Map<String, dynamic> Function(Map<String, dynamic>? body)?
  sendMessageResponder;

  bool leadCaptureCompleted = false;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    required String visitorId,
    String? sessionToken,
  }) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    calls.add(RecordedCall(path: path, sessionToken: sessionToken));
    if (path.contains('/api/embed/config/')) return embedConfigResponse;
    if (path.contains('/handoff-availability')) {
      return handoffAvailabilityResponse;
    }
    if (path.contains('/lead-capture/status')) {
      return {'hasCompletedForm': leadCaptureCompleted};
    }
    if (path.contains('/messages/public')) return {'messages': []};
    if (path.contains('/status')) return {'status': 'ai_active'};
    return {};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    required String visitorId,
    String? sessionToken,
    Map<String, dynamic>? body,
    bool throwOnError = true,
  }) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    calls.add(RecordedCall(path: path, sessionToken: sessionToken, body: body));
    if (path.contains('/api/chat/message')) {
      return sendMessageResponder?.call(body) ??
          {'response': 'ok', 'sessionId': 'sess_1', 'sessionToken': 'tok_1'};
    }
    if (path.contains('/ensure-conversation')) {
      return {'conversationId': 'sess_1', 'sessionToken': 'tok_1'};
    }
    if (path.contains('/handoff')) {
      return {'status': 'waiting', 'queuePosition': 1};
    }
    if (path.contains('/submit-form')) {
      return {'success': true, 'leadId': 'lead_1', 'nextAction': 'none'};
    }
    return {};
  }
}

const testConfig = FrontFaceChatConfig(
  projectId: 'test-project',
  publishableKey: 'pk_test',
);
