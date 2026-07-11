import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/frontface_chat_strings.dart';
import '../config/frontface_chat_theme.dart';
import '../models/frontface_models.dart';
import '../provider/frontface_chat_provider.dart';
import '../utils/text_direction.dart';
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

  // Cached (not a context.read(...) getter) so dispose() can safely detach
  // the listener even if the ancestor Provider is torn down in the same
  // frame as this widget (e.g. when FrontFaceChat.open()'s scoped provider
  // and this screen are popped together).
  late final FrontFaceChatProvider _provider = context
      .read<FrontFaceChatProvider>();
  FrontFaceChatStrings get _strings => _provider.strings;

  int _lastMessageCount = 0;
  bool _lastSending = false;

  // Computed (not cached) so it always reflects the latest typed content
  // and the latest strings.textDirection — including after a runtime
  // FrontFaceChatProvider.updateStrings() call.
  TextDirection get _inputDirection => _controller.text.isEmpty
      ? _strings.textDirection
      : detectTextDirection(_controller.text);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeChat());
    _provider.addListener(_onProviderUpdate);
    _controller.addListener(_updateInputDirection);
  }

  void _updateInputDirection() {
    // The TextField's textDirection argument is only re-evaluated when this
    // State rebuilds, so trigger one on every keystroke.
    setState(() {});
  }

  Future<void> _initializeChat() async {
    await _provider.initialize();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderUpdate);
    _controller.removeListener(_updateInputDirection);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    // Sending always pins to the latest message (WhatsApp-style).
    _scrollToLatest(force: true);
    await _provider.sendMessage(text);
  }

  void _onProviderUpdate() {
    final count = _provider.messages.length;
    final sending = _provider.isSending;
    final changed = count != _lastMessageCount || sending != _lastSending;
    _lastMessageCount = count;
    _lastSending = sending;
    // Only nudge when content actually changed — every notifyListeners()
    // used to fire a huge animateTo and felt like jumpy overscrolling.
    if (changed) _scrollToLatest();
  }

  /// Reverse ListView: offset 0 is the visual bottom (newest messages).
  /// Matches WhatsApp — stay put if the user scrolled up to read history.
  void _scrollToLatest({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      const nearBottomThreshold = 80.0;
      final nearBottom = position.pixels <= nearBottomThreshold;
      if (!force && !nearBottom) return;
      if (position.pixels <= 0.5) return;

      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
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
    // Rebuild this whole screen (not just the inner Consumer widgets) on
    // every provider change, including a runtime FrontFaceChatStrings swap
    // via updateStrings(), so Directionality and icon mirroring stay live.
    context.watch<FrontFaceChatProvider>();
    final isRtl = _strings.textDirection == TextDirection.rtl;
    return Directionality(
      textDirection: _strings.textDirection,
      child: Scaffold(
        backgroundColor: widget.theme.backgroundColor,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: widget.theme.primaryColor,
          foregroundColor: widget.theme.onPrimaryColor,
          leading: IconButton(
            onPressed: _close,
            // Always use back; Directionality (RTL/LTR) mirrors it.
            // Manually swapping to arrow_forward_ios in RTL double-flipped
            // the icon and looked wrong in Arabic.
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: widget.theme.onPrimaryColor,
            ),
          ),
          title: Consumer<FrontFaceChatProvider>(
            builder: (context, provider, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _strings.title ?? provider.config.title,
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
                        color: widget.theme.onPrimaryColor.withValues(
                          alpha: 0.85,
                        ),
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
                            color: widget.theme.onPrimaryColor.withValues(
                              alpha: 0.8,
                            ),
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
                  onPressed: provider.isInitializing
                      ? null
                      : provider.startNewChat,
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
                message: _strings.loadingChat,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                          },
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          // Newest at the visual bottom (offset 0) — same
                          // pattern as WhatsApp. Avoids jumpy animateTo on
                          // every message; the list naturally grows downward.
                          reverse: true,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount:
                              provider.messages.length +
                              (provider.isSending ? 1 : 0),
                          itemBuilder: (context, index) {
                            // index 0 is the bottom of the chat.
                            if (provider.isSending && index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: FrontFaceTypingIndicator(
                                  theme: widget.theme,
                                ),
                              );
                            }
                            final messageIndex = provider.isSending
                                ? index - 1
                                : index;
                            final message = provider.messages[
                                provider.messages.length - 1 - messageIndex];
                            return FrontFaceMessageBubble(
                              message: message,
                              theme: widget.theme,
                              strings: _strings,
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
                              textDirection: _inputDirection,
                              onSubmitted: (_) => _sendMessage(),
                              decoration: InputDecoration(
                                hintText: provider.config.placeholder.isNotEmpty
                                    ? provider.config.placeholder
                                    : _strings.typeMessage,
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
                                child: Transform.flip(
                                  flipX: isRtl,
                                  child: Icon(
                                    Icons.send_rounded,
                                    color: widget.theme.onPrimaryColor,
                                    size: 20,
                                  ),
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
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String message;
  final FrontFaceChatTheme theme;

  const _LoadingView({required this.message, required this.theme});

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
            message,
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
