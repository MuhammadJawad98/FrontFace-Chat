import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';

void main() {
  test('copyWith overrides only provided fields', () {
    const base = FrontFaceChatStrings();
    final updated = base.copyWith(
      attach: 'إضافة مرفق',
      shareLocation: 'مشاركة الموقع',
      textDirection: TextDirection.rtl,
    );

    expect(updated.attach, 'إضافة مرفق');
    expect(updated.shareLocation, 'مشاركة الموقع');
    expect(updated.textDirection, TextDirection.rtl);
    // Untouched fields keep English defaults
    expect(updated.takePhoto, 'Take photo');
    expect(updated.online, 'Online');
  });

  test('english pack uses professional attachment label', () {
    expect(FrontFaceChatStrings.english.attach, 'Add attachment');
  });

  test('arabic pack is rtl and translates attachments', () {
    const ar = FrontFaceChatStrings.arabic;
    expect(ar.textDirection, TextDirection.rtl);
    expect(ar.attach, 'إضافة مرفق');
    expect(ar.shareLocation, 'مشاركة الموقع');
    expect(ar.imageLoadFailed, 'تعذر تحميل الصورة');
  });

  test('forLanguage resolves en and ar', () {
    expect(FrontFaceChatStrings.forLanguage('en').attach, 'Add attachment');
    expect(FrontFaceChatStrings.forLanguage('AR_SA').attach, 'إضافة مرفق');
    expect(FrontFaceChatStrings.forLanguage('fr').attach, 'Add attachment');
  });

  test('call packs cover screen and transcript lines', () {
    expect(FrontFaceChatStrings.english.audioCall, 'Audio call');
    expect(FrontFaceChatStrings.english.missedCall, 'Missed call');
    expect(FrontFaceChatStrings.arabic.audioCall, 'مكالمة صوتية');
    expect(FrontFaceChatStrings.arabic.missedCall, 'مكالمة فائتة');
    expect(FrontFaceChatStrings.arabic.callEnded, 'انتهت المكالمة');
  });

  test('formatCallTranscriptLine uses host language', () {
    const ar = FrontFaceChatStrings.arabic;
    expect(
      ar.formatCallTranscriptLine(outcome: 'completed', durationSeconds: 8),
      'مكالمة صوتية · 0:08',
    );
    expect(ar.formatCallTranscriptLine(outcome: 'missed'), 'مكالمة فائتة');
    expect(
      ar.formatCallTranscriptLine(outcome: 'dropped', durationSeconds: 69),
      'انقطعت المكالمة · 1:09',
    );
    expect(
      ar.formatCallTranscriptLine(outcome: null, fallback: 'legacy'),
      'legacy',
    );
  });

  test('host can override call strings via copyWith', () {
    final fr = FrontFaceChatStrings.english.copyWith(
      callSupport: 'Appeler le support',
      audioCall: 'Appel audio',
      missedCall: 'Appel manqué',
    );
    expect(fr.callSupport, 'Appeler le support');
    expect(
      fr.formatCallTranscriptLine(outcome: 'completed', durationSeconds: 90),
      'Appel audio · 1:30',
    );
    expect(fr.formatCallTranscriptLine(outcome: 'missed'), 'Appel manqué');
  });
}
