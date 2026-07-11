import 'package:flutter/material.dart' show TextDirection;

/// Localizable UI strings for the chat package.
/// Pass a custom instance to [FrontFaceChatScreen] for i18n.
class FrontFaceChatStrings {
  final String online;
  final String newChat;
  final String retry;
  final String startNewChat;
  final String beforeWeChat;
  final String leadFormSubtitle;
  final String continueToChat;
  final String email;
  final String emailRequired;
  final String invalidEmail;
  final String requiredField;
  final String additionalInfo;
  final String waitingForAgent;
  final String waitingForAgentWithPosition;
  final String agentJoined;
  final String agentHereToHelp;
  final String conversationEnded;
  final String failedToLoadChat;
  final String failedToSendMessage;
  final String failedToSubmitForm;
  final String couldNotConnectAgent;
  final String chatUnavailable;
  final String typeMessage;
  final String talkToHuman;
  final String messageCopied;
  final String loadingChat;

  /// Unused by the SDK. Kept for backwards compatibility with apps that
  /// still pass a custom value. Session death is recovered silently via
  /// `ensure-conversation` — the user never sees an expiry message.
  final String sessionExpired;

  /// Overrides the chat title shown in the app bar. The title normally
  /// comes from the FrontFace dashboard (`config.title`) and is whatever
  /// language the project owner configured there — set this when you need
  /// a client-side translation instead of (or in addition to) the
  /// dashboard value. Leave `null` to use the dashboard's title as-is.
  final String? title;

  /// Text direction for the chat UI. Set to [TextDirection.rtl] for
  /// right-to-left locales (e.g. Arabic, Hebrew).
  final TextDirection textDirection;

  const FrontFaceChatStrings({
    this.online = 'Online',
    this.newChat = 'New chat',
    this.retry = 'Retry',
    this.startNewChat = 'Start new chat',
    this.beforeWeChat = 'Before we chat',
    this.leadFormSubtitle =
        'Please share your details so we can help you better.',
    this.continueToChat = 'Continue to chat',
    this.email = 'Email',
    this.emailRequired = 'Email is required',
    this.invalidEmail = 'Enter a valid email',
    this.requiredField = 'Required',
    this.additionalInfo = 'Additional info',
    this.waitingForAgent = 'Waiting for an agent...',
    this.waitingForAgentWithPosition =
        'Waiting for an agent (position {position})',
    this.agentJoined = 'An agent joined the chat',
    this.agentHereToHelp = '{name} is here to help',
    this.conversationEnded = 'Conversation ended',
    this.failedToLoadChat = 'Failed to load chat. Please try again.',
    this.failedToSendMessage = 'Failed to send message.',
    this.failedToSubmitForm = 'Failed to submit form.',
    this.couldNotConnectAgent = 'Could not connect you to an agent.',
    this.chatUnavailable = 'Chat is currently unavailable.',
    this.typeMessage = 'Type a message...',
    this.talkToHuman = 'Talk to a human',
    this.messageCopied = 'Copied to clipboard',
    this.loadingChat = 'Loading chat...',
    this.sessionExpired = 'Your session has expired. Please start again.',
    this.title,
    this.textDirection = TextDirection.ltr,
  });

  String agentHelp(String name) => agentHereToHelp.replaceAll('{name}', name);

  String waitingPosition(int position) =>
      waitingForAgentWithPosition.replaceAll('{position}', '$position');
}
