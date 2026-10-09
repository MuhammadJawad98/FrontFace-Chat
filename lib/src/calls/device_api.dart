import 'dart:async';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'http_json.dart';
import 'models.dart';
import 'transport.dart';

/// The endpoints a registered phone uses for calls from support (`/api/widget/calls`). They need the
/// project's mobile client key and the phone's credential, not a chat session: a push can wake the app
/// long after its chat session expired.
class DeviceApi implements CallTransport {
  DeviceApi({
    required this.baseUrl,
    required this.clientKey,
    required this.credential,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.onInvalid,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String clientKey;

  /// `<deviceId>.<secret>`, from the registration.
  final String credential;
  final Duration timeout;

  /// Called when the server no longer knows this phone's credential (signed out elsewhere, replaced).
  final void Function()? onInvalid;
  final http.Client _http;

  /// The longest the state request is held open by the server, and how long to wait for it.
  static const stateWaitSeconds = 25;
  static const stateTimeout = Duration(seconds: stateWaitSeconds + 10);

  String get deviceId => credential.split('.').first;

  String get _base => '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/widget/calls';
  String _call(String callId, [String rest = '']) => '$_base/${Uri.encodeComponent(callId)}$rest';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-FrontFace-Key': clientKey,
        'X-FrontFace-Device': credential,
      };

  @override
  Future<CallResult> get(String callId) async => _result(await _send('GET', _call(callId)));

  /// The call as soon as it changes, or after [stateWaitSeconds] if it did not (a long poll).
  Future<CallResult> state(String callId) async => _result(await _send(
        'GET',
        _call(callId, '/state?wait=$stateWaitSeconds'),
        timeout: stateTimeout,
      ));

  /// Answers the call (again after a lost connection: a rejoin) and returns where to join its audio.
  Future<StartedCall> answer(String callId) async {
    final json = await _send('POST', _call(callId, '/answer'), body: const {});
    final call = json['call'] as Map<String, dynamic>;
    final media = json['media'] as Map<String, dynamic>;
    final agent = call['agent'];
    return StartedCall(
      callId: call['id'] as String,
      status: call['status'] as String,
      queuePosition: null,
      mediaUrl: media['url'] as String,
      mediaToken: media['token'] as String,
      created: false,
      agentName: agent is Map ? agent['name'] as String? : null,
    );
  }

  Future<CallResult> decline(String callId) async =>
      _result(await _send('POST', _call(callId, '/decline'), body: const {}));

  @override
  Future<CallResult> end(String callId, {bool connectFailed = false}) async => _result(await _send(
        'POST',
        _call(callId, '/end'),
        body: {if (connectFailed) 'reason': 'connect_failed'},
      ));

  /// Answering again gives a fresh token for the same call. A call that is over, or a phone whose
  /// registration is gone, has nothing to join.
  @override
  Future<RejoinResult> rejoin(String callId) async {
    try {
      return Rejoin(await answer(callId));
    } on CallsException catch (e) {
      if (e.status == 401 || e.status == 404 || e.status == 409) return const CallGone();
      rethrow;
    }
  }

  /// This phone signs out: it stops ringing for the customer.
  Future<void> unregister() => _send('DELETE', '$_base/devices/${Uri.encodeComponent(deviceId)}');

  void close() => _http.close();

  CallResult _result(Map<String, dynamic> json) =>
      CallResult.fromJson(json['call'] as Map<String, dynamic>);

  Future<Map<String, dynamic>> _send(
    String method,
    String url, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    try {
      return await sendJson(_http, method, url,
          headers: _headers, timeout: timeout ?? this.timeout, body: body);
    } on CallsException catch (e) {
      if (e.status == 401 && e.code == CallsErrorCode.deviceInvalid) onInvalid?.call();
      rethrow;
    }
  }
}
