import 'package:flutter/widgets.dart' show TextDirection;

/// Detects the base direction of [text] from its first strong-direction
/// character, so mixed-locale chat content (e.g. English typed into an
/// Arabic-configured chat) renders with its own natural direction instead
/// of inheriting the ambient RTL/LTR layout direction.
TextDirection detectTextDirection(String text) {
  for (final rune in text.runes) {
    if (_isRtlCodePoint(rune)) return TextDirection.rtl;
    if (_isLtrCodePoint(rune)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

bool _isRtlCodePoint(int cp) {
  // Hebrew, Arabic, Syriac, Arabic Supplement, Thaana, NKo (contiguous).
  if (cp >= 0x0590 && cp <= 0x07FF) return true;
  // Hebrew presentation forms / Arabic presentation forms A.
  if (cp >= 0xFB1D && cp <= 0xFDFF) return true;
  // Arabic presentation forms B.
  if (cp >= 0xFE70 && cp <= 0xFEFF) return true;
  return false;
}

bool _isLtrCodePoint(int cp) {
  // Basic Latin letters A-Z, a-z.
  return (cp >= 0x0041 && cp <= 0x005A) || (cp >= 0x0061 && cp <= 0x007A);
}
