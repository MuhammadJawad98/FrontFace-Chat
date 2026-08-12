import 'package:flutter/material.dart';

import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';

class FrontFaceCsatPrompt extends StatefulWidget {
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final Future<void> Function(int rating, String? feedback) onSubmit;

  const FrontFaceCsatPrompt({
    super.key,
    required this.theme,
    required this.strings,
    required this.onSubmit,
  });

  @override
  State<FrontFaceCsatPrompt> createState() => _FrontFaceCsatPromptState();
}

class _FrontFaceCsatPromptState extends State<FrontFaceCsatPrompt> {
  int _rating = 0;
  final _feedbackController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1 || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        _rating,
        _feedbackController.text.trim().isEmpty
            ? null
            : _feedbackController.text.trim(),
      );
      if (mounted) setState(() => _submitted = true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          widget.strings.csatThanks,
          textAlign: TextAlign.center,
          style: TextStyle(color: widget.theme.primaryColor),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.theme.inputBackgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.strings.csatTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return IconButton(
                onPressed: _submitting ? null : () => setState(() => _rating = star),
                icon: Icon(
                  star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: widget.theme.primaryColor,
                ),
              );
            }),
          ),
          TextField(
            controller: _feedbackController,
            enabled: !_submitting,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: widget.strings.additionalInfo,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.theme.primaryColor,
              foregroundColor: widget.theme.onPrimaryColor,
            ),
            onPressed: _rating < 1 || _submitting ? null : _submit,
            child: Text(widget.strings.csatSubmit),
          ),
        ],
      ),
    );
  }
}
