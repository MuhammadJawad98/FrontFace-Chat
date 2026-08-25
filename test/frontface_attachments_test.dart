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

    test('media does not require host uploader', () {
      const FrontFaceAttachmentsConfig(enableImages: true).validate();
      const FrontFaceAttachmentsConfig(enableAudio: true).validate();
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

    test('toLocationData maps API fields', () {
      final data = FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.location,
        latitude: 24.7,
        longitude: 46.6,
        accuracyMeters: 12,
        label: 'Riyadh',
        capturedAt: DateTime.utc(2026, 8, 24, 18, 20),
      ).toLocationData();
      expect(data?.toJson(), {
        'latitude': 24.7,
        'longitude': 46.6,
        'accuracy_m': 12.0,
        'label': 'Riyadh',
        'captured_at': '2026-08-24T18:20:00.000Z',
      });
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

  group('FrontFaceMessagePart', () {
    test('parses location / image / audio parts from history JSON', () {
      final locationMsg = FrontFaceChatMessage.fromJson({
        'id': 'm1',
        'content': '',
        'senderType': 'customer',
        'createdAt': '2026-08-24T18:20:00Z',
        'parts': [
          {
            'type': 'location',
            'derivedText': 'Al Olaya',
            'payload': {
              'latitude': 24.7136,
              'longitude': 46.6753,
              'label': 'Al Olaya',
            },
          },
        ],
      });
      expect(locationMsg.parts.single.type, FrontFaceMessagePartType.location);
      expect(locationMsg.attachment?.latitude, 24.7136);
      expect(locationMsg.attachment?.label, 'Al Olaya');

      final imageMsg = FrontFaceChatMessage.fromJson({
        'id': 'm2',
        'content': '',
        'senderType': 'customer',
        'createdAt': '2026-08-24T18:21:00Z',
        'parts': [
          {
            'type': 'image',
            'url': 'https://cdn.example.com/signed.jpg',
            'derivedText': 'meal photo',
            'mediaAssetId': 'asset-img',
          },
        ],
      });
      expect(imageMsg.attachment?.kind, FrontFaceAttachmentKind.image);
      expect(imageMsg.attachment?.url, 'https://cdn.example.com/signed.jpg');
      expect(imageMsg.attachment?.derivedText, 'meal photo');

      final audioMsg = FrontFaceChatMessage.fromJson({
        'id': 'm3',
        'content': '',
        'senderType': 'customer',
        'createdAt': '2026-08-24T18:22:00Z',
        'parts': [
          {
            'type': 'audio',
            'url': 'https://cdn.example.com/voice.m4a',
            'processingStatus': 'ready',
            'derivedText': 'please deliver tomorrow',
            'payload': {'duration_ms': 4200},
          },
        ],
      });
      expect(audioMsg.attachment?.kind, FrontFaceAttachmentKind.audio);
      expect(
        audioMsg.attachment?.processingStatus,
        FrontFaceMediaProcessingStatus.ready,
      );
      expect(audioMsg.attachment?.derivedText, 'please deliver tomorrow');
    });
  });
}
