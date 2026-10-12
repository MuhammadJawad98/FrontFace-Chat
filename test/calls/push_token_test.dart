import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemStore implements CallDeviceStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  group('looksLikeIosVoipPushToken', () {
    test('accepts 64 hex', () {
      expect(
        looksLikeIosVoipPushToken('a' * 64),
        isTrue,
      );
      expect(
        looksLikeIosVoipPushToken('${'AbCdEf0123456789' * 4}'),
        isTrue,
      );
    });

    test('rejects FCM and wrong length', () {
      expect(
        looksLikeIosVoipPushToken(
          'cXk2abc:APA91b${'x' * 120}',
        ),
        isFalse,
      );
      expect(looksLikeIosVoipPushToken('a' * 63), isFalse);
      expect(looksLikeFcmPushToken('cXk2:APA91bxx'), isTrue);
    });
  });

  test('registerDevice on iOS rejects FCM-shaped tokens', () async {
    final calls = FrontFaceCalls(
      baseUrl: 'https://api.example',
      clientKey: 'pk_test',
      visitorId: 'visitor-1',
      deviceStore: _MemStore(),
      platformOverride: 'ios',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      calls.registerDevice(
        conversationId: 'conv-1',
        sessionToken: 'session-1',
        pushToken: 'cXk2abc:APA91b${'x' * 100}',
      ),
      throwsA(
        isA<CallsException>().having(
          (e) => e.code,
          'code',
          CallsErrorCode.invalidPushToken,
        ),
      ),
    );
  });
}
