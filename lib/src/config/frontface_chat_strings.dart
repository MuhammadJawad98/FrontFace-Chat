import 'package:flutter/material.dart' show TextDirection;

/// Localizable UI strings for the chat package.
///
/// Every user-visible label has an English default. Pass only the fields you
/// want to override — the rest keep their defaults. Use [copyWith] to tweak an
/// existing instance (e.g. switch language at runtime via
/// [FrontFaceChatProvider.updateStrings]).
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

  /// Overrides the dashboard label for lead-form field 2 (often "Phone Number").
  /// When `null`, the FrontFace dashboard label is used. Set this for i18n,
  /// e.g. English `Phone Number` or Arabic `رقم الهاتف`.
  final String? field2Label;

  /// Overrides the dashboard label for lead-form field 3. When `null`, the
  /// dashboard label is used.
  final String? field3Label;

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

  /// Label used for product detail CTAs in assistant Markdown
  /// (e.g. `[View Details](https://…)`). The model may emit "View Listings"
  /// on mobile and "View Details" on web — both are normalized to this
  /// string. Override for Arabic, e.g. `عرض التفاصيل`.
  final String viewDetails;

  final String ticketReferenceLabel;
  final String viewTicket;
  final String ticketFailed;
  final String csatTitle;
  final String csatSubmit;
  final String csatThanks;
  final String offlineTitle;
  final String offlineName;
  final String offlineMessage;
  final String offlineSubmit;
  final String offlineSuccess;

  // Attachments (optional features — still overridable when disabled)
  final String attach;
  final String shareLocation;
  final String sendLocation;
  final String sharedLocation;
  final String openInMaps;
  final String attachPhoto;
  final String takePhoto;
  final String attachVideo;
  final String recordVideo;
  final String attachAudio;
  final String recordVoice;
  final String startRecording;
  final String stopRecording;
  final String imageAttachment;
  final String audioAttachment;
  final String videoAttachment;
  final String transcriptPending;
  final String transcriptFailed;
  final String attachmentTooLarge;
  final String attachmentUnavailable;
  final String attachmentUploadFailed;
  final String locationPermissionDenied;
  final String locationServicesDisabled;
  final String locationUnavailable;
  final String permissionLocationTitle;
  final String permissionLocationBody;
  final String permissionCameraTitle;
  final String permissionCameraBody;
  final String permissionPhotosTitle;
  final String permissionPhotosBody;
  final String permissionVideosTitle;
  final String permissionVideosBody;
  final String permissionMicTitle;
  final String permissionMicBody;
  final String permissionContinue;
  final String permissionNotNow;
  final String permissionOpenSettingsBody;
  final String openSettings;

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
    this.field2Label,
    this.field3Label,
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
    this.viewDetails = 'View Details',
    this.ticketReferenceLabel = 'Reference',
    this.viewTicket = 'View ticket',
    this.ticketFailed = 'Could not create a support ticket.',
    this.csatTitle = 'How was your experience?',
    this.csatSubmit = 'Submit rating',
    this.csatThanks = 'Thanks for your feedback!',
    this.offlineTitle = 'Leave us a message',
    this.offlineName = 'Name',
    this.offlineMessage = 'Message',
    this.offlineSubmit = 'Send message',
    this.offlineSuccess = 'Message sent. We will get back to you soon.',
    this.attach = 'Attach',
    this.shareLocation = 'Share location',
    this.sendLocation = 'Send this location',
    this.sharedLocation = 'Shared location',
    this.openInMaps = 'Open in Maps',
    this.attachPhoto = 'Photo library',
    this.takePhoto = 'Take photo',
    this.attachVideo = 'Video library',
    this.recordVideo = 'Record video',
    this.attachAudio = 'Audio file',
    this.recordVoice = 'Record voice note',
    this.startRecording = 'Start recording',
    this.stopRecording = 'Send voice note',
    this.imageAttachment = 'Image',
    this.audioAttachment = 'Voice note',
    this.videoAttachment = 'Video attachment',
    this.transcriptPending = 'Transcribing…',
    this.transcriptFailed = 'Transcript unavailable',
    this.attachmentTooLarge = 'That file is too large to send.',
    this.attachmentUnavailable = 'Attachment unavailable',
    this.attachmentUploadFailed = 'Could not upload attachment. Try again.',
    this.locationPermissionDenied =
        'Location permission is required to share your position.',
    this.locationServicesDisabled =
        'Turn on Location Services to share your position.',
    this.locationUnavailable = 'Could not determine your location.',
    this.permissionLocationTitle = 'Location access',
    this.permissionLocationBody =
        'FrontFace needs your location so you can share it with support.',
    this.permissionCameraTitle = 'Camera access',
    this.permissionCameraBody =
        'FrontFace needs the camera to take a photo for support.',
    this.permissionPhotosTitle = 'Photo access',
    this.permissionPhotosBody =
        'FrontFace needs photo access so you can attach an image.',
    this.permissionVideosTitle = 'Video access',
    this.permissionVideosBody =
        'FrontFace needs video access so you can attach a clip.',
    this.permissionMicTitle = 'Microphone access',
    this.permissionMicBody =
        'FrontFace needs the microphone to record a voice note for support.',
    this.permissionContinue = 'Continue',
    this.permissionNotNow = 'Not now',
    this.permissionOpenSettingsBody =
        'Permission was denied. You can enable it in Settings.',
    this.openSettings = 'Open Settings',
    this.sessionExpired = 'Your session has expired. Please start again.',
    this.title,
    this.textDirection = TextDirection.ltr,
  });

  String agentHelp(String name) => agentHereToHelp.replaceAll('{name}', name);

  String waitingPosition(int position) =>
      waitingForAgentWithPosition.replaceAll('{position}', '$position');

  /// Returns a copy with only the provided fields replaced.
  ///
  /// Useful for partial translations or runtime language switches:
  /// ```dart
  /// provider.updateStrings(
  ///   strings.copyWith(attach: 'إرفاق', shareLocation: 'مشاركة الموقع'),
  /// );
  /// ```
  FrontFaceChatStrings copyWith({
    String? online,
    String? newChat,
    String? retry,
    String? startNewChat,
    String? beforeWeChat,
    String? leadFormSubtitle,
    String? continueToChat,
    String? email,
    String? emailRequired,
    String? invalidEmail,
    String? requiredField,
    String? additionalInfo,
    String? field2Label,
    String? field3Label,
    bool clearField2Label = false,
    bool clearField3Label = false,
    String? waitingForAgent,
    String? waitingForAgentWithPosition,
    String? agentJoined,
    String? agentHereToHelp,
    String? conversationEnded,
    String? failedToLoadChat,
    String? failedToSendMessage,
    String? failedToSubmitForm,
    String? couldNotConnectAgent,
    String? chatUnavailable,
    String? typeMessage,
    String? talkToHuman,
    String? messageCopied,
    String? loadingChat,
    String? viewDetails,
    String? ticketReferenceLabel,
    String? viewTicket,
    String? ticketFailed,
    String? csatTitle,
    String? csatSubmit,
    String? csatThanks,
    String? offlineTitle,
    String? offlineName,
    String? offlineMessage,
    String? offlineSubmit,
    String? offlineSuccess,
    String? attach,
    String? shareLocation,
    String? sendLocation,
    String? sharedLocation,
    String? openInMaps,
    String? attachPhoto,
    String? takePhoto,
    String? attachVideo,
    String? recordVideo,
    String? attachAudio,
    String? recordVoice,
    String? startRecording,
    String? stopRecording,
    String? imageAttachment,
    String? audioAttachment,
    String? videoAttachment,
    String? transcriptPending,
    String? transcriptFailed,
    String? attachmentTooLarge,
    String? attachmentUnavailable,
    String? attachmentUploadFailed,
    String? locationPermissionDenied,
    String? locationServicesDisabled,
    String? locationUnavailable,
    String? permissionLocationTitle,
    String? permissionLocationBody,
    String? permissionCameraTitle,
    String? permissionCameraBody,
    String? permissionPhotosTitle,
    String? permissionPhotosBody,
    String? permissionVideosTitle,
    String? permissionVideosBody,
    String? permissionMicTitle,
    String? permissionMicBody,
    String? permissionContinue,
    String? permissionNotNow,
    String? permissionOpenSettingsBody,
    String? openSettings,
    String? sessionExpired,
    String? title,
    bool clearTitle = false,
    TextDirection? textDirection,
  }) {
    return FrontFaceChatStrings(
      online: online ?? this.online,
      newChat: newChat ?? this.newChat,
      retry: retry ?? this.retry,
      startNewChat: startNewChat ?? this.startNewChat,
      beforeWeChat: beforeWeChat ?? this.beforeWeChat,
      leadFormSubtitle: leadFormSubtitle ?? this.leadFormSubtitle,
      continueToChat: continueToChat ?? this.continueToChat,
      email: email ?? this.email,
      emailRequired: emailRequired ?? this.emailRequired,
      invalidEmail: invalidEmail ?? this.invalidEmail,
      requiredField: requiredField ?? this.requiredField,
      additionalInfo: additionalInfo ?? this.additionalInfo,
      field2Label: clearField2Label ? null : (field2Label ?? this.field2Label),
      field3Label: clearField3Label ? null : (field3Label ?? this.field3Label),
      waitingForAgent: waitingForAgent ?? this.waitingForAgent,
      waitingForAgentWithPosition:
          waitingForAgentWithPosition ?? this.waitingForAgentWithPosition,
      agentJoined: agentJoined ?? this.agentJoined,
      agentHereToHelp: agentHereToHelp ?? this.agentHereToHelp,
      conversationEnded: conversationEnded ?? this.conversationEnded,
      failedToLoadChat: failedToLoadChat ?? this.failedToLoadChat,
      failedToSendMessage: failedToSendMessage ?? this.failedToSendMessage,
      failedToSubmitForm: failedToSubmitForm ?? this.failedToSubmitForm,
      couldNotConnectAgent: couldNotConnectAgent ?? this.couldNotConnectAgent,
      chatUnavailable: chatUnavailable ?? this.chatUnavailable,
      typeMessage: typeMessage ?? this.typeMessage,
      talkToHuman: talkToHuman ?? this.talkToHuman,
      messageCopied: messageCopied ?? this.messageCopied,
      loadingChat: loadingChat ?? this.loadingChat,
      viewDetails: viewDetails ?? this.viewDetails,
      ticketReferenceLabel: ticketReferenceLabel ?? this.ticketReferenceLabel,
      viewTicket: viewTicket ?? this.viewTicket,
      ticketFailed: ticketFailed ?? this.ticketFailed,
      csatTitle: csatTitle ?? this.csatTitle,
      csatSubmit: csatSubmit ?? this.csatSubmit,
      csatThanks: csatThanks ?? this.csatThanks,
      offlineTitle: offlineTitle ?? this.offlineTitle,
      offlineName: offlineName ?? this.offlineName,
      offlineMessage: offlineMessage ?? this.offlineMessage,
      offlineSubmit: offlineSubmit ?? this.offlineSubmit,
      offlineSuccess: offlineSuccess ?? this.offlineSuccess,
      attach: attach ?? this.attach,
      shareLocation: shareLocation ?? this.shareLocation,
      sendLocation: sendLocation ?? this.sendLocation,
      sharedLocation: sharedLocation ?? this.sharedLocation,
      openInMaps: openInMaps ?? this.openInMaps,
      attachPhoto: attachPhoto ?? this.attachPhoto,
      takePhoto: takePhoto ?? this.takePhoto,
      attachVideo: attachVideo ?? this.attachVideo,
      recordVideo: recordVideo ?? this.recordVideo,
      attachAudio: attachAudio ?? this.attachAudio,
      recordVoice: recordVoice ?? this.recordVoice,
      startRecording: startRecording ?? this.startRecording,
      stopRecording: stopRecording ?? this.stopRecording,
      imageAttachment: imageAttachment ?? this.imageAttachment,
      audioAttachment: audioAttachment ?? this.audioAttachment,
      videoAttachment: videoAttachment ?? this.videoAttachment,
      transcriptPending: transcriptPending ?? this.transcriptPending,
      transcriptFailed: transcriptFailed ?? this.transcriptFailed,
      attachmentTooLarge: attachmentTooLarge ?? this.attachmentTooLarge,
      attachmentUnavailable:
          attachmentUnavailable ?? this.attachmentUnavailable,
      attachmentUploadFailed:
          attachmentUploadFailed ?? this.attachmentUploadFailed,
      locationPermissionDenied:
          locationPermissionDenied ?? this.locationPermissionDenied,
      locationServicesDisabled:
          locationServicesDisabled ?? this.locationServicesDisabled,
      locationUnavailable: locationUnavailable ?? this.locationUnavailable,
      permissionLocationTitle:
          permissionLocationTitle ?? this.permissionLocationTitle,
      permissionLocationBody:
          permissionLocationBody ?? this.permissionLocationBody,
      permissionCameraTitle:
          permissionCameraTitle ?? this.permissionCameraTitle,
      permissionCameraBody: permissionCameraBody ?? this.permissionCameraBody,
      permissionPhotosTitle:
          permissionPhotosTitle ?? this.permissionPhotosTitle,
      permissionPhotosBody: permissionPhotosBody ?? this.permissionPhotosBody,
      permissionVideosTitle:
          permissionVideosTitle ?? this.permissionVideosTitle,
      permissionVideosBody: permissionVideosBody ?? this.permissionVideosBody,
      permissionMicTitle: permissionMicTitle ?? this.permissionMicTitle,
      permissionMicBody: permissionMicBody ?? this.permissionMicBody,
      permissionContinue: permissionContinue ?? this.permissionContinue,
      permissionNotNow: permissionNotNow ?? this.permissionNotNow,
      permissionOpenSettingsBody:
          permissionOpenSettingsBody ?? this.permissionOpenSettingsBody,
      openSettings: openSettings ?? this.openSettings,
      sessionExpired: sessionExpired ?? this.sessionExpired,
      title: clearTitle ? null : (title ?? this.title),
      textDirection: textDirection ?? this.textDirection,
    );
  }
}
