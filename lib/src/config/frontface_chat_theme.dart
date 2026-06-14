import 'package:flutter/material.dart';

/// Visual styling for the chat UI. Override any field to match your app.
class FrontFaceChatTheme {
  final Color primaryColor;
  final Color onPrimaryColor;
  final Color backgroundColor;
  final Color inputBackgroundColor;
  final Color userBubbleColor;
  final Color userBubbleTextColor;
  final Color assistantBubbleColor;
  final Color assistantBubbleTextColor;
  final Color assistantBubbleBorderColor;
  final Color subtitleColor;
  final Color errorColor;
  final Color onlineIndicatorColor;
  final Color agentNameColor;

  const FrontFaceChatTheme({
    this.primaryColor = const Color(0xFF000000),
    this.onPrimaryColor = Colors.white,
    this.backgroundColor = const Color(0xFFF4F5F8),
    this.inputBackgroundColor = const Color(0xFFF6F6F6),
    this.userBubbleColor = const Color(0xFF000000),
    this.userBubbleTextColor = Colors.white,
    this.assistantBubbleColor = Colors.white,
    this.assistantBubbleTextColor = const Color(0xFF272424),
    this.assistantBubbleBorderColor = const Color(0xFFE2E8F0),
    this.subtitleColor = const Color(0xFF6C737F),
    this.errorColor = const Color(0xFFF04438),
    this.onlineIndicatorColor = const Color(0xFF17B26A),
    this.agentNameColor = const Color(0xFFF76E26),
  });

  FrontFaceChatTheme copyWith({
    Color? primaryColor,
    Color? onPrimaryColor,
    Color? backgroundColor,
    Color? inputBackgroundColor,
    Color? userBubbleColor,
    Color? userBubbleTextColor,
    Color? assistantBubbleColor,
    Color? assistantBubbleTextColor,
    Color? assistantBubbleBorderColor,
    Color? subtitleColor,
    Color? errorColor,
    Color? onlineIndicatorColor,
    Color? agentNameColor,
  }) {
    return FrontFaceChatTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      onPrimaryColor: onPrimaryColor ?? this.onPrimaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      inputBackgroundColor: inputBackgroundColor ?? this.inputBackgroundColor,
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      userBubbleTextColor: userBubbleTextColor ?? this.userBubbleTextColor,
      assistantBubbleColor: assistantBubbleColor ?? this.assistantBubbleColor,
      assistantBubbleTextColor:
          assistantBubbleTextColor ?? this.assistantBubbleTextColor,
      assistantBubbleBorderColor:
          assistantBubbleBorderColor ?? this.assistantBubbleBorderColor,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      errorColor: errorColor ?? this.errorColor,
      onlineIndicatorColor: onlineIndicatorColor ?? this.onlineIndicatorColor,
      agentNameColor: agentNameColor ?? this.agentNameColor,
    );
  }
}
