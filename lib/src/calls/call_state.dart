import 'models.dart';

/// What the call screen shows. A [CallSession] moves through these in order; [CallEnded] and
/// [CallContinuedElsewhere] are final.
sealed class CallState {
  const CallState();
}

/// Joining the audio (a second or two after tapping Call, or while rejoining).
final class CallConnecting extends CallState {
  const CallConnecting();
  @override
  String toString() => 'CallConnecting';
}

/// Waiting for an agent. [queuePosition] 1 = next in line (null when unknown).
final class CallRinging extends CallState {
  const CallRinging(this.queuePosition);
  final int? queuePosition;
  @override
  String toString() => 'CallRinging($queuePosition)';
}

/// An agent answered. [agentName] arrives a moment after the answer, when the agent's audio joins:
/// this state is emitted again with the name.
final class CallConnected extends CallState {
  const CallConnected({required this.since, this.agentName});

  /// When the answer was seen, for the call timer.
  final DateTime since;
  final String? agentName;
  @override
  String toString() => 'CallConnected($agentName)';
}

/// The network dropped for a moment; the package is getting the audio back. Keep the call screen.
final class CallReconnecting extends CallState {
  const CallReconnecting();
  @override
  String toString() => 'CallReconnecting';
}

/// The call is over. [result] is the server's record (outcome, duration, agent); its outcome is
/// [CallOutcome.unknown] only if the server could not be reached to ask.
final class CallEnded extends CallState {
  const CallEnded(this.result);
  final CallResult result;
  @override
  String toString() => 'CallEnded($result)';
}

/// The same customer joined this call from another device or session, which took the audio over.
/// The call itself goes on there; this session stops.
final class CallContinuedElsewhere extends CallState {
  const CallContinuedElsewhere();
  @override
  String toString() => 'CallContinuedElsewhere';
}
