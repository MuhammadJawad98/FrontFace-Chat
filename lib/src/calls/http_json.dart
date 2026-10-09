import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Sends one JSON request to the FrontFace API and returns the JSON object it answers with. Any other
/// answer becomes a [CallsException]: the API's error code, or [CallsErrorCode.network] when there was
/// no answer in [timeout].
Future<Map<String, dynamic>> sendJson(
  http.Client client,
  String method,
  String url, {
  required Map<String, String> headers,
  required Duration timeout,
  Map<String, dynamic>? body,
  void Function(int status)? onStatus,
}) async {
  final http.Response res;
  try {
    final request = http.Request(method, Uri.parse(url))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    res = await http.Response.fromStream(await client.send(request).timeout(timeout));
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
  if (res.statusCode >= 200 && res.statusCode < 300) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (res.statusCode == 204) return const {};
  }
  final error = decoded is Map ? decoded['error'] : null;
  final call = error is Map ? error['call'] : null;
  throw CallsException(
    status: res.statusCode,
    code: error is Map ? (error['code'] as String? ?? 'HTTP_${res.statusCode}') : 'HTTP_${res.statusCode}',
    message: error is Map ? (error['message'] as String? ?? '') : res.reasonPhrase ?? '',
    retryAfterSeconds: error is Map ? (error['retryAfter'] as num?)?.toInt() : null,
    callId: call is Map ? call['id'] as String? : null,
  );
}
