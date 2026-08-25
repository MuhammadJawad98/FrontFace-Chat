import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/frontface_attachments_config.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../services/frontface_permission_gate.dart';
import 'frontface_location_picker.dart';
import 'frontface_voice_recorder.dart';

/// Bottom sheet listing enabled attachment actions.
class FrontFaceAttachmentSheet {
  FrontFaceAttachmentSheet._();

  static Future<void> show({
    required BuildContext context,
    required FrontFaceAttachmentsConfig attachments,
    required FrontFaceChatTheme theme,
    required FrontFaceChatStrings strings,
    required Future<void> Function(FrontFaceAttachmentPayload payload)
        onLocation,
    required Future<void> Function(FrontFacePendingAttachment pending) onMedia,
  }) async {
    if (!attachments.anyEnabled) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bottom = MediaQuery.viewPaddingOf(sheetContext).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom > 0 ? 4 : 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attachments.enableLocation)
                  ListTile(
                    leading: Icon(Icons.location_on_outlined,
                        color: theme.primaryColor),
                    title: Text(strings.shareLocation),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _pickLocation(
                        context: context,
                        attachments: attachments,
                        theme: theme,
                        strings: strings,
                        onLocation: onLocation,
                      );
                    },
                  ),
                if (attachments.enableImages) ...[
                  ListTile(
                    leading:
                        Icon(Icons.photo_outlined, color: theme.primaryColor),
                    title: Text(strings.attachPhoto),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _pickImage(
                        context: context,
                        source: ImageSource.gallery,
                        attachments: attachments,
                        strings: strings,
                        onMedia: onMedia,
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.photo_camera_outlined,
                        color: theme.primaryColor),
                    title: Text(strings.takePhoto),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _pickImage(
                        context: context,
                        source: ImageSource.camera,
                        attachments: attachments,
                        strings: strings,
                        onMedia: onMedia,
                      );
                    },
                  ),
                ],
                if (attachments.enableAudio) ...[
                  ListTile(
                    leading: Icon(Icons.mic_none, color: theme.primaryColor),
                    title: Text(strings.recordVoice),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _recordVoice(
                        context: context,
                        attachments: attachments,
                        theme: theme,
                        strings: strings,
                        onMedia: onMedia,
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.audiotrack_outlined,
                        color: theme.primaryColor),
                    title: Text(strings.attachAudio),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _pickAudio(
                        context: context,
                        attachments: attachments,
                        strings: strings,
                        onMedia: onMedia,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _pickLocation({
    required BuildContext context,
    required FrontFaceAttachmentsConfig attachments,
    required FrontFaceChatTheme theme,
    required FrontFaceChatStrings strings,
    required Future<void> Function(FrontFaceAttachmentPayload payload)
        onLocation,
  }) async {
    final key = attachments.googleMapsApiKey?.trim();
    if (key == null || key.isEmpty) return;
    if (!context.mounted) return;
    final payload = await FrontFaceLocationPickerScreen.open(
      context,
      theme: theme,
      strings: strings,
      googleMapsApiKey: key,
    );
    if (payload != null) await onLocation(payload);
  }

  static Future<void> _pickImage({
    required BuildContext context,
    required ImageSource source,
    required FrontFaceAttachmentsConfig attachments,
    required FrontFaceChatStrings strings,
    required Future<void> Function(FrontFacePendingAttachment pending) onMedia,
  }) async {
    final gate = const FrontFacePermissionGate();
    final permission =
        source == ImageSource.camera ? Permission.camera : Permission.photos;
    final ok = await gate.ensure(
      context: context,
      permission: permission,
      strings: strings,
      rationaleTitle: source == ImageSource.camera
          ? strings.permissionCameraTitle
          : strings.permissionPhotosTitle,
      rationaleBody: source == ImageSource.camera
          ? strings.permissionCameraBody
          : strings.permissionPhotosBody,
    );
    if (!ok || !context.mounted) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2048,
    );
    if (file == null) return;

    final length = await File(file.path).length();
    if (length > attachments.maxImageBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.attachmentTooLarge)),
        );
      }
      return;
    }

    await onMedia(
      FrontFacePendingAttachment(
        kind: FrontFaceAttachmentKind.image,
        path: file.path,
        fileName: file.name,
        mimeType: file.mimeType ?? 'image/jpeg',
        byteLength: length,
      ),
    );
  }

  static Future<void> _recordVoice({
    required BuildContext context,
    required FrontFaceAttachmentsConfig attachments,
    required FrontFaceChatTheme theme,
    required FrontFaceChatStrings strings,
    required Future<void> Function(FrontFacePendingAttachment pending) onMedia,
  }) async {
    if (!context.mounted) return;
    final pending = await FrontFaceVoiceRecorderSheet.show(
      context,
      theme: theme,
      strings: strings,
      maxAudioBytes: attachments.maxAudioBytes,
    );
    if (pending != null) await onMedia(pending);
  }

  static Future<void> _pickAudio({
    required BuildContext context,
    required FrontFaceAttachmentsConfig attachments,
    required FrontFaceChatStrings strings,
    required Future<void> Function(FrontFacePendingAttachment pending) onMedia,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'webm'],
      withData: false,
    );
    final file = result?.files.single;
    final path = file?.path;
    if (file == null || path == null) return;

    final length = file.size;
    if (length > attachments.maxAudioBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.attachmentTooLarge)),
        );
      }
      return;
    }

    await onMedia(
      FrontFacePendingAttachment(
        kind: FrontFaceAttachmentKind.audio,
        path: path,
        fileName: file.name,
        mimeType: 'audio/${file.extension ?? 'mpeg'}',
        byteLength: length,
      ),
    );
  }
}
