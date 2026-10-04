import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// The answer to `POST …/calls`: the call, and where and how to join its audio.
class StartedCall {
  const StartedCall({
    required this.callId,
    required this.status,
    required this.queuePosition,
    required this.mediaUrl,
    required this.mediaToken,
    required this.created,
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
}

/// The four call endpoints of the FrontFace app API. One instance per conversation and session.
class CallsApi {
  CallsApi({
    required this.baseUrl,
    required this.clientKey,
    required this.visitorId,
    required this.conversationId,
    required this.sessionToken,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String clientKey;
  final String visitorId;
  final String conversationId;
  final String sessionToken;
  final Duration timeout;
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

  Future<CallAvailability> availability() async {
    final json = await _send('GET', '$_base/availability');
    if (json['available'] == true) return const CallAvailability.available();
    return CallAvailability.unavailable(
      CallUnavailableReason.parse(json['reason'] as String?),
    );
  }

  /// Starts a call, or returns the customer's open call with a fresh token to rejoin it.
  Future<StartedCall> start({String? platform, String? appVersion}) async {
    final body = <String, dynamic>{
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
    };
    late int status;
    final json = await _send('POST', _base, body: body, onStatus: (s) => status = s);
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

  Future<CallResult> get(String callId) async {
    final json = await _send('GET', '$_base/${Uri.encodeComponent(callId)}');
    return CallResult.fromJson(json['call'] as Map<String, dynamic>);
  }

  /// Hangs up ([connectFailed] false) or reports that the audio connection could not be made.
  Future<CallResult> end(String callId, {bool connectFailed = false}) async {
    final json = await _send(
      'POST',
      '$_base/${Uri.encodeComponent(callId)}/end',
      body: {if (connectFailed) 'reason': 'connect_failed'},
    );
    return CallResult.fromJson(json['call'] as Map<String, dynamic>);
  }

  void close() => _http.close();

  Future<Map<String, dynamic>> _send(
    String method,
    String url, {
    Map<String, dynamic>? body,
    void Function(int status)? onStatus,
  }) async {
    final http.Response res;
    try {
      final request = http.Request(method, Uri.parse(url))..headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw const CallsException(
          status: 0, code: CallsErrorCode.network, message: 'The request timed out');
    } catch (e) {
      throw CallsException(status: 0, code: CallsErrorCode.network, message: '$e');
    }
    onStatus?.call(res.statusCode);
    Object? decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      decoded = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300 && decoded is Map<String, dynamic>) {
      return decoded;
    }
    final error = decoded is Map ? decoded['error'] : null;
    throw CallsException(
      status: res.statusCode,
      code: error is Map ? (error['code'] as String? ?? 'HTTP_${res.statusCode}') : 'HTTP_${res.statusCode}',
      message: error is Map ? (error['message'] as String? ?? '') : res.reasonPhrase ?? '',
      retryAfterSeconds: error is Map ? (error['retryAfter'] as num?)?.toInt() : null,
    );
  }
}
