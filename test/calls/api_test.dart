import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:frontface_chat/src/calls/api.dart';
import 'package:frontface_chat/src/calls/room_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

CallsApi apiAnswering(http.Response Function(http.Request) answer) => CallsApi(
      baseUrl: 'https://api.example/',
      clientKey: 'pk_test',
      visitorId: 'visitor-1',
      conversationId: conversationId,
      sessionToken: 'session-1',
      httpClient: MockClient((request) async => answer(request)),
    );

void main() {
  test('sends the chat credentials and the platform with a start', () async {
    late http.Request sent;
    final api = apiAnswering((request) {
      sent = request;
      return FakeServer.json(201, startJson());
    });

    final call = await api.start(platform: 'ios', appVersion: '5.2.0');

    expect(sent.url.toString(), 'https://api.example/api/widget/conversations/$conversationId/calls');
    expect(sent.headers['X-FrontFace-Key'], 'pk_test');
    expect(sent.headers['X-Visitor-Id'], 'visitor-1');
    expect(sent.headers['X-FrontFace-Session'], 'session-1');
    expect(jsonDecode(sent.body), {'platform': 'ios', 'appVersion': '5.2.0'});
    expect(call.created, isTrue);
    expect(call.queuePosition, 1);
    expect(call.mediaToken, 'tok-1');
  });

  test('availability says why the button is hidden', () async {
    for (final (body, expected) in [
      ({'available': true}, null),
      ({'available': false, 'reason': 'no_agents'}, CallUnavailableReason.noAgents),
      ({'available': false, 'reason': 'outside_hours'}, CallUnavailableReason.outsideHours),
      ({'available': false, 'reason': 'something_new'}, CallUnavailableReason.unknown),
    ]) {
      final result = await apiAnswering((_) => FakeServer.json(200, body)).availability();
      expect(result.available, expected == null, reason: '$body');
      expect(result.reason, expected, reason: '$body');
    }
  });

  test('refusals become CallsException with the API code', () async {
    final busy = apiAnswering((_) => FakeServer.json(409, {
          'error': {'code': 'NO_AGENTS_AVAILABLE', 'message': 'No agent is available to take a call'},
        }));
    await expectLater(
      busy.start(),
      throwsA(isA<CallsException>()
          .having((e) => e.status, 'status', 409)
          .having((e) => e.code, 'code', CallsErrorCode.noAgentsAvailable)),
    );

    final limited = apiAnswering((_) => FakeServer.json(429, {
          'error': {'code': 'RATE_LIMITED', 'message': 'Too many requests', 'retryAfter': 590},
        }));
    await expectLater(
      limited.start(),
      throwsA(isA<CallsException>().having((e) => e.retryAfterSeconds, 'retryAfter', 590)),
    );

    final gateway = apiAnswering((_) => http.Response('<html>bad gateway</html>', 502));
    await expectLater(
      gateway.start(),
      throwsA(isA<CallsException>().having((e) => e.code, 'code', 'HTTP_502')),
    );

    final offline = CallsApi(
      baseUrl: 'https://api.example',
      clientKey: 'k',
      visitorId: 'v',
      conversationId: conversationId,
      sessionToken: 's',
      httpClient: MockClient((_) async => throw const SocketLikeError()),
    );
    await expectLater(
      offline.availability(),
      throwsA(isA<CallsException>().having((e) => e.code, 'code', CallsErrorCode.network)),
    );
  });

  test('the outcome reads every field the app shows', () async {
    final result = await apiAnswering((_) => FakeServer.json(
        200, callJson('ended', outcome: 'missed', endedBy: 'system'))).get(callId);
    expect(result.isEnded, isTrue);
    expect(result.outcome, CallOutcome.missed);
    expect(result.endedBy, CallEndedBy.system);
    expect(result.agentName, isNull);
    expect(result.durationSeconds, isNull);
  });

  test('room metadata: only version 1 of the contract is read', () {
    expect(parseRoomState('{"v":1,"state":"ringing","queuePosition":3}')?.queuePosition, 3);
    expect(parseRoomState('{"v":1,"state":"connected","queuePosition":null}')?.state, 'connected');
    for (final other in [null, '', 'not json', '{"v":2,"state":"ringing"}', '{"v":1}']) {
      expect(parseRoomState(other), isNull, reason: '$other');
    }
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
