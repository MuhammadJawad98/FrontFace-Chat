import 'package:frontface_chat/src/config/frontface_chat_config.dart';
import 'package:frontface_chat/src/models/frontface_models.dart';
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
  final List<PutCall> putCalls = [];

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
    'mode': 'live',
    'buttonText': '',
  };

  Map<String, dynamic> Function(Map<String, dynamic>? body)?
  sendMessageResponder;

  bool leadCaptureCompleted = false;

  /// Canned history returned by GET .../messages/public — set this to
  /// simulate hydrating a conversation with existing messages on reload.
  List<Map<String, dynamic>> messagesResponse = [];

  /// Canned unified history for GET /api/customers/history (newest → oldest).
  /// When non-null, [getWithSessionAuth] returns this instead of [messagesResponse].
  List<Map<String, dynamic>>? customerHistoryResponse;

  /// Optional second page for unified history pagination tests.
  List<Map<String, dynamic>> customerHistoryPage2 = [];

  /// When true, GET /api/customers/history throws 403 NOT_VERIFIED.
  bool customerHistoryNotVerified = false;

  Map<String, dynamic> mediaUploadResponse = {
    'assetId': 'asset_1',
    'uploadUrl': 'https://storage.example.com/upload/signed',
    'token': 'upload_tok',
    'path': 'media/asset_1',
  };

  bool putShouldFail = false;

  /// If set, any get/post call whose path contains this substring throws
  /// [forcedError] instead of returning a canned response — used to
  /// simulate a 403 SESSION_INVALID (or any other) error from the server.
  String? forcedErrorPathContains;
  FrontFaceApiException? forcedError;

  /// How many more times [forcedError] may be thrown. Defaults to unlimited
  /// (`null`). Set to `1` so a recovery+retry path can succeed after the
  /// first stale-session failure.
  int? forcedErrorRemaining;

  void _maybeThrow(String path) {
    final substring = forcedErrorPathContains;
    if (substring == null || !path.contains(substring)) return;
    final remaining = forcedErrorRemaining;
    if (remaining != null) {
      if (remaining <= 0) return;
      forcedErrorRemaining = remaining - 1;
    }
    throw forcedError!;
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    required String visitorId,
    String? sessionToken,
  }) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    calls.add(RecordedCall(path: path, sessionToken: sessionToken));
    _maybeThrow(path);
    if (path.contains('/api/embed/config/')) return embedConfigResponse;
    if (path.contains('/handoff-availability')) {
      return handoffAvailabilityResponse;
    }
    if (path.contains('/lead-capture/status')) {
      return {'hasCompletedForm': leadCaptureCompleted};
    }
    if (path.contains('/messages/public')) {
      return {'messages': messagesResponse};
    }
    if (path.contains('/status')) return {'status': 'ai_active'};
    return {};
  }

  @override
  Future<Map<String, dynamic>> getWithSessionAuth(
    String path, {
    required String sessionToken,
  }) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    calls.add(RecordedCall(path: path, sessionToken: sessionToken));
    _maybeThrow(path);

    if (path.contains('/api/customers/history')) {
      if (customerHistoryNotVerified || customerHistoryResponse == null) {
        throw const FrontFaceApiException(
          code: 'NOT_VERIFIED',
          message: 'Customer is not verified.',
          statusCode: 403,
        );
      }
      if (path.contains('cursor=page2')) {
        return {'messages': customerHistoryPage2};
      }
      if (customerHistoryPage2.isNotEmpty) {
        return {
          'messages': customerHistoryResponse!,
          'nextCursor': 'page2',
        };
      }
      return {'messages': customerHistoryResponse!};
    }
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
    _maybeThrow(path);
    if (path.contains('/api/media/uploads')) {
      return mediaUploadResponse;
    }
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
    if (path.contains('/realtime-token')) {
      return {
        'token': 'jwt_test_token',
        'expiresAt':
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                1000,
      };
    }
    if (path.contains('/typing') || path.contains('/presence')) {
      return {'ok': true};
    }
    if (path.contains('/customers/identify')) {
      return {
        'contact': {'name': 'Test User', 'email': 'test@example.com'},
        'verifiedIdentity': {'externalId': 'user_1', 'name': 'Test User'},
      };
    }
    if (path.contains('/offline-messages')) {
      return {'success': true, 'conversationId': 'offline_1'};
    }
    if (path.contains('/csat')) {
      return {'success': true};
    }
    if (path.contains('/submit-form')) {
      return {'success': true, 'leadId': 'lead_1', 'nextAction': 'none'};
    }
    return {};
  }

  @override
  Future<void> putBytes(
    String uploadUrl, {
    required List<int> bytes,
    required String contentType,
  }) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    putCalls.add(
      PutCall(url: uploadUrl, byteLength: bytes.length, contentType: contentType),
    );
    if (putShouldFail) {
      throw const FrontFaceApiException(
        code: 'UPLOAD_FAILED',
        message: 'Media upload failed',
        statusCode: 500,
      );
    }
  }
}

class PutCall {
  final String url;
  final int byteLength;
  final String contentType;

  PutCall({
    required this.url,
    required this.byteLength,
    required this.contentType,
  });
}

const testConfig = FrontFaceChatConfig(
  projectId: 'test-project',
  publishableKey: 'pk_test',
);
