import 'package:flutter/material.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const ExampleApp());
}

enum ExampleLanguage { english, arabic }

FrontFaceChatStrings get _englishStrings => FrontFaceChatStrings.english.copyWith(
      field2Label: 'Phone Number',
    );

FrontFaceChatStrings get _arabicStrings => FrontFaceChatStrings.arabic;

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FrontFace Chat Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _projectIdController = TextEditingController();
  final _publishableKeyController = TextEditingController();
  final _mapsKeyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _debugStatus;
  ExampleLanguage _language = ExampleLanguage.english;

  FrontFaceChatStrings get _strings => switch (_language) {
        ExampleLanguage.english => _englishStrings,
        ExampleLanguage.arabic => _arabicStrings,
      };

  bool get _isArabic => _language == ExampleLanguage.arabic;

  @override
  void dispose() {
    _projectIdController.dispose();
    _publishableKeyController.dispose();
    _mapsKeyController.dispose();
    super.dispose();
  }

  FrontFaceChatConfig? _buildConfig() {
    if (!_formKey.currentState!.validate()) return null;
    final mapsKey = _mapsKeyController.text.trim();
    final hasMapsKey =
        mapsKey.isNotEmpty && mapsKey != 'YOUR_GOOGLE_MAPS_API_KEY';
    return FrontFaceChatConfig(
      projectId: _projectIdController.text.trim(),
      publishableKey: _publishableKeyController.text.trim(),
      // Attachments are off by default in the SDK — enable them here for demos.
      // Maps key is optional: with a key → map picker; without → GPS share only.
      attachments: FrontFaceAttachmentsConfig(
        enableLocation: true,
        enableImages: true,
        enableAudio: true,
        googleMapsApiKey: hasMapsKey ? mapsKey : null,
      ),
    );
  }

  Future<void> _openChat({FrontFaceChatTheme? theme}) async {
    final config = _buildConfig();
    if (config == null || !mounted) return;

    // Custom route so the example can switch language while chat is open
    // via FrontFaceChatProvider.updateStrings().
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => ChangeNotifierProvider(
          create: (_) => FrontFaceChat.createProvider(
            config: config,
            strings: _strings,
          ),
          child: _ExampleChatHost(
            theme: theme ?? const FrontFaceChatTheme(),
            initialLanguage: _language,
          ),
        ),
      ),
    );
  }

  Future<void> _corruptSessionToken() async {
    if (!_formKey.currentState!.validate()) return;
    final projectId = _projectIdController.text.trim();
    final corrupted =
        await FrontFaceChat.debugCorruptSessionToken(projectId);
    if (!mounted) return;
    setState(() {
      _debugStatus = corrupted
          ? (_isArabic
              ? 'تم إفساد رمز الجلسة. افتح المحادثة — يجب أن تظهر '
                  'نموذج البيانات أولاً بدون تحية، وبعد الإرسال تُنشأ '
                  'جلسة جديدة مع تحية من الـ API.'
              : 'Session token corrupted. Open chat — you should see the lead '
                  'form (chat cleared, no greeting yet). After submit, a new '
                  'session is created and the API greeting appears.')
          : (_isArabic
              ? 'لا يوجد رمز جلسة بعد. افتح المحادثة وأكمل النموذج أو '
                  'أرسل رسالة أولاً، ثم أغلق المحادثة وحاول مرة أخرى.'
              : 'No stored session token yet. Open chat, complete the lead '
                  'form / send a message first, close chat, then try again.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isArabic ? 'مثال FrontFace Chat' : 'FrontFace Chat Example'),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  _isArabic
                      ? 'أدخل بيانات Mobile SDK من لوحة FrontFace، ثم افتح المحادثة.'
                      : 'Enter your Mobile SDK credentials from the FrontFace dashboard, then open chat.',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                Text(
                  _isArabic ? 'اللغة' : 'Language',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<ExampleLanguage>(
                  segments: const [
                    ButtonSegment(
                      value: ExampleLanguage.english,
                      label: Text('English'),
                      icon: Icon(Icons.language, size: 18),
                    ),
                    ButtonSegment(
                      value: ExampleLanguage.arabic,
                      label: Text('العربية'),
                      icon: Icon(Icons.translate, size: 18),
                    ),
                  ],
                  selected: {_language},
                  onSelectionChanged: (value) {
                    setState(() => _language = value.first);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _isArabic
                      ? 'جرّب رقم الهاتف، زر الرجوع، واتجاه الواجهة بالعربية.'
                      : 'Test phone label, back button, and layout direction.',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _projectIdController,
                  decoration: InputDecoration(
                    labelText: _isArabic ? 'معرّف المشروع' : 'Project ID',
                    hintText: 'e.g. 92b2d515-0000-45a7-8b0a-df20a33ceb2a',
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return _isArabic
                          ? 'معرّف المشروع مطلوب'
                          : 'Project ID is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _publishableKeyController,
                  decoration: InputDecoration(
                    labelText:
                        _isArabic ? 'المفتاح العام' : 'Publishable key',
                    hintText: 'pk_...',
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return _isArabic
                          ? 'المفتاح العام مطلوب'
                          : 'Publishable key is required';
                    }
                    if (!trimmed.startsWith('pk_')) {
                      return _isArabic
                          ? 'يجب أن يبدأ المفتاح بـ pk_'
                          : 'Key should start with pk_';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _mapsKeyController,
                  decoration: InputDecoration(
                    labelText: _isArabic
                        ? 'مفتاح Google Maps (اختياري)'
                        : 'Google Maps API key (optional)',
                    hintText: 'AIza… (optional — map + place search)',
                    border: const OutlineInputBorder(),
                    helperText: _isArabic
                        ? 'بدون مفتاح: مشاركة GPS فقط. مع مفتاح: خريطة وبحث — '
                            'يجب وضع نفس المفتاح أيضاً في AppDelegate و AndroidManifest ثم إعادة البناء.'
                        : 'No key → GPS share only. With a key → map + search — '
                            'also set the same key in AppDelegate & AndroidManifest, then rebuild.',
                    helperMaxLines: 4,
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _openChat(),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () => _openChat(),
                  child: Text(_isArabic ? 'فتح المحادثة' : 'Open chat'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _openChat(
                    theme: const FrontFaceChatTheme(
                      primaryColor: Color(0xFF2563EB),
                      userBubbleColor: Color(0xFF2563EB),
                      userBubbleTextColor: Colors.white,
                      assistantBubbleColor: Color(0xFFEFF6FF),
                      assistantBubbleTextColor: Color(0xFF1E3A8A),
                      assistantBubbleBorderColor: Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Text(
                    _isArabic
                        ? 'فتح المحادثة (سمة مخصصة)'
                        : 'Open chat (custom theme)',
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  _isArabic ? 'اختبار انتهاء الجلسة' : 'Session expiry testing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _isArabic
                      ? 'رموز الجلسة تنتهي بعد 24 ساعة من عدم النشاط. '
                          'الرمز التالف والمنتهي يعطيان نفس الخطأ 403:\n'
                          '1. افتح المحادثة → أكمل النموذج → أرسل رسالة\n'
                          '2. أغلق المحادثة → اضغط «إفساد رمز الجلسة»\n'
                          '3. افتح المحادثة مرة أخرى\n'
                          'المتوقع: مسح المحادثة وإظهار النموذج ثم تحية الـ API.'
                      : 'Session tokens expire after 24h of inactivity. Expired and '
                          'tampered tokens both return 403 SESSION_INVALID — so you can '
                          'test without waiting:\n'
                          '1. Open chat → complete lead form → send a message\n'
                          '2. Close chat → tap “Corrupt stored session token”\n'
                          '3. Open chat again (or send a message)\n'
                          'Expected: chat cleared, lead form shown again; after submit, '
                          'a new session is created and the API greeting appears.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _corruptSessionToken,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: Text(
                    _isArabic
                        ? 'إفساد رمز الجلسة المخزّن'
                        : 'Corrupt stored session token',
                  ),
                ),
                if (_debugStatus != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _debugStatus!,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openChat(),
          child: const Icon(Icons.chat_bubble_outline),
        ),
      ),
    );
  }
}

/// Hosts [FrontFaceChatScreen] and a language toggle that calls
/// [FrontFaceChatProvider.updateStrings] live while chat is open.
class _ExampleChatHost extends StatefulWidget {
  final FrontFaceChatTheme theme;
  final ExampleLanguage initialLanguage;

  const _ExampleChatHost({
    required this.theme,
    required this.initialLanguage,
  });

  @override
  State<_ExampleChatHost> createState() => _ExampleChatHostState();
}

class _ExampleChatHostState extends State<_ExampleChatHost> {
  late ExampleLanguage _language = widget.initialLanguage;

  FrontFaceChatStrings get _strings => switch (_language) {
        ExampleLanguage.english => _englishStrings,
        ExampleLanguage.arabic => _arabicStrings,
      };

  void _setLanguage(ExampleLanguage language) {
    if (language == _language) return;
    setState(() => _language = language);
    context.read<FrontFaceChatProvider>().updateStrings(_strings);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FrontFaceChatScreen(theme: widget.theme),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 56),
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(24),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: SegmentedButton<ExampleLanguage>(
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: ExampleLanguage.english,
                        label: Text('EN'),
                      ),
                      ButtonSegment(
                        value: ExampleLanguage.arabic,
                        label: Text('AR'),
                      ),
                    ],
                    selected: {_language},
                    onSelectionChanged: (value) => _setLanguage(value.first),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
