import 'package:flutter/material.dart';
import 'package:frontface_chat/frontface_chat.dart';

void main() {
  runApp(const ExampleApp());
}

/// Replace with your FrontFace Mobile SDK credentials from the dashboard.
const _config = FrontFaceChatConfig(
  projectId: 'YOUR_PROJECT_UUID',
  publishableKey: 'pk_YOUR_PUBLISHABLE_KEY',
  // debugLogging: true,
);

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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FrontFace Chat Example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => _openChat(context),
              child: const Text('Open chat'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _openChatWithTheme(context),
              child: const Text('Open chat (custom theme)'),
            ),
          ],
        ),
      ),
      floatingActionButton: FrontFaceChat.fab(
        context,
        config: _config,
      ),
    );
  }

  Future<void> _openChat(BuildContext context) {
    return FrontFaceChat.open(
      context,
      config: _config,
    );
  }

  Future<void> _openChatWithTheme(BuildContext context) {
    return FrontFaceChat.open(
      context,
      config: _config,
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
}
