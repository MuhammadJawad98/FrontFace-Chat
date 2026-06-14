enum FrontFaceSenderType { customer, agent, ai, system }

enum FrontFaceConversationStatus {
  aiActive,
  waiting,
  agentActive,
  resolved,
  closed,
}

enum FrontFaceLeadCaptureMode { emailAfter, emailFirst, emailRequired }

class FrontFaceChatMessage {
  final String id;
  final String content;
  final FrontFaceSenderType senderType;
  final String? senderName;
  final DateTime createdAt;

  const FrontFaceChatMessage({
    required this.id,
    required this.content,
    required this.senderType,
    this.senderName,
    required this.createdAt,
  });

  bool get isVisitor => senderType == FrontFaceSenderType.customer;

  factory FrontFaceChatMessage.fromJson(Map<String, dynamic> json) {
    return FrontFaceChatMessage(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      content: json['content']?.toString() ?? '',
      senderType: _parseSenderType(json['senderType']?.toString()),
      senderName: json['senderName']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  factory FrontFaceChatMessage.local({
    required String content,
    required FrontFaceSenderType senderType,
    String? senderName,
  }) {
    return FrontFaceChatMessage(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      content: content,
      senderType: senderType,
      senderName: senderName,
      createdAt: DateTime.now(),
    );
  }

  static FrontFaceSenderType _parseSenderType(String? value) {
    switch (value) {
      case 'customer':
        return FrontFaceSenderType.customer;
      case 'agent':
        return FrontFaceSenderType.agent;
      case 'system':
        return FrontFaceSenderType.system;
      default:
        return FrontFaceSenderType.ai;
    }
  }
}

class FrontFaceEmbedConfig {
  final bool enabled;
  final String title;
  final String greeting;
  final String greetingIntro;
  final String placeholder;
  final String primaryColor;
  final bool leadCaptureEnabled;
  final FrontFaceLeadCaptureMode? leadCaptureMode;
  final bool emailRequired;
  final String? field2Label;
  final bool field2Enabled;
  final bool field2Required;
  final String? field3Label;
  final bool field3Enabled;
  final bool field3Required;

  const FrontFaceEmbedConfig({
    this.enabled = true,
    this.title = 'Chat with us',
    this.greeting = 'Hi! How can I help you today?',
    this.greetingIntro = '',
    this.placeholder = 'Type a message...',
    this.primaryColor = '#0a0a0a',
    this.leadCaptureEnabled = false,
    this.leadCaptureMode,
    this.emailRequired = true,
    this.field2Label,
    this.field2Enabled = false,
    this.field2Required = false,
    this.field3Label,
    this.field3Enabled = false,
    this.field3Required = false,
  });

  factory FrontFaceEmbedConfig.fromJson(Map<String, dynamic> json) {
    final config = json['config'] as Map<String, dynamic>? ?? {};
    final leadCapture = json['leadCapture'] as Map<String, dynamic>? ?? {};
    final formFields = leadCapture['formFields'] as Map<String, dynamic>? ?? {};
    final field2 = formFields['field_2'] as Map<String, dynamic>? ?? {};
    final field3 = formFields['field_3'] as Map<String, dynamic>? ?? {};
    final emailField = formFields['email'] as Map<String, dynamic>? ?? {};

    return FrontFaceEmbedConfig(
      enabled: json['enabled'] as bool? ?? true,
      title: config['title']?.toString() ?? 'Chat with us',
      greeting: config['greeting']?.toString() ?? 'Hi! How can I help you today?',
      greetingIntro: config['greetingIntro']?.toString() ?? '',
      placeholder: config['placeholder']?.toString() ?? 'Type a message...',
      primaryColor: config['primaryColor']?.toString() ?? '#0a0a0a',
      leadCaptureEnabled: leadCapture['enabled'] as bool? ?? false,
      leadCaptureMode: _parseLeadCaptureMode(
        leadCapture['capture_mode']?.toString(),
      ),
      emailRequired: emailField['required'] as bool? ?? true,
      field2Label: field2['label']?.toString(),
      field2Enabled: field2['enabled'] as bool? ?? false,
      field2Required: field2['required'] as bool? ?? false,
      field3Label: field3['label']?.toString(),
      field3Enabled: field3['enabled'] as bool? ?? false,
      field3Required: field3['required'] as bool? ?? false,
    );
  }

  static FrontFaceLeadCaptureMode? _parseLeadCaptureMode(String? value) {
    switch (value) {
      case 'email_after':
        return FrontFaceLeadCaptureMode.emailAfter;
      case 'email_first':
        return FrontFaceLeadCaptureMode.emailFirst;
      case 'email_required':
        return FrontFaceLeadCaptureMode.emailRequired;
      default:
        return null;
    }
  }
}

class FrontFaceHandoffAvailability {
  final bool available;
  final bool showButton;
  final String buttonText;

  const FrontFaceHandoffAvailability({
    this.available = false,
    this.showButton = false,
    this.buttonText = 'Talk to a human',
  });

  factory FrontFaceHandoffAvailability.fromJson(Map<String, dynamic> json) {
    return FrontFaceHandoffAvailability(
      available: json['available'] as bool? ?? false,
      showButton: json['showButton'] as bool? ?? false,
      buttonText: json['buttonText']?.toString() ?? 'Talk to a human',
    );
  }
}

class FrontFaceApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final int? retryAfter;

  const FrontFaceApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  @override
  String toString() => message;
}
