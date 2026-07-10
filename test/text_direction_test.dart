import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/src/utils/text_direction.dart';

void main() {
  group('detectTextDirection — English', () {
    test('plain English sentence is ltr', () {
      expect(
        detectTextDirection('How do I reset my password?'),
        TextDirection.ltr,
      );
    });

    test('English sentence containing an Arabic word later stays ltr', () {
      expect(detectTextDirection('Say hello: مرحبا'), TextDirection.ltr);
    });

    test('URL is ltr', () {
      expect(
        detectTextDirection('https://example.com/path'),
        TextDirection.ltr,
      );
    });

    test('email address is ltr', () {
      expect(detectTextDirection('user@example.com'), TextDirection.ltr);
    });
  });

  group('detectTextDirection — Arabic', () {
    test('plain Arabic sentence is rtl', () {
      expect(
        detectTextDirection('مرحبا! كيف يمكنني مساعدتك اليوم؟'),
        TextDirection.rtl,
      );
    });

    test('Arabic sentence containing an English word later stays rtl', () {
      expect(
        detectTextDirection('أريد أن أبيع سيارتي Mazda'),
        TextDirection.rtl,
      );
    });

    test('Arabic sentence starting with punctuation then Arabic is rtl', () {
      expect(detectTextDirection('«مرحبا»'), TextDirection.rtl);
    });
  });

  group('detectTextDirection — neutral / edge cases', () {
    test('empty string defaults to ltr', () {
      expect(detectTextDirection(''), TextDirection.ltr);
    });

    test('whitespace-only defaults to ltr', () {
      expect(detectTextDirection('   \n\t '), TextDirection.ltr);
    });

    test('digits-only Western numerals default to ltr', () {
      expect(detectTextDirection('12345'), TextDirection.ltr);
    });

    test('punctuation-only defaults to ltr', () {
      expect(detectTextDirection('!!! ...'), TextDirection.ltr);
    });

    test('emoji-only defaults to ltr (no strong-direction letters)', () {
      expect(detectTextDirection('😀🎉👍'), TextDirection.ltr);
    });

    test('first strong character wins when Latin precedes Arabic', () {
      expect(detectTextDirection('Mazda مازدا'), TextDirection.ltr);
    });

    test('first strong character wins when Arabic precedes Latin', () {
      expect(detectTextDirection('مازدا Mazda'), TextDirection.rtl);
    });
  });
}
