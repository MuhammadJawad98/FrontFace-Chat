import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/frontface_attachments_config.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../services/frontface_permission_gate.dart';
import 'frontface_current_location_sheet.dart';
import 'frontface_location_picker.dart';
import 'frontface_voice_recorder.dart';

/// Bottom sheet listing enabled attachment actions.
class FrontFaceAttachmentSheet {
  FrontFaceAttachmentSheet._();

  /// Prefer Android's system Photo Picker so gallery attach works without
  /// READ_MEDIA_IMAGES / READ_MEDIA_VIDEO (Play photo & video policy).
  static void _ensureAndroidPhotoPicker() {
    final impl = ImagePickerPlatform.instance;
    if (impl is ImagePickerAndroid) {
      impl.useAndroidPhotoPicker = true;
    }
  }

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
      showDragHandle: false,
      useSafeArea: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _AttachmentSheetBody(
          attachments: attachments,
          theme: theme,
          strings: strings,
          onPick: (action) async {
            Navigator.pop(sheetContext);
            switch (action) {
              case _SheetAction.location:
                await _pickLocation(
                  context: context,
                  attachments: attachments,
                  theme: theme,
                  strings: strings,
                  onLocation: onLocation,
                );
              case _SheetAction.gallery:
                await _pickImage(
                  context: context,
                  source: ImageSource.gallery,
                  attachments: attachments,
                  strings: strings,
                  onMedia: onMedia,
                );
              case _SheetAction.camera:
                await _pickImage(
                  context: context,
                  source: ImageSource.camera,
                  attachments: attachments,
                  strings: strings,
                  onMedia: onMedia,
                );
              case _SheetAction.recordVoice:
                await _recordVoice(
                  context: context,
                  attachments: attachments,
                  theme: theme,
                  strings: strings,
                  onMedia: onMedia,
                );
              case _SheetAction.audioFile:
                await _pickAudio(
                  context: context,
                  attachments: attachments,
                  strings: strings,
                  onMedia: onMedia,
                );
            }
          },
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
    if (!context.mounted) return;
    final key = attachments.googleMapsApiKey?.trim();
    final FrontFaceAttachmentPayload? payload;
    if (key != null && key.isNotEmpty) {
      payload = await FrontFaceLocationPickerScreen.open(
        context,
        theme: theme,
        strings: strings,
        googleMapsApiKey: key,
      );
    } else {
      // No Maps key — share current GPS without the map UI.
      payload = await FrontFaceCurrentLocationSheet.show(
        context,
        theme: theme,
        strings: strings,
      );
    }
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
    final bool ok;
    if (source == ImageSource.camera) {
      ok = await gate.ensure(
        context: context,
        permission: Permission.camera,
        strings: strings,
        rationaleTitle: strings.permissionCameraTitle,
        rationaleBody: strings.permissionCameraBody,
      );
    } else {
      // Android Photo Picker does not need READ_MEDIA_IMAGES; iOS still does.
      ok = await gate.ensurePhotoLibrary(
        context: context,
        strings: strings,
      );
    }
    if (!ok || !context.mounted) return;

    if (source == ImageSource.gallery) {
      _ensureAndroidPhotoPicker();
    }

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
    // Stay on file_picker 11.x: v12 pulls android_file_picker (Flutter ≥3.38)
    // and breaks many host Android release builds. v11 uses static pickFiles.
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'webm'],
      withData: false,
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return;
    final file = files.first;
    final path = file.path;
    if (path == null) return;

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

enum _SheetAction { location, gallery, camera, recordVoice, audioFile }

class _AttachmentSheetBody extends StatelessWidget {
  final FrontFaceAttachmentsConfig attachments;
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final Future<void> Function(_SheetAction action) onPick;

  const _AttachmentSheetBody({
    required this.attachments,
    required this.theme,
    required this.strings,
    required this.onPick,
  });

  List<_SheetItem> get _items {
    final items = <_SheetItem>[];
    if (attachments.enableLocation) {
      items.add(
        _SheetItem(
          action: _SheetAction.location,
          icon: Icons.location_on_rounded,
          label: strings.shareLocation,
          tint: const Color(0xFFE11D48),
        ),
      );
    }
    if (attachments.enableImages) {
      items.add(
        _SheetItem(
          action: _SheetAction.gallery,
          icon: Icons.photo_library_rounded,
          label: strings.attachPhoto,
          tint: const Color(0xFF2563EB),
        ),
      );
      items.add(
        _SheetItem(
          action: _SheetAction.camera,
          icon: Icons.photo_camera_rounded,
          label: strings.takePhoto,
          tint: const Color(0xFF0891B2),
        ),
      );
    }
    if (attachments.enableAudio) {
      items.add(
        _SheetItem(
          action: _SheetAction.recordVoice,
          icon: Icons.mic_rounded,
          label: strings.recordVoice,
          tint: const Color(0xFF7C3AED),
        ),
      );
      items.add(
        _SheetItem(
          action: _SheetAction.audioFile,
          icon: Icons.audio_file_rounded,
          label: strings.attachAudio,
          tint: const Color(0xFF059669),
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final useGrid = items.length >= 3;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.subtitleColor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  strings.attach,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.assistantBubbleTextColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (useGrid)
                _ActionGrid(
                  items: items,
                  theme: theme,
                  onPick: onPick,
                )
              else
                _ActionList(
                  items: items,
                  theme: theme,
                  onPick: onPick,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetItem {
  final _SheetAction action;
  final IconData icon;
  final String label;
  final Color tint;

  const _SheetItem({
    required this.action,
    required this.icon,
    required this.label,
    required this.tint,
  });
}

class _ActionGrid extends StatelessWidget {
  final List<_SheetItem> items;
  final FrontFaceChatTheme theme;
  final Future<void> Function(_SheetAction action) onPick;

  const _ActionGrid({
    required this.items,
    required this.theme,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Taller tiles so 2-line labels (e.g. "Record voice message") fit.
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return _GridTile(
          item: item,
          theme: theme,
          onTap: () => onPick(item.action),
        );
      },
    );
  }
}

class _GridTile extends StatelessWidget {
  final _SheetItem item;
  final FrontFaceChatTheme theme;
  final VoidCallback onTap;

  const _GridTile({
    required this.item,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.tint, size: 22),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: theme.assistantBubbleTextColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionList extends StatelessWidget {
  final List<_SheetItem> items;
  final FrontFaceChatTheme theme;
  final Future<void> Function(_SheetAction action) onPick;

  const _ActionList({
    required this.items,
    required this.theme,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ListRow(
            item: items[i],
            theme: theme,
            onTap: () => onPick(items[i].action),
          ),
        ],
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  final _SheetItem item;
  final FrontFaceChatTheme theme;
  final VoidCallback onTap;

  const _ListRow({
    required this.item,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.tint, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.assistantBubbleTextColor,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.subtitleColor.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
