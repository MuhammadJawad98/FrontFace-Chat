import 'frontface_chat_strings.dart';

/// Optional chat attachments (location, images, voice notes).
///
/// All features default to **off**. Image and voice upload go through FrontFace
/// signed URLs (`POST /api/media/uploads` → `PUT` bytes → `parts` on
/// `POST /api/chat/message`) — no host uploader is required.
///
/// Location sharing needs [googleMapsApiKey] for the in-chat map picker, plus
/// the same key in the host Android/iOS native config (see README).
class FrontFaceAttachmentsConfig {
  /// Show "Share location" and open an in-app Google Map picker.
  final bool enableLocation;

  /// Allow picking / capturing images (JPEG/PNG/WebP/GIF, max 10 MB).
  final bool enableImages;

  /// Allow recording / attaching voice notes (max 25 MB).
  final bool enableAudio;

  /// Google Maps API key for the map picker + static map previews.
  final String? googleMapsApiKey;

  /// Max image size in bytes (API cap: 10 MB).
  final int maxImageBytes;

  /// Max audio size in bytes (API cap: 25 MB).
  final int maxAudioBytes;

  const FrontFaceAttachmentsConfig({
    this.enableLocation = false,
    this.enableImages = false,
    this.enableAudio = false,
    this.googleMapsApiKey,
    this.maxImageBytes = 10 * 1024 * 1024,
    this.maxAudioBytes = 25 * 1024 * 1024,
  });

  /// Nothing enabled — attach button hidden.
  static const disabled = FrontFaceAttachmentsConfig();

  bool get anyEnabled => enableLocation || enableImages || enableAudio;

  bool get mediaEnabled => enableImages || enableAudio;

  void validate() {
    if (enableLocation &&
        (googleMapsApiKey == null || googleMapsApiKey!.trim().isEmpty)) {
      throw ArgumentError(
        'FrontFaceAttachmentsConfig.googleMapsApiKey is required when '
        'enableLocation is true.',
      );
    }
  }
}

/// Kind of pending attachment.
enum FrontFaceAttachmentKind { location, image, audio }

/// Audio transcript pipeline status from `MessagePart.processingStatus`.
enum FrontFaceMediaProcessingStatus { pending, ready, failed }

/// Local file waiting to be uploaded to FrontFace storage.
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

/// Location payload for `POST /api/chat/message` (`location` field).
class FrontFaceLocationData {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String? label;
  final DateTime? capturedAt;

  const FrontFaceLocationData({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.label,
    this.capturedAt,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_m': accuracyMeters,
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
        if (capturedAt != null)
          'captured_at': capturedAt!.toUtc().toIso8601String(),
      };
}

/// UI helper for local provisional bubbles / legacy text parse.
class FrontFaceAttachmentPayload {
  final FrontFaceAttachmentKind kind;
  final String? url;
  final double? latitude;
  final double? longitude;
  final String? label;
  final double? accuracyMeters;
  final DateTime? capturedAt;
  final String? derivedText;
  final FrontFaceMediaProcessingStatus? processingStatus;

  const FrontFaceAttachmentPayload({
    required this.kind,
    this.url,
    this.latitude,
    this.longitude,
    this.label,
    this.accuracyMeters,
    this.capturedAt,
    this.derivedText,
    this.processingStatus,
  });

  FrontFaceLocationData? toLocationData() {
    if (kind != FrontFaceAttachmentKind.location) return null;
    if (latitude == null || longitude == null) return null;
    return FrontFaceLocationData(
      latitude: latitude!,
      longitude: longitude!,
      accuracyMeters: accuracyMeters,
      label: label,
      capturedAt: capturedAt ?? DateTime.now().toUtc(),
    );
  }

  /// Display fallback when [FrontFaceMessagePart]s are absent.
  String toMessageContent([FrontFaceChatStrings? strings]) {
    final s = strings ?? const FrontFaceChatStrings();
    switch (kind) {
      case FrontFaceAttachmentKind.location:
        final lat = latitude ?? 0;
        final lng = longitude ?? 0;
        final name = (label != null && label!.trim().isNotEmpty)
            ? label!.trim()
            : s.sharedLocation;
        return '📍 $name\nhttps://maps.google.com/?q=$lat,$lng';
      case FrontFaceAttachmentKind.image:
        return '🖼️ ${s.imageAttachment}';
      case FrontFaceAttachmentKind.audio:
        return '🎵 ${s.audioAttachment}';
    }
  }

  /// Provisional metadata for optimistic local bubbles.
  Map<String, dynamic> toMetadata() => {
        'attachment': {
          'type': kind.name,
          if (url != null) 'url': url,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (label != null) 'label': label,
          if (accuracyMeters != null) 'accuracy_m': accuracyMeters,
          if (capturedAt != null)
            'captured_at': capturedAt!.toUtc().toIso8601String(),
        },
      };

  /// Best-effort parse from plain message content + optional metadata.
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
          accuracyMeters: (raw['accuracy_m'] as num?)?.toDouble(),
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

    if (content.contains('🖼️') ||
        RegExp(r'https?://\S+\.(jpe?g|png|gif|webp)', caseSensitive: false)
            .hasMatch(content)) {
      final urlMatch =
          RegExp(r'https?://\S+').firstMatch(content)?.group(0);
      return FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.image,
        url: urlMatch,
      );
    }

    if (content.contains('🎵') ||
        RegExp(r'https?://\S+\.(mp3|m4a|wav|ogg|webm)', caseSensitive: false)
            .hasMatch(content)) {
      final urlMatch =
          RegExp(r'https?://\S+').firstMatch(content)?.group(0);
      return FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.audio,
        url: urlMatch,
      );
    }

    return null;
  }
}
