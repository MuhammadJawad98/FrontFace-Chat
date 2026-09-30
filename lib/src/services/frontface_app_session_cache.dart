import '../models/frontface_models.dart';

/// In-memory caches that live for the process lifetime (one app session).
///
/// LIVE_REPLIES §8:
/// - ensure-conversation token: once per app session, reuse after
/// - embed/config: cache for the session
/// - handoff-availability: cache for the session
class FrontFaceAppSessionCache {
  FrontFaceAppSessionCache._();

  static String? visitorId;
  static String? conversationId;
  static String? sessionToken;
  static FrontFaceEmbedConfig? embedConfig;
  static FrontFaceHandoffAvailability? handoff;

  static bool hasSessionFor(String visitorId) {
    final v = visitorId.trim();
    return v.isNotEmpty &&
        FrontFaceAppSessionCache.visitorId == v &&
        conversationId != null &&
        conversationId!.isNotEmpty &&
        sessionToken != null &&
        sessionToken!.isNotEmpty;
  }

  static void setSession({
    required String visitorId,
    required String conversationId,
    required String sessionToken,
  }) {
    FrontFaceAppSessionCache.visitorId = visitorId.trim();
    FrontFaceAppSessionCache.conversationId = conversationId;
    FrontFaceAppSessionCache.sessionToken = sessionToken;
  }

  static void clear() {
    visitorId = null;
    conversationId = null;
    sessionToken = null;
    embedConfig = null;
    handoff = null;
  }
}
