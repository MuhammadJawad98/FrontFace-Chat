import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class FrontFaceVisitorStore {
  static const _visitorIdKey = 'frontface_visitor_id';
  static const _sessionIdPrefix = 'frontface_session_id_';
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

  Future<bool> hasCompletedLeadForm(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_leadCompletedPrefix$projectId') ?? false;
  }

  Future<void> setLeadFormCompleted(String projectId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_leadCompletedPrefix$projectId', value);
  }
}
