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
    });
  });

  group('FrontFaceChatStrings — Arabic overrides', () {
    const strings = FrontFaceChatStrings(
      textDirection: TextDirection.rtl,
      typeMessage: 'اكتب رسالة...',
      talkToHuman: 'تحدث مع شخص',
      loadingChat: 'جارٍ تحميل المحادثة...',
      messageCopied: 'تم النسخ',
      agentHereToHelp: '{name} هنا لمساعدتك',
      waitingForAgentWithPosition: 'في انتظار وكيل (الترتيب {position})',
    );

    test('is rtl', () {
      expect(strings.textDirection, TextDirection.rtl);
    });

    test('overrides every localizable fallback string', () {
      expect(strings.typeMessage, 'اكتب رسالة...');
      expect(strings.talkToHuman, 'تحدث مع شخص');
      expect(strings.loadingChat, 'جارٍ تحميل المحادثة...');
      expect(strings.messageCopied, 'تم النسخ');
    });

    test('placeholder substitution works with Arabic templates', () {
      expect(strings.agentHelp('سارة'), 'سارة هنا لمساعدتك');
      expect(strings.waitingPosition(2), 'في انتظار وكيل (الترتيب 2)');
    });
  });

  test('FrontFaceChatTheme copyWith overrides colors', () {
    const theme = FrontFaceChatTheme();
    final updated = theme.copyWith(primaryColor: const Color(0xFF123456));
    expect(updated.primaryColor, const Color(0xFF123456));
    expect(updated.backgroundColor, theme.backgroundColor);
  });
}
