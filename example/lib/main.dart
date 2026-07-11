import 'package:flutter/material.dart';
import 'package:frontface_chat/frontface_chat.dart';

void main() {
  runApp(const ExampleApp());
}

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
  final _formKey = GlobalKey<FormState>();
  String? _debugStatus;

  @override
  void dispose() {
    _projectIdController.dispose();
    _publishableKeyController.dispose();
    super.dispose();
  }

  FrontFaceChatConfig? _buildConfig() {
    if (!_formKey.currentState!.validate()) return null;
    return FrontFaceChatConfig(
      projectId: _projectIdController.text.trim(),
      publishableKey: _publishableKeyController.text.trim(),
      // debugLogging: true,
    );
  }

  Future<void> _openChat() async {
    final config = _buildConfig();
    if (config == null || !mounted) return;
    await FrontFaceChat.open(context, config: config);
  }

  Future<void> _openChatWithTheme() async {
    final config = _buildConfig();
    if (config == null || !mounted) return;
    await FrontFaceChat.open(
      context,
      config: config,
      theme: const FrontFaceChatTheme(
        primaryColor: Color(0xFF2563EB),
        userBubbleColor: Color(0xFF2563EB),
      ),
      strings: const FrontFaceChatStrings(
        online: 'متصل',
        beforeWeChat: 'قبل الدردشة',
        continueToChat: 'متابعة',
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
          ? 'Session token corrupted. Open chat — you should see the lead '
              'form (chat cleared, no greeting yet). After submit, a new '
              'session is created and the API greeting appears.'
          : 'No stored session token yet. Open chat, complete the lead '
              'form / send a message first, close chat, then try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FrontFace Chat Example')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Enter your Mobile SDK credentials from the FrontFace dashboard, then open chat.',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _projectIdController,
                decoration: const InputDecoration(
                  labelText: 'Project ID',
                  hintText: 'e.g. 92b2d515-0000-45a7-8b0a-df20a33ceb2a',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Project ID is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _publishableKeyController,
                decoration: const InputDecoration(
                  labelText: 'Publishable key',
                  hintText: 'pk_...',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _openChat(),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Publishable key is required';
                  }
                  if (!trimmed.startsWith('pk_')) {
                    return 'Key should start with pk_';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _openChat,
                child: const Text('Open chat'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _openChatWithTheme,
                child: const Text('Open chat (custom theme)'),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Session expiry testing',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Session tokens expire after 24h of inactivity. Expired and '
                'tampered tokens both return 403 SESSION_INVALID — so you can '
                'test without waiting:\n'
                '1. Open chat → complete lead form → send a message\n'
                '2. Close chat → tap “Corrupt stored session token”\n'
                '3. Open chat again (or send a message)\n'
                'Expected: chat cleared, lead form shown again; after submit, '
                'a new session is created and the API greeting appears — '
                'no greeting before the form, no error toast.',
                style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _corruptSessionToken,
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('Corrupt stored session token'),
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
        onPressed: _openChat,
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}
