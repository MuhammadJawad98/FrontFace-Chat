import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';

void main() {
  group('FrontFaceAttachmentsConfig', () {
    test('disabled by default', () {
      expect(FrontFaceAttachmentsConfig.disabled.anyEnabled, isFalse);
      FrontFaceAttachmentsConfig.disabled.validate();
    });

    test('location requires googleMapsApiKey', () {
      expect(
        () => const FrontFaceAttachmentsConfig(enableLocation: true).validate(),
        throwsArgumentError,
      );
      const FrontFaceAttachmentsConfig(
        enableLocation: true,
        googleMapsApiKey: 'AIza-test',
      ).validate();
    });

    test('media requires uploader', () {
      expect(
        () => const FrontFaceAttachmentsConfig(enableImages: true).validate(),
        throwsArgumentError,
      );
    });
  });

  group('FrontFaceAttachmentPayload', () {
    test('location message content includes maps URL', () {
      const payload = FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.location,
        latitude: 25.2,
        longitude: 55.27,
        label: 'Office',
      );
      final content = payload.toMessageContent();
      expect(content, contains('📍 Office'));
      expect(content, contains('https://maps.google.com/?q=25.2,55.27'));
    });

    test('toMessageContent uses localized strings when provided', () {
      const ar = FrontFaceChatStrings(
        sharedLocation: 'موقع مشترك',
        imageAttachment: 'صورة',
      );
      const location = FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.location,
        latitude: 1,
        longitude: 2,
      );
      expect(location.toMessageContent(ar), contains('موقع مشترك'));

      const image = FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.image,
        url: 'https://cdn.example.com/a.jpg',
      );
      expect(image.toMessageContent(ar), startsWith('🖼️ صورة'));
    });

    test('tryParse recovers location from content', () {
      final parsed = FrontFaceAttachmentPayload.tryParse(
        content: '📍 Shared location\nhttps://maps.google.com/?q=1.5,2.5',
      );
      expect(parsed?.kind, FrontFaceAttachmentKind.location);
      expect(parsed?.latitude, 1.5);
      expect(parsed?.longitude, 2.5);
    });

    test('tryParse recovers image from content', () {
      final parsed = FrontFaceAttachmentPayload.tryParse(
        content: '🖼️ Image\nhttps://cdn.example.com/a.jpg',
      );
      expect(parsed?.kind, FrontFaceAttachmentKind.image);
      expect(parsed?.url, 'https://cdn.example.com/a.jpg');
    });
  });
}
