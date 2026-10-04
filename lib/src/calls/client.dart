import 'dart:async';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import 'api.dart';
import 'call_session.dart';
import 'livekit_media.dart';
import 'models.dart';

/// Entry point: check whether the customer can call, and start a call.
///
/// Uses the same credentials as the chat: the project's mobile client key, the install's visitor
/// id, and the `conversationId` + `sessionToken` pair from `ensure-conversation`.
class FrontFaceCalls {
  FrontFaceCalls({
    required this.baseUrl,
    required this.clientKey,
    required this.visitorId,
    this.appVersion,
    this.noiseCancellation = true,
    this.speakerOnAtStart = false,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// `https://api.frontface.app` in production.
  final String baseUrl;
  final String clientKey;
  final String visitorId;

  /// Sent with each call, so problems can be matched to an app release.
  final String? appVersion;

  /// Krisp noise cancellation on the customer's microphone, on iOS and Android only.
  final bool noiseCancellation;

  /// Start on the loudspeaker instead of the earpiece (iOS and Android).
  final bool speakerOnAtStart;

  final http.Client? _httpClient;
  CallSession? _active;

  String? get _platform => Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
          ? 'android'
          : null;

  CallsApi _api(String conversationId, String sessionToken) => CallsApi(
        baseUrl: baseUrl,
        clientKey: clientKey,
        visitorId: visitorId,
        conversationId: conversationId,
        sessionToken: sessionToken,
        httpClient: _httpClient,
      );

  /// Whether to show the Call button. Check when the chat opens (and on resume), not in a loop.
  Future<CallAvailability> availability({
    required String conversationId,
    required String sessionToken,
  }) =>
      _api(conversationId, sessionToken).availability();

  /// Starts a call (or rejoins the customer's open one) and joins its audio.
  ///
  /// Ask for the microphone permission before calling this, so a refused permission never creates
  /// a call. Throws [CallsException] when the server refuses (see [CallsErrorCode]). While a call
  /// is in progress, returns that same session.
  Future<CallSession> startCall({
    required String conversationId,
    required String sessionToken,
  }) async {
    final active = _active;
    if (active != null && !active.isOver) return active;

    final api = _api(conversationId, sessionToken);
    final started = await api.start(platform: _platform, appVersion: appVersion);
    final session = CallSession.internal(
      api: api,
      media: LiveKitMedia(
        noiseCancellation: noiseCancellation,
        speakerOnAtStart: speakerOnAtStart,
      ),
      started: started,
      platform: _platform,
      appVersion: appVersion,
    );
    _active = session;
    unawaited(session.start(started));
    return session;
  }
}
