import 'dart:async';

import 'package:flutter/material.dart';

import '../config/frontface_chat_config.dart';
import '../config/frontface_chat_strings.dart';
import '../models/frontface_models.dart';
import '../services/frontface_api_service.dart';
import '../services/frontface_visitor_store.dart';

class FrontFaceChatProvider extends ChangeNotifier {
  FrontFaceChatProvider({
    required FrontFaceChatConfig config,
    FrontFaceChatStrings strings = const FrontFaceChatStrings(),
    FrontFaceApiService? api,
    FrontFaceVisitorStore? store,
  }) : _chatConfig = config,
       _strings = strings,
       _api = api ?? FrontFaceApiService(config: config, store: store),
       _store = store ?? FrontFaceVisitorStore();

  final FrontFaceChatConfig _chatConfig;
  FrontFaceChatStrings _strings;
  final FrontFaceApiService _api;
  final FrontFaceVisitorStore _store;

  final List<FrontFaceChatMessage> _messages = [];
  Timer? _pollTimer;
  int _pollTick = 0;
  String? _lastMessageAt;
  bool _disposed = false;

  String? _visitorId;
  String? _sessionId;
  String? _sessionToken;
  FrontFaceEmbedConfig _embedConfig = const FrontFaceEmbedConfig();
  FrontFaceConversationStatus _status = FrontFaceConversationStatus.aiActive;
  FrontFaceHandoffAvailability _handoffAvailability =
      const FrontFaceHandoffAvailability();

  bool _isInitializing = false;
  bool _isSending = false;
  bool _isHandoffLoading = false;
  bool _showLeadForm = false;
  bool _leadFormCompleted = false;
  String? _error;
  String? _agentName;
  int? _queuePosition;
  String? _statusBanner;

  FrontFaceChatStrings get strings => _strings;

  /// Swaps the active [FrontFaceChatStrings] at runtime (e.g. when the host
  /// app's language changes while the chat is open) and notifies listeners
  /// so the UI re-renders in the new language immediately.
  void updateStrings(FrontFaceChatStrings strings) {
    _strings = strings;
    _updateStatusBanner();
    _notify();
  }

  List<FrontFaceChatMessage> get messages => List.unmodifiable(_messages);
  FrontFaceEmbedConfig get config => _embedConfig;
  bool get isInitializing => _isInitializing;
  bool get isSending => _isSending;
  bool get isHandoffLoading => _isHandoffLoading;
  bool get showLeadForm => _showLeadForm;
  String? get error => _error;
  String? get agentName => _agentName;
  int? get queuePosition => _queuePosition;
  String? get statusBanner => _statusBanner;
  FrontFaceConversationStatus get status => _status;
  bool get canChat =>
      !_isInitializing &&
      !_showLeadForm &&
      _status != FrontFaceConversationStatus.resolved &&
      _status != FrontFaceConversationStatus.closed;

  bool get showHandoffButton =>
      _handoffAvailability.showButton &&
      _status == FrontFaceConversationStatus.aiActive;

  String get handoffButtonText => _handoffAvailability.buttonText.isNotEmpty
      ? _handoffAvailability.buttonText
      : _strings.talkToHuman;

  bool get isInHandoff =>
      _status == FrontFaceConversationStatus.waiting ||
      _status == FrontFaceConversationStatus.agentActive;

  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;
    _error = null;
    notifyListeners();

    try {
      _visitorId = await _api.getOrCreateVisitorId();
      _embedConfig = await _api.fetchEmbedConfig(_visitorId!);
      if (!_embedConfig.enabled) {
        throw FrontFaceApiException(
          code: 'DISABLED',
          message: _strings.chatUnavailable,
        );
      }

      _leadFormCompleted = await _store.hasCompletedLeadForm(
        _chatConfig.projectId,
      );
      if (!_leadFormCompleted) {
        _leadFormCompleted = await _api.getLeadCaptureStatus(_visitorId!);
        if (_leadFormCompleted) {
          await _store.setLeadFormCompleted(_chatConfig.projectId, true);
        }
      }

      _messages.clear();
      _lastMessageAt = null;
      _sessionId = await _store.getSessionId(_chatConfig.projectId);
      _sessionToken = await _store.getSessionToken(_chatConfig.projectId);

      // Lead capture requirement wins even over an already-stored session —
      // a stored sessionId only means the conversation exists server-side,
      // not that this visitor has been identified. Without this check
      // first, a session created before lead capture was required (or
      // before requireLeadCaptureBeforeChat was turned on) would hydrate
      // straight past the form.
      if (_shouldShowLeadFormBeforeChat()) {
        _showLeadForm = true;
      } else if (_sessionId != null) {
        try {
          await _hydrateConversation();
        } on FrontFaceApiException catch (e) {
          if (!_isSessionExpired(e)) rethrow;
          await _handleSessionExpired();
        }
      } else {
        _appendGreetingIfNeeded();
      }

      _handoffAvailability = await _api.getHandoffAvailability(_visitorId!);
    } on FrontFaceApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = _strings.failedToLoadChat;
    } finally {
      _isInitializing = false;
      _notify();
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _visitorId == null || _isSending || !canChat) return;

    _isSending = true;
    _error = null;
    _appendMessage(
      FrontFaceChatMessage.local(
        content: trimmed,
        senderType: FrontFaceSenderType.customer,
      ),
    );
    _notify();

    try {
      final response = await _api.sendMessage(
        visitorId: _visitorId!,
        message: trimmed,
        sessionId: _sessionId,
        sessionToken: _sessionToken,
        conversationHistory: _buildConversationHistory(),
      );

      await _applySessionFromResponse(response);

      final assistantText = response['response']?.toString() ?? '';
      final handoff = response['handoff'] as Map<String, dynamic>?;

      if (assistantText.isNotEmpty) {
        _appendMessage(
          FrontFaceChatMessage.local(
            content: assistantText,
            senderType: FrontFaceSenderType.ai,
          ),
        );
      }

      if (_shouldEnterHandoff(assistantText, handoff)) {
        _applyHandoffFromResponse(handoff);
        _startPolling();
      } else {
        _handoffAvailability = await _api.getHandoffAvailability(_visitorId!);
        _evaluateLeadFormAfterSend();
      }
    } on FrontFaceApiException catch (e) {
      if (_isSessionExpired(e)) {
        await _handleSessionExpired();
      } else {
        _error = e.message;
      }
    } catch (_) {
      _error = _strings.failedToSendMessage;
    } finally {
      _isSending = false;
      _notify();
    }
  }

  Future<void> submitLeadForm({
    required String email,
    String? field2,
    String? field3,
  }) async {
    if (_visitorId == null) return;

    final formData = <String, dynamic>{'email': email.trim()};
    if (_embedConfig.field2Enabled && (field2?.trim().isNotEmpty ?? false)) {
      formData['field_2'] = {
        'label': _embedConfig.field2Label ?? 'Field 2',
        'value': field2!.trim(),
      };
    }
    if (_embedConfig.field3Enabled && (field3?.trim().isNotEmpty ?? false)) {
      formData['field_3'] = {
        'label': _embedConfig.field3Label ?? 'Field 3',
        'value': field3!.trim(),
      };
    }

    try {
      final response = await _api.submitLeadForm(
        visitorId: _visitorId!,
        formData: formData,
        sessionId: _sessionId,
      );

      await _applySessionFromResponse(response);

      final greeting = response['assembledGreeting']?.toString();
      if (greeting != null && greeting.isNotEmpty) {
        _appendMessage(
          FrontFaceChatMessage.local(
            content: greeting,
            senderType: FrontFaceSenderType.ai,
          ),
        );
      } else {
        _appendGreetingIfNeeded();
      }

      await _store.setLeadFormCompleted(_chatConfig.projectId, true);
      _leadFormCompleted = true;
      _showLeadForm = false;
      _error = null;
    } on FrontFaceApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = _strings.failedToSubmitForm;
    }
    _notify();
  }

  Future<void> requestHuman() async {
    if (_visitorId == null || _isHandoffLoading) return;

    _isHandoffLoading = true;
    _error = null;
    _notify();

    try {
      if (_sessionId == null) {
        final ensured = await _api.ensureConversation(visitorId: _visitorId!);
        await _applySessionFromResponse({
          'sessionId': ensured['conversationId'],
          'sessionToken': ensured['sessionToken'],
        });
      }
      if (_sessionId == null) {
        throw FrontFaceApiException(
          code: 'NO_CONVERSATION',
          message: _strings.couldNotConnectAgent,
        );
      }

      final result = await _api.triggerHandoff(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
      );
      _applyHandoffResult(result);
      _startPolling();
    } on FrontFaceApiException catch (e) {
      if (_isSessionExpired(e)) {
        await _handleSessionExpired();
      } else {
        _error = e.message;
      }
    } catch (_) {
      _error = _strings.couldNotConnectAgent;
    } finally {
      _isHandoffLoading = false;
      _notify();
    }
  }

  Future<void> startNewChat() async {
    _stopPolling();
    _sessionId = null;
    _sessionToken = null;
    _messages.clear();
    _status = FrontFaceConversationStatus.aiActive;
    _agentName = null;
    _queuePosition = null;
    _statusBanner = null;
    _error = null;
    await _store.saveSessionId(_chatConfig.projectId, null);
    await _store.saveSessionToken(_chatConfig.projectId, null);

    if (_shouldShowLeadFormBeforeChat()) {
      _showLeadForm = true;
    } else {
      _appendGreetingIfNeeded();
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }

  Future<void> _hydrateConversation() async {
    if (_visitorId == null || _sessionId == null) return;

    final messages = await _api.fetchMessages(
      visitorId: _visitorId!,
      conversationId: _sessionId!,
      sessionToken: _sessionToken,
    );
    for (final message in messages) {
      _appendMessage(message);
    }

    final statusData = await _api.getConversationStatus(
      visitorId: _visitorId!,
      conversationId: _sessionId!,
      sessionToken: _sessionToken,
    );
    _applyStatus(statusData['status']?.toString());
    _agentName = statusData['assignedAgent']?['name']?.toString();
    _queuePosition = statusData['queuePosition'] as int?;

    if (isInHandoff) {
      _updateStatusBanner();
      _startPolling();
    } else if (_messages.isEmpty) {
      _appendGreetingIfNeeded();
    }
  }

  void _startPolling() {
    _stopPolling();
    if (!isInHandoff || _sessionId == null || _visitorId == null) return;

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_disposed || _sessionId == null || _visitorId == null) return;
      _pollTick++;
      await _pollMessages();
      if (_pollTick % 5 == 0) await _pollStatus();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollTick = 0;
  }

  Future<void> _pollMessages() async {
    try {
      final messages = await _api.fetchMessages(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
        after: _lastMessageAt,
      );
      for (final message in messages) {
        if (message.senderType == FrontFaceSenderType.customer) continue;
        _appendMessage(message);
      }
    } on FrontFaceApiException catch (e) {
      if (_isSessionExpired(e)) {
        await _handleSessionExpired();
        _notify();
      }
    } catch (_) {}
  }

  Future<void> _pollStatus() async {
    try {
      final statusData = await _api.getConversationStatus(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
      );
      _applyStatus(statusData['status']?.toString());
      _agentName = statusData['assignedAgent']?['name']?.toString();
      _queuePosition = statusData['queuePosition'] as int?;
      _updateStatusBanner();

      if (_status == FrontFaceConversationStatus.resolved ||
          _status == FrontFaceConversationStatus.closed) {
        _stopPolling();
      }
      _notify();
    } on FrontFaceApiException catch (e) {
      if (_isSessionExpired(e)) {
        await _handleSessionExpired();
        _notify();
      }
    } catch (_) {}
  }

  static const _sessionExpiredCodes = {
    'SESSION_INVALID',
    'SESSION_CONVERSATION_MISMATCH',
  };

  bool _isSessionExpired(Object error) =>
      error is FrontFaceApiException &&
      _sessionExpiredCodes.contains(error.code);

  /// Clears the stale session and, if lead capture is enabled, requires it
  /// again before the next message — mirrors "start a new chat" but is
  /// triggered automatically when the backend rejects the stored session
  /// (expired/invalidated `sessionToken`) instead of by a user tap.
  Future<void> _handleSessionExpired() async {
    _stopPolling();
    _sessionId = null;
    _sessionToken = null;
    _messages.clear();
    _status = FrontFaceConversationStatus.aiActive;
    _agentName = null;
    _queuePosition = null;
    _statusBanner = null;
    await _store.saveSessionId(_chatConfig.projectId, null);
    await _store.saveSessionToken(_chatConfig.projectId, null);

    _appendMessage(
      FrontFaceChatMessage.local(
        content: _strings.sessionExpired,
        senderType: FrontFaceSenderType.system,
      ),
    );

    if (_embedConfig.leadCaptureEnabled) {
      _leadFormCompleted = false;
      await _store.setLeadFormCompleted(_chatConfig.projectId, false);
      _showLeadForm = true;
    } else {
      _showLeadForm = false;
      _appendGreetingIfNeeded();
    }
    _error = null;
  }

  Future<void> _applySessionFromResponse(Map<String, dynamic> response) async {
    final newSessionId = response['sessionId']?.toString();
    if (newSessionId != null && newSessionId.isNotEmpty) {
      _sessionId = newSessionId;
      await _store.saveSessionId(_chatConfig.projectId, newSessionId);
    }

    final newSessionToken = response['sessionToken']?.toString();
    if (newSessionToken != null && newSessionToken.isNotEmpty) {
      _sessionToken = newSessionToken;
      await _store.saveSessionToken(_chatConfig.projectId, newSessionToken);
    }
  }

  bool _shouldShowLeadFormBeforeChat() {
    if (!_embedConfig.leadCaptureEnabled || _leadFormCompleted) return false;
    if (_chatConfig.requireLeadCaptureBeforeChat) return true;
    final mode = _embedConfig.leadCaptureMode;
    return mode == FrontFaceLeadCaptureMode.emailFirst ||
        mode == FrontFaceLeadCaptureMode.emailRequired;
  }

  void _evaluateLeadFormAfterSend() {
    if (!_embedConfig.leadCaptureEnabled || _leadFormCompleted) return;
    if (_embedConfig.leadCaptureMode == FrontFaceLeadCaptureMode.emailAfter &&
        _messages.any((m) => m.senderType == FrontFaceSenderType.customer)) {
      _showLeadForm = true;
      _notify();
    }
  }

  void _appendGreetingIfNeeded() {
    // Guard on an existing AI message (not "any message") so a leading
    // system note — e.g. the session-expired notice — doesn't suppress
    // the greeting that should follow it.
    if (_messages.any((m) => m.senderType == FrontFaceSenderType.ai)) return;
    final greeting = _embedConfig.greeting.trim();
    if (greeting.isEmpty) return;

    _appendMessage(
      FrontFaceChatMessage.local(
        content: greeting,
        senderType: FrontFaceSenderType.ai,
      ),
    );
  }

  void _appendMessage(FrontFaceChatMessage message) {
    if (_messages.any((m) => m.id == message.id)) return;
    _messages.add(message);
    _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _lastMessageAt = message.createdAt.toUtc().toIso8601String();
  }

  List<Map<String, String>> _buildConversationHistory() {
    final history = <Map<String, String>>[];
    for (final message in _messages.reversed) {
      if (message.senderType == FrontFaceSenderType.system) continue;
      final role = message.senderType == FrontFaceSenderType.customer
          ? 'user'
          : 'assistant';
      history.insert(0, {'role': role, 'content': message.content});
      if (history.length >= 10) break;
    }
    return history;
  }

  bool _shouldEnterHandoff(String response, Map<String, dynamic>? handoff) {
    if (handoff == null) return false;
    if (handoff['triggered'] == true) return true;
    final reason = handoff['reason']?.toString();
    return response.isEmpty &&
        (reason == 'in_queue' || reason == 'agent_handling');
  }

  void _applyHandoffFromResponse(Map<String, dynamic>? handoff) {
    if (handoff == null) return;
    final reason = handoff['reason']?.toString();
    if (reason == 'agent_handling') {
      _status = FrontFaceConversationStatus.agentActive;
    } else {
      _status = FrontFaceConversationStatus.waiting;
      _queuePosition = handoff['queuePosition'] as int?;
    }
    _updateStatusBanner();
  }

  void _applyHandoffResult(Map<String, dynamic> result) {
    final status = result['status']?.toString();
    switch (status) {
      case 'agent_active':
        _status = FrontFaceConversationStatus.agentActive;
        _agentName = result['assignedAgent']?['name']?.toString();
        break;
      case 'waiting':
        _status = FrontFaceConversationStatus.waiting;
        _queuePosition = result['queuePosition'] as int?;
        break;
      default:
        _status = FrontFaceConversationStatus.waiting;
    }
    _updateStatusBanner();
  }

  void _applyStatus(String? value) {
    switch (value) {
      case 'waiting':
        _status = FrontFaceConversationStatus.waiting;
        break;
      case 'agent_active':
        _status = FrontFaceConversationStatus.agentActive;
        break;
      case 'resolved':
        _status = FrontFaceConversationStatus.resolved;
        break;
      case 'closed':
        _status = FrontFaceConversationStatus.closed;
        break;
      default:
        _status = FrontFaceConversationStatus.aiActive;
    }
  }

  void _updateStatusBanner() {
    switch (_status) {
      case FrontFaceConversationStatus.waiting:
        _statusBanner = _queuePosition != null
            ? _strings.waitingPosition(_queuePosition!)
            : _strings.waitingForAgent;
        break;
      case FrontFaceConversationStatus.agentActive:
        _statusBanner = _agentName != null
            ? _strings.agentHelp(_agentName!)
            : _strings.agentJoined;
        break;
      case FrontFaceConversationStatus.resolved:
      case FrontFaceConversationStatus.closed:
        _statusBanner = _strings.conversationEnded;
        break;
      default:
        _statusBanner = null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
