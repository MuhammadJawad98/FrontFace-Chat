import 'frontface_chat_strings.dart';

/// Optional chat attachments (location, images, audio, video).
///
/// All features default to **off**. Enable only what your host app needs, and
/// provide [uploader] when any media type is enabled (FrontFace's public chat
/// API does not yet accept raw file uploads — the host uploads the file and
/// returns a public HTTPS URL that is sent as the message body).
///
/// Location sharing needs [googleMapsApiKey] for the in-chat map picker, plus
/// the same key in the host app's Android/iOS native config (see README).
class FrontFaceAttachmentsConfig {
  /// Show "Share location" and open an in-app Google Map picker.
  final bool enableLocation;

  /// Allow picking / capturing images.
  final bool enableImages;

  /// Allow picking audio files.
  final bool enableAudio;

  /// Allow picking / capturing videos.
  final bool enableVideo;

  /// Google Maps / Places API key used by the Flutter map picker and static
  /// map previews. Also configure this key in AndroidManifest / AppDelegate.
  final String? googleMapsApiKey;

  /// Uploads a local media file and returns a public HTTPS URL.
  ///
  /// Required when [enableImages], [enableAudio], or [enableVideo] is true.
  final FrontFaceAttachmentUploader? uploader;

  /// Max image size in bytes (default 10 MB).
  final int maxImageBytes;

  /// Max audio size in bytes (default 15 MB).
  final int maxAudioBytes;

  /// Max video size in bytes (default 50 MB).
  final int maxVideoBytes;

  const FrontFaceAttachmentsConfig({
    this.enableLocation = false,
    this.enableImages = false,
    this.enableAudio = false,
    this.enableVideo = false,
    this.googleMapsApiKey,
    this.uploader,
    this.maxImageBytes = 10 * 1024 * 1024,
    this.maxAudioBytes = 15 * 1024 * 1024,
    this.maxVideoBytes = 50 * 1024 * 1024,
  });

  /// Nothing enabled — attach button hidden.
  static const disabled = FrontFaceAttachmentsConfig();

  bool get anyEnabled =>
      enableLocation || enableImages || enableAudio || enableVideo;

  bool get mediaEnabled => enableImages || enableAudio || enableVideo;

  void validate() {
    if (enableLocation &&
        (googleMapsApiKey == null || googleMapsApiKey!.trim().isEmpty)) {
      throw ArgumentError(
        'FrontFaceAttachmentsConfig.googleMapsApiKey is required when '
        'enableLocation is true.',
      );
    }
    if (mediaEnabled && uploader == null) {
      throw ArgumentError(
        'FrontFaceAttachmentsConfig.uploader is required when images, audio, '
        'or video attachments are enabled (host must upload and return a URL).',
      );
    }
  }
}

/// Kind of pending / uploaded attachment.
enum FrontFaceAttachmentKind { location, image, audio, video }

/// Local file waiting to be uploaded (or already chosen).
class FrontFacePendingAttachment {
  final FrontFaceAttachmentKind kind;
  final String path;
  final String? fileName;
  final String? mimeType;
  final int? byteLength;

  const FrontFacePendingAttachment({
    required this.kind,
    required this.path,
    this.fileName,
    this.mimeType,
    this.byteLength,
  });
}

/// Result of a successful host-side upload.
class FrontFaceUploadedAttachment {
  final String url;
  final String? fileName;
  final String? mimeType;

  const FrontFaceUploadedAttachment({
    required this.url,
    this.fileName,
    this.mimeType,
  });
}

/// Host-provided upload hook. Must return a publicly reachable HTTPS URL.
typedef FrontFaceAttachmentUploader = Future<FrontFaceUploadedAttachment>
    Function(FrontFacePendingAttachment attachment);

/// Parsed attachment hints embedded in message content / metadata for UI.
class FrontFaceAttachmentPayload {
  final FrontFaceAttachmentKind kind;
  final String? url;
  final double? latitude;
  final double? longitude;
  final String? label;

  const FrontFaceAttachmentPayload({
    required this.kind,
    this.url,
    this.latitude,
    this.longitude,
    this.label,
  });

  /// Builds the plain-text body sent to `POST /api/chat/message`.
  ///
  /// Pass [strings] so location/media labels match the host app language.
  String toMessageContent([FrontFaceChatStrings? strings]) {
    final s = strings ?? const FrontFaceChatStrings();
    switch (kind) {
      case FrontFaceAttachmentKind.location:
        final lat = latitude ?? 0;
        final lng = longitude ?? 0;
        final mapsUrl = 'https://maps.google.com/?q=$lat,$lng';
        final name = (label != null && label!.trim().isNotEmpty)
            ? label!.trim()
            : s.sharedLocation;
        return '📍 $name\n$mapsUrl';
      case FrontFaceAttachmentKind.image:
        return '🖼️ ${s.imageAttachment}\n${url ?? ''}';
      case FrontFaceAttachmentKind.audio:
        return '🎵 ${s.audioAttachment}\n${url ?? ''}';
      case FrontFaceAttachmentKind.video:
        return '🎬 ${s.videoAttachment}\n${url ?? ''}';
    }
  }

  Map<String, dynamic> toMetadata() => {
        'attachment': {
          'type': kind.name,
          if (url != null) 'url': url,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (label != null) 'label': label,
        },
      };

  /// Best-effort parse from message content + optional metadata.
  static FrontFaceAttachmentPayload? tryParse({
    required String content,
    Map<String, dynamic>? metadata,
  }) {
    final raw = metadata?['attachment'];
    if (raw is Map) {
      final type = raw['type']?.toString();
      FrontFaceAttachmentKind? kind;
      for (final value in FrontFaceAttachmentKind.values) {
        if (value.name == type) {
          kind = value;
          break;
        }
      }
      if (kind != null) {
        return FrontFaceAttachmentPayload(
          kind: kind,
          url: raw['url']?.toString(),
          latitude: (raw['latitude'] as num?)?.toDouble(),
          longitude: (raw['longitude'] as num?)?.toDouble(),
          label: raw['label']?.toString(),
        );
      }
    }

    final mapsMatch = RegExp(
      r'https://maps\.google\.com/\?q=(-?\d+\.?\d*),(-?\d+\.?\d*)',
    ).firstMatch(content);
    if (mapsMatch != null || content.contains('📍')) {
      return FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.location,
        latitude: double.tryParse(mapsMatch?.group(1) ?? ''),
        longitude: double.tryParse(mapsMatch?.group(2) ?? ''),
        url: mapsMatch?.group(0),
        label: content.split('\n').first.replaceFirst('📍', '').trim(),
      );
    }

    final urlMatch = RegExp(r'https?://\S+').firstMatch(content);
    final url = urlMatch?.group(0);
    if (url == null) return null;

    if (content.contains('🖼️') ||
        RegExp(r'\.(png|jpe?g|gif|webp)(\?|$)', caseSensitive: false)
            .hasMatch(url)) {
      return FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.image,
        url: url,
      );
    }
    if (content.contains('🎵') ||
        RegExp(r'\.(mp3|m4a|wav|aac|ogg)(\?|$)', caseSensitive: false)
            .hasMatch(url)) {
      return FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.audio,
        url: url,
      );
    }
    if (content.contains('🎬') ||
        RegExp(r'\.(mp4|mov|webm|m4v)(\?|$)', caseSensitive: false)
            .hasMatch(url)) {
      return FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.video,
        url: url,
      );
    }
    return null;
  }
}
