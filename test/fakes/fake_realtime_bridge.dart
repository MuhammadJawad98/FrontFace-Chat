import 'package:frontface_chat/src/services/frontface_realtime_bridge.dart';

/// In-memory Realtime bridge for provider tests.
class FakeRealtimeBridge implements FrontFaceRealtimeBridge {
  bool _connected = false;
  void Function(String event, Map<String, dynamic> payload)? onEvent;
  void Function()? onDisconnected;
  String? lastJwt;
  String? lastApiKey;
  String? lastConversationId;
  int connectCount = 0;
  int disconnectCount = 0;
  bool failNextConnect = false;

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
    connectCount++;
    lastApiKey = apiKey;
    lastJwt = jwt;
    lastConversationId = conversationId;
    this.onEvent = onEvent;
    this.onDisconnected = onDisconnected;
    if (failNextConnect) {
      failNextConnect = false;
      _connected = false;
      return false;
    }
    _connected = true;
    return true;
  }

  @override
  Future<void> refreshAuth(String jwt) async {
    lastJwt = jwt;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    _connected = false;
  }

  void emit(String event, Map<String, dynamic> payload) {
    onEvent?.call(event, payload);
  }

  void emitDisconnected() {
    _connected = false;
    onDisconnected?.call();
  }
}
