enum FrontFaceSenderType { customer, agent, ai, system }

enum FrontFaceConversationStatus {
  aiActive,
  waiting,
  agentActive,
  resolved,
  closed,
}

enum FrontFaceLeadCaptureMode { emailAfter, emailFirst, emailRequired }

/// Handoff availability mode from `GET .../handoff-availability`.
enum FrontFaceHandoffMode { live, ticket, unavailable }

/// Ticket action status from chat/handoff responses (§5.1).
enum FrontFaceTicketStatus {
  created,
  existingTicketReused,
  contactRequired,
  failed,
}

class FrontFaceMessageMetadata {
  final Map<String, dynamic> raw;

  const FrontFaceMessageMetadata(this.raw);

  factory FrontFaceMessageMetadata.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const FrontFaceMessageMetadata({});
    return FrontFaceMessageMetadata(Map<String, dynamic>.from(json));
  }

  bool get isEmpty => raw.isEmpty;

  bool get isCsatPrompt => raw['csat_prompt'] == true;

  String? get ticketReference => raw['ticket_reference']?.toString();

  String? get event => raw['event']?.toString();

  bool get isInactivityWarning => event == 'inactivity_warning';

  bool get isAutoClosed => event == 'auto_closed';

  Map<String, dynamic>? get ticketCard {
    final card = raw['ticket'];
    if (card is Map) return Map<String, dynamic>.from(card);
    if (ticketReference != null) {
      return {
        'reference': ticketReference,
        if (raw['subject'] != null) 'subject': raw['subject'],
        if (raw['accessUrl'] != null) 'accessUrl': raw['accessUrl'],
      };
    }
    return null;
  }
}

class FrontFaceChatMessage {
  final String id;
  final String content;
  final FrontFaceSenderType senderType;
  final String? senderName;
  final DateTime createdAt;
  final FrontFaceMessageMetadata metadata;

  const FrontFaceChatMessage({
    required this.id,
    required this.content,
    required this.senderType,
    this.senderName,
    required this.createdAt,
    this.metadata = const FrontFaceMessageMetadata({}),
  });

  bool get isVisitor => senderType == FrontFaceSenderType.customer;

  bool get hasTicketCard => metadata.ticketCard != null;

  bool get isCsatPrompt => metadata.isCsatPrompt;

  factory FrontFaceChatMessage.fromJson(Map<String, dynamic> json) {
    final content = json['content']?.toString() ?? '';
    final senderType = _parseSenderType(json['senderType']?.toString());
    final createdAt =
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now();
    final rawId = json['id']?.toString();
    final id = (rawId != null && rawId.isNotEmpty)
        ? rawId
        : 'srv_${senderType.name}_${createdAt.toUtc().toIso8601String()}_${content.hashCode}';

    return FrontFaceChatMessage(
      id: id,
      content: content,
      senderType: senderType,
      senderName: json['senderName']?.toString(),
      createdAt: createdAt,
      metadata: FrontFaceMessageMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>?,
      ),
    );
  }

  factory FrontFaceChatMessage.local({
    required String content,
    required FrontFaceSenderType senderType,
    String? senderName,
    String? id,
    FrontFaceMessageMetadata metadata = const FrontFaceMessageMetadata({}),
  }) {
    return FrontFaceChatMessage(
      id: id ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
      content: content,
      senderType: senderType,
      senderName: senderName,
      createdAt: DateTime.now(),
      metadata: metadata,
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

class FrontFaceChannelButton {
  final String type;
  final String url;
  final String? label;
  final String? iconUrl;

  const FrontFaceChannelButton({
    required this.type,
    required this.url,
    this.label,
    this.iconUrl,
  });

  String get displayLabel {
    if (label != null && label!.trim().isNotEmpty) return label!.trim();
    switch (type) {
      case 'whatsapp':
        return 'WhatsApp';
      case 'instagram':
        return 'Instagram';
      case 'facebook':
        return 'Facebook';
      case 'email':
        return 'Email';
      case 'phone':
        return 'Phone';
      default:
        return type;
    }
  }

  factory FrontFaceChannelButton.fromJson(Map<String, dynamic> json) {
    return FrontFaceChannelButton(
      type: json['type']?.toString() ?? 'custom',
      url: json['url']?.toString() ?? '',
      label: json['label']?.toString(),
      iconUrl: json['iconUrl']?.toString(),
    );
  }
}

class FrontFaceEmbedNotice {
  final bool enabled;
  final String text;

  const FrontFaceEmbedNotice({this.enabled = false, this.text = ''});

  factory FrontFaceEmbedNotice.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FrontFaceEmbedNotice();
    return FrontFaceEmbedNotice(
      enabled: json['enabled'] as bool? ?? false,
      text: json['text']?.toString() ?? '',
    );
  }
}

/// Supabase Realtime settings from bootstrap `GET /api/embed/config/{projectId}`.
class FrontFaceRealtimeConfig {
  final bool enabled;
  final String supabaseUrl;
  final String apiKey;
  final bool tokenBased;

  const FrontFaceRealtimeConfig({
    this.enabled = false,
    this.supabaseUrl = '',
    this.apiKey = '',
    this.tokenBased = true,
  });

  bool get canConnect =>
      enabled && supabaseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  factory FrontFaceRealtimeConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FrontFaceRealtimeConfig();
    return FrontFaceRealtimeConfig(
      enabled: json['enabled'] as bool? ?? false,
      supabaseUrl: json['supabaseUrl']?.toString() ?? '',
      apiKey: json['apiKey']?.toString() ??
          json['supabaseAnonKey']?.toString() ??
          '',
      tokenBased: json['tokenBased'] as bool? ?? true,
    );
  }
}

class FrontFaceEmbedConfig {
  final bool enabled;
  final String title;
  final String greeting;
  final String greetingIntro;
  final String placeholder;
  final String primaryColor;
  final String? avatarUrl;
  final String? bubbleColor;
  final List<String> starters;
  final FrontFaceEmbedNotice notice;
  final List<FrontFaceChannelButton> channels;
  final bool feedbackEnabled;
  final bool copyEnabled;
  final bool hideBranding;
  final String localeDefault;
  final bool leadCaptureEnabled;
  final FrontFaceLeadCaptureMode? leadCaptureMode;
  final bool emailRequired;
  final String? field2Label;
  final bool field2Enabled;
  final bool field2Required;
  final String? field3Label;
  final bool field3Enabled;
  final bool field3Required;
  final FrontFaceRealtimeConfig realtime;

  const FrontFaceEmbedConfig({
    this.enabled = true,
    this.title = 'Chat with us',
    this.greeting = 'Hi! How can I help you today?',
    this.greetingIntro = '',
    this.placeholder = '',
    this.primaryColor = '#0a0a0a',
    this.avatarUrl,
    this.bubbleColor,
    this.starters = const [],
    this.notice = const FrontFaceEmbedNotice(),
    this.channels = const [],
    this.feedbackEnabled = false,
    this.copyEnabled = true,
    this.hideBranding = false,
    this.localeDefault = 'en',
    this.leadCaptureEnabled = false,
    this.leadCaptureMode,
    this.emailRequired = true,
    this.field2Label,
    this.field2Enabled = false,
    this.field2Required = false,
    this.field3Label,
    this.field3Enabled = false,
    this.field3Required = false,
    this.realtime = const FrontFaceRealtimeConfig(),
  });

  factory FrontFaceEmbedConfig.fromJson(Map<String, dynamic> json) {
    final config = json['config'] as Map<String, dynamic>? ?? {};
    final leadCapture = json['leadCapture'] as Map<String, dynamic>? ?? {};
    final formFields = leadCapture['formFields'] as Map<String, dynamic>? ?? {};
    final field2 = formFields['field_2'] as Map<String, dynamic>? ?? {};
    final field3 = formFields['field_3'] as Map<String, dynamic>? ?? {};
    final emailField = formFields['email'] as Map<String, dynamic>? ?? {};
    final realtime = json['realtime'] as Map<String, dynamic>?;
    final channelsRaw = config['channels'] as List<dynamic>? ?? [];
    final startersRaw = config['starters'] as List<dynamic>? ?? [];

    return FrontFaceEmbedConfig(
      enabled: json['enabled'] as bool? ?? true,
      title: config['title']?.toString() ?? 'Chat with us',
      greeting:
          config['greeting']?.toString() ?? 'Hi! How can I help you today?',
      greetingIntro: config['greetingIntro']?.toString() ?? '',
      placeholder: config['placeholder']?.toString() ?? '',
      primaryColor: config['primaryColor']?.toString() ?? '#0a0a0a',
      avatarUrl: config['avatarUrl']?.toString(),
      bubbleColor: config['bubbleColor']?.toString(),
      starters: startersRaw.map((e) => e.toString()).toList(),
      notice: FrontFaceEmbedNotice.fromJson(
        config['notice'] as Map<String, dynamic>?,
      ),
      channels: channelsRaw
          .whereType<Map>()
          .map((e) => FrontFaceChannelButton.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .where((c) => c.url.isNotEmpty)
          .toList(),
      feedbackEnabled: config['feedbackEnabled'] as bool? ?? false,
      copyEnabled: config['copyEnabled'] as bool? ?? true,
      hideBranding: config['hideBranding'] as bool? ?? false,
      localeDefault: config['localeDefault']?.toString() ?? 'en',
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
      realtime: FrontFaceRealtimeConfig.fromJson(realtime),
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
  final FrontFaceHandoffMode? mode;
  final bool showOfflineForm;
  final String? reason;

  const FrontFaceHandoffAvailability({
    this.available = false,
    this.showButton = false,
    this.buttonText = '',
    this.mode,
    this.showOfflineForm = false,
    this.reason,
  });

  /// Standing "Talk to a human" button — only when `mode == live` and
  /// `showButton == true` (AI-driven escalation change, 2026-08-07).
  bool get showLiveHandoffButton =>
      mode == FrontFaceHandoffMode.live && showButton;

  factory FrontFaceHandoffAvailability.fromJson(Map<String, dynamic> json) {
    return FrontFaceHandoffAvailability(
      available: json['available'] as bool? ?? false,
      showButton: json['showButton'] as bool? ?? false,
      buttonText: json['buttonText']?.toString() ?? '',
      mode: _parseMode(json['mode']?.toString()),
      showOfflineForm: json['showOfflineForm'] as bool? ?? false,
      reason: json['reason']?.toString(),
    );
  }

  static FrontFaceHandoffMode? _parseMode(String? value) {
    switch (value) {
      case 'live':
        return FrontFaceHandoffMode.live;
      case 'ticket':
        return FrontFaceHandoffMode.ticket;
      case 'unavailable':
        return FrontFaceHandoffMode.unavailable;
      default:
        return null;
    }
  }
}

class FrontFaceTicketAction {
  final FrontFaceTicketStatus status;
  final String? ticketId;
  final String? reference;
  final String? subject;
  final String? accessUrl;
  final String? intentId;
  final List<String> allowedFields;
  final String? message;

  const FrontFaceTicketAction({
    required this.status,
    this.ticketId,
    this.reference,
    this.subject,
    this.accessUrl,
    this.intentId,
    this.allowedFields = const [],
    this.message,
  });

  bool get isCommitted =>
      status == FrontFaceTicketStatus.created ||
      status == FrontFaceTicketStatus.existingTicketReused;

  factory FrontFaceTicketAction.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      throw const FormatException('empty ticket');
    }
    final statusRaw = json['status']?.toString() ?? '';
    final status = switch (statusRaw) {
      'created' => FrontFaceTicketStatus.created,
      'existing_ticket_reused' => FrontFaceTicketStatus.existingTicketReused,
      'contact_required' => FrontFaceTicketStatus.contactRequired,
      'failed' => FrontFaceTicketStatus.failed,
      _ => throw FormatException('unknown ticket status: $statusRaw'),
    };
    final allowed = json['allowedFields'];
    return FrontFaceTicketAction(
      status: status,
      ticketId: json['ticketId']?.toString(),
      reference: json['reference']?.toString(),
      subject: json['subject']?.toString(),
      accessUrl: json['accessUrl']?.toString(),
      intentId: json['intentId']?.toString(),
      allowedFields: allowed is List
          ? allowed.map((e) => e.toString()).toList()
          : const [],
      message: json['message']?.toString(),
    );
  }

  static FrontFaceTicketAction? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return FrontFaceTicketAction.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  FrontFaceMessageMetadata toMessageMetadata() {
    if (!isCommitted) return const FrontFaceMessageMetadata({});
    return FrontFaceMessageMetadata({
      'ticket_reference': reference,
      'subject': subject,
      'accessUrl': accessUrl,
      'ticket': {
        'reference': reference,
        'subject': subject,
        'accessUrl': accessUrl,
        'ticketId': ticketId,
      },
    });
  }
}

class FrontFaceIdentifyResult {
  final Map<String, dynamic>? contact;
  final Map<String, dynamic>? verifiedIdentity;
  final List<String> warnings;

  const FrontFaceIdentifyResult({
    this.contact,
    this.verifiedIdentity,
    this.warnings = const [],
  });

  factory FrontFaceIdentifyResult.fromJson(Map<String, dynamic> json) {
    final warningsRaw = json['warnings'];
    return FrontFaceIdentifyResult(
      contact: json['contact'] as Map<String, dynamic>?,
      verifiedIdentity: json['verifiedIdentity'] as Map<String, dynamic>?,
      warnings: warningsRaw is List
          ? warningsRaw.map((e) => e.toString()).toList()
          : const [],
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

/// Thrown when `POST /api/customers/identify` fails.
class FrontFaceIdentifyException implements Exception {
  final String code;
  final String message;

  const FrontFaceIdentifyException({required this.code, required this.message});

  @override
  String toString() => message;
}
