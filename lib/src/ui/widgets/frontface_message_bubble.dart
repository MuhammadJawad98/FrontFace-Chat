import 'package:flutter/material.dart';

import '../../config/frontface_chat_theme.dart';
import '../../models/frontface_models.dart';

class FrontFaceMessageBubble extends StatelessWidget {
  final FrontFaceChatMessage message;
  final FrontFaceChatTheme theme;

  const FrontFaceMessageBubble({
    super.key,
    required this.message,
    required this.theme,
  });

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
              style: TextStyle(fontSize: 12, color: theme.subtitleColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isVisitor ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isVisitor ? theme.userBubbleColor : theme.assistantBubbleColor,
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
            Text(
              message.content,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: isVisitor
                    ? theme.userBubbleTextColor
                    : theme.assistantBubbleTextColor,
              ),
            ),
          ],
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
      alignment: Alignment.centerLeft,
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
                final delay = index * 0.2;
                final value = (_controller.value + delay) % 1.0;
                final scale = 0.5 + (Curves.easeInOut.transform(value) * 0.5);
                final opacity =
                    0.35 + (Curves.easeInOut.transform(value) * 0.65);
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
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
