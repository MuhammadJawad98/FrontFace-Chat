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

  test(
    'history keeps every customer hello even when text matches',
    () async {
      SharedPreferences.setMockInitialValues({
        'frontface_visitor_id': 'mob_stable_visitor',
        'frontface_lead_completed_${testConfig.projectId}': true,
      });

      final page = jsonDecode('''
{
  "messages": [
    {
      "id": "21ee3151-e546-4dca-9bf2-b1cf56dded2e",
      "senderType": "customer",
      "content": "how are you",
      "metadata": {},
      "parts": [],
      "createdAt": "2026-09-13T11:59:57.979932+00:00"
    },
    {
      "id": "d49cbac8-620f-40be-b669-1798ae8a7a5a",
      "senderType": "customer",
      "content": "hello",
      "metadata": {},
      "parts": [],
      "createdAt": "2026-09-13T11:59:43.342835+00:00"
    },
    {
      "id": "72105401-f9d2-48a8-8f2d-6812ccd07de9",
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

      final hellos = provider.messages.where((m) => m.content == 'hello').toList();
      expect(hellos, hasLength(2));
      expect(
        hellos.map((m) => m.id),
        containsAll([
          'd49cbac8-620f-40be-b669-1798ae8a7a5a',
          '72105401-f9d2-48a8-8f2d-6812ccd07de9',
        ]),
      );
      expect(
        provider.messages.any((m) => m.content == 'how are you'),
        isTrue,
      );
    },
  );

  test(
    'history keeps every API message id including many identical hellos',
    () async {
      SharedPreferences.setMockInitialValues({
        'frontface_visitor_id': 'mob_stable_visitor',
        'frontface_lead_completed_${testConfig.projectId}': true,
      });

      final hellos = List.generate(
        6,
        (i) => {
          'id': 'hello_$i',
          'senderType': 'customer',
          'content': 'hello',
          'metadata': {},
          'parts': [],
          'createdAt':
              DateTime.utc(2026, 8, 24 + i, 10, 0, 0).toIso8601String(),
        },
      );

      final fake = FakeApiManager(testConfig)
        ..embedConfigResponse = _lead
        ..leadCaptureCompleted = true
        ..customerHistoryResponse = hellos;

      final api = FrontFaceApiService(config: testConfig, apiManager: fake);
      final provider = FrontFaceChatProvider(
        config: testConfig,
        api: api,
        store: FrontFaceVisitorStore(),
      );
      await provider.initialize();

      expect(provider.messages, hasLength(6));
      expect(
        provider.messages.every((m) => m.content == 'hello'),
        isTrue,
      );
      expect(
        provider.messages.map((m) => m.id).toSet(),
        hasLength(6),
      );
    },
  );
}
