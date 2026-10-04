import 'package:flutter/material.dart';

/// Bundled Noto Sans Arabic family (used automatically for RTL / Arabic UI).
const kFrontFaceArabicFontFamily = 'FrontFaceArabic';

/// Visual styling for the chat UI. Override any field to match your app.
///
/// Bubble colors are **optional** — omit them to keep the defaults:
/// - User (visitor): [userBubbleColor] / [userBubbleTextColor]
/// - Agent / assistant: [assistantBubbleColor] / [assistantBubbleTextColor]
///
/// Call screen colors are also optional — omit them to keep the immersive
/// dark defaults, or override to match your brand:
/// - [callBackgroundColor] / [callSurfaceColor]
/// - [callOnBackgroundColor] / [callOnBackgroundMutedColor]
/// - [callAccentColor] (pulse / status; defaults to white)
/// - [callAvatarBackgroundColor] / [callAvatarIconColor]
/// - [callHangUpColor]
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

  /// Full-screen call background.
  final Color callBackgroundColor;

  /// Call chips / inactive control fill.
  final Color callSurfaceColor;

  /// Primary text and icons on the call screen.
  final Color callOnBackgroundColor;

  /// Secondary text on the call screen (status detail, control labels).
  final Color callOnBackgroundMutedColor;

  /// Avatar ring, pulse, and status accents on the call screen.
  /// Defaults to white so it stays visible on the dark call background.
  final Color callAccentColor;

  /// Fill behind the call / agent icon. Defaults to a light black
  /// (`0xFF374151`) so it lifts off [callBackgroundColor].
  final Color callAvatarBackgroundColor;

  /// Call / agent icon color. Defaults to white.
  final Color callAvatarIconColor;

  /// Hang-up button fill.
  final Color callHangUpColor;

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
    this.callBackgroundColor = const Color(0xFF111827),
    this.callSurfaceColor = const Color(0xFF1F2937),
    this.callOnBackgroundColor = const Color(0xFFF9FAFB),
    this.callOnBackgroundMutedColor = const Color(0xFF9CA3AF),
    this.callAccentColor = const Color(0xFFF9FAFB),
    this.callAvatarBackgroundColor = const Color(0xFF374151),
    this.callAvatarIconColor = const Color(0xFFF9FAFB),
    this.callHangUpColor = const Color(0xFFEF4444),
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
    Color? callBackgroundColor,
    Color? callSurfaceColor,
    Color? callOnBackgroundColor,
    Color? callOnBackgroundMutedColor,
    Color? callAccentColor,
    Color? callAvatarBackgroundColor,
    Color? callAvatarIconColor,
    Color? callHangUpColor,
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
      callBackgroundColor: callBackgroundColor ?? this.callBackgroundColor,
      callSurfaceColor: callSurfaceColor ?? this.callSurfaceColor,
      callOnBackgroundColor:
          callOnBackgroundColor ?? this.callOnBackgroundColor,
      callOnBackgroundMutedColor:
          callOnBackgroundMutedColor ?? this.callOnBackgroundMutedColor,
      callAccentColor: callAccentColor ?? this.callAccentColor,
      callAvatarBackgroundColor:
          callAvatarBackgroundColor ?? this.callAvatarBackgroundColor,
      callAvatarIconColor: callAvatarIconColor ?? this.callAvatarIconColor,
      callHangUpColor: callHangUpColor ?? this.callHangUpColor,
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
      arabicFontFamily: clearArabicFontFamily
          ? null
          : (arabicFontFamily ?? this.arabicFontFamily),
    );
  }
}
