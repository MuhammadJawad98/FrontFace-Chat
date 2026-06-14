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

  const FrontFaceChatConfig({
    required this.projectId,
    required this.publishableKey,
    this.baseUrl = 'https://api.frontface.app',
    this.debugLogging = false,
  });
}
