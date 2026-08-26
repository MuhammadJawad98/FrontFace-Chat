import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/frontface_chat_strings.dart';

/// Requests OS permissions only when the user taps an attachment action.
///
/// Flow:
/// 1. If already usable → proceed (no UI).
/// 2. Otherwise show the **native** system permission dialog immediately.
/// 3. In-app popup **only** when access is permanently denied (open Settings),
///    or when location services are turned off.
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
    if (_isUsable(status)) return true;
    if (!context.mounted) return false;

    if (_needsSettings(status)) {
      await _promptOpenSettings(
        context: context,
        strings: strings,
        title: rationaleTitle,
        body: strings.permissionOpenSettingsBody,
      );
      if (!context.mounted) return false;
      status = await permission.status;
      return _isUsable(status);
    }

    // Native system prompt — no custom dark dialog first.
    status = await permission.request();
    if (_isUsable(status)) return true;
    if (!context.mounted) return false;

    status = await permission.status;
    if (_isUsable(status)) return true;

    if (_needsSettings(status) && context.mounted) {
      await _promptOpenSettings(
        context: context,
        strings: strings,
        title: rationaleTitle,
        body: strings.permissionOpenSettingsBody,
      );
      if (!context.mounted) return false;
      status = await permission.status;
      return _isUsable(status);
    }

    return false;
  }

  /// Location via [Geolocator] so it matches `getCurrentPosition` / Maps.
  Future<bool> ensureLocation({
    required BuildContext context,
    required FrontFaceChatStrings strings,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        await _showInfoDialog(
          context: context,
          strings: strings,
          title: strings.permissionLocationTitle,
          body: strings.locationServicesDisabled,
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return true;
    }
    if (!context.mounted) return false;

    if (permission == LocationPermission.deniedForever) {
      await _promptOpenSettings(
        context: context,
        strings: strings,
        title: strings.permissionLocationTitle,
        body: strings.permissionOpenSettingsBody,
      );
      if (!context.mounted) return false;
      permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    }

    // Native system prompt.
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return true;
    }

    if (permission == LocationPermission.deniedForever && context.mounted) {
      await _promptOpenSettings(
        context: context,
        strings: strings,
        title: strings.permissionLocationTitle,
        body: strings.permissionOpenSettingsBody,
      );
      if (!context.mounted) return false;
      permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    }

    return false;
  }

  /// Photo library: Android Photo Picker needs no runtime permission.
  /// iOS still requires Photos access (native prompt).
  Future<bool> ensurePhotoLibrary({
    required BuildContext context,
    required FrontFaceChatStrings strings,
  }) async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) return true;
    return ensure(
      context: context,
      permission: Permission.photos,
      strings: strings,
      rationaleTitle: strings.permissionPhotosTitle,
      rationaleBody: strings.permissionPhotosBody,
    );
  }

  static bool _isUsable(PermissionStatus status) =>
      status.isGranted || status.isLimited || status.isProvisional;

  static bool _needsSettings(PermissionStatus status) =>
      status.isPermanentlyDenied || status.isRestricted;

  Future<void> _showInfoDialog({
    required BuildContext context,
    required FrontFaceChatStrings strings,
    required String title,
    required String body,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.permissionContinue),
          ),
        ],
      ),
    );
  }

  Future<void> _promptOpenSettings({
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
  }
}
