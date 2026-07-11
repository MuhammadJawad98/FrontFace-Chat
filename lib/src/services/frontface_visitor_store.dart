import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class FrontFaceVisitorStore {
  static const _visitorIdKey = 'frontface_visitor_id';
  static const _sessionIdPrefix = 'frontface_session_id_';
  static const _sessionTokenPrefix = 'frontface_session_token_';
  static const _leadCompletedPrefix = 'frontface_lead_completed_';

  Future<String> getOrCreateVisitorId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_visitorIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final visitorId =
        'mob_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
    await prefs.setString(_visitorIdKey, visitorId);
    return visitorId;
  }

  Future<String?> getSessionId(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_sessionIdPrefix$projectId');
  }

  Future<void> saveSessionId(String projectId, String? sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_sessionIdPrefix$projectId';
    if (sessionId == null || sessionId.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, sessionId);
  }

  Future<String?> getSessionToken(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_sessionTokenPrefix$projectId');
  }

  Future<void> saveSessionToken(String projectId, String? sessionToken) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_sessionTokenPrefix$projectId';
    if (sessionToken == null || sessionToken.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, sessionToken);
  }

  Future<bool> hasCompletedLeadForm(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_leadCompletedPrefix$projectId') ?? false;
  }

  Future<void> setLeadFormCompleted(String projectId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_leadCompletedPrefix$projectId', value);
  }

  /// Debug helper: mangles the persisted `sessionToken` so the next API call
  /// that requires `X-FrontFace-Session` returns `403 SESSION_INVALID`.
  /// Expired and tampered tokens hit the same server path — this is how to
  /// exercise silent session recovery without waiting 24h.
  ///
  /// Returns `false` if there is no stored token to corrupt.
  Future<bool> corruptSessionToken(String projectId) async {
    final token = await getSessionToken(projectId);
    if (token == null || token.isEmpty) return false;

    final last = token[token.length - 1];
    final corrupted =
        '${token.substring(0, token.length - 1)}${last == 'a' ? 'b' : 'a'}';
    await saveSessionToken(projectId, corrupted);
    return true;
  }
}
