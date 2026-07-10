import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../models/frontface_models.dart';
import '../../utils/text_direction.dart';

/// Link tap schemes allowed when rendering assistant/agent Markdown.
/// Never allow `javascript:` or other executable schemes here.
const _allowedLinkSchemes = {'https', 'http', 'mailto'};

Future<void> _onTapMarkdownLink(String text, String? href, String title) async {
  if (href == null) return;
  final uri = Uri.tryParse(href);
  if (uri == null || !_allowedLinkSchemes.contains(uri.scheme.toLowerCase())) {
    return;
  }
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class FrontFaceMessageBubble extends StatelessWidget {
  final FrontFaceChatMessage message;
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;

  const FrontFaceMessageBubble({
    super.key,
    required this.message,
    required this.theme,
    this.strings = const FrontFaceChatStrings(),
  });

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.messageCopied),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVisitor = message.isVisitor;
    final isSystem = message.senderType == FrontFaceSenderType.system;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.content,
              textDirection: detectTextDirection(message.content),
              style: TextStyle(fontSize: 12, color: theme.subtitleColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isVisitor
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: () => _copyMessage(context),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isVisitor
                ? theme.userBubbleColor
                : theme.assistantBubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isVisitor ? 14 : 4),
              bottomRight: Radius.circular(isVisitor ? 4 : 14),
            ),
            border: isVisitor
                ? null
                : Border.all(color: theme.assistantBubbleBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isVisitor && message.senderName?.isNotEmpty == true) ...[
                Text(
                  message.senderName!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.agentNameColor,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (isVisitor)
                Text(
                  message.content,
                  textDirection: detectTextDirection(message.content),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: theme.userBubbleTextColor,
                  ),
                )
              else
                Directionality(
                  textDirection: detectTextDirection(message.content),
                  child: MarkdownBody(
                    data: message.content,
                    onTapLink: _onTapMarkdownLink,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          p: TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            color: theme.assistantBubbleTextColor,
                          ),
                          strong: TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: theme.assistantBubbleTextColor,
                          ),
                          em: TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontStyle: FontStyle.italic,
                            color: theme.assistantBubbleTextColor,
                          ),
                          listBullet: TextStyle(
                            fontSize: 15,
                            color: theme.assistantBubbleTextColor,
                          ),
                          a: TextStyle(color: theme.primaryColor),
                          code: TextStyle(
                            fontSize: 13.5,
                            backgroundColor: theme.backgroundColor,
                            color: theme.assistantBubbleTextColor,
                          ),
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FrontFaceTypingIndicator extends StatefulWidget {
  final FrontFaceChatTheme theme;

  const FrontFaceTypingIndicator({super.key, required this.theme});

  @override
  State<FrontFaceTypingIndicator> createState() =>
      _FrontFaceTypingIndicatorState();
}

class _FrontFaceTypingIndicatorState extends State<FrontFaceTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: widget.theme.assistantBubbleColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(14),
          ),
          border: Border.all(color: widget.theme.assistantBubbleBorderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final phase = (_controller.value + index * 0.2) % 1.0;
                final wave = math.sin(phase * 2 * math.pi).clamp(0.0, 1.0);
                final dy = -wave * 5;
                final opacity = 0.4 + wave * 0.6;
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Opacity(opacity: opacity, child: child),
                );
              },
              child: Container(
                width: 8,
                height: 8,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
                decoration: BoxDecoration(
                  color: widget.theme.primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
