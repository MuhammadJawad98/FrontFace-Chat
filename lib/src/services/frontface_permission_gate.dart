import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/frontface_chat_strings.dart';

/// Requests OS permissions only when the user taps an attachment action.
///
/// Flow:
/// 1. If already granted → proceed.
/// 2. If denied → show an in-app rationale, then the system prompt.
/// 3. If permanently denied → offer to open app Settings.
class FrontFacePermissionGate {
  const FrontFacePermissionGate();

  Future<bool> ensure({
    required BuildContext context,
    required Permission permission,
    required FrontFaceChatStrings strings,
    required String rationaleTitle,
    required String rationaleBody,
  }) async {
    var status = await permission.status;

    if (status.isGranted || status.isLimited) return true;
    if (!context.mounted) return false;

    if (status.isPermanentlyDenied) {
      return _promptOpenSettings(
        context: context,
        strings: strings,
        title: rationaleTitle,
        body: strings.permissionOpenSettingsBody,
      );
    }

    // Denied (or first ask) — explain before the system dialog.
    final proceed = await _showRationale(
      context: context,
      strings: strings,
      title: rationaleTitle,
      body: rationaleBody,
    );
    if (!proceed || !context.mounted) return false;

    status = await permission.request();
    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied && context.mounted) {
      return _promptOpenSettings(
        context: context,
        strings: strings,
        title: rationaleTitle,
        body: strings.permissionOpenSettingsBody,
      );
    }
    return false;
  }

  Future<bool> _showRationale({
    required BuildContext context,
    required FrontFaceChatStrings strings,
    required String title,
    required String body,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.permissionNotNow),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.permissionContinue),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool> _promptOpenSettings({
    required BuildContext context,
    required FrontFaceChatStrings strings,
    required String title,
    required String body,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.permissionNotNow),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.openSettings),
          ),
        ],
      ),
    );
    if (result == true) {
      await openAppSettings();
    }
    return false;
  }
}
