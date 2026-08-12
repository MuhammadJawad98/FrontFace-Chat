import 'package:flutter/material.dart';

import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../models/frontface_models.dart';
import 'frontface_message_bubble.dart';

class FrontFaceTicketCard extends StatelessWidget {
  final FrontFaceMessageMetadata metadata;
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;

  const FrontFaceTicketCard({
    super.key,
    required this.metadata,
    required this.theme,
    this.strings = const FrontFaceChatStrings(),
  });

  @override
  Widget build(BuildContext context) {
    final card = metadata.ticketCard;
    if (card == null) return const SizedBox.shrink();

    final reference = card['reference']?.toString();
    final subject = card['subject']?.toString();
    final accessUrl = card['accessUrl']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.inputBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reference != null && reference.isNotEmpty) ...[
            Text(
              strings.ticketReferenceLabel,
              style: TextStyle(
                fontSize: 12,
                color: theme.primaryColor.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              reference,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
          if (subject != null && subject.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(subject, style: const TextStyle(fontSize: 14)),
          ],
          if (accessUrl != null && accessUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => openFrontFaceMarkdownLink(
                strings.viewTicket,
                accessUrl,
                strings.viewTicket,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(strings.viewTicket),
            ),
          ],
        ],
      ),
    );
  }
}
