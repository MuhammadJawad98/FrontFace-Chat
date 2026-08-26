import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';

void main() {
  test('FrontFaceChatConfig holds credentials', () {
    const config = FrontFaceChatConfig(
      projectId: 'test-project-id',
      publishableKey: 'pk_test',
    );

    expect(config.projectId, 'test-project-id');
    expect(config.publishableKey, 'pk_test');
    expect(config.baseUrl, 'https://api.frontface.app');
    expect(config.showNewChatButton, isTrue);
  });

  test('FrontFaceChatConfig can hide new-chat button', () {
    const config = FrontFaceChatConfig(
      projectId: 'test-project-id',
      publishableKey: 'pk_test',
      showNewChatButton: false,
    );
    expect(config.showNewChatButton, isFalse);
  });

  test('FrontFaceChatStrings supports placeholders', () {
    const strings = FrontFaceChatStrings();
    expect(strings.agentHelp('Alex'), 'Alex is here to help');
    expect(strings.waitingPosition(3), 'Waiting for an agent (position 3)');
  });

  group('FrontFaceChatStrings — English defaults', () {
    const strings = FrontFaceChatStrings();

    test('defaults to ltr', () {
      expect(strings.textDirection, TextDirection.ltr);
    });

    test('has English fallback copy for server-omitted fields', () {
      expect(strings.typeMessage, 'Type a message...');
      expect(strings.talkToHuman, 'Talk to a human');
      expect(strings.loadingChat, 'Loading chat...');
      expect(strings.messageCopied, 'Copied to clipboard');
      expect(
        strings.sessionExpired,
        'Your session has expired. Please start again.',
      );
    });
  });

  test(
    'FrontFaceChatConfig requireLeadCaptureBeforeChat defaults to true',
    () {
      const config = FrontFaceChatConfig(
        projectId: 'test-project-id',
        publishableKey: 'pk_test',
      );
      expect(config.requireLeadCaptureBeforeChat, isTrue);
    },
  );

  group('FrontFaceChatStrings — Arabic overrides', () {
    const strings = FrontFaceChatStrings.arabic;

    test('is rtl', () {
      expect(strings.textDirection, TextDirection.rtl);
    });

    test('overrides every localizable fallback string', () {
      expect(strings.typeMessage, 'اكتب رسالة...');
      expect(strings.talkToHuman, 'تحدث مع شخص');
      expect(strings.loadingChat, 'جارٍ تحميل المحادثة...');
      expect(strings.messageCopied, 'تم النسخ إلى الحافظة');
    });

    test('placeholder substitution works with Arabic templates', () {
      expect(strings.agentHelp('سارة'), 'سارة هنا لمساعدتك');
      expect(strings.waitingPosition(2), 'بانتظار وكيل (الترتيب 2)');
    });
  });

  test('FrontFaceChatTheme copyWith overrides colors', () {
    const theme = FrontFaceChatTheme();
    final updated = theme.copyWith(
      primaryColor: const Color(0xFF123456),
      userBubbleColor: const Color(0xFF2563EB),
      userBubbleTextColor: Colors.white,
      assistantBubbleColor: const Color(0xFFEFF6FF),
      assistantBubbleTextColor: const Color(0xFF1E3A8A),
    );
    expect(updated.primaryColor, const Color(0xFF123456));
    expect(updated.userBubbleColor, const Color(0xFF2563EB));
    expect(updated.userBubbleTextColor, Colors.white);
    expect(updated.assistantBubbleColor, const Color(0xFFEFF6FF));
    expect(updated.assistantBubbleTextColor, const Color(0xFF1E3A8A));
    expect(updated.backgroundColor, theme.backgroundColor);
  });

  test('FrontFaceChatTheme uses Arabic font family for RTL', () {
    const theme = FrontFaceChatTheme();
    expect(theme.arabicFontFamily, kFrontFaceArabicFontFamily);
    expect(
      theme.resolvedFontFamily(TextDirection.rtl),
      kFrontFaceArabicFontFamily,
    );
    expect(theme.resolvedFontFamily(TextDirection.ltr), isNull);
    expect(
      theme.textStyle(TextDirection.rtl, fontSize: 14).fontFamily,
      kFrontFaceArabicFontFamily,
    );
  });
}
