import 'package:flutter/material.dart';

import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../models/frontface_models.dart';

class FrontFaceLeadForm extends StatefulWidget {
  final FrontFaceEmbedConfig config;
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final Future<void> Function(String email, String? field2, String? field3)
  onSubmit;

  const FrontFaceLeadForm({
    super.key,
    required this.config,
    required this.theme,
    required this.strings,
    required this.onSubmit,
  });

  @override
  State<FrontFaceLeadForm> createState() => _FrontFaceLeadFormState();
}

class _FrontFaceLeadFormState extends State<FrontFaceLeadForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _field2Controller = TextEditingController();
  final _field3Controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _field2Controller.dispose();
    _field3Controller.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: widget.theme.assistantBubbleBorderColor),
    );

    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: widget.theme.assistantBubbleColor,
      labelStyle: TextStyle(color: widget.theme.subtitleColor),
      floatingLabelStyle: TextStyle(color: widget.theme.primaryColor),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: widget.theme.primaryColor, width: 1.5),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: widget.theme.errorColor),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: widget.theme.errorColor, width: 1.5),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    await widget.onSubmit(
      _emailController.text.trim(),
      _field2Controller.text.trim().isEmpty
          ? null
          : _field2Controller.text.trim(),
      _field3Controller.text.trim().isEmpty
          ? null
          : _field3Controller.text.trim(),
    );
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.strings.beforeWeChat,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              widget.strings.leadFormSubtitle,
              style: TextStyle(fontSize: 14, color: widget.theme.subtitleColor),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              cursorColor: widget.theme.primaryColor,
              decoration: _fieldDecoration(widget.strings.email),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return widget.strings.emailRequired;
                }
                if (!value.contains('@')) return widget.strings.invalidEmail;
                return null;
              },
            ),
            if (widget.config.field2Enabled) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _field2Controller,
                cursorColor: widget.theme.primaryColor,
                decoration: _fieldDecoration(
                  widget.config.field2Label ?? widget.strings.additionalInfo,
                ),
                validator: widget.config.field2Required
                    ? (value) => value == null || value.trim().isEmpty
                          ? widget.strings.requiredField
                          : null
                    : null,
              ),
            ],
            if (widget.config.field3Enabled) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _field3Controller,
                cursorColor: widget.theme.primaryColor,
                decoration: _fieldDecoration(
                  widget.config.field3Label ?? widget.strings.additionalInfo,
                ),
                validator: widget.config.field3Required
                    ? (value) => value == null || value.trim().isEmpty
                          ? widget.strings.requiredField
                          : null
                    : null,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.primaryColor,
                  foregroundColor: widget.theme.onPrimaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.theme.onPrimaryColor,
                        ),
                      )
                    : Text(widget.strings.continueToChat),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
