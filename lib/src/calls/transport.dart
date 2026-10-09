import 'api.dart';
import 'models.dart';

/// How a [CallSession] talks to the server about its call: the conversation API for a call the customer
/// made, the device API for a call from support. The session's rules are the same for both.
abstract interface class CallTransport {
  /// The server's record of the call.
  Future<CallResult> get(String callId);

  /// Hangs up ([connectFailed] false) or reports that the audio connection could not be made.
  Future<CallResult> end(String callId, {bool connectFailed = false});

  /// A fresh media token to join this same call again after the audio dropped. Throws when the server
  /// could not be reached (the session tries again).
  Future<RejoinResult> rejoin(String callId);
}

sealed class RejoinResult {
  const RejoinResult();
}

/// Join again with this.
final class Rejoin extends RejoinResult {
  const Rejoin(this.call);
  final StartedCall call;
}

/// The call is over; there is nothing to join.
final class CallGone extends RejoinResult {
  const CallGone();
}
