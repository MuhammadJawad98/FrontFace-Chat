import 'dart:convert';

/// Where the package keeps this phone's registration for calls from support between launches. The
/// value includes a secret: keep it in secure storage (Keychain / Keystore), for example with
/// flutter_secure_storage. The background push handler must be able to read it too.
abstract interface class CallDeviceStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// What the package stores: the credential, and what it was registered with (to skip registering again
/// when nothing changed).
class StoredDevice {
  const StoredDevice({
    required this.id,
    required this.secret,
    required this.pushToken,
    required this.visitorId,
    required this.clientKey,
    required this.registeredAt,
  });

  final String id;
  final String secret;
  final String pushToken;
  final String visitorId;
  final String clientKey;
  final DateTime registeredAt;

  /// `X-FrontFace-Device`.
  String get credential => '$id.$secret';

  /// Registered with these, less than [maxAge] ago: no need to register again.
  bool isFresh({
    required String pushToken,
    required String visitorId,
    required String clientKey,
    required DateTime now,
    Duration maxAge = const Duration(hours: 24),
  }) =>
      pushToken == this.pushToken &&
      visitorId == this.visitorId &&
      clientKey == this.clientKey &&
      now.difference(registeredAt) < maxAge;

  String encode() => jsonEncode({
        'id': id,
        'secret': secret,
        'pushToken': pushToken,
        'visitorId': visitorId,
        'clientKey': clientKey,
        'registeredAt': registeredAt.toUtc().toIso8601String(),
      });

  /// Null for anything that is not a value this package wrote.
  static StoredDevice? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map) return null;
      return StoredDevice(
        id: json['id'] as String,
        secret: json['secret'] as String,
        pushToken: json['pushToken'] as String,
        visitorId: json['visitorId'] as String,
        clientKey: json['clientKey'] as String,
        registeredAt: DateTime.parse(json['registeredAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
