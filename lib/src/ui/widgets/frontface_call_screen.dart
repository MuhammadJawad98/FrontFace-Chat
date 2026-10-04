import 'dart:async';

import 'package:flutter/material.dart';

import '../../calls/calls.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';

/// Full-screen call UI driven by [CallSession.state] / [CallSession.changes].
class FrontFaceCallScreen extends StatefulWidget {
  const FrontFaceCallScreen({
    super.key,
    required this.session,
    this.strings = const FrontFaceChatStrings(),
    this.theme = const FrontFaceChatTheme(),
  });

  final CallSession session;
  final FrontFaceChatStrings strings;
  final FrontFaceChatTheme theme;

  @override
  State<FrontFaceCallScreen> createState() => _FrontFaceCallScreenState();
}

class _FrontFaceCallScreenState extends State<FrontFaceCallScreen> {
  bool _speaker = false;
  Timer? _tick;

  FrontFaceChatStrings get _s => widget.strings;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.session.state is CallConnected) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (!widget.session.isOver) unawaited(widget.session.hangUp());
    unawaited(widget.session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = widget.theme;
    return PopScope(
      canPop: session.isOver,
      child: Directionality(
        textDirection: _s.textDirection,
        child: Scaffold(
          backgroundColor: theme.backgroundColor,
          body: SafeArea(
            child: StreamBuilder<CallState>(
              initialData: session.state,
              stream: session.changes,
              builder: (context, snapshot) {
                final state = snapshot.data ?? session.state;
                final ended = state is CallEnded ||
                    state is CallContinuedElsewhere;
                return SizedBox.expand(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                      const Spacer(),
                      Icon(
                        Icons.call,
                        size: 56,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _title(state),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: theme.assistantBubbleTextColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _detail(state),
                        style: TextStyle(
                          fontSize: 15,
                          color: theme.subtitleColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      if (ended)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: theme.onPrimaryColor,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(_s.callClose),
                          ),
                        )
                      else
                        _controls(session),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        ),
      ),
    );
  }

  Widget _controls(CallSession session) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton.filledTonal(
            tooltip: session.muted ? _s.callUnmute : _s.callMute,
            icon: Icon(session.muted ? Icons.mic_off : Icons.mic),
            onPressed: () async {
              await session.setMuted(!session.muted);
              setState(() {});
            },
          ),
          IconButton.filled(
            tooltip: _s.callHangUp,
            style: IconButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.call_end),
            onPressed: () => session.hangUp(),
          ),
          IconButton.filledTonal(
            tooltip: _speaker ? _s.callEarpiece : _s.callSpeaker,
            icon: Icon(_speaker ? Icons.volume_up : Icons.hearing),
            onPressed: () async {
              _speaker = !_speaker;
              await session.setSpeakerOn(_speaker);
              setState(() {});
            },
          ),
        ],
      );

  String _title(CallState state) => switch (state) {
        CallConnecting() => _s.callingSupport,
        CallRinging() => _s.callingSupport,
        CallConnected(:final agentName) => agentName ?? _s.callSupport,
        CallReconnecting() => _s.callReconnecting,
        CallEnded(:final result) => _endedTitle(result),
        CallContinuedElsewhere() => _s.callMoved,
      };

  String _detail(CallState state) => switch (state) {
        CallConnecting() => '',
        CallRinging(:final queuePosition) => switch (queuePosition) {
            null || 1 => _s.callYouAreNext,
            final n => _s.callPeopleAhead.replaceAll('{count}', '${n - 1}'),
          },
        CallConnected(:final since) =>
          _clock(DateTime.now().difference(since)),
        CallReconnecting() => _s.callReconnecting,
        CallEnded(:final result) => switch (result.outcome) {
            CallOutcome.completed when result.durationSeconds != null =>
              _clock(Duration(seconds: result.durationSeconds!)),
            CallOutcome.missed => _s.callNoAgents,
            CallOutcome.failed => _s.callCouldNotConnect,
            CallOutcome.dropped => _s.callDisconnected,
            _ => '',
          },
        CallContinuedElsewhere() => _s.callMovedDetail,
      };

  String _endedTitle(CallResult result) => switch (result.outcome) {
        CallOutcome.completed => _s.callEnded,
        CallOutcome.missed => _s.callNoAnswer,
        CallOutcome.cancelled => _s.callCancelled,
        CallOutcome.failed => _s.callCouldNotConnect,
        CallOutcome.dropped => _s.callDisconnected,
        _ => _s.callEnded,
      };

  String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Customer-facing copy when [CallsException] prevents starting a call.
String frontFaceCallRefusalMessage(
  CallsException e,
  FrontFaceChatStrings strings,
) =>
    switch (e.code) {
      CallsErrorCode.noAgentsAvailable => strings.callNoAgents,
      CallsErrorCode.callsBusy => strings.callBusy,
      CallsErrorCode.outsideHours => strings.callOutsideHours,
      CallsErrorCode.rateLimited => strings.callRateLimited,
      CallsErrorCode.notVerified => strings.callNotVerified,
      CallsErrorCode.network => strings.callNetworkError,
      _ => strings.callStartFailed,
    };
