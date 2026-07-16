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
    required String message,
    String? sessionId,
    String? sessionToken,
    List<Map<String, String>>? conversationHistory,
  }) async {
    final context = await _buildContext();
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
        if (conversationHistory != null && conversationHistory.isNotEmpty)
          'conversationHistory': conversationHistory,
        if (context.isNotEmpty) 'context': context,
      },
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

  Future<Map<String, dynamic>> _buildContext() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return {
        'device': 'mobile',
        'os': Platform.isIOS ? 'iOS' : 'Android',
        'appVersion': packageInfo.version,
        'language': Platform.localeName,
      };
    } catch (_) {
      return {'device': 'mobile'};
    }
  }
}
