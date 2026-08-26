import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config/frontface_chat_config.dart';
import '../config/frontface_chat_strings.dart';
import '../models/frontface_models.dart';
import '../services/frontface_api_service.dart';
import '../services/frontface_realtime_bridge.dart';
import '../services/frontface_visitor_store.dart';

class FrontFaceChatProvider extends ChangeNotifier
    with WidgetsBindingObserver {
  FrontFaceChatProvider({
    required FrontFaceChatConfig config,
    FrontFaceChatStrings strings = const FrontFaceChatStrings(),
    FrontFaceApiService? api,
    FrontFaceVisitorStore? store,
    FrontFaceRealtimeBridge? realtime,
  }) : _chatConfig = config,
       _strings = strings,
       _api = api ?? FrontFaceApiService(config: config, store: store),
       _store = store ?? FrontFaceVisitorStore(),
       _realtime = realtime ?? FrontFaceSupabaseRealtimeBridge() {
    config.attachments.validate();
  }

  final FrontFaceChatConfig _chatConfig;
  FrontFaceChatStrings _strings;
  final FrontFaceApiService _api;
  final FrontFaceVisitorStore _store;
  final FrontFaceRealtimeBridge _realtime;

  final List<FrontFaceChatMessage> _messages = [];
  Timer? _pollTimer;
  Timer? _typingStopTimer;
  Timer? _presenceHeartbeatTimer;
  Timer? _realtimeRefreshTimer;
  int _pollTick = 0;
  String? _lastMessageAt;
  bool _disposed = false;
  bool _pollInFlight = false;
  bool _customerIsTyping = false;
  bool _agentTyping = false;
  bool _isAppForeground = true;
  bool _lifecycleObserving = false;

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
  bool _showOfflineForm = false;
  bool _csatSubmitted = false;
  FrontFaceIdentifyResult? _identifyResult;

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

  /// Attachment options from [FrontFaceChatConfig.attachments].
  FrontFaceAttachmentsConfig get attachmentsConfig => _chatConfig.attachments;

  /// Whether the app-bar refresh / new-chat button is shown.
  bool get showNewChatButton => _chatConfig.showNewChatButton;

  /// Stable visitor id used on every request (`X-Visitor-Id` + body).
  /// Null until [initialize] / [setVisitorId] runs.
  String? get visitorId => _visitorId;

  /// Active conversation id (`sessionId`), when known.
  String? get sessionId => _sessionId;

  bool get isInitializing => _isInitializing;
  bool get isSending => _isSending;
  bool get isHandoffLoading => _isHandoffLoading;
  bool get showLeadForm => _showLeadForm;
  String? get error => _error;
  String? get agentName => _agentName;
  int? get queuePosition => _queuePosition;
  String? get statusBanner => _statusBanner;
  FrontFaceConversationStatus get status => _status;

  /// True while a human agent is typing (Realtime only — never faked).
  bool get agentTyping => _agentTyping;

  /// Bottom "typing" dots. Hidden while an attachment upload loader is on the
  /// user bubble so media sends feel instant rather than agent-first.
  bool get showTypingIndicator =>
      agentTyping || (isSending && !_hasUploadingCustomerAttachment);

  bool get _hasUploadingCustomerAttachment => _messages.any(
        (m) =>
            m.senderType == FrontFaceSenderType.customer &&
            m.isAttachmentUploading,
      );

  /// Whether the Realtime channel is currently subscribed.
  bool get isRealtimeConnected => _realtime.isConnected;

  bool get canChat =>
      !_isInitializing &&
      !_showLeadForm &&
      _status != FrontFaceConversationStatus.resolved &&
      _status != FrontFaceConversationStatus.closed;

  bool get showHandoffButton =>
      _handoffAvailability.showLiveHandoffButton &&
      _status == FrontFaceConversationStatus.aiActive &&
      !_showOfflineForm;

  bool get showOfflineForm => _showOfflineForm;

  bool get showCsatPrompt =>
      !_csatSubmitted && _messages.any((m) => m.isCsatPrompt);

  List<FrontFaceChannelButton> get channels => _embedConfig.channels;

  FrontFaceIdentifyResult? get identifyResult => _identifyResult;

  String get handoffButtonText => _handoffAvailability.buttonText.isNotEmpty
      ? _handoffAvailability.buttonText
      : _strings.talkToHuman;

  bool get isInHandoff =>
      _status == FrontFaceConversationStatus.waiting ||
      _status == FrontFaceConversationStatus.agentActive;

  bool get isAgentActive =>
      _status == FrontFaceConversationStatus.agentActive;

  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;
    _error = null;
    notifyListeners();
    _ensureLifecycleObserver();

    try {
      await _resolveVisitorId();
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
        // Never show a local greeting while the lead form is pending.
        _messages.clear();
      } else {
        try {
          await _resolveAndHydrateHistory();
        } on FrontFaceApiException catch (e) {
          if (!_isSessionStale(e)) rethrow;
          await _recoverStaleSession();
        }
      }

      _handoffAvailability = await _api.getHandoffAvailability(_visitorId!);
      if (_handoffAvailability.showOfflineForm) {
        _showOfflineForm = true;
      }
    } on FrontFaceApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = _strings.failedToLoadChat;
    } finally {
      _isInitializing = false;
      _notify();
    }
  }

  /// Sets a stable account-keyed visitor id (from your backend after login).
  ///
  /// Persist before [initialize] so history follows the user across devices.
  /// Call [resetUser] on logout.
  Future<void> setVisitorId(String visitorId) async {
    await _api.setVisitorId(visitorId);
    _visitorId = visitorId.trim();
    _notify();
  }

  Future<void> _resolveVisitorId() async {
    final configured = _chatConfig.visitorId?.trim();
    if (configured != null && configured.isNotEmpty) {
      await _api.setVisitorId(configured);
      _visitorId = configured;
    } else {
      _visitorId = await _api.getOrCreateVisitorId();
    }
    if (kDebugMode && _chatConfig.debugLogging) {
      debugPrint(
        '[FrontFace] visitorId=$_visitorId (must stay identical across launches)',
      );
    }
  }

  /// Resolves the visitor's active conversation, then loads full transcript.
  ///
  /// When local `sessionId` is missing (cleared storage, new install of the
  /// same account-keyed visitor, etc.), `ensure-conversation` recovers it —
  /// history is keyed to [visitorId], not to locally cached session ids.
  Future<void> _resolveAndHydrateHistory() async {
    if (_visitorId == null) return;

    if (_sessionId == null) {
      final ensured = await _api.ensureConversation(visitorId: _visitorId!);
      await _applySessionFromResponse(ensured);
    }

    if (_sessionId != null) {
      await _hydrateConversation();
    } else {
      _appendGreetingIfNeeded();
    }
  }

  /// Links the logged-in user to this visitor using a JWT from your backend.
  ///
  /// Your backend team mints the token (see `IDENTITY_VERIFICATION_GUIDE.md`).
  /// Never blocks chat — failures throw [FrontFaceIdentifyException].
  Future<FrontFaceIdentifyResult> identify(String token) async {
    if (_visitorId == null) {
      await _resolveVisitorId();
    }
    try {
      final result = await _api.identifyCustomer(
        visitorId: _visitorId!,
        token: token.trim(),
      );
      _identifyResult = result;
      _notify();
      return result;
    } on FrontFaceApiException catch (e) {
      throw FrontFaceIdentifyException(code: e.code, message: e.message);
    }
  }

  /// Logout helper: rotate visitor id and clear this project's session/chat.
  Future<void> resetUser() async {
    await _leaveHandoffSideEffects(sendOffline: false);
    _visitorId = await _store.rotateVisitorId();
    _sessionId = null;
    _sessionToken = null;
    _messages.clear();
    _lastMessageAt = null;
    _status = FrontFaceConversationStatus.aiActive;
    _agentName = null;
    _queuePosition = null;
    _statusBanner = null;
    _error = null;
    _showOfflineForm = false;
    _csatSubmitted = false;
    _identifyResult = null;
    _showLeadForm = false;
    await _store.saveSessionId(_chatConfig.projectId, null);
    await _store.saveSessionToken(_chatConfig.projectId, null);
    await _store.setLeadFormCompleted(_chatConfig.projectId, false);
    _leadFormCompleted = false;
    if (_embedConfig.leadCaptureEnabled && _chatConfig.requireLeadCaptureBeforeChat) {
      _showLeadForm = true;
    } else {
      _appendGreetingIfNeeded();
    }
    _handoffAvailability = await _api.getHandoffAvailability(_visitorId!);
    _notify();
  }

  Future<void> submitCsat(int rating, {String? feedback}) async {
    if (_visitorId == null || _sessionId == null) return;
    if (rating < 1 || rating > 5) return;
    try {
      await _api.submitCsat(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
        rating: rating,
        feedback: feedback,
      );
      _csatSubmitted = true;
      _notify();
    } catch (_) {}
  }

  Future<void> submitOfflineMessage({
    required String name,
    required String email,
    required String message,
  }) async {
    if (_visitorId == null) return;
    try {
      await _api.submitOfflineMessage(
        visitorId: _visitorId!,
        name: name,
        email: email,
        message: message,
      );
      _showOfflineForm = false;
      _error = null;
      _messages.add(
        FrontFaceChatMessage.local(
          content: _strings.offlineSuccess,
          senderType: FrontFaceSenderType.system,
        ),
      );
      _notify();
    } on FrontFaceApiException catch (e) {
      _error = e.message;
      _notify();
    } catch (_) {
      _error = _strings.failedToSendMessage;
      _notify();
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _visitorId == null || _isSending || !canChat) return;

    stopTyping();
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
      await _deliverMessage(trimmed);
    } on FrontFaceApiException catch (e) {
      if (_isSessionStale(e)) {
        // Clear chat and return to the lead form — session + greeting
        // are created only after the form is submitted again.
        await _recoverStaleSession();
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

  /// Sends a location pin via `POST /api/chat/message` `location` object.
  Future<void> sendLocationAttachment(FrontFaceAttachmentPayload location) async {
    if (location.kind != FrontFaceAttachmentKind.location) return;
    if (_visitorId == null || _isSending || !canChat) return;
    if (!_chatConfig.attachments.enableLocation) return;

    final data = location.toLocationData();
    if (data == null) return;

    final uploading = location.copyWith(
      uploadStatus: FrontFaceAttachmentUploadStatus.uploading,
    );
    final content = uploading.toMessageContent(_strings);
    final part = FrontFaceMessagePart.localLocation(data);
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';

    stopTyping();
    _isSending = true;
    _error = null;
    _appendMessage(
      FrontFaceChatMessage.local(
        id: localId,
        content: content,
        senderType: FrontFaceSenderType.customer,
        metadata: FrontFaceMessageMetadata(uploading.toMetadata()),
        parts: [part],
      ),
    );
    _notify();

    try {
      await _deliverMessage(
        '',
        location: data.toJson(),
      );
      // Promote local bubble in place (keeps order), then fold in server URLs.
      await _mergeServerHistory();
      _markLocalAttachmentSent(localId);
    } on FrontFaceApiException catch (e) {
      _markLocalAttachmentFailed(localId);
      if (_isSessionStale(e)) {
        await _recoverStaleSession();
      } else {
        _error = e.message;
      }
    } catch (_) {
      _markLocalAttachmentFailed(localId);
      _error = _strings.failedToSendMessage;
    } finally {
      _isSending = false;
      _notify();
    }
  }

  /// Uploads image/audio via FrontFace signed URL, then sends `parts`.
  Future<void> sendMediaAttachment(FrontFacePendingAttachment pending) async {
    if (_visitorId == null || _isSending || !canChat) return;
    final cfg = _chatConfig.attachments;
    final allowed = switch (pending.kind) {
      FrontFaceAttachmentKind.image => cfg.enableImages,
      FrontFaceAttachmentKind.audio => cfg.enableAudio,
      FrontFaceAttachmentKind.location => false,
    };
    if (!allowed) return;

    final mime = _normalizeMime(pending);
    if (mime == null) {
      _error = _strings.attachmentUploadFailed;
      _notify();
      return;
    }

    stopTyping();
    _isSending = true;
    _error = null;

    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final provisional = switch (pending.kind) {
      FrontFaceAttachmentKind.image => FrontFaceMessagePart.localImage(
          localPath: pending.path,
        ),
      FrontFaceAttachmentKind.audio => FrontFaceMessagePart.localAudio(
          localPath: pending.path,
        ),
      FrontFaceAttachmentKind.location => null,
    };
    final placeholder = FrontFaceAttachmentPayload(
      kind: pending.kind,
      url: pending.path,
      label: pending.fileName,
      uploadStatus: FrontFaceAttachmentUploadStatus.uploading,
    );
    // Show the local file in the user bubble immediately with a loader.
    _appendMessage(
      FrontFaceChatMessage.local(
        id: localId,
        content: placeholder.toMessageContent(_strings),
        senderType: FrontFaceSenderType.customer,
        metadata: FrontFaceMessageMetadata(placeholder.toMetadata()),
        parts: provisional == null ? const [] : [provisional],
      ),
    );
    _notify();

    try {
      await _ensureConversationReady();
      if (_sessionId == null) {
        throw const FrontFaceApiException(
          code: 'NO_CONVERSATION',
          message: 'Could not start a conversation for media upload.',
        );
      }

      final bytes = await File(pending.path).readAsBytes();
      final maxBytes = pending.kind == FrontFaceAttachmentKind.image
          ? cfg.maxImageBytes
          : cfg.maxAudioBytes;
      if (bytes.length > maxBytes) {
        throw FrontFaceApiException(
          code: 'FILE_TOO_LARGE',
          message: _strings.attachmentTooLarge,
        );
      }

      final reservation = await _api.reserveMediaUpload(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
        mime: mime,
        byteSize: bytes.length,
        filename: pending.fileName,
      );
      // Stamp asset id on the local bubble so history merge can match it.
      _stampLocalMediaAssetId(localId, reservation.assetId);
      await _api.uploadMediaBytes(
        uploadUrl: reservation.uploadUrl,
        bytes: bytes,
        contentType: mime,
      );
      await _deliverMessage(
        '',
        parts: [
          {'mediaAssetId': reservation.assetId},
        ],
      );
      await _mergeServerHistory();
      _markLocalAttachmentSent(localId);
    } on FrontFaceApiException catch (e) {
      _markLocalAttachmentFailed(localId);
      if (_isSessionStale(e)) {
        await _recoverStaleSession();
      } else {
        _error = e.message;
      }
    } catch (_) {
      _markLocalAttachmentFailed(localId);
      _error = _strings.attachmentUploadFailed;
    } finally {
      _isSending = false;
      _notify();
    }
  }

  Future<void> _ensureConversationReady() async {
    if (_sessionId != null) return;
    final ensured = await _api.ensureConversation(visitorId: _visitorId!);
    await _applySessionFromResponse(ensured);
  }

  String? _normalizeMime(FrontFacePendingAttachment pending) {
    final raw = (pending.mimeType ?? '').toLowerCase().trim();
    if (pending.kind == FrontFaceAttachmentKind.image) {
      const allowed = {
        'image/jpeg',
        'image/jpg',
        'image/png',
        'image/webp',
        'image/gif',
      };
      if (allowed.contains(raw)) {
        return raw == 'image/jpg' ? 'image/jpeg' : raw;
      }
      final name = (pending.fileName ?? pending.path).toLowerCase();
      if (name.endsWith('.png')) return 'image/png';
      if (name.endsWith('.webp')) return 'image/webp';
      if (name.endsWith('.gif')) return 'image/gif';
      return 'image/jpeg';
    }
    if (pending.kind == FrontFaceAttachmentKind.audio) {
      const allowed = {
        'audio/webm',
        'audio/mp4',
        'audio/mpeg',
        'audio/ogg',
        'audio/wav',
        'audio/x-wav',
        'audio/aac',
        'audio/m4a',
      };
      if (allowed.contains(raw)) {
        if (raw == 'audio/x-wav') return 'audio/wav';
        if (raw == 'audio/aac' || raw == 'audio/m4a') return 'audio/mp4';
        return raw;
      }
      final name = (pending.fileName ?? pending.path).toLowerCase();
      if (name.endsWith('.webm')) return 'audio/webm';
      if (name.endsWith('.m4a') || name.endsWith('.aac') || name.endsWith('.mp4')) {
        return 'audio/mp4';
      }
      if (name.endsWith('.ogg')) return 'audio/ogg';
      if (name.endsWith('.wav')) return 'audio/wav';
      if (name.endsWith('.mp3')) return 'audio/mpeg';
      return 'audio/mp4';
    }
    return null;
  }

  /// Posts [trimmed] and applies the assistant reply / handoff side-effects.
  /// Does not append the customer bubble — callers own that.
  Future<void> _deliverMessage(
    String trimmed, {
    Map<String, dynamic>? location,
    List<Map<String, String>>? parts,
  }) async {
    final response = await _api.sendMessage(
      visitorId: _visitorId!,
      message: trimmed,
      sessionId: _sessionId,
      sessionToken: _sessionToken,
      conversationHistory: _buildConversationHistory(),
      location: location,
      parts: parts,
    );

    await _applySessionFromResponse(response);

    final assistantText = response['response']?.toString() ?? '';
    final ticket = FrontFaceTicketAction.tryParse(
      response['ticket'] as Map<String, dynamic>?,
    );
    if (ticket != null) {
      final skipHandoff = await _handleTicketAction(
        ticket,
        assistantText: assistantText,
        response: response,
      );
      if (skipHandoff) {
        _handoffAvailability = await _api.getHandoffAvailability(_visitorId!);
        return;
      }
    }

    final handoff = response['handoff'] as Map<String, dynamic>?;

    // Provisional bubble for UX — if this triggers handoff, the same text is
    // also stored server-side and would duplicate when polling unless we
    // replace local messages with GET /messages/public (server = source of truth).
    if (assistantText.isNotEmpty) {
      _appendAssistantFromResponse(response, assistantText);
    }

    if (_shouldEnterHandoff(assistantText, handoff)) {
      _applyHandoffFromResponse(handoff);
      await _enterHandoffMode();
    } else {
      _handoffAvailability = await _api.getHandoffAvailability(_visitorId!);
      _evaluateLeadFormAfterSend();
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
        await _applySessionFromResponse(ensured);
      }
      if (_sessionId == null) {
        throw FrontFaceApiException(
          code: 'NO_CONVERSATION',
          message: _strings.couldNotConnectAgent,
        );
      }

      await _triggerHandoff();
    } on FrontFaceApiException catch (e) {
      if (_isSessionStale(e)) {
        await _recoverStaleSession();
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

  Future<void> _triggerHandoff() async {
    final result = await _api.triggerHandoff(
      visitorId: _visitorId!,
      conversationId: _sessionId!,
      sessionToken: _sessionToken,
    );

    final status = result['status']?.toString();
    if (status == 'ticket') {
      final ticket = FrontFaceTicketAction.tryParse(
        result['ticket'] as Map<String, dynamic>?,
      );
      if (ticket != null) {
        await _handleTicketAction(
          ticket,
          assistantText: result['message']?.toString() ?? '',
          response: result,
        );
      }
      return;
    }

    if (status == 'offline' || result['showOfflineForm'] == true) {
      _showOfflineForm = true;
      final offlineMsg = result['message']?.toString();
      if (offlineMsg != null && offlineMsg.isNotEmpty) {
        _appendMessage(
          FrontFaceChatMessage.local(
            content: offlineMsg,
            senderType: FrontFaceSenderType.system,
          ),
        );
      }
      _notify();
      return;
    }

    _applyHandoffResult(result);
    await _enterHandoffMode();
  }

  /// Enter live handoff: merge in the server history, bookmark the newest
  /// `createdAt`, then poll with `?after=`.
  ///
  /// The chat HTTP response and GET /messages/public can both contain the same
  /// handoff confirmation ("I'm connecting you…"). Local bubbles have no
  /// server id, so id-based de-dupe alone can't catch that — but we merge
  /// (never clear) the local transcript, relying on _appendMessage's
  /// sender+content de-dupe to drop the local copy once the server one
  /// arrives.
  ///
  /// Message recovery still uses HTTP polling. Realtime is used for ephemeral
  /// agent typing (and optional status events); presence/typing POSTs go to
  /// the dashboard.
  Future<void> _enterHandoffMode() async {
    try {
      await _mergeServerHistory();
    } catch (_) {
      // Keep provisional local messages; incremental polls may still catch up.
    }
    _updateStatusBanner();
    _startPolling();
    await _startPresenceHeartbeat();
    await _startRealtime();
  }

  /// Composer keystrokes → dashboard typing indicator (agent_active only).
  void onComposerChanged(String _) {
    if (!isAgentActive || !_isAppForeground) return;
    if (_visitorId == null || _sessionId == null) return;

    if (!_customerIsTyping) {
      _customerIsTyping = true;
      unawaited(_postTyping(true));
    }

    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(milliseconds: 1200), () {
      _customerIsTyping = false;
      unawaited(_postTyping(false));
    });
  }

  /// Forces typing:stop — call on send, background, leave handoff, dispose.
  void stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    if (!_customerIsTyping) return;
    _customerIsTyping = false;
    unawaited(_postTyping(false));
  }

  /// Fetches full history (no `?after=`) and merges it into the existing
  /// transcript via `_appendMessage`'s de-dupe — never clears first.
  ///
  /// The GET fires right after a POST that may have just created the
  /// visitor's own message; the server isn't guaranteed to have indexed it
  /// yet (read-after-write lag). Clearing `_messages` and trusting the GET
  /// as complete would silently drop that just-sent message whenever the
  /// fetch beat the server's own write. Merging keeps everything we already
  /// know is real (confirmed by the POST response) while still de-duping
  /// against the server's copy once it shows up.
  Future<void> _mergeServerHistory() async {
    if (_visitorId == null || _sessionId == null) return;

    final messages = await _api.fetchMessages(
      visitorId: _visitorId!,
      conversationId: _sessionId!,
      sessionToken: _sessionToken,
    );

    for (final message in messages) {
      _appendMessage(message);
    }
  }

  Future<void> startNewChat() async {
    await _leaveHandoffSideEffects(sendOffline: true);
    _sessionId = null;
    _sessionToken = null;
    _messages.clear();
    _lastMessageAt = null;
    _status = FrontFaceConversationStatus.aiActive;
    _agentName = null;
    _queuePosition = null;
    _statusBanner = null;
    _error = null;
    _showOfflineForm = false;
    _csatSubmitted = false;
    await _store.saveSessionId(_chatConfig.projectId, null);
    await _store.saveSessionToken(_chatConfig.projectId, null);

    // A new session always starts with lead capture when enabled —
    // no local greeting until submit-form returns assembledGreeting.
    if (_embedConfig.leadCaptureEnabled) {
      _leadFormCompleted = false;
      await _store.setLeadFormCompleted(_chatConfig.projectId, false);
      _showLeadForm = true;
    } else {
      _showLeadForm = false;
      _appendGreetingIfNeeded();
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_lifecycleObserving) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserving = false;
    }
    stopTyping();
    unawaited(_leaveHandoffSideEffects(sendOffline: true));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isAppForeground = true;
        if (isInHandoff) {
          unawaited(_startPresenceHeartbeat());
          unawaited(_startRealtime());
        }
        break;
      case AppLifecycleState.inactive:
        if (isInHandoff) unawaited(_sendPresence('idle'));
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _isAppForeground = false;
        stopTyping();
        _stopPresenceHeartbeat();
        _clearAgentTyping();
        unawaited(_stopRealtime());
        if (isInHandoff) unawaited(_sendPresence('offline'));
        break;
    }
  }

  Future<void> _hydrateConversation() async {
    if (_visitorId == null || _sessionId == null) return;

    // initialize() already cleared `_messages` — append server history directly.
    await _mergeServerHistory();

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
      await _startPresenceHeartbeat();
      await _startRealtime();
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
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final messages = await _api.fetchMessages(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
        after: _lastMessageAt,
      );
      final beforeCount = _messages.length;
      for (final message in messages) {
        if (message.senderType == FrontFaceSenderType.customer) continue;
        _appendMessage(message);
      }
      if (_messages.length != beforeCount) _notify();
    } on FrontFaceApiException catch (e) {
      if (_isSessionStale(e)) {
        await _recoverStaleSession();
        _notify();
      }
    } catch (_) {
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _pollStatus() async {
    try {
      final statusData = await _api.getConversationStatus(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
      );
      final wasAgentActive = isAgentActive;
      _applyStatus(statusData['status']?.toString());
      _agentName = statusData['assignedAgent']?['name']?.toString();
      _queuePosition = statusData['queuePosition'] as int?;
      _updateStatusBanner();

      if (_status == FrontFaceConversationStatus.resolved ||
          _status == FrontFaceConversationStatus.closed) {
        await _leaveHandoffSideEffects(sendOffline: true);
      } else if (wasAgentActive && !isAgentActive) {
        stopTyping();
        _clearAgentTyping();
      }
      _notify();
    } on FrontFaceApiException catch (e) {
      if (_isSessionStale(e)) {
        await _recoverStaleSession();
        _notify();
      }
    } catch (_) {}
  }

  /// Codes that mean the stored `sessionToken` is no longer valid.
  /// Expired and tampered tokens both land here — there is no renew API.
  static const _sessionStaleCodes = {
    'SESSION_INVALID',
    'SESSION_PROJECT_MISMATCH',
    'SESSION_VISITOR_MISMATCH',
    'SESSION_CONVERSATION_MISMATCH',
  };

  bool _isSessionStale(Object error) =>
      error is FrontFaceApiException &&
      _sessionStaleCodes.contains(error.code);

  /// Handles a 403 SESSION_* by starting a fresh session flow:
  /// clear the chat, drop the stale token, and (when lead capture is
  /// enabled) show the lead form again. The session and chatbot greeting
  /// are created only when the form is submitted (`assembledGreeting`).
  ///
  /// No user-facing "session expired" error is shown.
  Future<void> _recoverStaleSession() async {
    await _leaveHandoffSideEffects(sendOffline: false);
    _sessionId = null;
    _sessionToken = null;
    _messages.clear();
    _lastMessageAt = null;
    _status = FrontFaceConversationStatus.aiActive;
    _agentName = null;
    _queuePosition = null;
    _statusBanner = null;
    _error = null;
    await _store.saveSessionId(_chatConfig.projectId, null);
    await _store.saveSessionToken(_chatConfig.projectId, null);

    if (_embedConfig.leadCaptureEnabled) {
      _leadFormCompleted = false;
      await _store.setLeadFormCompleted(_chatConfig.projectId, false);
      _showLeadForm = true;
    } else {
      _showLeadForm = false;
      _appendGreetingIfNeeded();
    }
  }

  Future<void> _applySessionFromResponse(Map<String, dynamic> response) async {
    final newSessionId =
        response['sessionId']?.toString() ??
        response['conversationId']?.toString();
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
    if (!_embedConfig.leadCaptureEnabled) return false;

    // Default Mobile UX: lead form is the first step of creating a session.
    // Once lead capture is completed for this visitor, skip the form even if
    // the local sessionId was lost — history is recovered via
    // ensure-conversation (keyed to visitorId).
    if (_chatConfig.requireLeadCaptureBeforeChat) {
      if (_leadFormCompleted) return false;
      return true;
    }

    if (_leadFormCompleted) return false;
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
    // system note doesn't suppress the greeting that should follow it.
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

  void _appendAssistantFromResponse(
    Map<String, dynamic> response,
    String assistantText,
  ) {
    final am = response['assistantMessage'];
    if (am is Map<String, dynamic>) {
      final merged = Map<String, dynamic>.from(am);
      merged['content'] = assistantText;
      merged['senderType'] ??= 'ai';
      _appendMessage(FrontFaceChatMessage.fromJson(merged));
      return;
    }
    _appendMessage(
      FrontFaceChatMessage.local(
        content: assistantText,
        senderType: FrontFaceSenderType.ai,
      ),
    );
  }

  /// Returns `true` when handoff must be skipped for this response.
  Future<bool> _handleTicketAction(
    FrontFaceTicketAction ticket, {
    required String assistantText,
    Map<String, dynamic>? response,
  }) async {
    switch (ticket.status) {
      case FrontFaceTicketStatus.created:
      case FrontFaceTicketStatus.existingTicketReused:
        if (assistantText.isNotEmpty) {
          final am = response?['assistantMessage'];
          if (am is Map<String, dynamic>) {
            final merged = Map<String, dynamic>.from(am);
            merged['content'] = assistantText;
            merged['senderType'] ??= 'ai';
            merged['metadata'] = {
              ...?merged['metadata'] as Map<String, dynamic>?,
              ...ticket.toMessageMetadata().raw,
            };
            _appendMessage(FrontFaceChatMessage.fromJson(merged));
          } else {
            _appendMessage(
              FrontFaceChatMessage.local(
                content: assistantText,
                senderType: FrontFaceSenderType.ai,
                metadata: ticket.toMessageMetadata(),
              ),
            );
          }
        } else if (ticket.reference != null) {
          _appendMessage(
            FrontFaceChatMessage.local(
              content: ticket.subject ?? ticket.reference!,
              senderType: FrontFaceSenderType.ai,
              metadata: ticket.toMessageMetadata(),
            ),
          );
        }
        return true;
      case FrontFaceTicketStatus.contactRequired:
        if (assistantText.isNotEmpty) {
          _appendAssistantFromResponse(response ?? {}, assistantText);
        }
        return true;
      case FrontFaceTicketStatus.failed:
        _error = ticket.message ?? _strings.ticketFailed;
        if (assistantText.isNotEmpty) {
          _appendAssistantFromResponse(response ?? {}, assistantText);
        }
        return true;
    }
  }

  void _appendMessage(FrontFaceChatMessage message) {
    if (_messages.any((m) => m.id == message.id)) return;

    final content = message.content.trim();
    final isLocal = message.id.startsWith('local_');

    if (!isLocal) {
      // Server copy of a provisional HTTP bubble (local_* id) — drop the
      // local one so bot / handoff confirmations don't appear twice.
      _messages.removeWhere(
        (m) =>
            m.id.startsWith('local_') &&
            m.senderType == message.senderType &&
            m.content.trim() == content &&
            content.isNotEmpty,
      );

      // Location / media: replace the matching local provisional **in place**
      // so list order stays stable (user bubble stays above the agent reply).
      if (message.hasParts) {
        final idx = _messages.lastIndexWhere(
          (m) =>
              m.id.startsWith('local_') &&
              m.senderType == message.senderType &&
              m.hasParts &&
              _attachmentPartsOverlap(m.parts, message.parts),
        );
        if (idx >= 0) {
          final local = _messages[idx];
          final mergedParts =
              _mergePartsPreferLocal(local.parts, message.parts);
          // Never promote to a blank bubble — if the server part can't be
          // rendered yet, keep the local attachment the user already saw.
          final promoted = FrontFaceChatMessage(
            id: message.id,
            content:
                message.content.isNotEmpty ? message.content : local.content,
            senderType: message.senderType,
            senderName: message.senderName ?? local.senderName,
            createdAt: local.createdAt,
            metadata: _mergeAttachmentMetadata(local.metadata, message.metadata),
            parts: mergedParts,
          );
          final parts = (promoted.attachment == null && local.attachment != null)
              ? local.parts
              : mergedParts;
          _messages[idx] = FrontFaceChatMessage(
            id: promoted.id,
            content: promoted.content,
            senderType: promoted.senderType,
            senderName: promoted.senderName,
            createdAt: promoted.createdAt,
            metadata: promoted.metadata,
            parts: parts,
          );
          _lastMessageAt = _messages.isEmpty
              ? null
              : _messages.last.createdAt.toUtc().toIso8601String();
          return;
        }
      }
    }

    // Same sender + text already shown (server id, earlier local, or a
    // second poll of the same payload with a different id) — skip.
    if (content.isNotEmpty &&
        _messages.any(
          (m) =>
              m.senderType == message.senderType &&
              m.content.trim() == content,
        )) {
      return;
    }

    // Same attachment parts already shown (empty-content location/media).
    if (message.hasParts &&
        _messages.any(
          (m) =>
              m.senderType == message.senderType &&
              m.hasParts &&
              _attachmentPartsOverlap(m.parts, message.parts),
        )) {
      return;
    }

    _messages.add(message);
    _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // Bookmark must be the newest message after sort — not the one just
    // appended — so handoff polling `?after=` doesn't skip or re-fetch.
    _lastMessageAt = _messages.isEmpty
        ? null
        : _messages.last.createdAt.toUtc().toIso8601String();
  }

  /// Keep a local file path / location pin as fallback display when the
  /// server part is incomplete — avoids a blank flicker on promote.
  List<FrontFaceMessagePart> _mergePartsPreferLocal(
    List<FrontFaceMessagePart> local,
    List<FrontFaceMessagePart> server,
  ) {
    if (server.isEmpty) return local;
    if (local.isEmpty) return server;
    return server.map((part) {
      FrontFaceMessagePart? match;
      for (final l in local) {
        if (l.type == part.type) {
          match = l;
          break;
        }
      }
      if (match == null) return part;

      if (part.type == FrontFaceMessagePartType.location) {
        final lat = part.latitude ?? match.latitude;
        final lng = part.longitude ?? match.longitude;
        if (lat == null || lng == null) return match;
        return FrontFaceMessagePart(
          id: part.id ?? match.id,
          type: part.type,
          processingStatus: part.processingStatus ?? match.processingStatus,
          position: part.position ?? match.position,
          mediaAssetId: part.mediaAssetId ?? match.mediaAssetId,
          url: part.url ?? match.url,
          derivedText: part.derivedText ?? match.derivedText,
          payload: {
            ...match.payload,
            ...part.payload,
            'latitude': lat,
            'longitude': lng,
            if ((part.label ?? match.label) != null)
              'label': part.label ?? match.label,
          },
        );
      }

      final localPath = match.localPath;
      if (localPath == null || localPath.isEmpty) return part;
      final serverUrl = part.url;
      final hasRemote = serverUrl != null &&
          (serverUrl.startsWith('http://') || serverUrl.startsWith('https://'));
      if (hasRemote) {
        return FrontFaceMessagePart(
          id: part.id,
          type: part.type,
          processingStatus: part.processingStatus,
          position: part.position,
          mediaAssetId: part.mediaAssetId ?? match.mediaAssetId,
          url: serverUrl,
          derivedText: part.derivedText ?? match.derivedText,
          payload: {
            ...part.payload,
            'local_path': localPath,
          },
        );
      }
      return FrontFaceMessagePart(
        id: part.id,
        type: part.type,
        processingStatus: part.processingStatus,
        position: part.position,
        mediaAssetId: part.mediaAssetId ?? match.mediaAssetId,
        url: serverUrl ?? localPath,
        derivedText: part.derivedText ?? match.derivedText,
        payload: {
          ...part.payload,
          'local_path': localPath,
        },
      );
    }).toList();
  }

  /// Prefer server metadata, but keep local attachment fields (coords / url)
  /// when the server omits them — and drop the uploading flag.
  FrontFaceMessageMetadata _mergeAttachmentMetadata(
    FrontFaceMessageMetadata local,
    FrontFaceMessageMetadata server,
  ) {
    final merged = Map<String, dynamic>.from(local.raw);
    for (final entry in server.raw.entries) {
      merged[entry.key] = entry.value;
    }
    final localAtt = local.raw['attachment'];
    final serverAtt = server.raw['attachment'];
    if (localAtt is Map || serverAtt is Map) {
      final att = <String, dynamic>{
        if (localAtt is Map) ...Map<String, dynamic>.from(localAtt),
        if (serverAtt is Map) ...Map<String, dynamic>.from(serverAtt),
      };
      att.remove('upload_status');
      if (att.isNotEmpty) {
        merged['attachment'] = att;
      } else {
        merged.remove('attachment');
      }
    }
    return FrontFaceMessageMetadata(merged);
  }

  /// True when both sides share a location pin (approx) or the same media asset.
  bool _attachmentPartsOverlap(
    List<FrontFaceMessagePart> a,
    List<FrontFaceMessagePart> b,
  ) {
    for (final left in a) {
      for (final right in b) {
        if (left.type != right.type) continue;
        switch (left.type) {
          case FrontFaceMessagePartType.location:
            final latL = left.latitude;
            final lngL = left.longitude;
            final latR = right.latitude;
            final lngR = right.longitude;
            if (latL != null &&
                lngL != null &&
                latR != null &&
                lngR != null &&
                (latL - latR).abs() < 0.00015 &&
                (lngL - lngR).abs() < 0.00015) {
              return true;
            }
            // Incomplete server location (missing coords) while a single local
            // location is uploading — still pair so we don't drop the bubble.
            if (_hasSingleUploadingProvisionalOfType(
                  FrontFaceMessagePartType.location,
                ) &&
                ((latL == null || lngL == null) ||
                    (latR == null || lngR == null))) {
              return true;
            }
          case FrontFaceMessagePartType.image:
          case FrontFaceMessagePartType.audio:
            if (left.mediaAssetId != null &&
                left.mediaAssetId == right.mediaAssetId) {
              return true;
            }
            final urlL = left.url;
            final urlR = right.url;
            if (urlL != null &&
                urlR != null &&
                urlL.isNotEmpty &&
                urlL == urlR) {
              return true;
            }
            // Newest uploading provisional of this kind ↔ server part of the
            // same kind (only while a single upload is in flight).
            if (_isProvisionalMedia(left) != _isProvisionalMedia(right) &&
                _hasSingleUploadingProvisionalOfType(left.type)) {
              return true;
            }
        }
      }
    }
    return false;
  }

  /// Restricts provisional↔server media matching so older history cannot
  /// steal the in-flight local bubble.
  bool _hasSingleUploadingProvisionalOfType(FrontFaceMessagePartType type) {
    var count = 0;
    for (final m in _messages) {
      if (!m.id.startsWith('local_')) continue;
      if (!m.isAttachmentUploading) continue;
      if (m.parts.any((p) => p.type == type && _isProvisionalMedia(p))) {
        count++;
        if (count > 1) return false;
      }
    }
    return count == 1;
  }

  bool _isProvisionalMedia(FrontFaceMessagePart part) {
    if (part.localPath != null && part.localPath!.isNotEmpty) return true;
    final url = part.url;
    if (url == null || url.isEmpty) return part.mediaAssetId == null;
    return !url.startsWith('http://') && !url.startsWith('https://');
  }

  void _stampLocalMediaAssetId(String localId, String assetId) {
    final idx = _messages.indexWhere((m) => m.id == localId);
    if (idx < 0) return;
    final local = _messages[idx];
    final parts = local.parts.map((p) {
      if (p.type != FrontFaceMessagePartType.image &&
          p.type != FrontFaceMessagePartType.audio) {
        return p;
      }
      return FrontFaceMessagePart(
        id: p.id,
        type: p.type,
        processingStatus: p.processingStatus,
        position: p.position,
        mediaAssetId: assetId,
        url: p.url,
        derivedText: p.derivedText,
        payload: p.payload,
      );
    }).toList();
    _messages[idx] = FrontFaceChatMessage(
      id: local.id,
      content: local.content,
      senderType: local.senderType,
      senderName: local.senderName,
      createdAt: local.createdAt,
      metadata: local.metadata,
      parts: parts,
    );
  }

  void _markLocalAttachmentSent(String localId) {
    _patchLocalAttachmentStatus(
      localId,
      FrontFaceAttachmentUploadStatus.sent,
    );
  }

  void _markLocalAttachmentFailed(String localId) {
    _patchLocalAttachmentStatus(
      localId,
      FrontFaceAttachmentUploadStatus.failed,
    );
  }

  void _patchLocalAttachmentStatus(
    String localId,
    FrontFaceAttachmentUploadStatus status,
  ) {
    final idx = _messages.indexWhere((m) => m.id == localId);
    if (idx < 0) {
      // Already promoted to a server id — patch newest customer attachment.
      final fallback = _messages.lastIndexWhere(
        (m) =>
            m.senderType == FrontFaceSenderType.customer &&
            m.hasParts &&
            (m.isAttachmentUploading ||
                m.attachment?.uploadStatus ==
                    FrontFaceAttachmentUploadStatus.failed),
      );
      if (fallback < 0) return;
      _patchAttachmentStatusAt(fallback, status);
      return;
    }
    _patchAttachmentStatusAt(idx, status);
  }

  void _patchAttachmentStatusAt(
    int idx,
    FrontFaceAttachmentUploadStatus status,
  ) {
    final local = _messages[idx];
    final raw = Map<String, dynamic>.from(local.metadata.raw);
    final attachment = Map<String, dynamic>.from(
      (raw['attachment'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    if (status == FrontFaceAttachmentUploadStatus.sent) {
      attachment.remove('upload_status');
    } else {
      attachment['upload_status'] = status.name;
    }
    if (attachment.isNotEmpty) {
      raw['attachment'] = attachment;
    } else {
      raw.remove('attachment');
    }
    _messages[idx] = FrontFaceChatMessage(
      id: local.id,
      content: local.content,
      senderType: local.senderType,
      senderName: local.senderName,
      createdAt: local.createdAt,
      metadata: FrontFaceMessageMetadata(raw),
      parts: local.parts,
    );
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

  void _ensureLifecycleObserver() {
    if (_lifecycleObserving) return;
    // WidgetsBinding may be unavailable in pure Dart unit tests.
    try {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleObserving = true;
      final lifecycle = SchedulerBinding.instance.lifecycleState;
      _isAppForeground = lifecycle == null ||
          lifecycle == AppLifecycleState.resumed;
    } catch (_) {
      _isAppForeground = true;
    }
  }

  Future<void> _leaveHandoffSideEffects({required bool sendOffline}) async {
    stopTyping();
    _stopPresenceHeartbeat();
    _clearAgentTyping();
    _stopPolling();
    await _stopRealtime();
    if (sendOffline && _visitorId != null && _sessionId != null) {
      await _sendPresence('offline');
    }
  }

  Future<void> _postTyping(bool isTyping) async {
    if (_visitorId == null || _sessionId == null) return;
    try {
      await _api.sendTyping(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
        isTyping: isTyping,
      );
    } catch (_) {}
  }

  Future<void> _sendPresence(String status) async {
    if (_visitorId == null || _sessionId == null) return;
    try {
      await _api.sendPresence(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
        status: status,
      );
    } catch (_) {}
  }

  Future<void> _startPresenceHeartbeat() async {
    if (!isInHandoff || !_isAppForeground) return;
    _stopPresenceHeartbeat();
    await _sendPresence('online');
    _presenceHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_disposed || !isInHandoff || !_isAppForeground) return;
        unawaited(_sendPresence('online'));
      },
    );
  }

  void _stopPresenceHeartbeat() {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = null;
  }

  Future<void> _startRealtime() async {
    if (_disposed || !isInHandoff) return;
    if (!_embedConfig.realtime.canConnect) return;
    if (_visitorId == null || _sessionId == null) return;

    try {
      final tokenRes = await _api.fetchRealtimeToken(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
      );
      final jwt = tokenRes['token']?.toString() ?? '';
      if (jwt.isEmpty) {
        _clearAgentTyping();
        return;
      }

      final ok = await _realtime.connect(
        supabaseUrl: _embedConfig.realtime.supabaseUrl,
        apiKey: _embedConfig.realtime.apiKey,
        jwt: jwt,
        conversationId: _sessionId!,
        onEvent: _onRealtimeEvent,
        onDisconnected: () {
          _clearAgentTyping();
          _notify();
        },
      );

      if (!ok) {
        _clearAgentTyping();
        return;
      }

      _scheduleRealtimeTokenRefresh(tokenRes['expiresAt']);
    } catch (_) {
      _clearAgentTyping();
    }
  }

  void _scheduleRealtimeTokenRefresh(Object? expiresAtRaw) {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;

    int? expiresAt;
    if (expiresAtRaw is int) {
      expiresAt = expiresAtRaw;
    } else if (expiresAtRaw is num) {
      expiresAt = expiresAtRaw.toInt();
    } else if (expiresAtRaw != null) {
      expiresAt = int.tryParse(expiresAtRaw.toString());
    }
    if (expiresAt == null) return;

    // expiresAt is unix seconds from the API.
    final refreshAt = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
        .subtract(const Duration(seconds: 60));
    final delay = refreshAt.difference(DateTime.now());
    if (delay.isNegative) {
      unawaited(_refreshRealtimeToken());
      return;
    }
    _realtimeRefreshTimer = Timer(delay, () {
      unawaited(_refreshRealtimeToken());
    });
  }

  Future<void> _refreshRealtimeToken() async {
    if (_disposed || !isInHandoff) return;
    if (_visitorId == null || _sessionId == null) return;
    try {
      final tokenRes = await _api.fetchRealtimeToken(
        visitorId: _visitorId!,
        conversationId: _sessionId!,
        sessionToken: _sessionToken,
      );
      final jwt = tokenRes['token']?.toString() ?? '';
      if (jwt.isEmpty) {
        await _stopRealtime();
        _clearAgentTyping();
        return;
      }
      await _realtime.refreshAuth(jwt);
      _scheduleRealtimeTokenRefresh(tokenRes['expiresAt']);
    } catch (_) {
      await _stopRealtime();
      _clearAgentTyping();
      _notify();
    }
  }

  Future<void> _stopRealtime() async {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    await _realtime.disconnect();
  }

  void _onRealtimeEvent(String event, Map<String, dynamic> payload) {
    if (_disposed) return;
    final data = _extractRealtimeData(payload);

    if (event == 'typing:start' || event == 'typing:stop') {
      final participant = data?['participant'];
      final type = participant is Map
          ? participant['type']?.toString()
          : null;
      if (type != 'agent') return;

      if (event == 'typing:start') {
        _agentTyping = true;
        final name = participant is Map
            ? participant['name']?.toString()
            : null;
        if (name != null && name.isNotEmpty) _agentName = name;
      } else {
        _agentTyping = false;
      }
      _notify();
      return;
    }

    if (event == 'message:new') {
      final messageJson = data?['message'];
      if (messageJson is! Map) return;
      final message = FrontFaceChatMessage.fromJson(
        Map<String, dynamic>.from(messageJson),
      );
      if (message.senderType == FrontFaceSenderType.customer) return;
      // Fresh agent message implies they stopped typing.
      _agentTyping = false;
      _appendMessage(message);
      _notify();
      return;
    }

    if (event == 'conversation:status_changed') {
      final status = data?['status']?.toString();
      final queue = data?['queuePosition'];
      if (queue is int) _queuePosition = queue;
      _applyStatus(status);
      if (!isInHandoff) {
        unawaited(_leaveHandoffSideEffects(sendOffline: true));
      } else if (!isAgentActive) {
        stopTyping();
        _clearAgentTyping();
      }
      _updateStatusBanner();
      _notify();
      return;
    }

    if (event == 'conversation:assigned') {
      final agent = data?['agent'];
      if (agent is Map) {
        final name = agent['name']?.toString();
        if (name != null && name.isNotEmpty) _agentName = name;
      }
      _status = FrontFaceConversationStatus.agentActive;
      _updateStatusBanner();
      _notify();
      return;
    }

    if (event == 'queue:position_updated') {
      final position = data?['position'];
      if (position is int) {
        _queuePosition = position;
        _updateStatusBanner();
        _notify();
      }
      return;
    }

    if (event == 'conversation:resolved') {
      final resolution = data?['resolution']?.toString();
      if (resolution == 'ai_active') {
        _status = FrontFaceConversationStatus.aiActive;
      } else {
        _status = FrontFaceConversationStatus.resolved;
      }
      unawaited(_leaveHandoffSideEffects(sendOffline: true));
      _updateStatusBanner();
      _notify();
    }
  }

  Map<String, dynamic>? _extractRealtimeData(Map<String, dynamic> payload) {
    final nested = payload['payload'];
    if (nested is Map) {
      final data = nested['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(nested);
    }
    final data = payload['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  void _clearAgentTyping() {
    if (!_agentTyping) return;
    _agentTyping = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
