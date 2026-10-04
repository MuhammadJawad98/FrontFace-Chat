/// The audio connection, as the call logic needs it. The only implementation that talks to the media
/// server is `LiveKitMedia`; tests use a fake.
abstract interface class MediaConnection {
  Stream<MediaEvent> get events;

  /// The room metadata right after connecting (the server's state at that moment).
  String? get roomMetadata;

  /// Connects and turns the microphone on. Throws if the media server cannot be reached.
  Future<void> connect(String url, String token);
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setSpeakerOn(bool on);
  Future<void> disconnect();
  Future<void> dispose();
}

sealed class MediaEvent {
  const MediaEvent();
}

final class MetadataChanged extends MediaEvent {
  const MetadataChanged(this.metadata);
  final String? metadata;
}

/// The agent's audio joined (the only other participant a call room admits).
final class RemoteJoined extends MediaEvent {
  const RemoteJoined(this.name);
  final String? name;
}

final class RemoteLeft extends MediaEvent {
  const RemoteLeft();
}

/// Whether the agent is speaking right now.
final class RemoteSpeaking extends MediaEvent {
  const RemoteSpeaking(this.speaking);
  final bool speaking;
}

final class MediaReconnecting extends MediaEvent {
  const MediaReconnecting();
}

final class MediaReconnected extends MediaEvent {
  const MediaReconnected();
}

enum DisconnectKind {
  /// This app disconnected (hang-up).
  byUs,

  /// The same identity joined from elsewhere and took the place over.
  duplicateIdentity,

  /// The server closed the room or removed this participant: the call ended (or is ending).
  closedByServer,

  /// The connection was lost and the media library gave up reconnecting.
  connectionLost,
}

final class MediaDisconnected extends MediaEvent {
  const MediaDisconnected(this.kind);
  final DisconnectKind kind;
}
