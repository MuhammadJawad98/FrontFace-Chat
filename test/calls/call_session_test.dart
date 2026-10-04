import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/frontface_chat.dart';
import 'package:frontface_chat/src/calls/api.dart';
import 'package:frontface_chat/src/calls/media.dart';

import 'support.dart';

void main() {
  late Log log;
  late FakeServer server;
  late FakeMedia media;
  late List<CallState> seen;

  Future<CallSession> started({String status = 'ringing', int? position = 2}) async {
    final api = server.api();
    final call = await api.start();
    final session = CallSession.internal(
      api: api,
      media: media,
      started: call,
      rejoinWindow: const Duration(milliseconds: 200),
      retryDelays: const [Duration(milliseconds: 10)],
    );
    seen.add(session.state);
    session.changes.listen(seen.add);
    await session.start(call);
    await settle();
    return session;
  }

  setUp(() {
    log = [];
    server = FakeServer(log);
    media = FakeMedia(log);
    seen = [];
    server.startAnswers.add(FakeServer.json(201, startJson(position: 2)));
  });

  test('rings with the queue position, connects, gets the agent name, then shows the server outcome', () async {
    media.roomMetadata = metadata('ringing', 2);
    final session = await started();
    expect(session.state, isA<CallRinging>().having((s) => s.queuePosition, 'position', 2));

    media.emit(MetadataChanged(metadata('connected')));
    await settle();
    expect(session.state, isA<CallConnected>().having((s) => s.agentName, 'agent', null));

    media.emit(const RemoteJoined('Sara'));
    await settle();
    expect(session.state, isA<CallConnected>().having((s) => s.agentName, 'agent', 'Sara'));

    // The agent hangs up: the server closes the room; the app reads the outcome once.
    server.getAnswers.add(FakeServer.json(200,
        callJson('ended', outcome: 'completed', endedBy: 'agent', duration: 8, agent: 'Sara')));
    media.emit(const MediaDisconnected(DisconnectKind.closedByServer));
    final last = await session.done;

    expect(last, isA<CallEnded>());
    final result = (last as CallEnded).result;
    expect(result.outcome, CallOutcome.completed);
    expect(result.endedBy, CallEndedBy.agent);
    expect(result.durationSeconds, 8);
    expect(log, isNot(contains('POST end')), reason: 'the app never ends a call the server ended');
    expect(seen.whereType<CallRinging>(), isNotEmpty);
  });

  test('an answered call that loses its audio rejoins the same call with a fresh token', () async {
    media.roomMetadata = metadata('connected');
    final session = await started(status: 'active');
    expect(session.state, isA<CallConnected>());

    server.getAnswers.add(FakeServer.json(200, callJson('active')));
    server.startAnswers
      ..clear()
      ..add(FakeServer.json(200, startJson(status: 'active', position: null, token: 'tok-2')));
    media.emit(const MediaDisconnected(DisconnectKind.connectionLost));
    await settle();

    expect(media.tokens, ['tok-1', 'tok-2'], reason: 'the first token is never reused');
    expect(session.state, isA<CallConnected>());
    expect(session.isOver, isFalse);
    expect(log, isNot(contains('POST end')));
  });

  test('when the same customer joins from elsewhere the call goes on there and is not ended here', () async {
    media.roomMetadata = metadata('connected');
    final session = await started(status: 'active');

    media.emit(const MediaDisconnected(DisconnectKind.duplicateIdentity));
    final last = await session.done;

    expect(last, isA<CallContinuedElsewhere>());
    expect(log, isNot(contains('POST end')));
  });

  test('hanging up tells the server before leaving the audio', () async {
    media.roomMetadata = metadata('connected');
    final session = await started(status: 'active');
    server.endAnswers.add(FakeServer.json(200,
        callJson('ended', outcome: 'completed', endedBy: 'customer', duration: 31, agent: 'Sara')));

    final result = await session.hangUp();

    expect(log.indexOf('POST end'), lessThan(log.indexOf('media.disconnect')));
    expect(server.endBodies.single, isEmpty, reason: 'a plain hang-up');
    expect(result.outcome, CallOutcome.completed);
    expect(session.state, isA<CallEnded>());
  });

  test('when the audio cannot connect the server is told connect_failed and the call ends as failed', () async {
    media.failConnect = true;
    server.endAnswers.add(FakeServer.json(200, callJson('ended', outcome: 'failed', endedBy: 'customer')));

    final session = await started();

    expect(server.endBodies.single, {'reason': 'connect_failed'});
    expect(session.state, isA<CallEnded>().having((s) => s.result.outcome, 'outcome', CallOutcome.failed));
  });

  test('a call the server ended while the app was offline shows the server outcome', () async {
    media.roomMetadata = metadata('connected');
    final session = await started(status: 'active');

    server.getAnswers
      ..add(FakeServer.json(200, callJson('active')))
      ..add(FakeServer.json(200, callJson('ended', outcome: 'dropped', endedBy: 'system', duration: 40)));
    server.startAnswers
      ..clear()
      ..add(FakeServer.json(503, {'error': {'code': 'CALLS_UNAVAILABLE', 'message': 'down'}}));
    media.emit(const MediaDisconnected(DisconnectKind.connectionLost));
    final last = await session.done;

    expect(seen, contains(isA<CallReconnecting>()));
    expect((last as CallEnded).result.outcome, CallOutcome.dropped);
    expect(log, isNot(contains('POST end')));
  });

  test('a new call created by a rejoin after the old one ended is hung up at once', () async {
    media.roomMetadata = metadata('connected');
    final session = await started(status: 'active');

    server.getAnswers
      ..add(FakeServer.json(200, callJson('active')))
      ..add(FakeServer.json(200, callJson('ended', outcome: 'completed', endedBy: 'agent', duration: 12)));
    server.startAnswers
      ..clear()
      ..add(FakeServer.json(201, startJson(id: 'f0000000-0000-4000-8000-000000000000', token: 'tok-new')));
    server.endAnswers.add(FakeServer.json(200, callJson('ended', outcome: 'cancelled', id: 'f0000000-0000-4000-8000-000000000000')));
    media.emit(const MediaDisconnected(DisconnectKind.connectionLost));
    final last = await session.done;

    expect(media.tokens, isNot(contains('tok-new')), reason: 'never joins a call nobody asked for');
    expect(log, contains('POST end'));
    expect((last as CallEnded).result.outcome, CallOutcome.completed);
  });

  test('mute survives a rejoin', () async {
    media.roomMetadata = metadata('connected');
    final session = await started(status: 'active');
    await session.setMuted(true);
    expect(media.micEnabled, isFalse);

    server.getAnswers.add(FakeServer.json(200, callJson('active')));
    server.startAnswers
      ..clear()
      ..add(FakeServer.json(200, startJson(status: 'active', position: null, token: 'tok-2')));
    media.emit(const MediaDisconnected(DisconnectKind.connectionLost));
    await settle();

    expect(media.tokens.last, 'tok-2');
    expect(media.micEnabled, isFalse);
  });

  test('StartedCall marks a rejoin (200) apart from a new call (201)', () async {
    server.startAnswers
      ..clear()
      ..add(FakeServer.json(200, startJson()));
    final StartedCall again = await server.api().start();
    expect(again.created, isFalse);
  });
}
