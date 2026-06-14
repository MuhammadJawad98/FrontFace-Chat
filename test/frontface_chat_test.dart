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

  test('FrontFaceChatTheme copyWith overrides colors', () {
    const theme = FrontFaceChatTheme();
    final updated = theme.copyWith(primaryColor: const Color(0xFF123456));
    expect(updated.primaryColor, const Color(0xFF123456));
    expect(updated.backgroundColor, theme.backgroundColor);
  });
}
