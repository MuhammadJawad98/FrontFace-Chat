import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/frontface_chat_strings.dart';
import '../config/frontface_chat_theme.dart';
import '../models/frontface_models.dart';
import '../provider/frontface_chat_provider.dart';
import 'widgets/frontface_lead_form.dart';
import 'widgets/frontface_message_bubble.dart';

/// Full-screen native FrontFace chat UI.
///
/// Requires a [FrontFaceChatProvider] above this widget in the tree.
/// Prefer [FrontFaceChat.open] for a one-line integration.
class FrontFaceChatScreen extends StatefulWidget {
  final FrontFaceChatTheme theme;
  final VoidCallback? onClose;

  const FrontFaceChatScreen({
    super.key,
    this.theme = const FrontFaceChatTheme(),
    this.onClose,
  });

  @override
  State<FrontFaceChatScreen> createState() => _FrontFaceChatScreenState();
}

class _FrontFaceChatScreenState extends State<FrontFaceChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  FrontFaceChatProvider get _provider => context.read<FrontFaceChatProvider>();
  FrontFaceChatStrings get _strings => _provider.strings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeChat());
    _provider.addListener(_scrollToBottom);
  }

  Future<void> _initializeChat() async {
    await _provider.initialize();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _provider.removeListener(_scrollToBottom);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    await _provider.sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.theme.backgroundColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: widget.theme.primaryColor,
        foregroundColor: widget.theme.onPrimaryColor,
        leading: IconButton(
          onPressed: _close,
          icon: Icon(Icons.arrow_back_ios, color: widget.theme.onPrimaryColor),
        ),
        title: Consumer<FrontFaceChatProvider>(
          builder: (context, provider, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.config.title,
                  style: TextStyle(
                    color: widget.theme.onPrimaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                if (provider.statusBanner != null)
                  Text(
                    provider.statusBanner!,
                    style: TextStyle(
                      color: widget.theme.onPrimaryColor.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  )
                else
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: widget.theme.onlineIndicatorColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _strings.online,
                        style: TextStyle(
                          color: widget.theme.onPrimaryColor
                              .withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
        actions: [
          Consumer<FrontFaceChatProvider>(
            builder: (context, provider, _) {
              if (provider.messages.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: _strings.newChat,
                onPressed:
                    provider.isInitializing ? null : provider.startNewChat,
                icon: const Icon(Icons.refresh_rounded),
              );
            },
          ),
        ],
      ),
      body: Consumer<FrontFaceChatProvider>(
        builder: (context, provider, _) {
          if (provider.isInitializing) {
            return _LoadingView(
              greeting: provider.config.greeting,
              theme: widget.theme,
            );
          }

          if (provider.error != null && provider.messages.isEmpty) {
            return _ErrorView(
              message: provider.error!,
              theme: widget.theme,
              retryLabel: _strings.retry,
              onRetry: _initializeChat,
            );
          }

          return Column(
            children: [
              if (provider.error != null)
                Container(
                  width: double.infinity,
                  color: widget.theme.errorColor.withValues(alpha: 0.1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    provider.error!,
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.theme.errorColor,
                    ),
                  ),
                ),
              Expanded(
                child: provider.showLeadForm
                    ? FrontFaceLeadForm(
                        config: provider.config,
                        theme: widget.theme,
                        strings: _strings,
                        onSubmit: (email, field2, field3) async {
                          await provider.submitLeadForm(
                            email: email,
                            field2: field2,
                            field3: field3,
                          );
                          _scrollToBottom();
                        },
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: provider.messages.length +
                            (provider.isSending ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (provider.isSending &&
                              index == provider.messages.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: FrontFaceTypingIndicator(
                                theme: widget.theme,
                              ),
                            );
                          }
                          return FrontFaceMessageBubble(
                            message: provider.messages[index],
                            theme: widget.theme,
                          );
                        },
                      ),
              ),
              if (provider.showHandoffButton)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: provider.isHandoffLoading
                          ? null
                          : () async {
                              await provider.requestHuman();
                              _scrollToBottom();
                            },
                      icon: provider.isHandoffLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: widget.theme.primaryColor,
                              ),
                            )
                          : const Icon(Icons.support_agent_rounded),
                      label: Text(provider.handoffButtonText),
                    ),
                  ),
                ),
              if (provider.status == FrontFaceConversationStatus.resolved ||
                  provider.status == FrontFaceConversationStatus.closed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.primaryColor,
                        foregroundColor: widget.theme.onPrimaryColor,
                      ),
                      onPressed: provider.startNewChat,
                      child: Text(_strings.startNewChat),
                    ),
                  ),
                ),
              if (provider.canChat && !provider.showLeadForm)
                SafeArea(
                  top: false,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            enabled: !provider.isSending,
                            cursorColor: widget.theme.primaryColor,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: provider.config.placeholder,
                              filled: true,
                              fillColor: widget.theme.inputBackgroundColor,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: widget.theme.primaryColor,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: provider.isSending ? null : _sendMessage,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.send_rounded,
                                color: widget.theme.onPrimaryColor,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String greeting;
  final FrontFaceChatTheme theme;

  const _LoadingView({required this.greeting, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            greeting,
            style: TextStyle(fontSize: 14, color: theme.subtitleColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final FrontFaceChatTheme theme;
  final String retryLabel;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.theme,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.errorColor),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.subtitleColor),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: theme.onPrimaryColor,
              ),
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
