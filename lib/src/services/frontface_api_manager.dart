import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/frontface_chat_config.dart';
import '../models/frontface_models.dart';

class FrontFaceApiManager {
  FrontFaceApiManager(this.config);

  final FrontFaceChatConfig config;

  /// Never logs in release/profile builds — even if [FrontFaceChatConfig.debugLogging]
  /// is accidentally left `true` in production.
  bool get _canLog => kDebugMode && config.debugLogging;

  Map<String, String> _headers(String visitorId, {String? sessionToken}) => {
        'Content-Type': 'application/json',
        'X-FrontFace-Key': config.publishableKey,
        'X-Visitor-Id': visitorId,
        if (sessionToken != null && sessionToken.isNotEmpty)
          'X-FrontFace-Session': sessionToken,
      };

  String _url(String path) => '${config.baseUrl}$path';

  Future<Map<String, dynamic>> get(
    String path, {
    required String visitorId,
    String? sessionToken,
  }) async {
    final url = _url(path);
    final headers = _headers(visitorId, sessionToken: sessionToken);
    _logCurl('GET', url, headers);

    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      _log('GET (${response.statusCode}): ${response.body}');
      return _parseResponse(response);
    } on FrontFaceApiException {
      rethrow;
    } on SocketException {
      throw const FrontFaceApiException(
        code: 'NETWORK_ERROR',
        message:
            "You're offline. Check your internet connection and try again.",
      );
    } catch (_) {
      throw const FrontFaceApiException(
        code: 'UNKNOWN_ERROR',
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    required String visitorId,
    String? sessionToken,
    Map<String, dynamic>? body,
    bool throwOnError = true,
  }) async {
    final url = _url(path);
    final headers = _headers(visitorId, sessionToken: sessionToken);
    _logCurl('POST', url, headers, body: body);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      _log('POST (${response.statusCode}): ${response.body}');
      return _parseResponse(response, throwOnError: throwOnError);
    } on FrontFaceApiException {
      rethrow;
    } on SocketException {
      if (!throwOnError) return {};
      throw const FrontFaceApiException(
        code: 'NETWORK_ERROR',
        message:
            "You're offline. Check your internet connection and try again.",
      );
    } catch (_) {
      if (!throwOnError) return {};
      throw const FrontFaceApiException(
        code: 'UNKNOWN_ERROR',
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  /// PUT raw bytes to a signed upload URL (no FrontFace auth headers).
  Future<void> putBytes(
    String uploadUrl, {
    required List<int> bytes,
    required String contentType,
  }) async {
    // Never log the signed upload URL (contains tokens in query string).
    _log('PUT (${bytes.length} bytes, $contentType)');
    try {
      final response = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': contentType},
        body: bytes,
      );
      _log('PUT (${response.statusCode})');
      if (response.statusCode >= 400) {
        throw FrontFaceApiException(
          code: 'UPLOAD_FAILED',
          message: 'Media upload failed (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } on FrontFaceApiException {
      rethrow;
    } on SocketException {
      throw const FrontFaceApiException(
        code: 'NETWORK_ERROR',
        message:
            "You're offline. Check your internet connection and try again.",
      );
    } catch (e) {
      if (e is FrontFaceApiException) rethrow;
      throw const FrontFaceApiException(
        code: 'UNKNOWN_ERROR',
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  Map<String, dynamic> _parseResponse(
    http.Response response, {
    bool throwOnError = true,
  }) {
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    }

    if (response.statusCode >= 400) {
      if (!throwOnError) return data;
      final error = data['error'] as Map<String, dynamic>? ?? {};
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
      throw FrontFaceApiException(
        code: error['code']?.toString() ?? 'UNKNOWN_ERROR',
        message: error['message']?.toString() ?? 'Something went wrong.',
        statusCode: response.statusCode,
        retryAfter: retryAfter,
      );
    }
    return data;
  }

  void _log(String message) {
    if (!_canLog) return;
    debugPrint('[FrontFace] $message');
  }

  void _logCurl(
    String method,
    String url,
    Map<String, String> headers, {
    Map<String, dynamic>? body,
  }) {
    if (!_canLog) return;
    // Redact secrets so even debug console dumps aren't copy-pasteable credentials.
    final safeHeaders = headers.map((key, value) {
      final lower = key.toLowerCase();
      if (lower.contains('key') ||
          lower.contains('session') ||
          lower.contains('authorization') ||
          lower.contains('token')) {
        return MapEntry(key, '***');
      }
      return MapEntry(key, value);
    });
    final headerStrings = safeHeaders.entries
        .map((e) => '-H "${e.key}: ${e.value}"')
        .join(' ');
    final bodyString = body != null
        ? "--data-raw '${jsonEncode(body).replaceAll("'", "'\"'\"'")}'"
        : '';
    debugPrint('[FrontFace] curl -X $method $headerStrings $bodyString "$url"');
  }
}
