import 'package:flutter/material.dart';

import '../../config/frontface_chat_theme.dart';
import '../../models/frontface_models.dart';
import 'frontface_message_bubble.dart';

class FrontFaceChannelButtons extends StatelessWidget {
  final List<FrontFaceChannelButton> channels;
  final FrontFaceChatTheme theme;

  const FrontFaceChannelButtons({
    super.key,
    required this.channels,
    required this.theme,
  });

  IconData _iconFor(String type) {
    switch (type) {
      case 'whatsapp':
        return Icons.chat_rounded;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'facebook':
        return Icons.facebook_rounded;
      case 'email':
        return Icons.email_outlined;
      case 'phone':
        return Icons.phone_outlined;
      default:
        return Icons.open_in_new_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: channels.map((channel) {
          return OutlinedButton.icon(
            onPressed: channel.url.isEmpty
                ? null
                : () => openFrontFaceMarkdownLink(
                      channel.displayLabel,
                      channel.url,
                      channel.displayLabel,
                    ),
            icon: Icon(_iconFor(channel.type), size: 18),
            label: Text(channel.displayLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.3)),
            ),
          );
        }).toList(),
      ),
    );
  }
}
