import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _FrontFaceCallScreenState extends State<FrontFaceCallScreen>
    with SingleTickerProviderStateMixin {
  bool _speaker = false;
  Timer? _tick;
  late final AnimationController _pulse;

  FrontFaceChatStrings get _s => widget.strings;
  FrontFaceChatTheme get _theme => widget.theme;

  Color get _surface => _theme.callBackgroundColor;
  Color get _surfaceSoft => _theme.callSurfaceColor;
  Color get _onSurface => _theme.callOnBackgroundColor;
  Color get _onSurfaceMuted => _theme.callOnBackgroundMutedColor;
  Color get _accent => _theme.callAccentColor;
  Color get _hangUp => _theme.callHangUpColor;

  bool get _isLightBackground =>
      ThemeData.estimateBrightnessForColor(_surface) == Brightness.light;

  SystemUiOverlayStyle get _systemUi => _isLightBackground
      ? SystemUiOverlayStyle.dark
      : SystemUiOverlayStyle.light;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.session.state is CallConnected) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    if (!widget.session.isOver) unawaited(widget.session.hangUp());
    unawaited(widget.session.dispose());
    super.dispose();
  }

  bool _isActive(CallState state) =>
      state is CallConnecting ||
      state is CallRinging ||
      state is CallConnected ||
      state is CallReconnecting;

  bool _isEnded(CallState state) =>
      state is CallEnded || state is CallContinuedElsewhere;

  bool _shouldPulse(CallState state) =>
      state is CallConnecting ||
      state is CallRinging ||
      state is CallReconnecting;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return PopScope(
      canPop: session.isOver,
      child: Directionality(
        textDirection: _s.textDirection,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: _systemUi,
          child: Scaffold(
            backgroundColor: _surface,
            body: StreamBuilder<CallState>(
              initialData: session.state,
              stream: session.changes,
              builder: (context, snapshot) {
                final state = snapshot.data ?? session.state;
                return SafeArea(
                  child: SizedBox.expand(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                      child: Column(
                        children: [
                          _topBar(state),
                          const Spacer(flex: 2),
                          _avatar(state),
                          const SizedBox(height: 28),
                          Text(
                            _title(state),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              height: 1.2,
                              color: _onSurface,
                              fontFamily: _theme.resolvedFontFamily(
                                _s.textDirection,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _detail(state),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              color: _onSurfaceMuted,
                              fontFamily: _theme.resolvedFontFamily(
                                _s.textDirection,
                              ),
                            ),
                          ),
                          const Spacer(flex: 3),
                          if (_isEnded(state))
                            _endedActions()
                          else if (_isActive(state))
                            _controls(session),
                        ],
                      ),
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

  Widget _topBar(CallState state) {
    final label = switch (state) {
      CallConnecting() || CallRinging() => _s.callingSupport,
      CallConnected() => _s.callSupport,
      CallReconnecting() => _s.callReconnecting,
      CallEnded() => _s.callEnded,
      CallContinuedElsewhere() => _s.callMoved,
    };
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _surfaceSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (state) {
                  CallConnected() => _theme.onlineIndicatorColor,
                  CallEnded() || CallContinuedElsewhere() => _onSurfaceMuted,
                  _ => _accent,
                },
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _onSurface,
                  fontFamily: _theme.resolvedFontFamily(_s.textDirection),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(CallState state) {
    final icon = switch (state) {
      CallEnded(:final result) => switch (result.outcome) {
          CallOutcome.completed => Icons.call_end_rounded,
          CallOutcome.missed || CallOutcome.cancelled => Icons.phone_missed_rounded,
          CallOutcome.failed || CallOutcome.dropped => Icons.wifi_off_rounded,
          _ => Icons.call_end_rounded,
        },
      CallContinuedElsewhere() => Icons.phonelink_ring_rounded,
      CallConnected() => Icons.support_agent_rounded,
      _ => Icons.call_rounded,
    };
    final pulseColor = switch (state) {
      CallEnded(:final result)
          when result.outcome == CallOutcome.completed =>
        _theme.onlineIndicatorColor,
      CallEnded() || CallContinuedElsewhere() => _onSurfaceMuted,
      _ => _accent,
    };
    final avatarBg = switch (state) {
      CallEnded(:final result)
          when result.outcome == CallOutcome.completed =>
        _theme.onlineIndicatorColor.withValues(alpha: 0.22),
      CallEnded() || CallContinuedElsewhere() => _surfaceSoft,
      _ => _theme.callAvatarBackgroundColor,
    };
    final iconColor = switch (state) {
      CallEnded(:final result)
          when result.outcome == CallOutcome.completed =>
        _theme.onlineIndicatorColor,
      CallEnded() || CallContinuedElsewhere() => _onSurfaceMuted,
      _ => _theme.callAvatarIconColor,
    };

    return SizedBox(
      width: 168,
      height: 168,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _shouldPulse(state) ? _pulse.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (_shouldPulse(state)) ...[
                _pulseRing(pulseColor, 0.22 + (t * 0.28), 1.0 + (t * 0.35)),
                _pulseRing(
                  pulseColor,
                  0.12 + (((t + 0.5) % 1.0) * 0.2),
                  1.15 + (((t + 0.5) % 1.0) * 0.4),
                ),
              ],
              child!,
            ],
          );
        },
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarBg,
            border: Border.all(
              color: iconColor.withValues(alpha: 0.35),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _isLightBackground ? 0.1 : 0.35,
                ),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(icon, size: 48, color: iconColor),
        ),
      ),
    );
  }

  Widget _pulseRing(Color color, double opacity, double scale) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _controls(CallSession session) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundControl(
            icon: session.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: session.muted ? _s.callUnmute : _s.callMute,
            active: session.muted,
            onTap: () async {
              HapticFeedback.selectionClick();
              await session.setMuted(!session.muted);
              if (mounted) setState(() {});
            },
          ),
          _roundControl(
            icon: Icons.call_end_rounded,
            label: _s.callHangUp,
            size: 84,
            iconSize: 36,
            background: _hangUp,
            foreground: Colors.white,
            onTap: () {
              HapticFeedback.mediumImpact();
              unawaited(session.hangUp());
            },
          ),
          _roundControl(
            icon: _speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
            label: _speaker ? _s.callEarpiece : _s.callSpeaker,
            active: _speaker,
            onTap: () async {
              HapticFeedback.selectionClick();
              _speaker = !_speaker;
              await session.setSpeakerOn(_speaker);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _roundControl({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    double size = 72,
    double iconSize = 30,
    Color? background,
    Color? foreground,
  }) {
    final bg = background ??
        (active ? _onSurface : _surfaceSoft);
    final fg = foreground ??
        (active ? _surface : _onSurface);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _isLightBackground ? 0.08 : 0.28,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, size: iconSize, color: fg),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: math.max(size, 88),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _onSurfaceMuted,
              fontFamily: _theme.resolvedFontFamily(_s.textDirection),
            ),
          ),
        ),
      ],
    );
  }

  Widget _endedActions() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _theme.primaryColor,
          foregroundColor: _theme.onPrimaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: _theme.resolvedFontFamily(_s.textDirection),
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(_s.callClose),
      ),
    );
  }

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
