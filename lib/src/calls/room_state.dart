import 'dart:convert';

/// What the server publishes in the call room's metadata: `{"v":1,"state":…,"queuePosition":…}`.
class RoomState {
  const RoomState(this.state, this.queuePosition);

  /// `ringing`, `connected` or `ended`.
  final String state;
  final int? queuePosition;
}

/// Reads the room metadata; null for anything that is not version 1 of the contract.
RoomState? parseRoomState(String? metadata) {
  if (metadata == null || metadata.isEmpty) return null;
  try {
    final json = jsonDecode(metadata);
    if (json is! Map || json['v'] != 1) return null;
    final state = json['state'];
    if (state is! String) return null;
    return RoomState(state, (json['queuePosition'] as num?)?.toInt());
  } on FormatException {
    return null;
  }
}
