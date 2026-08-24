import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/frontface_attachments_config.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';

/// Renders a location / media attachment card inside a chat bubble.
class FrontFaceAttachmentCard extends StatelessWidget {
  final FrontFaceAttachmentPayload attachment;
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final bool onPrimary;
  final String? googleMapsApiKey;

  const FrontFaceAttachmentCard({
    super.key,
    required this.attachment,
    required this.theme,
    required this.strings,
    this.onPrimary = false,
    this.googleMapsApiKey,
  });

  Color get _fg => onPrimary ? theme.onPrimaryColor : theme.primaryColor;
  Color get _muted =>
      onPrimary ? theme.onPrimaryColor.withValues(alpha: 0.85) : theme.subtitleColor;

  Future<void> _openUrl() async {
    final raw = attachment.url;
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    switch (attachment.kind) {
      case FrontFaceAttachmentKind.location:
        return _LocationCard(
          attachment: attachment,
          strings: strings,
          fg: _fg,
          muted: _muted,
          onOpen: _openUrl,
          mapsApiKey: googleMapsApiKey,
        );
      case FrontFaceAttachmentKind.image:
        return _ImageCard(
          url: attachment.url,
          fg: _fg,
          muted: _muted,
          strings: strings,
          onOpen: _openUrl,
        );
      case FrontFaceAttachmentKind.audio:
      case FrontFaceAttachmentKind.video:
        return _MediaLinkCard(
          kind: attachment.kind,
          url: attachment.url,
          fg: _fg,
          muted: _muted,
          strings: strings,
          onOpen: _openUrl,
        );
    }
  }
}

class _LocationCard extends StatelessWidget {
  final FrontFaceAttachmentPayload attachment;
  final FrontFaceChatStrings strings;
  final Color fg;
  final Color muted;
  final VoidCallback onOpen;
  final String? mapsApiKey;

  const _LocationCard({
    required this.attachment,
    required this.strings,
    required this.fg,
    required this.muted,
    required this.onOpen,
    this.mapsApiKey,
  });

  @override
  Widget build(BuildContext context) {
    final lat = attachment.latitude;
    final lng = attachment.longitude;
    final hasCoords = lat != null && lng != null;

    Widget? preview;
    if (hasCoords && mapsApiKey != null && mapsApiKey!.isNotEmpty) {
      final staticUrl =
          'https://maps.googleapis.com/maps/api/staticmap'
          '?center=$lat,$lng&zoom=15&size=400x180&markers=color:red%7C$lat,$lng'
          '&key=$mapsApiKey';
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          staticUrl,
          height: 120,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview != null) ...[preview, const SizedBox(height: 8)],
          Row(
            children: [
              Icon(Icons.location_on, color: fg, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  attachment.label?.isNotEmpty == true
                      ? attachment.label!
                      : strings.sharedLocation,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (hasCoords)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 26),
              child: Text(
                '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 26),
            child: Text(
              strings.openInMaps,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String? url;
  final Color fg;
  final Color muted;
  final FrontFaceChatStrings strings;
  final VoidCallback onOpen;

  const _ImageCard({
    required this.url,
    required this.fg,
    required this.muted,
    required this.strings,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Text(strings.attachmentUnavailable, style: TextStyle(color: muted));
    }
    return InkWell(
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url!,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 80,
            alignment: Alignment.center,
            child: Text(strings.attachmentUnavailable,
                style: TextStyle(color: muted)),
          ),
        ),
      ),
    );
  }
}

class _MediaLinkCard extends StatelessWidget {
  final FrontFaceAttachmentKind kind;
  final String? url;
  final Color fg;
  final Color muted;
  final FrontFaceChatStrings strings;
  final VoidCallback onOpen;

  const _MediaLinkCard({
    required this.kind,
    required this.url,
    required this.fg,
    required this.muted,
    required this.strings,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final isAudio = kind == FrontFaceAttachmentKind.audio;
    return InkWell(
      onTap: url == null ? null : onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Icon(
            isAudio ? Icons.audiotrack : Icons.videocam,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAudio ? strings.audioAttachment : strings.videoAttachment,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
          Icon(Icons.open_in_new, size: 16, color: muted),
        ],
      ),
    );
  }
}
