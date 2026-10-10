import 'dart:async';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'api.dart';
import 'call_session.dart';
import 'device_api.dart';
import 'device_store.dart';
import 'incoming.dart';
import 'livekit_media.dart';
import 'media.dart';
import 'models.dart';

/// Where an iPhone's VoIP pushes go: `sandbox` for builds run from Xcode, `production` for TestFlight
/// and the App Store.
enum ApnsEnvironment { sandbox, production }

/// Entry point: check whether the customer can call, start a call, and take calls from support.
///
/// Uses the same credentials as the chat: the project's mobile client key, the install's visitor
/// id, and the `conversationId` + `sessionToken` pair from `ensure-conversation`. Calls from support
/// also need a [deviceStore], where the phone's registration is kept.
class FrontFaceCalls {
  FrontFaceCalls({
    required this.baseUrl,
    required this.clientKey,
    required this.visitorId,
    this.appVersion,
    this.noiseCancellation = true,
    this.speakerOnAtStart = false,
    this.deviceStore,
    http.Client? httpClient,
    @visibleForTesting this.platformOverride,
    @visibleForTesting this.mediaFactory,
  }) : _httpClient = httpClient;

  /// `https://api.frontface.app` in production.
  final String baseUrl;
  final String clientKey;
  final String visitorId;

  /// Sent with each call, so problems can be matched to an app release.
  final String? appVersion;

  /// Krisp noise cancellation on the customer's microphone, on iOS and Android only.
  ///
  /// If Krisp fails during connect, [LiveKitMedia] retries once without it.
  final bool noiseCancellation;

  /// Start on the loudspeaker instead of the earpiece (iOS and Android).
  final bool speakerOnAtStart;

  /// Keeps this phone's registration for calls from support (secure storage). Needed for
  /// [registerDevice], [unregisterDevice] and [incomingCall].
  final CallDeviceStore? deviceStore;

  /// `ios` or `android` on a desktop test run; apps leave it null.
  @visibleForTesting
  final String? platformOverride;

  /// The audio connection, replaced in tests.
  @visibleForTesting
  final MediaConnection Function()? mediaFactory;

  final http.Client? _httpClient;
  CallSession? _active;

  String? get _platform =>
      platformOverride ??
      (Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : null);

  CallsApi _api(String conversationId, String sessionToken) => CallsApi(
        baseUrl: baseUrl,
        clientKey: clientKey,
        visitorId: visitorId,
        conversationId: conversationId,
        sessionToken: sessionToken,
        httpClient: _httpClient,
        platform: _platform,
        appVersion: appVersion,
      );

  MediaConnection _media() =>
      mediaFactory?.call() ??
      LiveKitMedia(noiseCancellation: noiseCancellation, speakerOnAtStart: speakerOnAtStart);

  /// Whether to show the Call button. Check when the chat opens (and on resume), not in a loop.
  Future<CallAvailability> availability({
    required String conversationId,
    required String sessionToken,
  }) =>
      _api(conversationId, sessionToken).availability();

  /// Starts a call (or rejoins the customer's open one) and joins its audio.
  ///
  /// Ask for the microphone permission before calling this, so a refused permission never creates
  /// a call. Throws [CallsException] when the server refuses (see [CallsErrorCode]); with
  /// [CallsErrorCode.callInProgress], support is calling the customer: [CallsException.callId] is that
  /// call, for [incomingCall]. While a call is in progress, returns that same session.
  Future<CallSession> startCall({
    required String conversationId,
    required String sessionToken,
  }) async {
    final active = _active;
    if (active != null && !active.isOver) return active;

    final api = _api(conversationId, sessionToken);
    final started = await api.start();
    return _begin(CallSession.internal(api: api, media: _media(), started: started), started);
  }

  CallSession _begin(CallSession session, StartedCall started) {
    _active = session;
    unawaited(session.start(started));
    return session;
  }

  // ---------------------------------------------------------------------------------------------
  // Calls from support
  // ---------------------------------------------------------------------------------------------

  /// Whether a push is one of FrontFace's call pushes: the app's own push handling must ignore these.
  static bool isCallPush(Map<dynamic, dynamic> data) => isCallPushData(data);

  /// Reads a FrontFace call push (FCM `data`, or the VoIP payload); null for any other push.
  static CallPush? parsePush(Map<dynamic, dynamic> data) => parseCallPush(data);

  /// Registers this phone to ring when support calls the customer: after sign-in, on every launch
  /// while signed in, and whenever the push token changes (iOS: the PushKit VoIP token; Android: the
  /// FCM token). Only verified customers' phones can register.
  ///
  /// Asks the server only when something changed or a day has passed, unless [force] is set.
  /// Throws [CallsException] when the server refuses (for example [CallsErrorCode.notVerified]).
  Future<void> registerDevice({
    required String conversationId,
    required String sessionToken,
    required String pushToken,
    ApnsEnvironment apnsEnvironment = ApnsEnvironment.production,
    bool force = false,
  }) async {
    final store = _requireStore();
    final platform = _platform;
    if (platform != 'ios' && platform != 'android') {
      throw const CallsException(
          status: 0, code: CallsErrorCode.deviceNotRegistered, message: 'Only iOS and Android phones');
    }
    final stored = StoredDevice.decode(await store.read());
    final now = DateTime.now();
    if (!force &&
        stored != null &&
        stored.isFresh(pushToken: pushToken, visitorId: visitorId, clientKey: clientKey, now: now)) {
      return;
    }
    final registered = await _api(conversationId, sessionToken).registerDevice(
      platform: platform!,
      pushToken: pushToken,
      apnsEnvironment: platform == 'ios' ? apnsEnvironment.name : null,
      appVersion: appVersion,
      credential: stored?.credential,
    );
    // A re-registration (no new secret) keeps the secret this phone holds.
    final secret = registered.secret ?? (registered.id == stored?.id ? stored?.secret : null);
    if (secret == null) {
      throw const CallsException(
          status: 0, code: CallsErrorCode.deviceNotRegistered, message: 'No credential was issued');
    }
    await store.write(StoredDevice(
      id: registered.id,
      secret: secret,
      pushToken: pushToken,
      visitorId: visitorId,
      clientKey: clientKey,
      registeredAt: now,
    ).encode());
  }

  /// Stops this phone ringing for the customer. Call it when the customer signs out, and on any launch
  /// while signed out (it does nothing when the phone is not registered). Throws [CallsException] with
  /// [CallsErrorCode.network] when the server could not be reached; the registration is kept, so call
  /// it again later.
  Future<void> unregisterDevice() async {
    final store = _requireStore();
    final stored = StoredDevice.decode(await store.read());
    if (stored == null) {
      await store.delete();
      return;
    }
    try {
      await _deviceApi(stored).unregister();
    } on CallsException catch (e) {
      // 401/403/404: the server has no such registration for this phone any more.
      if (e.status == 0 || e.status >= 500) rethrow;
    }
    await store.delete();
  }

  /// A call from support ringing on this phone, by the call id from its push (or the system call
  /// screen's id). Works in a fresh process (a background handler, the app opened from the call
  /// screen): it needs only the stored registration. Throws [CallsException] with
  /// [CallsErrorCode.deviceNotRegistered] when this phone is not registered.
  Future<IncomingCall> incomingCall(String callId, {String? agentName}) async {
    final store = _requireStore();
    final stored = StoredDevice.decode(await store.read());
    if (stored == null) {
      throw const CallsException(
          status: 0, code: CallsErrorCode.deviceNotRegistered, message: 'This phone is not registered for calls');
    }
    final api = _deviceApi(stored);
    return IncomingCall.internal(
      callId: callId,
      agentName: agentName,
      api: api,
      join: (answered) async {
        final active = _active;
        if (active != null && !active.isOver) {
          if (active.callId == answered.callId) return active;
          throw const CallsException(
              status: 409, code: CallsErrorCode.callInProgress, message: 'Another call is in progress');
        }
        return _begin(CallSession.internal(api: api, media: _media(), started: answered), answered);
      },
    );
  }

  CallDeviceStore _requireStore() {
    final store = deviceStore;
    if (store == null) {
      throw StateError('Calls from support need a deviceStore (see CALLS_GUIDE.md)');
    }
    return store;
  }

  DeviceApi _deviceApi(StoredDevice stored) => DeviceApi(
        baseUrl: baseUrl,
        clientKey: clientKey,
        credential: stored.credential,
        httpClient: _httpClient,
        // The server no longer knows this phone: forget it, so the next registerDevice registers.
        onInvalid: () => unawaited(deviceStore?.delete()),
      );
}
