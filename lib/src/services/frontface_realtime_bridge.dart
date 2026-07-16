import 'dart:async';

import 'package:realtime_client/realtime_client.dart';

/// Abstraction over Supabase Realtime so unit tests can inject a fake.
abstract class FrontFaceRealtimeBridge {
  bool get isConnected;

  /// Connects with [apiKey] as the socket apikey and [jwt] via [setAuth].
  Future<bool> connect({
    required String supabaseUrl,
    required String apiKey,
    required String jwt,
    required String conversationId,
    required void Function(String event, Map<String, dynamic> payload) onEvent,
    required void Function() onDisconnected,
  });

  Future<void> refreshAuth(String jwt);

  Future<void> disconnect();
}

/// Production bridge using `realtime_client`.
class FrontFaceSupabaseRealtimeBridge implements FrontFaceRealtimeBridge {
  RealtimeClient? _client;
  RealtimeChannel? _channel;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect({
    required String supabaseUrl,
    required String apiKey,
    required String jwt,
    required String conversationId,
    required void Function(String event, Map<String, dynamic> payload) onEvent,
    required void Function() onDisconnected,
  }) async {
    await disconnect();

    final endpoint = _toRealtimeEndpoint(supabaseUrl);
    final client = RealtimeClient(
      endpoint,
      params: {'apikey': apiKey},
    );
    _client = client;

    await client.setAuth(jwt);
    // subscribe() opens the socket when needed (connect() is package-internal).

    final channel = client.channel(
      'conversation:$conversationId',
      const RealtimeChannelConfig(self: false, private: true),
    );
    _channel = channel;

    final completer = Completer<bool>();

    void handle(String event, Map<String, dynamic> payload) {
      onEvent(event, payload);
    }

    channel
      ..onBroadcast(
        event: 'typing:start',
        callback: (payload) => handle('typing:start', payload),
      )
      ..onBroadcast(
        event: 'typing:stop',
        callback: (payload) => handle('typing:stop', payload),
      )
      ..onBroadcast(
        event: 'message:new',
        callback: (payload) => handle('message:new', payload),
      )
      ..onBroadcast(
        event: 'conversation:status_changed',
        callback: (payload) => handle('conversation:status_changed', payload),
      )
      ..onBroadcast(
        event: 'conversation:assigned',
        callback: (payload) => handle('conversation:assigned', payload),
      )
      ..onBroadcast(
        event: 'queue:position_updated',
        callback: (payload) => handle('queue:position_updated', payload),
      )
      ..onBroadcast(
        event: 'conversation:resolved',
        callback: (payload) => handle('conversation:resolved', payload),
      )
      ..subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _connected = true;
          if (!completer.isCompleted) completer.complete(true);
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          _connected = false;
          onDisconnected();
          if (!completer.isCompleted) completer.complete(false);
        }
      });

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _connected = false;
        return false;
      },
    );
  }

  @override
  Future<void> refreshAuth(String jwt) async {
    await _client?.setAuth(jwt);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.unsubscribe();
      } catch (_) {}
    }
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  static String _toRealtimeEndpoint(String supabaseUrl) {
    final uri = Uri.parse(supabaseUrl.trim());
    final scheme = uri.scheme == 'http' ? 'ws' : 'wss';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/realtime/v1',
    ).toString();
  }
}
