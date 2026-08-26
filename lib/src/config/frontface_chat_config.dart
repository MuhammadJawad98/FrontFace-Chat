import 'frontface_attachments_config.dart';

export 'frontface_attachments_config.dart';

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

  /// Enable debug console logs (curl + responses). Defaults to `false`.
  ///
  /// Logs are **never** emitted in release/profile builds (`kDebugMode` gate),
  /// even if this is set to `true` — so production cannot leak keys, session
  /// tokens, or signed upload URLs via the terminal. Use only while debugging
  /// a local/dev build.
  final bool debugLogging;

  /// Shows the lead-capture form (email/phone/etc.) before the first
  /// message and before any conversation/session is created.
  ///
  /// Defaults to `true` so the Mobile SDK treats lead capture as the
  /// first step of creating a session: no local greeting is shown, and
  /// the conversation (plus the API `assembledGreeting`) starts only
  /// after the form is submitted. This applies even when the dashboard
  /// `capture_mode` is `email_after`.
  ///
  /// Set to `false` to follow the dashboard mode instead (`email_after`
  /// shows greeting first, then the form after the first exchange;
  /// `email_first` / `email_required` still show the form first).
  ///
  /// Has no effect if lead capture itself is disabled on the dashboard
  /// (`leadCapture.enabled == false`).
  final bool requireLeadCaptureBeforeChat;

  /// Optional account-keyed visitor id for logged-in users.
  ///
  /// When set, the SDK persists and uses this value instead of generating a
  /// per-install `mob_*` id. Same user on any device then shares one history
  /// thread. Must be stable and unguessable (e.g. HMAC from your backend) —
  /// never the raw user id. Leave null for anonymous / device-scoped chats.
  final String? visitorId;

  /// Shows the app-bar refresh (“new chat”) button. Defaults to `true`.
  ///
  /// Set to `false` to hide it when the host app starts sessions itself or
  /// does not want users to reset the conversation from chat.
  final bool showNewChatButton;

  /// Optional attachments (location / images / voice). Defaults off.
  ///
  /// See [FrontFaceAttachmentsConfig]. Image and voice upload use FrontFace
  /// signed URLs — no host uploader required. [FrontFaceAttachmentsConfig.googleMapsApiKey]
  /// is optional: with a key you get the map picker + previews; without it,
  /// location still shares the device GPS pin.
  final FrontFaceAttachmentsConfig attachments;

  const FrontFaceChatConfig({
    required this.projectId,
    required this.publishableKey,
    this.baseUrl = 'https://api.frontface.app',
    this.debugLogging = false,
    this.requireLeadCaptureBeforeChat = true,
    this.visitorId,
    this.showNewChatButton = true,
    this.attachments = FrontFaceAttachmentsConfig.disabled,
  });
}
