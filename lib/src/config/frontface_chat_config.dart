/// Credentials and settings for your FrontFace project.
///
/// Get [projectId] and [publishableKey] from the FrontFace dashboard
/// under **Mobile SDK**.
class FrontFaceChatConfig {
  /// FrontFace project UUID (NOT the `pk_` key).
  final String projectId;

  /// Publishable mobile SDK key (`pk_…`).
  final String publishableKey;

  /// API base URL. Defaults to production.
  final String baseUrl;

  /// Enable debug curl logs in the console.
  final bool debugLogging;

  /// Forces the lead-capture form (email/phone/etc.) to show before the
  /// first message is sent — and before any conversation/session is
  /// created — regardless of the `capture_mode` configured on the
  /// FrontFace dashboard. Set this when you want "collect contact info,
  /// then start the session" on every fresh conversation, independent of
  /// the dashboard's `email_after` / `email_first` / `email_required`
  /// setting. Has no effect if lead capture itself is disabled on the
  /// dashboard (`leadCapture.enabled == false`).
  final bool requireLeadCaptureBeforeChat;

  const FrontFaceChatConfig({
    required this.projectId,
    required this.publishableKey,
    this.baseUrl = 'https://api.frontface.app',
    this.debugLogging = false,
    this.requireLeadCaptureBeforeChat = false,
  });
}
