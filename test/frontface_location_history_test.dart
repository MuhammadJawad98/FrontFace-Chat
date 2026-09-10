import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:frontface_chat/src/services/frontface_api_service.dart';
import 'package:frontface_chat/src/services/frontface_visitor_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_api_manager.dart';

final _lead = {
  'enabled': true,
  'config': {'greeting': 'Hi!', 'placeholder': ''},
  'leadCapture': {
    'enabled': true,
    'capture_mode': 'email_after',
    'formFields': {
      'email': {'required': true},
    },
  },
};

void main() {
  test(
    'history keeps every location message even when coords match',
    () async {
      SharedPreferences.setMockInitialValues({
        'frontface_visitor_id': 'mob_stable_visitor',
        'frontface_lead_completed_${testConfig.projectId}': true,
      });

      final page = jsonDecode('''
{
  "messages": [
    {
      "id": "loc_new",
      "senderType": "customer",
      "content": "",
      "metadata": {},
      "parts": [{
        "type": "location",
        "position": 0,
        "payload": {
          "label": "34 Ellis St, San Francisco, CA 94102, USA",
          "latitude": 37.785834,
          "longitude": -122.406417
        },
        "derivedText": "Customer shared location"
      }],
      "createdAt": "2026-09-09T00:13:51.915678+00:00"
    },
    {
      "id": "loc_old",
      "senderType": "customer",
      "content": "",
      "metadata": {},
      "parts": [{
        "type": "location",
        "position": 0,
        "payload": {
          "label": "34 Ellis St, San Francisco, CA 94102, USA",
          "latitude": 37.785834,
          "longitude": -122.406417
        },
        "derivedText": "Customer shared location"
      }],
      "createdAt": "2026-09-08T23:51:16.893995+00:00"
    },
    {
      "id": "hello1",
      "senderType": "customer",
      "content": "hello",
      "metadata": {},
      "parts": [],
      "createdAt": "2026-09-08T23:48:17.221053+00:00"
    }
  ]
}
''') as Map<String, dynamic>;

      final messages = (page['messages'] as List).cast<Map<String, dynamic>>();
      final fake = FakeApiManager(testConfig)
        ..embedConfigResponse = _lead
        ..leadCaptureCompleted = true
        ..customerHistoryResponse = messages;

      final api = FrontFaceApiService(config: testConfig, apiManager: fake);
      final provider = FrontFaceChatProvider(
        config: testConfig,
        api: api,
        store: FrontFaceVisitorStore(),
      );
      await provider.initialize();

      final locations = provider.messages
          .where((m) => m.attachment?.kind == FrontFaceAttachmentKind.location)
          .toList();
      expect(locations, hasLength(2));
      expect(locations.map((m) => m.id), containsAll(['loc_new', 'loc_old']));
    },
  );

  testWidgets('empty-content location part renders the location card', (
    tester,
  ) async {
    final message = FrontFaceChatMessage.fromJson(
      jsonDecode('''
{
  "id": "loc1",
  "senderType": "customer",
  "content": "",
  "metadata": {},
  "parts": [{
    "type": "location",
    "payload": {
      "label": "34 Ellis St, San Francisco, CA 94102, USA",
      "latitude": 37.785834,
      "longitude": -122.406417
    },
    "derivedText": "Customer shared location"
  }],
  "createdAt": "2026-09-09T00:13:51.915678+00:00"
}
''') as Map<String, dynamic>,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FrontFaceMessageBubble(
            message: message,
            theme: const FrontFaceChatTheme(),
          ),
        ),
      ),
    );

    expect(find.text('34 Ellis St, San Francisco, CA 94102, USA'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
  });
}
