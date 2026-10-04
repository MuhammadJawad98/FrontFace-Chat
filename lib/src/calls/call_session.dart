import 'dart:async';

import 'api.dart';
import 'call_state.dart';
import 'media.dart';
import 'models.dart';
import 'room_state.dart';

/// One call, from tapping Call to the end. Read [state] and listen to [changes] to drive the call
/// screen.
///
/// Rules this class follows (CALLS_GUIDE.md §5):
/// - Hanging up tells the server first, then leaves the audio. Leaving first would make an answered
///   call end as "dropped" after the server's 30 s grace instead of "completed".
/// - It never ends a call on its own: when the audio drops it asks the server, and rejoins while the
///   server still has the call ringing or active (with a fresh token from `POST …/calls`).
/// - The outcome shown at the end is always the server's (`GET …/calls/{id}`).
class CallSession {
  CallSession.internal({
    required CallsApi api,
    required MediaConnection media,
    required StartedCall started,
    this.platform,
    this.appVersion,
    this.rejoinWindow = const Duration(seconds: 25),
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)],
  })  : _api = api,
        _media = media,
        _callId = started.callId {
    _subscription = _media.events.listen(_onEvent);
  }

  final CallsApi _api;
  final MediaConnection _media;
  final String? platform;
  final String? appVersion;

  /// How long to keep trying to get the audio back after a drop (the server waits 30 s).
  final Duration rejoinWindow;
  final List<Duration> retryDelays;

  final String _callId;
  final _states = StreamController<CallState>.broadcast();
  final _speaking = StreamController<bool>.broadcast();
  late final StreamSubscription<MediaEvent> _subscription;

  CallState _state = const CallConnecting();
  CallState? _beforeReconnect;
  DateTime? _connectedSince;
  String? _agentName;
  bool _muted = false;
  bool _hangingUp = false;
  bool _recovering = false;
  final _done = Completer<CallState>();

  String get callId => _callId;

  /// The state now.
  CallState get state => _state;

  /// Every change from the moment you listen (a broadcast stream; it is always the same stream, so
  /// it is safe to pass to a StreamBuilder in `build`). Read [state] for the state now, for example
  /// as the StreamBuilder's `initialData`. Closes after a final state.
  Stream<CallState> get changes => _states.stream;

  /// Completes with [CallEnded] or [CallContinuedElsewhere].
  Future<CallState> get done => _done.future;

  /// True while the agent is speaking (for a speaking indicator).
  Stream<bool> get agentSpeaking => _speaking.stream;

  bool get muted => _muted;

  /// True once the call reached [CallEnded] or [CallContinuedElsewhere].
  bool get isOver => _isFinal(_state);

  static bool _isFinal(CallState s) => s is CallEnded || s is CallContinuedElsewhere;

  /// Joins the audio for a call that `POST …/calls` just returned.
  Future<void> start(StartedCall started) async {
    try {
      await _media.connect(started.mediaUrl, started.mediaToken);
    } catch (_) {
      // Never reached the media server: tell the server, which records the call as failed.
      CallResult? result;
      try {
        result = await _api.end(_callId, connectFailed: true);
      } catch (_) {}
      _finish(CallEnded(result ?? CallResult.unknown(_callId)));
      return;
    }
    if (_muted) await _media.setMicrophoneEnabled(false);
    _applyRoomState(parseRoomState(_media.roomMetadata) ??
        RoomState(started.status == 'active' ? 'connected' : 'ringing', started.queuePosition));
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    await _media.setMicrophoneEnabled(!muted);
  }

  Future<void> setSpeakerOn(bool on) => _media.setSpeakerOn(on);

  /// Ends the call for everyone and returns the server's record of it.
  Future<CallResult> hangUp() async {
    if (_state case CallEnded(:final result)) return result;
    _hangingUp = true;
    CallResult? result;
    try {
      result = await _api.end(_callId);
    } catch (_) {}
    await _media.disconnect();
    result ??= await _tryGet();
    _finish(CallEnded(result ?? CallResult.unknown(_callId)));
    return result ?? CallResult.unknown(_callId);
  }

  /// Releases the audio and listeners. Does not end the call; call [hangUp] first.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _media.dispose();
    await _states.close();
    await _speaking.close();
  }

  void _onEvent(MediaEvent event) {
    if (_isFinal(_state)) return;
    switch (event) {
      case MetadataChanged(:final metadata):
        final room = parseRoomState(metadata);
        if (room != null) _applyRoomState(room);
      case RemoteJoined(:final name):
        // Only the agent who answered is ever admitted, so the call is answered even if the
        // metadata update has not arrived yet.
        _agentName = name ?? _agentName;
        if (!_recovering) _setConnected();
      case RemoteLeft():
        break; // The server decides: the agent coming back, or the call ending.
      case RemoteSpeaking(:final speaking):
        if (!_speaking.isClosed) _speaking.add(speaking);
      case MediaReconnecting():
        if (_state is! CallReconnecting) _beforeReconnect = _state;
        _emit(const CallReconnecting());
      case MediaReconnected():
        _emit(_beforeReconnect ?? const CallConnecting());
      case MediaDisconnected(:final kind):
        switch (kind) {
          case DisconnectKind.byUs:
            break;
          case DisconnectKind.duplicateIdentity:
            // The customer joined from elsewhere. The call goes on there: never end it from here.
            _finish(const CallContinuedElsewhere());
          case DisconnectKind.closedByServer:
          case DisconnectKind.connectionLost:
            unawaited(_recover());
        }
    }
  }

  void _applyRoomState(RoomState room) {
    switch (room.state) {
      case 'ringing':
        if (_state is! CallConnected) _emit(CallRinging(room.queuePosition));
      case 'connected':
        _setConnected();
      case 'ended':
        unawaited(_recover());
    }
  }

  void _setConnected() {
    _connectedSince ??= DateTime.now();
    _emit(CallConnected(since: _connectedSince!, agentName: _agentName));
  }

  /// The audio dropped or the room closed: ask the server, and rejoin while it still has the call
  /// ringing or active. Only the server's "ended" ends the call here.
  Future<void> _recover() async {
    if (_hangingUp || _recovering || _isFinal(_state)) return;
    _recovering = true;
    if (_state is! CallReconnecting) _beforeReconnect = _state;
    final deadline = DateTime.now().add(rejoinWindow);
    try {
      for (var attempt = 0;; attempt++) {
        if (_hangingUp) return;
        final current = await _tryGet();
        if (current != null && current.isEnded) {
          _finish(CallEnded(current));
          return;
        }
        if (current != null && await _rejoin()) return;
        if (DateTime.now().isAfter(deadline)) break;
        if (attempt == 0) _emit(const CallReconnecting());
        await Future<void>.delayed(retryDelays[attempt.clamp(0, retryDelays.length - 1)]);
      }
      // Out of time: whatever the server recorded (it ends a call whose customer is gone).
      final last = await _tryGet();
      _finish(CallEnded(last != null && last.isEnded ? last : CallResult.unknown(_callId)));
    } finally {
      _recovering = false;
    }
  }

  /// Gets a fresh token for this same call and joins again. False if that failed for now.
  Future<bool> _rejoin() async {
    final StartedCall again;
    try {
      again = await _api.start(platform: platform, appVersion: appVersion);
    } catch (_) {
      return false;
    }
    if (again.callId != _callId) {
      // This call ended in between and the request started a new one, which nobody asked for.
      try {
        await _api.end(again.callId);
      } catch (_) {}
      final ended = await _tryGet();
      _finish(CallEnded(ended ?? CallResult.unknown(_callId)));
      return true;
    }
    try {
      await _media.connect(again.mediaUrl, again.mediaToken);
    } catch (_) {
      return false;
    }
    if (_muted) await _media.setMicrophoneEnabled(false);
    _recovering = false;
    _applyRoomState(parseRoomState(_media.roomMetadata) ??
        RoomState(again.status == 'active' ? 'connected' : 'ringing', again.queuePosition));
    return true;
  }

  Future<CallResult?> _tryGet() async {
    try {
      return await _api.get(_callId);
    } catch (_) {
      return null;
    }
  }

  void _emit(CallState next) {
    if (_isFinal(_state)) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _finish(CallState last) {
    if (_isFinal(_state)) return;
    _emit(last);
    if (!_done.isCompleted) _done.complete(last);
    unawaited(_states.close());
  }
}
