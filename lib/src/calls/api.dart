import 'dart:async';

import 'package:http/http.dart' as http;

import 'http_json.dart';
import 'models.dart';
import 'transport.dart';

/// This package's version, sent when a phone registers for calls from support.
const packageVersion = '1.7.2';

/// The answer to `POST …/calls`: the call, and where and how to join its audio.
class StartedCall {
  const StartedCall({
    required this.callId,
    required this.status,
    required this.queuePosition,
    required this.mediaUrl,
    required this.mediaToken,
    required this.created,
    this.agentName,
  });

  final String callId;

  /// `ringing` or `active` (an open call being rejoined).
  final String status;
  final int? queuePosition;
  final String mediaUrl;

  /// Valid for the first connect only (90 s). Never reuse it: ask `POST …/calls` again.
  final String mediaToken;

  /// 201: a new call. 200: the customer's call that was already open.
  final bool created;

  /// For a call from support: the agent who called (they are already in the call).
  final String? agentName;
}

/// What the server answered to a phone's registration for calls from support.
class RegisteredDevice {
  const RegisteredDevice({required this.id, required this.secret});
  final String id;

  /// Only for a new registration (201). Null when the phone re-registered with its credential (200):
  /// the secret it holds stays valid.
  final String? secret;
}

/// The four call endpoints of the FrontFace app API. One instance per conversation and session.
class CallsApi implements CallTransport {
  CallsApi({
    required this.baseUrl,
    required this.clientKey,
    required this.visitorId,
    required this.conversationId,
    required this.sessionToken,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.platform,
    this.appVersion,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String clientKey;
  final String visitorId;
  final String conversationId;
  final String sessionToken;
  final Duration timeout;

  /// Sent with each start (and rejoin), so problems can be matched to a platform and app release.
  final String? platform;
  final String? appVersion;
  final http.Client _http;

  String get _base =>
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/widget/conversations/'
      '${Uri.encodeComponent(conversationId)}/calls';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-FrontFace-Key': clientKey,
        'X-Visitor-Id': visitorId,
        'X-FrontFace-Session': sessionToken,
      };

  /// Version 2: start/end refusals can carry an open inbound call id.
  Map<String, String> get _headersV2 => {
        ..._headers,
        'X-FrontFace-Calls-Version': '2',
      };

  Future<CallAvailability> availability() async {
    // Same headers as 1.6.2 — Calls-Version is only needed for start/end.
    final json = await _send('GET', '$_base/availability');
    if (json['available'] == true) return const CallAvailability.available();
    return CallAvailability.unavailable(
      CallUnavailableReason.parse(json['reason'] as String?),
    );
  }

  /// Starts a call, or returns the customer's open call with a fresh token to rejoin it.
  Future<StartedCall> start({String? platform, String? appVersion}) async {
    final body = <String, dynamic>{
      if ((platform ?? this.platform) != null) 'platform': platform ?? this.platform,
      if ((appVersion ?? this.appVersion) != null) 'appVersion': appVersion ?? this.appVersion,
    };
    late int status;
    final json = await _send(
      'POST',
      _base,
      body: body,
      onStatus: (s) => status = s,
      headers: _headersV2,
    );
    final call = json['call'] as Map<String, dynamic>;
    final media = json['media'] as Map<String, dynamic>;
    return StartedCall(
      callId: call['id'] as String,
      status: call['status'] as String,
      queuePosition: (call['queuePosition'] as num?)?.toInt(),
      mediaUrl: media['url'] as String,
      mediaToken: media['token'] as String,
      created: status == 201,
    );
  }

  @override
  Future<CallResult> get(String callId) async {
    final json = await _send(
      'GET',
      '$_base/${Uri.encodeComponent(callId)}',
      headers: _headersV2,
    );
    return CallResult.fromJson(json['call'] as Map<String, dynamic>);
  }

  @override
  Future<CallResult> end(String callId, {bool connectFailed = false}) async {
    final json = await _send(
      'POST',
      '$_base/${Uri.encodeComponent(callId)}/end',
      body: {if (connectFailed) 'reason': 'connect_failed'},
      headers: _headersV2,
    );
    return CallResult.fromJson(json['call'] as Map<String, dynamic>);
  }

  /// A rejoin asks `POST …/calls` again: it returns the customer's open call with a fresh token. If that
  /// call ended in between, the request started a new call that nobody asked for: end it.
  @override
  Future<RejoinResult> rejoin(String callId) async {
    final again = await start();
    if (again.callId == callId) return Rejoin(again);
    try {
      await end(again.callId);
    } catch (_) {}
    return const CallGone();
  }

  /// Registers this phone for calls from support (`POST …/calls/devices`). [credential] is the one the
  /// phone already holds, so a re-registration keeps it.
  Future<RegisteredDevice> registerDevice({
    required String platform,
    required String pushToken,
    String? apnsEnvironment,
    String? appVersion,
    String? credential,
  }) async {
    final json = await _send(
      'POST',
      '$_base/devices',
      body: {
        'platform': platform,
        'pushToken': pushToken,
        'packageVersion': packageVersion,
        if (apnsEnvironment != null) 'apnsEnvironment': apnsEnvironment,
        if (appVersion != null) 'appVersion': appVersion,
      },
      extraHeaders: {
        if (credential != null) 'X-FrontFace-Device': credential,
      },
    );
    final device = json['device'] as Map<String, dynamic>;
    return RegisteredDevice(id: device['id'] as String, secret: device['secret'] as String?);
  }

  void close() => _http.close();

  Future<Map<String, dynamic>> _send(
    String method,
    String url, {
    Map<String, dynamic>? body,
    void Function(int status)? onStatus,
    Map<String, String>? headers,
    Map<String, String> extraHeaders = const {},
  }) =>
      sendJson(
        _http,
        method,
        url,
        headers: {...(headers ?? _headers), ...extraHeaders},
        timeout: timeout,
        body: body,
        onStatus: onStatus,
      );
}
