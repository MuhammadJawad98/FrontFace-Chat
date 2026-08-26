import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/frontface_chat_strings.dart';

/// Full-screen image preview with pinch / double-tap zoom.
class FrontFaceImageViewer {
  FrontFaceImageViewer._();

  static Future<void> open(
    BuildContext context, {
    required String url,
    FrontFaceChatStrings strings = const FrontFaceChatStrings(),
    String? semanticLabel,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _FrontFaceImageViewerPage(
              url: url,
              strings: strings,
              semanticLabel: semanticLabel,
            ),
          );
        },
      ),
    );
  }
}

class _FrontFaceImageViewerPage extends StatefulWidget {
  final String url;
  final FrontFaceChatStrings strings;
  final String? semanticLabel;

  const _FrontFaceImageViewerPage({
    required this.url,
    required this.strings,
    this.semanticLabel,
  });

  @override
  State<_FrontFaceImageViewerPage> createState() =>
      _FrontFaceImageViewerPageState();
}

class _FrontFaceImageViewerPageState extends State<_FrontFaceImageViewerPage> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  static bool _isLocal(String raw) =>
      !raw.startsWith('http://') && !raw.startsWith('https://');

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _close() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleDoubleTap() {
    final matrix = _transform.value;
    final isZoomed = matrix.getMaxScaleOnAxis() > 1.05;
    if (isZoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition;
    if (position == null) {
      _transform.value = Matrix4.identity()..scaleByDouble(2.5, 2.5, 1, 1);
      return;
    }
    final zoomed = Matrix4.identity()
      ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
    _transform.value = zoomed;
  }

  Widget _buildImage() {
    final url = widget.url;
    final error = _ViewerError(message: widget.strings.imageLoadFailed);
    if (_isLocal(url)) {
      return Image.file(
        File(url),
        fit: BoxFit.contain,
        semanticLabel: widget.semanticLabel,
        errorBuilder: (_, __, ___) => error,
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      semanticLabel: widget.semanticLabel,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: CupertinoActivityIndicator(color: Colors.white70),
        );
      },
      errorBuilder: (_, __, ___) => error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () {
                if (_transform.value.getMaxScaleOnAxis() <= 1.05) {
                  _close();
                }
              },
              onDoubleTapDown: (details) => _doubleTapDetails = details,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 5,
                clipBehavior: Clip.none,
                child: SizedBox.expand(
                  child: Center(child: _buildImage()),
                ),
              ),
            ),
            Positioned(
              top: top + 8,
              right: 12,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: _close,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  final String message;

  const _ViewerError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}
