import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/frontface_attachments_config.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import 'frontface_image_viewer.dart';
import 'frontface_voice_player.dart';

/// Renders a location / media attachment card inside a chat bubble.
class FrontFaceAttachmentCard extends StatelessWidget {
  final FrontFaceAttachmentPayload attachment;
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final bool isVisitor;
  final String? googleMapsApiKey;

  const FrontFaceAttachmentCard({
    super.key,
    required this.attachment,
    required this.theme,
    required this.strings,
    this.isVisitor = false,
    this.googleMapsApiKey,
  });

  Color get _fg => isVisitor
      ? theme.userBubbleTextColor
      : theme.assistantBubbleTextColor;
  Color get _muted => isVisitor
      ? theme.userBubbleTextColor.withValues(alpha: 0.85)
      : theme.subtitleColor;

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
    final Widget body;
    switch (attachment.kind) {
      case FrontFaceAttachmentKind.location:
        body = _LocationCard(
          attachment: attachment,
          strings: strings,
          fg: _fg,
          muted: _muted,
          onOpen: _openUrl,
          mapsApiKey: googleMapsApiKey,
        );
      case FrontFaceAttachmentKind.image:
        body = _ImageCard(
          url: attachment.url,
          alt: attachment.derivedText ?? attachment.label,
          muted: _muted,
          strings: strings,
        );
      case FrontFaceAttachmentKind.audio:
        body = _AudioCard(
          url: attachment.url,
          derivedText: attachment.derivedText,
          processingStatus: attachment.processingStatus,
          fg: _fg,
          muted: _muted,
          strings: strings,
        );
    }
    return _withUploadChrome(child: body);
  }

  Widget _withUploadChrome({required Widget child}) {
    Widget content = child;
    if (attachment.isUploading) {
      // Full-bubble dimmed overlay so the loader reads clearly on any media.
      content = AbsorbPointer(
        child: Stack(
          alignment: Alignment.center,
          children: [
            child,
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isVisitor
                      ? const Color(0x99000000) // light black on dark bubbles
                      : const Color(0xB3E5E7EB), // light gray on light bubbles
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: CupertinoActivityIndicator(
                    radius: 14,
                    color: isVisitor ? Colors.white : const Color(0xFF111827),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (attachment.isUploadFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 14, color: theme.errorColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  strings.attachmentUploadFailed,
                  style: TextStyle(
                    color: theme.errorColor,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return content;
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
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            staticUrl,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: muted.withValues(alpha: 0.12),
              alignment: Alignment.center,
              child: Icon(Icons.map_outlined, color: muted, size: 28),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview != null) ...[preview, const SizedBox(height: 10)],
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.location_on_rounded, color: fg, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.label?.isNotEmpty == true
                        ? attachment.label!
                        : strings.sharedLocation,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                  if (hasCoords)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        style: TextStyle(color: muted, fontSize: 11.5, height: 1.2),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Material(
          color: fg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(Icons.map_rounded, size: 16, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings.openInMaps,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_outward_rounded, size: 16, color: fg),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String? url;
  final String? alt;
  final Color muted;
  final FrontFaceChatStrings strings;

  const _ImageCard({
    required this.url,
    required this.alt,
    required this.muted,
    required this.strings,
  });

  void _openViewer(BuildContext context) {
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) return;
    FrontFaceImageViewer.open(
      context,
      url: imageUrl,
      strings: strings,
      semanticLabel: alt,
    );
  }

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
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return _loadingPlaceholder();
            },
            errorBuilder: (_, __, ___) => _unavailable(),
          )
        : Image.network(
            url!,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            semanticLabel: alt,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _loadingPlaceholder();
            },
            errorBuilder: (_, __, ___) => _unavailable(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openViewer(context),
            borderRadius: BorderRadius.circular(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: image,
            ),
          ),
        ),
        if (alt != null && alt!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(alt!, style: TextStyle(color: muted, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _loadingPlaceholder() => Container(
        height: 180,
        width: double.infinity,
        alignment: Alignment.center,
        color: muted.withValues(alpha: 0.12),
        child: CupertinoActivityIndicator(color: muted),
      );

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

  const _AudioCard({
    required this.url,
    required this.derivedText,
    required this.processingStatus,
    required this.fg,
    required this.muted,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.trim().isNotEmpty;

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
        if (hasUrl)
          FrontFaceVoicePlayer(
            url: url!,
            foreground: fg,
            muted: muted,
            strings: strings,
          )
        else
          Text(
            strings.attachmentUnavailable,
            style: TextStyle(color: muted, fontSize: 13),
          ),
        if (statusLine != null) ...[
          const SizedBox(height: 8),
          Text(
            statusLine,
            style: TextStyle(color: muted, fontSize: 12, height: 1.3),
          ),
        ],
      ],
    );
  }
}
