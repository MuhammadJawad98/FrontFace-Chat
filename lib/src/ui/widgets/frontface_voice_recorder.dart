import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../config/frontface_attachments_config.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../services/frontface_permission_gate.dart';

/// Modal sheet to record a voice note and return a [FrontFacePendingAttachment].
class FrontFaceVoiceRecorderSheet {
  FrontFaceVoiceRecorderSheet._();

  static Future<FrontFacePendingAttachment?> show(
    BuildContext context, {
    required FrontFaceChatTheme theme,
    required FrontFaceChatStrings strings,
    required int maxAudioBytes,
  }) {
    return showModalBottomSheet<FrontFacePendingAttachment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => _VoiceRecorderBody(
        theme: theme,
        strings: strings,
        maxAudioBytes: maxAudioBytes,
      ),
    );
  }
}

class _VoiceRecorderBody extends StatefulWidget {
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final int maxAudioBytes;

  const _VoiceRecorderBody({
    required this.theme,
    required this.strings,
    required this.maxAudioBytes,
  });

  @override
  State<_VoiceRecorderBody> createState() => _VoiceRecorderBodyState();
}

class _VoiceRecorderBodyState extends State<_VoiceRecorderBody> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _busy = false;
  String? _error;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  String? _path;
  String _mime = 'audio/mp4';

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      await _stopAndReturn();
      return;
    }
    await _start();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final gate = const FrontFacePermissionGate();
      final ok = await gate.ensure(
        context: context,
        permission: Permission.microphone,
        strings: widget.strings,
        rationaleTitle: widget.strings.permissionMicTitle,
        rationaleBody: widget.strings.permissionMicBody,
      );
      if (!ok || !mounted) return;

      final dir = await getTemporaryDirectory();
      final ext = (!kIsWeb && Platform.isIOS) ? 'm4a' : 'm4a';
      _mime = 'audio/mp4';
      _path =
          '${dir.path}/ff_voice_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _path!,
      );

      _elapsed = Duration.zero;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });
      setState(() => _recording = true);
    } catch (_) {
      setState(() => _error = widget.strings.attachmentUploadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopAndReturn() async {
    setState(() => _busy = true);
    try {
      _ticker?.cancel();
      final path = await _recorder.stop() ?? _path;
      setState(() => _recording = false);
      if (path == null || path.isEmpty) {
        setState(() => _error = widget.strings.attachmentUploadFailed);
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        setState(() => _error = widget.strings.attachmentUploadFailed);
        return;
      }
      final length = await file.length();
      if (length > widget.maxAudioBytes) {
        setState(() => _error = widget.strings.attachmentTooLarge);
        return;
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        FrontFacePendingAttachment(
          kind: FrontFaceAttachmentKind.audio,
          path: path,
          fileName: path.split(Platform.pathSeparator).last,
          mimeType: _mime,
          byteLength: length,
        ),
      );
    } catch (_) {
      setState(() => _error = widget.strings.attachmentUploadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _timerLabel {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.strings.recordVoice,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text(
            _timerLabel,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _recording
                  ? Theme.of(context).colorScheme.error
                  : widget.theme.primaryColor,
              foregroundColor: widget.theme.onPrimaryColor,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _busy ? null : _toggle,
            icon: Icon(_recording ? Icons.stop : Icons.mic),
            label: Text(
              _recording ? widget.strings.stopRecording : widget.strings.startRecording,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy || _recording
                ? null
                : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF111827),
            ),
            child: Text(widget.strings.permissionNotNow),
          ),
        ],
      ),
    );
  }
}
