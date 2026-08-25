import 'dart:io';

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
    if (_isLocalPath(raw)) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  static bool _isLocalPath(String raw) =>
      !raw.startsWith('http://') && !raw.startsWith('https://');

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
          alt: attachment.derivedText ?? attachment.label,
          fg: _fg,
          muted: _muted,
          strings: strings,
          onOpen: _openUrl,
        );
      case FrontFaceAttachmentKind.audio:
        return _AudioCard(
          url: attachment.url,
          derivedText: attachment.derivedText,
          processingStatus: attachment.processingStatus,
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
  final String? alt;
  final Color fg;
  final Color muted;
  final FrontFaceChatStrings strings;
  final VoidCallback onOpen;

  const _ImageCard({
    required this.url,
    required this.alt,
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

    final isLocal =
        !url!.startsWith('http://') && !url!.startsWith('https://');
    final image = isLocal
        ? Image.file(
            File(url!),
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _unavailable(),
          )
        : Image.network(
            url!,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            semanticLabel: alt,
            errorBuilder: (_, __, ___) => _unavailable(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: isLocal ? null : onOpen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: image,
          ),
        ),
        if (alt != null && alt!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(alt!, style: TextStyle(color: muted, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _unavailable() => Container(
        height: 80,
        alignment: Alignment.center,
        child: Text(strings.attachmentUnavailable, style: TextStyle(color: muted)),
      );
}

class _AudioCard extends StatelessWidget {
  final String? url;
  final String? derivedText;
  final FrontFaceMediaProcessingStatus? processingStatus;
  final Color fg;
  final Color muted;
  final FrontFaceChatStrings strings;
  final VoidCallback onOpen;

  const _AudioCard({
    required this.url,
    required this.derivedText,
    required this.processingStatus,
    required this.fg,
    required this.muted,
    required this.strings,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final canOpen = url != null &&
        url!.isNotEmpty &&
        (url!.startsWith('http://') || url!.startsWith('https://'));

    String? statusLine;
    if (derivedText != null && derivedText!.trim().isNotEmpty) {
      statusLine = derivedText;
    } else if (processingStatus == FrontFaceMediaProcessingStatus.pending) {
      statusLine = strings.transcriptPending;
    } else if (processingStatus == FrontFaceMediaProcessingStatus.failed) {
      statusLine = strings.transcriptFailed;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: canOpen ? onOpen : null,
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, color: fg, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.audioAttachment,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
              if (canOpen) Icon(Icons.open_in_new, size: 16, color: muted),
            ],
          ),
        ),
        if (statusLine != null) ...[
          const SizedBox(height: 6),
          Text(
            statusLine,
            style: TextStyle(color: muted, fontSize: 12, height: 1.3),
          ),
        ],
      ],
    );
  }
}
