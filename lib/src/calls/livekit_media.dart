import 'dart:async';
import 'dart:io' show Platform;

import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_noise_filter/livekit_noise_filter.dart';

import 'media.dart';

/// The audio connection on LiveKit, the media server behind FrontFace calls. The only file in this
/// package that knows the vendor.
class LiveKitMedia implements MediaConnection {
  LiveKitMedia({required this.noiseCancellation, required this.speakerOnAtStart});

  /// Krisp noise cancellation on the customer's microphone (iOS and Android only).
  final bool noiseCancellation;
  final bool speakerOnAtStart;

  final _events = StreamController<MediaEvent>.broadcast();
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  LiveKitNoiseFilter? _noiseFilter;
  bool _disconnecting = false;

  bool get _mobile => Platform.isIOS || Platform.isAndroid;

  @override
  Stream<MediaEvent> get events => _events.stream;

  @override
  String? get roomMetadata => _room?.metadata;

  @override
  Future<void> connect(String url, String token) async {
    await _closeRoom();
    _disconnecting = false;
    if (noiseCancellation && _noiseFilter == null && await LiveKitNoiseFilter.isSupported()) {
      _noiseFilter = LiveKitNoiseFilter();
    }
    final room = Room(
      roomOptions: RoomOptions(
        defaultAudioCaptureOptions: AudioCaptureOptions(
          noiseSuppression: true,
          echoCancellation: true,
          processor: _noiseFilter,
        ),
      ),
    );
    final listener = room.createListener()
      ..on<RoomMetadataChangedEvent>((e) => _emit(MetadataChanged(e.metadata)))
      ..on<ParticipantConnectedEvent>((e) => _emit(RemoteJoined(e.participant.name)))
      ..on<ParticipantDisconnectedEvent>((_) => _emit(const RemoteLeft()))
      ..on<ActiveSpeakersChangedEvent>(
        (e) => _emit(RemoteSpeaking(e.speakers.any((p) => p is RemoteParticipant))),
      )
      ..on<RoomReconnectingEvent>((_) => _emit(const MediaReconnecting()))
      ..on<RoomReconnectedEvent>((_) => _emit(const MediaReconnected()))
      ..on<RoomDisconnectedEvent>((e) => _emit(MediaDisconnected(_kind(e.reason))));
    _room = room;
    _listener = listener;

    await room.connect(url, token, connectOptions: const ConnectOptions(autoSubscribe: true));
    await room.localParticipant?.setMicrophoneEnabled(true);
    if (_mobile) await AudioManager.instance.setSpeakerOutputPreferred(speakerOnAtStart);
    // The agent may already be in the room (a rejoin).
    for (final p in room.remoteParticipants.values) {
      _emit(RemoteJoined(p.name));
    }
  }

  DisconnectKind _kind(DisconnectReason? reason) {
    if (_disconnecting || reason == DisconnectReason.clientInitiated) return DisconnectKind.byUs;
    return switch (reason) {
      DisconnectReason.duplicateIdentity => DisconnectKind.duplicateIdentity,
      DisconnectReason.roomDeleted ||
      DisconnectReason.participantRemoved ||
      DisconnectReason.serverShutdown =>
        DisconnectKind.closedByServer,
      _ => DisconnectKind.connectionLost,
    };
  }

  void _emit(MediaEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> setSpeakerOn(bool on) async {
    if (_mobile) await AudioManager.instance.setSpeakerOutputPreferred(on);
  }

  @override
  Future<void> disconnect() async {
    _disconnecting = true;
    await _room?.disconnect();
  }

  Future<void> _closeRoom() async {
    final room = _room, listener = _listener;
    _room = null;
    _listener = null;
    await listener?.dispose();
    if (room != null) {
      _disconnecting = true;
      await room.disconnect();
      await room.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    await _closeRoom();
    await _events.close();
  }
}
