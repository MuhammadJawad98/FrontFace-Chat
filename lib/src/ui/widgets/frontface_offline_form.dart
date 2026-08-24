import 'package:flutter/material.dart';

import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';

class FrontFaceOfflineForm extends StatefulWidget {
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final Future<void> Function(String name, String email, String message) onSubmit;

  /// Extra bottom padding so the submit button clears the home indicator /
  /// host bottom nav.
  final double bottomInset;

  const FrontFaceOfflineForm({
    super.key,
    required this.theme,
    required this.strings,
    required this.onSubmit,
    this.bottomInset = 0,
  });

  @override
  State<FrontFaceOfflineForm> createState() => _FrontFaceOfflineFormState();
}

class _FrontFaceOfflineFormState extends State<FrontFaceOfflineForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _messageController.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + widget.bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.strings.offlineTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              enabled: !_submitting,
              decoration: InputDecoration(labelText: widget.strings.offlineName),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? widget.strings.requiredField : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: widget.strings.email),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return widget.strings.emailRequired;
                if (!v.contains('@')) return widget.strings.invalidEmail;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _messageController,
              enabled: !_submitting,
              maxLines: 4,
              decoration: InputDecoration(labelText: widget.strings.offlineMessage),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? widget.strings.requiredField : null,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.theme.primaryColor,
                foregroundColor: widget.theme.onPrimaryColor,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _submitting ? null : _submit,
              child: Text(widget.strings.offlineSubmit),
            ),
          ],
        ),
      ),
    );
  }
}
