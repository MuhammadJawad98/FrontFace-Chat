import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:frontface_chat/src/calls/api.dart' show packageVersion;
import 'package:frontface_chat/src/calls/device_api.dart';
import 'package:frontface_chat/src/calls/media.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

/// Calls from support: the phone registers, a push rings it, the customer answers or declines.
/// Outbound calls the customer makes are covered by call_session_test.dart and api_test.dart.

const deviceId = '5b0f6c1e-3d2a-4f7b-9c8e-1a2b3c4d5e6f';
const otherCallId = 'b7c1d2e3-f4a5-4b6c-8d9e-0f1a2b3c4d5e';

class MemoryStore implements CallDeviceStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

/// One request the fake API got.
class Seen {
  Seen(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, dynamic>? body;
  @override
  String toString() => '$method $path';
}

/// A fake FrontFace API for the device endpoints. Each route answers from a queue (the last answer
/// repeats); a route with no answers is a 404.
class DeviceServer {
  final seen = <Seen>[];
  final answers = <String, List<Future<http.Response> Function()>>{};
  var unreachable = false;

  void on(String route, http.Response response, {Duration delay = Duration.zero}) =>
      (answers[route] ??= []).add(() => Future.delayed(delay, () => response));

  late final client = MockClient((request) async {
    final body = request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>;
    seen.add(Seen(request.method, request.url.path, request.headers, body));
    if (unreachable) throw const SocketLikeError();
    final route = '${request.method} ${_route(request.url)}';
    final queue = answers[route];
    if (queue == null || queue.isEmpty) return http.Response('{"error":{"code":"NOT_FOUND"}}', 404);
    return (queue.length > 1 ? queue.removeAt(0) : queue.first)();
  });

  static String _route(Uri url) {
    final p = url.path;
    if (p.endsWith('/calls/devices')) return 'register';
    if (p.contains('/api/widget/calls/devices/')) return 'unregister';
    if (p.endsWith('/state')) return 'state';
    for (final action in ['answer', 'decline', 'end']) {
      if (p.endsWith('/$action')) return action;
    }
    if (p.startsWith('/api/widget/calls/')) return 'get';
    if (p.endsWith('/calls')) return 'start';
    return p;
  }

  List<Seen> to(String route) => seen.where((s) => '${s.method} ${_route(Uri.parse('https://x${s.path}'))}' == route).toList();
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}

http.Response json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> deviceCall(String status,
        {String id = callId, String? outcome, String? endDetail, String? endedBy, bool answeredHere = false, String? agent = 'Sara'}) =>
    {
      'call': {
        'id': id,
        'status': status,
        'outcome': outcome,
        'endDetail': endDetail,
        'endedBy': endedBy,
        'durationSeconds': null,
        'ringDeadlineAt': '2026-10-08T10:00:45Z',
        'answeredHere': answeredHere,
        'agent': agent == null ? null : {'name': agent},
      },
    };

Map<String, dynamic> answered({String token = 'tok-answer'}) => {
      ...deviceCall('active', answeredHere: true),
      'media': {'url': 'wss://media.example', 'token': token},
    };

String stored({String pushToken = 'push-1', DateTime? at, String secret = 'secret-1'}) => jsonEncode({
      'id': deviceId,
      'secret': secret,
      'pushToken': pushToken,
      'visitorId': 'visitor-1',
      'clientKey': 'pk_test',
      'registeredAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
    });

void main() {
  late DeviceServer server;
  late MemoryStore store;
  late Log log;
  late FakeMedia media;

  /// What an app (or a background handler, in a fresh process) builds: constants and the store only.
  FrontFaceCalls calls() => FrontFaceCalls(
        baseUrl: 'https://api.example',
        clientKey: 'pk_test',
        visitorId: 'visitor-1',
        appVersion: '24.9.6',
        deviceStore: store,
        httpClient: server.client,
        platformOverride: 'android',
        mediaFactory: () => media,
      );

  Future<void> register(FrontFaceCalls c, {String pushToken = 'push-1', bool force = false}) => c.registerDevice(
      conversationId: conversationId, sessionToken: 'session-1', pushToken: pushToken, force: force);

  setUp(() {
    server = DeviceServer();
    store = MemoryStore();
    log = [];
    media = FakeMedia(log);
  });

  group('registering the phone', () {
    test('registers with the push token and keeps the credential', () async {
      server.on('POST register', json(201, {'device': {'id': deviceId, 'secret': 'secret-1'}}));
      await register(calls());

      final request = server.to('POST register').single;
      expect(request.body, containsPair('pushToken', 'push-1'));
      expect(request.body, containsPair('platform', 'android'));
      expect(request.body, containsPair('packageVersion', '1.7.0'));
      expect(request.headers['x-frontface-session'], 'session-1');
      expect(request.headers.containsKey('x-frontface-device'), isFalse, reason: 'nothing to send yet');
      final kept = jsonDecode(store.value!) as Map<String, dynamic>;
      expect('${kept['id']}.${kept['secret']}', '$deviceId.secret-1');
    });

    test('a launch with nothing changed does not ask the server again', () async {
      store.value = stored();
      await register(calls());
      expect(server.seen, isEmpty);
    });

    test('a new push token re-registers with the credential, and the secret stays the same', () async {
      store.value = stored();
      server.on('POST register', json(200, {'device': {'id': deviceId}}));
      await register(calls(), pushToken: 'push-2');

      expect(server.to('POST register').single.headers['x-frontface-device'], '$deviceId.secret-1');
      final kept = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(kept['secret'], 'secret-1');
      expect(kept['pushToken'], 'push-2');
    });

    test('a day after the last registration, it registers again', () async {
      store.value = stored(at: DateTime.now().subtract(const Duration(hours: 25)));
      server.on('POST register', json(200, {'device': {'id': deviceId}}));
      await register(calls());
      expect(server.to('POST register'), hasLength(1));
    });

    test('when the server issues a new secret (its registration was gone), the new one is kept', () async {
      store.value = stored();
      server.on('POST register', json(201, {'device': {'id': deviceId, 'secret': 'secret-2'}}));
      await register(calls(), force: true);
      expect((jsonDecode(store.value!) as Map)['secret'], 'secret-2');
    });

    test('an unverified customer cannot register: nothing is kept', () async {
      server.on('POST register', json(403, {'error': {'code': 'NOT_VERIFIED', 'message': 'Only verified customers can take calls'}}));
      await expectLater(register(calls()),
          throwsA(isA<CallsException>().having((e) => e.code, 'code', CallsErrorCode.notVerified)));
      expect(store.value, isNull);
    });

    test('signing out unregisters with the credential and forgets it', () async {
      store.value = stored();
      server.on('DELETE unregister', http.Response('', 204));
      await calls().unregisterDevice();

      final request = server.to('DELETE unregister').single;
      expect(request.path, endsWith('/api/widget/calls/devices/$deviceId'));
      expect(request.headers['x-frontface-device'], '$deviceId.secret-1');
      expect(store.value, isNull);
    });

    test('signing out with no network keeps the registration, to try again later', () async {
      store.value = stored();
      server.unreachable = true;
      await expectLater(calls().unregisterDevice(),
          throwsA(isA<CallsException>().having((e) => e.code, 'code', CallsErrorCode.network)));
      expect(store.value, isNotNull);
    });

    test('signing out a phone that is not registered asks nothing', () async {
      await calls().unregisterDevice();
      expect(server.seen, isEmpty);
    });
  });

  group('pushes', () {
    test('an incoming call push (FCM data: all strings)', () {
      final push = FrontFaceCalls.parsePush({
        'v': '1',
        'type': 'call.incoming',
        'callId': callId,
        'agentName': 'Sara',
        'ringDeadlineAt': '2026-10-08T10:00:45Z',
      });
      expect(push, isA<IncomingCallPush>());
      push as IncomingCallPush;
      expect(push.callId, callId);
      expect(push.agentName, 'Sara');
      expect(push.ringDeadline, DateTime.utc(2026, 10, 8, 10, 0, 45));
    });

    test('the same keys at the top level of a VoIP payload, next to aps', () {
      final push = FrontFaceCalls.parsePush({'aps': {}, 'v': '1', 'type': 'call.incoming', 'callId': callId});
      expect(push, isA<IncomingCallPush>().having((p) => p.callId, 'callId', callId));
    });

    test('a call that stopped ringing elsewhere', () {
      final push = FrontFaceCalls.parsePush({'v': '1', 'type': 'call.ended', 'callId': callId, 'detail': 'answered_elsewhere'});
      expect(push, isA<CallEndedPush>().having((p) => p.detail, 'detail', CallEndDetail.answeredElsewhere));
    });

    test("the app's own pushes are not ours; a newer call push is ours but not read", () {
      final own = {'type': 'order.shipped', 'orderId': '42'};
      expect(FrontFaceCalls.isCallPush(own), isFalse);
      expect(FrontFaceCalls.parsePush(own), isNull);

      final newer = {'v': '2', 'type': 'call.incoming', 'callId': callId};
      expect(FrontFaceCalls.isCallPush(newer), isTrue, reason: 'the app must still leave it alone');
      expect(FrontFaceCalls.parsePush(newer), isNull);
    });
  });

  group('answering', () {
    test('answered from a fresh process: only the stored registration is needed, and the call starts connected',
        () async {
      store.value = stored();
      server.on('POST answer', json(200, answered()));
      final incoming = await calls().incomingCall(callId);
      final session = await incoming.answer();
      await settle();

      final request = server.to('POST answer').single;
      expect(request.path, '/api/widget/calls/$callId/answer');
      expect(request.headers['x-frontface-device'], '$deviceId.secret-1');
      expect(request.headers['x-frontface-key'], 'pk_test');
      expect(request.headers.containsKey('x-frontface-session'), isFalse, reason: 'no chat session needed');
      expect(media.tokens, ['tok-answer']);
      expect(session.state, isA<CallConnected>().having((s) => s.agentName, 'agent', 'Sara'),
          reason: 'the agent is already in the call; their name comes with the answer');
    });

    test('a phone that is not registered cannot take the call', () async {
      await expectLater(calls().incomingCall(callId),
          throwsA(isA<CallsException>().having((e) => e.code, 'code', CallsErrorCode.deviceNotRegistered)));
    });

    test('too late: answered on another phone', () async {
      store.value = stored();
      server.on('POST answer', json(409, {'error': {'code': 'CALL_ANSWERED_ELSEWHERE', 'message': '…'}}));
      final incoming = await calls().incomingCall(callId);
      await expectLater(incoming.answer(),
          throwsA(isA<CallsException>().having((e) => e.code, 'code', CallsErrorCode.callAnsweredElsewhere)));
    });

    test('after the audio drops, it rejoins by answering again, never by starting a call', () async {
      store.value = stored();
      server.on('POST answer', json(200, answered(token: 'tok-1')));
      server.on('POST answer', json(200, answered(token: 'tok-2')));
      server.on('GET get', json(200, deviceCall('active', answeredHere: true)));
      final session = await (await calls().incomingCall(callId)).answer();
      await settle();

      media.emit(const MediaDisconnected(DisconnectKind.connectionLost));
      await settle();

      expect(media.tokens, ['tok-1', 'tok-2']);
      expect(server.to('POST answer'), hasLength(2));
      expect(server.to('POST start'), isEmpty);
      expect(session.state, isA<CallConnected>());
    });

    test('if the call ended while the audio was down, the session ends with the server outcome', () async {
      store.value = stored();
      server.on('POST answer', json(200, answered()));
      server.on('POST answer', json(409, {'error': {'code': 'CALL_ENDED', 'message': '…'}}));
      server.on('GET get', json(200, deviceCall('active', answeredHere: true)));
      server.on('GET get', json(200, deviceCall('ended', outcome: 'completed', endedBy: 'agent', answeredHere: true)));
      final session = await (await calls().incomingCall(callId)).answer();
      await settle();
      final states = <CallState>[];
      session.changes.listen(states.add);

      media.emit(const MediaDisconnected(DisconnectKind.connectionLost));
      final last = await session.done;
      expect(last, isA<CallEnded>().having((s) => s.result.outcome, 'outcome', CallOutcome.completed));
      expect(states.whereType<CallReconnecting>(), isEmpty,
          reason: 'the server said the call is over: end at once, without trying to get it back');
    });

    test('hanging up tells the server first, then leaves the audio', () async {
      store.value = stored();
      server.on('POST answer', json(200, answered()));
      server.on('POST end', json(200, deviceCall('ended', outcome: 'completed', endedBy: 'customer', answeredHere: true)));
      final session = await (await calls().incomingCall(callId)).answer();
      await settle();
      log.clear();
      server.seen.clear();
      final result = await session.hangUp();

      expect(server.to('POST end').single.path, '/api/widget/calls/$callId/end');
      expect(log, ['media.disconnect']);
      expect(result.endedBy, CallEndedBy.customer);
    });

    test('declining tells the server, which records why the call ended', () async {
      store.value = stored();
      server.on('POST decline', json(200, deviceCall('ended', outcome: 'missed', endDetail: 'declined', endedBy: 'customer')));
      final result = await (await calls().incomingCall(callId)).decline();
      expect(server.to('POST decline').single.path, '/api/widget/calls/$callId/decline');
      expect(result.endDetail, CallEndDetail.declined);
    });

    test("answering while another call is on the line is refused, and the same call returns its session", () async {
      store.value = stored();
      server.on('POST answer', json(200, answered()));
      final c = calls();
      final session = await (await c.incomingCall(callId)).answer();
      expect(await (await c.incomingCall(callId)).answer(), same(session));

      server.answers['POST answer'] = [
        () async => json(200, {...answered(), 'call': {...answered()['call'] as Map, 'id': otherCallId}})
      ];
      await expectLater((await c.incomingCall(otherCallId)).answer(),
          throwsA(isA<CallsException>().having((e) => e.code, 'code', CallsErrorCode.callInProgress)));
    });
  });

  group('while it rings', () {
    test('learns when the agent cancels, from a long poll', () async {
      store.value = stored();
      server.on('GET state', json(200, deviceCall('ringing')), delay: const Duration(milliseconds: 30));
      server.on('GET state', json(200, deviceCall('ended', outcome: 'cancelled', endDetail: 'agent_cancelled', endedBy: 'agent')));
      final result = await (await calls().incomingCall(callId)).stoppedRinging;

      expect(result.endDetail, CallEndDetail.agentCancelled);
      final polls = server.to('GET state');
      expect(polls, hasLength(2));
      expect(polls.first.path, '/api/widget/calls/$callId/state');
    });

    test('the long poll is allowed longer than a normal request (the server holds it up to 25 s)', () async {
      server.on('GET state', json(200, deviceCall('ringing')), delay: const Duration(milliseconds: 120));
      server.on('GET get', json(200, deviceCall('ringing')), delay: const Duration(milliseconds: 120));
      final api = DeviceApi(
        baseUrl: 'https://api.example',
        clientKey: 'pk_test',
        credential: '$deviceId.secret-1',
        httpClient: server.client,
        timeout: const Duration(milliseconds: 50),
      );
      expect((await api.state(callId)).status, 'ringing');
      await expectLater(api.get(callId),
          throwsA(isA<CallsException>().having((e) => e.code, 'code', CallsErrorCode.network)));
    });

    test('a network failure is retried; the answer still arrives', () async {
      store.value = stored();
      server.on('GET state', json(200, deviceCall('ended', outcome: 'missed', endDetail: 'no_answer', endedBy: 'system')));
      final incoming = IncomingCall.internal(
        callId: callId,
        api: DeviceApi(baseUrl: 'https://api.example', clientKey: 'pk_test', credential: '$deviceId.secret-1', httpClient: server.client),
        join: (_) => throw UnimplementedError(),
        retryDelays: const [Duration(milliseconds: 10)],
      );
      server.unreachable = true;
      final stopped = incoming.stoppedRinging;
      await settle();
      server.unreachable = false;
      expect((await stopped).endDetail, CallEndDetail.noAnswer);
    });

    test('a phone whose registration is gone stops ringing and forgets the registration', () async {
      store.value = stored();
      server.on('GET state', json(401, {'error': {'code': 'DEVICE_INVALID', 'message': '…'}}));
      final result = await (await calls().incomingCall(callId)).stoppedRinging;
      await settle();

      expect(result.isEnded, isTrue);
      expect(store.value, isNull, reason: 'the next registerDevice must register again, not skip');
    });
  });

  test('the version a phone registers with is the package version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(pubspec)?.group(1), packageVersion);
  });

  test('a call the customer makes while support is calling them is refused with that call', () async {
    server.on('POST start', json(409, {
      'error': {'code': 'CALL_IN_PROGRESS', 'message': 'A call from support is in progress', 'call': {'id': callId, 'direction': 'outbound'}},
    }));
    await expectLater(
      calls().startCall(conversationId: conversationId, sessionToken: 'session-1'),
      throwsA(isA<CallsException>()
          .having((e) => e.code, 'code', CallsErrorCode.callInProgress)
          .having((e) => e.callId, 'callId', callId)),
    );
    expect(server.to('POST start').single.headers['x-frontface-calls-version'], '2');
  });
}
