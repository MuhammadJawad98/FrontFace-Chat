import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';

void main() {
  test('copyWith overrides only provided fields', () {
    const base = FrontFaceChatStrings();
    final updated = base.copyWith(
      attach: 'إرفاق',
      shareLocation: 'مشاركة الموقع',
      textDirection: TextDirection.rtl,
    );

    expect(updated.attach, 'إرفاق');
    expect(updated.shareLocation, 'مشاركة الموقع');
    expect(updated.textDirection, TextDirection.rtl);
    // Untouched fields keep English defaults
    expect(updated.takePhoto, 'Take photo');
    expect(updated.online, 'Online');
  });
}
