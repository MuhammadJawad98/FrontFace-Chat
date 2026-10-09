import 'dart:async';

import 'api.dart';
import 'call_session.dart';
import 'device_api.dart';
import 'models.dart';

/// A push FrontFace sent this phone for a call from support. Read one with [parseCallPush].
sealed class CallPush {
  const CallPush(this.callId);

  /// Use it as the system call screen's id (CallKit / ConnectionService): it is a UUID.
  final String callId;
}

/// Support is calling: ring (show the system call screen) right away.
final class IncomingCallPush extends CallPush {
  const IncomingCallPush(super.callId, {this.agentName, this.ringDeadline});

  /// Who is calling, to show on the call screen.
  final String? agentName;

  /// When the server stops the ring; null if the push did not say.
  final DateTime? ringDeadline;
}

/// The call stopped ringing elsewhere (cancelled, answered on another phone): dismiss the call screen.
/// Android only; an iPhone learns it from [IncomingCall.stoppedRinging].
final class CallEndedPush extends CallPush {
  const CallEndedPush(super.callId, {this.detail});
  final CallEndDetail? detail;
}

/// Whether a push is one of FrontFace's call pushes (any version): the app's own push handling must
/// leave these alone. On Android they arrive as FCM data messages alongside the app's own.
bool isCallPushData(Map<dynamic, dynamic> data) {
  final type = data['type'];
  return type is String && type.startsWith('call.') && data['v'] != null;
}

/// Reads a call push (the FCM message's `data`, or the VoIP push's payload: the same keys, at the top
/// level). Null for anything else, including call pushes of a version this package does not know.
CallPush? parseCallPush(Map<dynamic, dynamic> data) {
  if ('${data['v']}' != '1') return null;
  final callId = data['callId'];
  if (callId is! String || callId.isEmpty) return null;
  return switch (data['type']) {
    'call.incoming' => IncomingCallPush(
        callId,
        agentName: data['agentName'] as String?,
        ringDeadline: DateTime.tryParse('${data['ringDeadlineAt'] ?? ''}'),
      ),
    'call.ended' => CallEndedPush(callId, detail: CallEndDetail.parse(data['detail'] as String?)),
    _ => null,
  };
}

/// A call from support ringing on this phone: answer it, decline it, and learn when it stops ringing.
///
/// Get one from `FrontFaceCalls.incomingCall` when the push arrives, or when the customer acts on the
/// system call screen, even in a fresh app process: it needs only the stored registration.
class IncomingCall {
  IncomingCall.internal({
    required this.callId,
    this.agentName,
    required DeviceApi api,
    required Future<CallSession> Function(StartedCall answered) join,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ],
  })  : _api = api,
        _join = join;

  final String callId;

  /// From the push, when there was one.
  final String? agentName;

  /// Waits between attempts when the state request fails (the network, not the server's answer).
  final List<Duration> retryDelays;

  final DeviceApi _api;
  final Future<CallSession> Function(StartedCall answered) _join;
  Future<CallResult>? _stopped;
  bool _closed = false;

  /// The server's view of the call now (for example, on opening the app from a push).
  Future<CallResult> status() => _api.get(callId);

  /// Answers and joins the audio. The session starts connected: the agent is already in the call.
  /// Answering again (after the app was closed mid-call) rejoins. Throws [CallsException] with
  /// [CallsErrorCode.callEnded] or [CallsErrorCode.callAnsweredElsewhere] when it is too late.
  Future<CallSession> answer() async => _join(await _api.answer(callId));

  /// Declines while it rings. Returns the server's record of the call.
  Future<CallResult> decline() => _api.decline(callId);

  /// Completes with the server's view once the call no longer rings on this phone: answered (here,
  /// [CallResult.answeredHere], or on another phone), cancelled, missed or declined. Dismiss the
  /// system call screen when it completes and was not answered here. Asks the server with a long poll,
  /// from the first time it is read until it completes or [close] is called.
  Future<CallResult> get stoppedRinging => _stopped ??= _pollUntilNotRinging();

  /// Stops asking the server ([stoppedRinging] then never completes).
  void close() => _closed = true;

  Future<CallResult> _pollUntilNotRinging() async {
    var failures = 0;
    while (!_closed) {
      try {
        final call = await _api.state(callId);
        failures = 0;
        if (call.status != 'ringing') return call;
      } on CallsException catch (e) {
        // Not this phone's call any more (another account signed in), or this phone's registration
        // is gone: it must stop ringing either way.
        if (e.status == 401 || e.status == 404) return CallResult.unknown(callId);
        await Future<void>.delayed(retryDelays[failures.clamp(0, retryDelays.length - 1)]);
        failures++;
      }
    }
    return Completer<CallResult>().future;
  }
}
