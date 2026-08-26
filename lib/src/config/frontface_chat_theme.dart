import 'package:flutter/material.dart';

/// Bundled Noto Sans Arabic family (used automatically for RTL / Arabic UI).
const kFrontFaceArabicFontFamily = 'FrontFaceArabic';

/// Visual styling for the chat UI. Override any field to match your app.
///
/// Bubble colors are **optional** — omit them to keep the defaults:
/// - User (visitor): [userBubbleColor] / [userBubbleTextColor]
/// - Agent / assistant: [assistantBubbleColor] / [assistantBubbleTextColor]
///
/// Typography:
/// - [fontFamily] — optional Latin / default UI font
/// - [arabicFontFamily] — used when chat [TextDirection] is RTL (defaults to
///   the bundled [kFrontFaceArabicFontFamily] Noto Sans Arabic)
class FrontFaceChatTheme {
  final Color primaryColor;
  final Color onPrimaryColor;
  final Color backgroundColor;
  final Color inputBackgroundColor;

  /// Background of visitor (user) message bubbles. Optional — defaults to black.
  final Color userBubbleColor;

  /// Text / icon color inside visitor bubbles. Optional — defaults to white.
  final Color userBubbleTextColor;

  /// Background of agent / assistant message bubbles. Optional — defaults to white.
  final Color assistantBubbleColor;

  /// Text / icon color inside agent / assistant bubbles. Optional.
  final Color assistantBubbleTextColor;

  /// Border around agent / assistant bubbles. Optional.
  final Color assistantBubbleBorderColor;

  final Color subtitleColor;
  final Color errorColor;
  final Color onlineIndicatorColor;
  final Color agentNameColor;

  /// Color for links inside assistant/agent Markdown messages. Defaults to
  /// a conventional link blue, independent of [primaryColor], since
  /// [primaryColor] is often black/brand-colored and wouldn't read as a
  /// tappable link.
  final Color linkColor;

  /// Optional font for LTR / default UI copy. When null, inherits the host
  /// app theme.
  final String? fontFamily;

  /// Font used when the chat is RTL (Arabic pack). Defaults to the bundled
  /// [kFrontFaceArabicFontFamily]. Set to another family registered in the
  /// host app, or `null` only if you pass an empty override via [copyWith]
  /// clearing — prefer leaving the default so Arabic glyphs render correctly.
  final String? arabicFontFamily;

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
    this.linkColor = const Color(0xFF2563EB),
    this.fontFamily,
    this.arabicFontFamily = kFrontFaceArabicFontFamily,
  });

  /// Resolves the font for the active chat direction.
  String? resolvedFontFamily(TextDirection textDirection) {
    if (textDirection == TextDirection.rtl) {
      return arabicFontFamily ?? fontFamily;
    }
    return fontFamily;
  }

  /// Builds a [TextStyle] that includes the resolved font for [textDirection].
  TextStyle textStyle(
    TextDirection textDirection, {
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return TextStyle(
      fontFamily: resolvedFontFamily(textDirection),
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      decoration: decoration,
      decorationColor: decorationColor,
    );
  }

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
    Color? linkColor,
    String? fontFamily,
    String? arabicFontFamily,
    bool clearFontFamily = false,
    bool clearArabicFontFamily = false,
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
      linkColor: linkColor ?? this.linkColor,
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
      arabicFontFamily: clearArabicFontFamily
          ? null
          : (arabicFontFamily ?? this.arabicFontFamily),
    );
  }
}
