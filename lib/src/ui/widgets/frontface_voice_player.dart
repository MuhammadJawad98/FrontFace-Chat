import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../config/frontface_chat_strings.dart';

/// Ensures only one in-chat voice note plays at a time.
class _VoicePlaybackCoordinator {
  _VoicePlaybackCoordinator._();
  static final instance = _VoicePlaybackCoordinator._();

  VoidCallback? _activePause;

  void claim(VoidCallback pause) {
    if (_activePause != null && !identical(_activePause, pause)) {
      _activePause!();
    }
    _activePause = pause;
  }

  void release(VoidCallback pause) {
    if (identical(_activePause, pause)) {
      _activePause = null;
    }
  }
}

/// Compact in-bubble voice note player (network or local file).
class FrontFaceVoicePlayer extends StatefulWidget {
  final String url;
  final Color foreground;
  final Color muted;
  final FrontFaceChatStrings strings;
  /// When true, play control shows a spinner (upload in progress) and is disabled.
  final bool isUploading;

  const FrontFaceVoicePlayer({
    super.key,
    required this.url,
    required this.foreground,
    required this.muted,
    required this.strings,
    this.isUploading = false,
  });

  @override
  State<FrontFaceVoicePlayer> createState() => _FrontFaceVoicePlayerState();
}

class _FrontFaceVoicePlayerState extends State<FrontFaceVoicePlayer> {
  late final AudioPlayer _player;
  late final VoidCallback _pauseSelf;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  bool _ready = false;
  bool _loading = false;
  bool _failed = false;
  bool _seeking = false;

  bool get _isPlaying => _state == PlayerState.playing;
  bool get _isLocal =>
      !widget.url.startsWith('http://') && !widget.url.startsWith('https://');

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _pauseSelf = () {
      unawaited(_player.pause());
    };
    _positionSub = _player.onPositionChanged.listen((pos) {
      if (!mounted || _seeking) return;
      setState(() => _position = pos);
    });
    _durationSub = _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _position = Duration.zero;
        _state = PlayerState.completed;
      });
      _VoicePlaybackCoordinator.instance.release(_pauseSelf);
    });
    // Warm source in the background — keep the play icon visible so chat
    // rebuilds (new messages) never flash a loader on existing voice notes.
    unawaited(_prepare(showSpinner: false));
  }

  @override
  void didUpdateWidget(covariant FrontFaceVoicePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _ready = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      unawaited(_prepare(showSpinner: false));
    }
  }

  Future<void> _prepare({required bool showSpinner}) async {
    final prepareUrl = widget.url;
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    } else if (mounted) {
      setState(() => _failed = false);
    }
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      final source = _isLocal
          ? DeviceFileSource(prepareUrl)
          : UrlSource(prepareUrl);
      await _player.setSource(source);
      final duration = await _player.getDuration();
      if (!mounted || widget.url != prepareUrl) return;
      setState(() {
        _duration = duration ?? Duration.zero;
        _ready = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || widget.url != prepareUrl) return;
      setState(() {
        _failed = true;
        _loading = false;
        _ready = false;
      });
    }
  }

  Future<void> _toggle() async {
    if (_failed || widget.isUploading) return;
    if (_loading) return;
    if (!_ready) {
      await _prepare(showSpinner: true);
      if (!_ready || !mounted) return;
    }
    if (_isPlaying) {
      await _player.pause();
      _VoicePlaybackCoordinator.instance.release(_pauseSelf);
      return;
    }
    _VoicePlaybackCoordinator.instance.claim(_pauseSelf);
    try {
      if (_state == PlayerState.completed ||
          (_duration > Duration.zero && _position >= _duration)) {
        await _player.seek(Duration.zero);
      }
      await _player.resume();
    } catch (_) {
      // Source may not be set yet on some platforms — set + play.
      try {
        final source = _isLocal
            ? DeviceFileSource(widget.url)
            : UrlSource(widget.url);
        await _player.play(source);
      } catch (_) {
        if (!mounted) return;
        setState(() => _failed = true);
        _VoicePlaybackCoordinator.instance.release(_pauseSelf);
      }
    }
  }

  Future<void> _seek(double value) async {
    final totalMs = _duration.inMilliseconds;
    if (totalMs <= 0) return;
    final target = Duration(milliseconds: value.round());
    setState(() {
      _seeking = true;
      _position = target;
    });
    await _player.seek(target);
    if (!mounted) return;
    setState(() => _seeking = false);
  }

  @override
  void dispose() {
    _VoicePlaybackCoordinator.instance.release(_pauseSelf);
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  String _format(Duration d) {
    final total = d.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final fg = widget.foreground;
    final muted = widget.muted;
    final maxMs =
        _duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final posMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    if (_failed) {
      return Text(
        strings.attachmentUnavailable,
        style: TextStyle(color: muted, fontSize: 13),
      );
    }

    // Local path may vanish after upload; still try if file exists.
    if (_isLocal && !File(widget.url).existsSync() && !_ready && !_loading) {
      return Text(
        strings.attachmentUnavailable,
        style: TextStyle(color: muted, fontSize: 13),
      );
    }

    final busy = _loading || widget.isUploading;
    final canSeek =
        _ready && _duration > Duration.zero && !widget.isUploading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Material(
              color: fg.withValues(alpha: 0.14),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: busy ? null : _toggle,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: busy
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        )
                      : Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: fg,
                          size: 26,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.audioAttachment,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                      activeTrackColor: fg,
                      inactiveTrackColor: muted.withValues(alpha: 0.35),
                      thumbColor: fg,
                      overlayColor: fg.withValues(alpha: 0.12),
                      padding: EdgeInsets.zero,
                    ),
                    child: SizedBox(
                      height: 28,
                      child: Slider(
                        min: 0,
                        max: maxMs,
                        value: posMs,
                        onChanged: canSeek
                            ? (v) => setState(() {
                                  _seeking = true;
                                  _position =
                                      Duration(milliseconds: v.round());
                                })
                            : null,
                        onChangeEnd: canSeek ? _seek : null,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        _format(_position),
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _format(_duration),
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
