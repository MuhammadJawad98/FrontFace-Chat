/// Why the Call button should be hidden (from `GET …/calls/availability`).
enum CallUnavailableReason {
  /// Calling is not set up on the server.
  notConfigured,

  /// Calls are switched off for this project.
  disabled,

  /// Only verified (identified) customers can call.
  notVerified,

  /// Outside the project's business hours.
  outsideHours,

  /// No agent is online right now.
  noAgents,

  /// Calling is temporarily unavailable (the media service is failing).
  providerUnavailable,

  /// A reason this package version does not know yet. Treat it as "hide the button".
  unknown;

  static CallUnavailableReason parse(String? value) => switch (value) {
        'not_configured' => notConfigured,
        'disabled' => disabled,
        'not_verified' => notVerified,
        'outside_hours' => outsideHours,
        'no_agents' => noAgents,
        'provider_unavailable' => providerUnavailable,
        _ => unknown,
      };
}

/// Whether to show the Call button.
class CallAvailability {
  const CallAvailability.available()
      : available = true,
        reason = null;
  const CallAvailability.unavailable(CallUnavailableReason this.reason)
      : available = false;

  final bool available;

  /// Set when [available] is false.
  final CallUnavailableReason? reason;

  @override
  String toString() =>
      available ? 'CallAvailability(available)' : 'CallAvailability($reason)';
}

/// How a call ended.
enum CallOutcome {
  /// The customer and an agent talked; [CallResult.durationSeconds] is set.
  completed,

  /// Nobody answered before the ring limit.
  missed,

  /// The customer hung up before anyone answered.
  cancelled,

  /// The call never connected (the app could not reach the media server).
  failed,

  /// An answered call was cut off (network lost, app killed) and did not come back in time.
  dropped,

  /// An outcome this package version does not know, or the app could not ask the server.
  unknown;

  static CallOutcome parse(String? value) => switch (value) {
        'completed' => completed,
        'missed' => missed,
        'cancelled' => cancelled,
        'failed' => failed,
        'dropped' => dropped,
        _ => unknown,
      };
}

/// Why a call from support ended without being answered on this phone (set by the server for calls from
/// support only).
enum CallEndDetail {
  /// The customer declined it (or hung up before answering).
  declined,

  /// Nobody answered before the ring time ran out.
  noAnswer,

  /// None of the customer's phones could be reached.
  unreachable,

  /// Another of the customer's phones answered it.
  answeredElsewhere,

  /// The agent cancelled before anyone answered.
  agentCancelled,

  /// A reason this package version does not know.
  unknown;

  static CallEndDetail? parse(String? value) => switch (value) {
        null => null,
        'declined' => declined,
        'no_answer' => noAnswer,
        'unreachable' => unreachable,
        'answered_elsewhere' => answeredElsewhere,
        'agent_cancelled' => agentCancelled,
        _ => unknown,
      };
}

/// Who ended the call.
enum CallEndedBy {
  customer,
  agent,

  /// The server (ring limit, connection lost, maximum length).
  system,
  unknown;

  static CallEndedBy parse(String? value) => switch (value) {
        'customer' => customer,
        'agent' => agent,
        'system' => system,
        _ => unknown,
      };
}

/// The server's view of a call (`GET …/calls/{callId}` and `POST …/end`).
class CallResult {
  const CallResult({
    required this.callId,
    required this.status,
    required this.outcome,
    required this.endedBy,
    required this.durationSeconds,
    required this.queuePosition,
    required this.agentName,
    this.endDetail,
    this.answeredHere,
  });

  /// What the app reports when it could not reach the server to ask.
  const CallResult.unknown(this.callId)
      : status = 'ended',
        outcome = CallOutcome.unknown,
        endedBy = CallEndedBy.unknown,
        durationSeconds = null,
        queuePosition = null,
        agentName = null,
        endDetail = null,
        answeredHere = null;

  factory CallResult.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'];
    return CallResult(
      callId: json['id'] as String,
      status: json['status'] as String,
      outcome: json['outcome'] == null
          ? null
          : CallOutcome.parse(json['outcome'] as String?),
      endedBy: json['endedBy'] == null
          ? null
          : CallEndedBy.parse(json['endedBy'] as String?),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      queuePosition: (json['queuePosition'] as num?)?.toInt(),
      agentName: agent is Map ? agent['name'] as String? : null,
      endDetail: CallEndDetail.parse(json['endDetail'] as String?),
      answeredHere: json['answeredHere'] as bool?,
    );
  }

  final String callId;

  /// `ringing`, `active` or `ended`.
  final String status;

  /// Set once [status] is `ended`.
  final CallOutcome? outcome;
  final CallEndedBy? endedBy;

  /// Talk time for an answered call.
  final int? durationSeconds;

  /// 1 = next in line, while ringing.
  final int? queuePosition;

  /// The agent who answered (display name), if any. For a call from support: the agent who called.
  final String? agentName;

  /// For a call from support that was not answered here: why it ended.
  final CallEndDetail? endDetail;

  /// For a call from support: whether it was answered on this phone (null for calls the customer made).
  final bool? answeredHere;

  bool get isEnded => status == 'ended';

  @override
  String toString() =>
      'CallResult($callId, $status, outcome: $outcome, endedBy: $endedBy, '
      'duration: $durationSeconds, agent: $agentName'
      '${endDetail == null ? '' : ', detail: $endDetail'})';
}

/// A request the server refused, or a failure reaching it.
class CallsException implements Exception {
  const CallsException({
    required this.status,
    required this.code,
    required this.message,
    this.retryAfterSeconds,
    this.callId,
  });

  /// HTTP status, or 0 when the server could not be reached.
  final int status;

  /// The API's error code, for example `NO_AGENTS_AVAILABLE` (see [CallsErrorCode]).
  final String code;
  final String message;

  /// For `RATE_LIMITED`: seconds until a new call can be started.
  final int? retryAfterSeconds;

  /// For `CALL_IN_PROGRESS`: the call from support that is open, to answer (or rejoin) instead.
  final String? callId;

  @override
  String toString() => 'CallsException($status $code: $message)';
}

/// The error codes the call endpoints return, plus [network] for "no response".
abstract final class CallsErrorCode {
  static const callsDisabled = 'CALLS_DISABLED';
  static const notVerified = 'NOT_VERIFIED';
  static const noAgentsAvailable = 'NO_AGENTS_AVAILABLE';
  static const callsBusy = 'CALLS_BUSY';
  static const outsideHours = 'OUTSIDE_HOURS';
  static const callsUnavailable = 'CALLS_UNAVAILABLE';
  static const rateLimited = 'RATE_LIMITED';
  static const notFound = 'NOT_FOUND';
  static const clientKeyRequired = 'CLIENT_KEY_REQUIRED';
  static const sessionInvalid = 'SESSION_INVALID';

  /// A call from support is open for this customer; [CallsException.callId] is that call.
  static const callInProgress = 'CALL_IN_PROGRESS';

  /// Calls from support: the call is over (cancelled, missed, or ended) before this phone acted on it.
  static const callEnded = 'CALL_ENDED';

  /// Calls from support: another of the customer's phones answered.
  static const callAnsweredElsewhere = 'CALL_ANSWERED_ELSEWHERE';

  /// Calls from support: this phone's registration is gone (signed out, or replaced). Register again.
  static const deviceInvalid = 'DEVICE_INVALID';

  /// Calls from support: this phone has not registered (no stored credential).
  static const deviceNotRegistered = 'DEVICE_NOT_REGISTERED';

  /// Calls from support: the push token is registered to another account that hasn't signed out on this
  /// phone. Carry on; it registers once that account signs out.
  static const tokenInUse = 'TOKEN_IN_USE';

  /// The server could not be reached (no network, timeout).
  static const network = 'NETWORK';
}
