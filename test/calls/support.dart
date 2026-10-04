import 'dart:async';
import 'dart:convert';

import 'package:frontface_chat/src/calls/api.dart';
import 'package:frontface_chat/src/calls/media.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const callId = 'eafec9d4-2d8a-4e8b-ad9b-9df5dd51dac9';
const conversationId = '776dce36-5947-4c41-a825-a25ddc0da7fc';

/// Everything the session did, in order, across the API and the audio connection.
typedef Log = List<String>;

String metadata(String state, [int? queuePosition]) =>
    jsonEncode({'v': 1, 'state': state, 'queuePosition': queuePosition});

Map<String, dynamic> callJson(
  String status, {
  String? outcome,
  String? endedBy,
  int? duration,
  String? agent,
  String id = callId,
}) =>
    {
      'call': {
        'id': id,
        'status': status,
        'outcome': outcome,
        'endedBy': endedBy,
        'durationSeconds': duration,
        'queuePosition': null,
        'agent': agent == null ? null : {'name': agent},
      },
    };

Map<String, dynamic> startJson({String status = 'ringing', int? position = 1, String token = 'tok-1', String id = callId}) => {
      'call': {
        'id': id,
        'status': status,
        'queuePosition': position,
        'ringDeadlineAt': '2026-10-03T00:22:13Z',
        'createdAt': '2026-10-03T00:21:28Z',
      },
      'media': {'url': 'wss://media.example', 'token': token},
    };

/// A fake FrontFace API. Each route answers from a queue (the last answer repeats).
class FakeServer {
  FakeServer(this.log);
  final Log log;
  final getAnswers = <http.Response>[];
  final startAnswers = <http.Response>[];
  final endAnswers = <http.Response>[];
  final endBodies = <Map<String, dynamic>>[];

  static http.Response json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  http.Response _next(List<http.Response> answers) =>
      answers.length > 1 ? answers.removeAt(0) : answers.first;

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/calls/$callId')) {
      log.add('GET call');
      return _next(getAnswers);
    }
    if (request.method == 'POST' && path.endsWith('/calls')) {
      log.add('POST start');
      return _next(startAnswers);
    }
    if (request.method == 'POST' && path.endsWith('/end')) {
      log.add('POST end');
      endBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _next(endAnswers);
    }
    return http.Response('not found', 404);
  });

  CallsApi api() => CallsApi(
        baseUrl: 'https://api.example',
        clientKey: 'pk_test',
        visitorId: 'visitor-1',
        conversationId: conversationId,
        sessionToken: 'session-1',
        httpClient: client,
      );
}

/// A fake audio connection: records what the session asks of it; tests push events into it.
class FakeMedia implements MediaConnection {
  FakeMedia(this.log);
  final Log log;
  final _events = StreamController<MediaEvent>.broadcast();
  final tokens = <String>[];
  bool failConnect = false;
  bool? micEnabled;

  @override
  String? roomMetadata;

  void emit(MediaEvent event) => _events.add(event);

  @override
  Stream<MediaEvent> get events => _events.stream;

  @override
  Future<void> connect(String url, String token) async {
    log.add('media.connect');
    tokens.add(token);
    if (failConnect) throw StateError('could not reach the media server');
    micEnabled = true;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async => micEnabled = enabled;

  @override
  Future<void> setSpeakerOn(bool on) async {}

  @override
  Future<void> disconnect() async => log.add('media.disconnect');

  @override
  Future<void> dispose() async => _events.close();
}

/// Lets queued events and futures run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
