/// Whether [token] looks like an Apple PushKit **VoIP** token (64 hex chars).
///
/// FCM tokens contain `:` (e.g. `…:APA91b…`) and must **not** be passed to
/// [FrontFaceCalls.registerDevice] on iOS — they cannot receive FrontFace VoIP
/// pushes, so the phone will not ring when the app is closed or locked.
bool looksLikeIosVoipPushToken(String token) {
  final t = token.trim();
  if (t.length != 64) return false;
  return RegExp(r'^[0-9a-fA-F]+$').hasMatch(t);
}

/// Whether [token] looks like a Firebase Cloud Messaging token (contains `:`).
bool looksLikeFcmPushToken(String token) => token.trim().contains(':');
