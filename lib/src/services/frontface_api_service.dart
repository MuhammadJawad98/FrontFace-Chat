import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../config/frontface_chat_config.dart';
import '../models/frontface_models.dart';
import 'frontface_api_manager.dart';
import 'frontface_visitor_store.dart';

class FrontFaceApiService {
  FrontFaceApiService({
    required this.config,
    FrontFaceVisitorStore? store,
    FrontFaceApiManager? apiManager,
  }) : _store = store ?? FrontFaceVisitorStore(),
       _api = apiManager ?? FrontFaceApiManager(config);

  final FrontFaceChatConfig config;
  final FrontFaceVisitorStore _store;
  final FrontFaceApiManager _api;

  Future<FrontFaceEmbedConfig> fetchEmbedConfig(String visitorId) async {
    final data = await _api.get(
      '/api/embed/config/${config.projectId}',
      visitorId: visitorId,
    );
    return FrontFaceEmbedConfig.fromJson(data);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String visitorId,
    String message = '',
    String? sessionId,
    String? sessionToken,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? location,
    List<Map<String, String>>? parts,
  }) async {
    final context = await _buildContext();
    final hasLocation = location != null && location.isNotEmpty;
    final hasParts = parts != null && parts.isNotEmpty;
    return _api.post(
      '/api/chat/message',
      visitorId: visitorId,
      sessionToken: sessionToken,
      body: {
        'projectId': config.projectId,
        'message': message,
        'visitorId': visitorId,
        'source': 'mobile',
        if (sessionId != null) 'sessionId': sessionId,
        // Only send history on the first message — redundant once session exists.
        if (sessionId == null &&
            conversationHistory != null &&
            conversationHistory.isNotEmpty)
          'conversationHistory': conversationHistory,
        if (context.isNotEmpty) 'context': context,
        if (hasLocation) 'location': location,
        if (hasParts) 'parts': parts,
      },
    );
  }

  /// Step 1 of image/voice send — reserve a signed PUT URL.
  Future<FrontFaceMediaUploadReservation> reserveMediaUpload({
    required String visitorId,
    required String conversationId,
    required String? sessionToken,
    required String mime,
    int? byteSize,
    String? filename,
  }) async {
    final data = await _api.post(
      '/api/media/uploads',
      visitorId: visitorId,
      sessionToken: sessionToken,
      body: {
        'projectId': config.projectId,
        'conversationId': conversationId,
        'mime': mime,
        if (byteSize != null) 'byteSize': byteSize,
        if (filename != null && filename.isNotEmpty) 'filename': filename,
      },
    );
    return FrontFaceMediaUploadReservation.fromJson(data);
  }

  /// Step 2 — PUT file bytes to the signed [uploadUrl].
  Future<void> uploadMediaBytes({
    required String uploadUrl,
    required List<int> bytes,
    required String contentType,
  }) {
    return _api.putBytes(
      uploadUrl,
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<Map<String, dynamic>> ensureConversation({
    required String visitorId,
  }) async {
    return _api.post(
      '/api/chat/ensure-conversation',
      visitorId: visitorId,
      body: {
        'projectId': config.projectId,
        'visitorId': visitorId,
        'source': 'mobile',
      },
    );
  }

  Future<FrontFaceHandoffAvailability> getHandoffAvailability(
    String visitorId,
  ) async {
    final data = await _api.get(
      '/api/projects/${config.projectId}/handoff-availability',
      visitorId: visitorId,
    );
    return FrontFaceHandoffAvailability.fromJson(data);
  }

  Future<Map<String, dynamic>> triggerHandoff({
    required String visitorId,
    required String conversationId,
    required String? sessionToken,
  }) async {
    return _api.post(
      '/api/conversations/$conversationId/handoff',
      visitorId: visitorId,
      sessionToken: sessionToken,
      body: {'reason': 'button_click'},
    );
  }

  Future<Map<String, dynamic>> getConversationStatus({
    required String visitorId,
    required String conversationId,
    required String? sessionToken,
  }) async {
    return _api.get(
      '/api/widget/conversations/$conversationId/status',
      visitorId: visitorId,
      sessionToken: sessionToken,
    );
  }

  Future<List<FrontFaceChatMessage>> fetchMessages({
    required String visitorId,
    required String conversationId,
    required String? sessionToken,
    String? after,
  }) async {
    final query = after == null ? '' : '?after=${Uri.encodeComponent(after)}';
    final data = await _api.get(
      '/api/widget/conversations/$conversationId/messages/public$query',
      visitorId: visitorId,
      sessionToken: sessionToken,
    );
    final messages = data['messages'] as List<dynamic>? ?? [];
    return messages
        .map((e) => FrontFaceChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> getLeadCaptureStatus(String visitorId) async {
    final data = await _api.get(
      '/api/chat/lead-capture/status'
      '?projectId=${config.projectId}&visitorId=${Uri.encodeComponent(visitorId)}',
      visitorId: visitorId,
    );
    return data['hasCompletedForm'] as bool? ?? false;
  }

  /// Best-effort customer typing indicator for the agent dashboard.
  Future<void> sendTyping({
    required String visitorId,
    required String conversationId,
    required String? sessionToken,
    required bool isTyping,
  }) async {
    await _api.post(
      '/api/widget/conversations/$conversationId/typing',
      visitorId: visitorId,
      sessionToken: sessionToken,
      throwOnError: false,
      body: {
        'isTyping': isTyping,
        'participantType': 'customer',
      },
    );
  }

  /// Best-effort customer presence for the agent dashboard.
  Future<void> sendPresence({
    required String visitorId,
    required String conversationId,
    required String? sessionToken,
    required String status,
  }) async {
    await _api.post(
      '/api/widget/conversations/$conversationId/presence',
      visitorId: visitorId,
      sessionToken: sessionToken,
      throwOnError: false,
      body: {
        'status': status,
        'visitorId': visitorId,
      },
    );
  }

  /// Short-lived JWT for private Realtime channel `conversation:<id>`.
  Future<Map<String, dynamic>> fetchRealtimeToken({
    required String visitorId,
    required String conversationId,
    required String? sessionToken,
  }) async {
    return _api.post(
      '/api/widget/conversations/$conversationId/realtime-token',
      visitorId: visitorId,
      sessionToken: sessionToken,
      body: const {},
    );
  }

  /// Links a logged-in user to this visitor via a JWT from the tenant backend.
  /// See [IDENTITY_VERIFICATION_GUIDE.md] — never blocks chat on failure.
  Future<FrontFaceIdentifyResult> identifyCustomer({
    required String visitorId,
    required String token,
  }) async {
    final data = await _api.post(
      '/api/customers/identify',
      visitorId: visitorId,
      body: {
        'projectId': config.projectId,
        'visitorId': visitorId,
        'token': token,
      },
    );
    return FrontFaceIdentifyResult.fromJson(data);
  }

  Future<void> submitCsat({
    required String visitorId,
    required String conversationId,
    required String? sessionToken,
    required int rating,
    String? feedback,
  }) async {
    await _api.post(
      '/api/widget/conversations/$conversationId/csat',
      visitorId: visitorId,
      sessionToken: sessionToken,
      throwOnError: false,
      body: {
        'rating': rating,
        if (feedback != null && feedback.trim().isNotEmpty)
          'feedback': feedback.trim(),
      },
    );
  }

  Future<void> submitOfflineMessage({
    required String visitorId,
    required String name,
    required String email,
    required String message,
  }) async {
    await _api.post(
      '/api/projects/${config.projectId}/offline-messages',
      visitorId: visitorId,
      body: {
        'name': name.trim(),
        'email': email.trim(),
        'message': message.trim(),
        'visitorId': visitorId,
      },
    );
  }

  Future<FrontFaceTicketAction> submitTicketIntentContact({
    required String visitorId,
    required String intentId,
    required String? sessionToken,
    String? email,
    String? phone,
  }) async {
    final data = await _api.post(
      '/api/ticket-intents/$intentId/contact',
      visitorId: visitorId,
      sessionToken: sessionToken,
      body: {
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
    );
    final ticket = data['ticket'] as Map<String, dynamic>?;
    final action = FrontFaceTicketAction.tryParse(ticket);
    if (action == null) {
      throw const FrontFaceApiException(
        code: 'INVALID_TICKET_RESPONSE',
        message: 'Unexpected ticket response.',
      );
    }
    return action;
  }

  Future<Map<String, dynamic>> submitLeadForm({
    required String visitorId,
    required Map<String, dynamic> formData,
    String? sessionId,
    String firstMessage = '',
  }) async {
    return _api.post(
      '/api/chat/lead-capture/submit-form',
      visitorId: visitorId,
      body: {
        'projectId': config.projectId,
        'visitorId': visitorId,
        'source': 'mobile',
        'formData': formData,
        'firstMessage': firstMessage,
        if (sessionId != null) 'sessionId': sessionId,
      },
    );
  }

  Future<String> getOrCreateVisitorId() => _store.getOrCreateVisitorId();

  Future<void> setVisitorId(String visitorId) => _store.setVisitorId(visitorId);

  Future<Map<String, dynamic>> _buildContext() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return {
        'device': 'mobile',
        'os': Platform.isIOS ? 'iOS' : 'Android',
        'osVersion': Platform.operatingSystemVersion,
        'appVersion': packageInfo.version,
        'language': Platform.localeName,
      };
    } catch (_) {
      return {'device': 'mobile'};
    }
  }
}
