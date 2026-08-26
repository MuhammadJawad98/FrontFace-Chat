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
}
