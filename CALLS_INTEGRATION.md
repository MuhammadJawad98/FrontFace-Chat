# FrontFace Calls — host app integration

How to add **audio calls** from `frontface_chat` (1.7.0+) to your Flutter app.

| Feature | Who does what |
|---|---|
| **Outbound** (customer taps Call in chat) | Package: button, LiveKit, call UI. Host: mic permissions, identify, Android FGS. |
| **Inbound** (support calls the customer) | Package: register / answer / decline / media. Host: push (FCM / VoIP), CallKit / ConnectionService, secure device store. |

---

## 1. Dependencies

```yaml
# pubspec.yaml
dependencies:
  frontface_chat: ^1.7.0

  # Required for inbound (secure device credential)
  flutter_secure_storage: ^9.0.0

  # Required for inbound system call UI (recommended)
  flutter_callkit_incoming: ^2.0.0

  # Android inbound pushes
  firebase_messaging: ^15.0.0

  # Mic permission before answer / start
  permission_handler: ^11.0.0
```

Use path / git if you are developing against this repo:

```yaml
frontface_chat:
  path: ../frontface_chat
```

---

## 2. Platform setup

### iOS (`ios/Runner/Info.plist`)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Needed to talk with support on a call.</string>

<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
  <!-- Inbound VoIP only: -->
  <string>voip</string>
</array>
```

For inbound on iPhone you also need **PushKit VoIP** wired in native code (or via `flutter_callkit_incoming`) so a VoIP push is reported to CallKit immediately. Sandbox vs production must match the build (`ApnsEnvironment.sandbox` for Xcode / development profiles, `.production` for TestFlight / App Store).

Also enable Xcode capabilities: **Push Notifications** and **Background Modes → Voice over IP** (+ Audio).

### Android (`AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />

<!-- flutter_background microphone service (outbound + answered inbound) -->
<service
    android:name="de.julianassmann.flutter_background.IsolateHolderService"
    android:exported="false"
    android:foregroundServiceType="microphone" />
```

If `livekit_noise_filter` fails to compile against a high `compileSdk`, raise the plugin `compileSdk` in the host `android/build.gradle.kts` as needed.

---

## 3. Outbound only (Call button in chat)

Verified customers see Call when the server says calls are available.

```dart
import 'package:frontface_chat/frontface_chat.dart';

final config = FrontFaceChatConfig(
  projectId: 'YOUR_PROJECT_UUID',
  publishableKey: 'pk_YOUR_KEY',
  enableCalls: true, // default
  callSpeakerOnAtStart: false,
  callNoiseCancellation: true,
);

// Prefer a long-lived provider so identify + session stay available
final chat = FrontFaceChat.createProvider(config: config);

await chat.initialize();

// JWT from YOUR backend after login (required or button stays not_verified)
await FrontFaceChat.identify(
  provider: chat,
  identityToken: frontfaceJwtFromBackend,
);

await FrontFaceChat.open(context, config: config);
// Or: put [chat] in MultiProvider and push FrontFaceChatScreen()
```

**Before starting a call** the chat UI asks for microphone permission. On Android, while a call is active, use:

```dart
await frontFaceKeepCallAliveInBackground(true);
// ... after call ends:
await frontFaceKeepCallAliveInBackground(false);
```

(The built-in call screen path already coordinates this for the in-chat Call button.)

Set `enableCalls: false` to hide calling entirely.

---

## 4. Inbound (support → customer)

You need all of: secure store, register after identify, push handling, system ring UI, answer/decline.

### 4.1 Secure device store

The registration includes a **secret**. Store it in Keychain / Keystore. Background handlers must be able to read it (iOS: `first_unlock`).

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontface_chat/frontface_chat.dart';

class SecureCallDeviceStore implements CallDeviceStore {
  static const _key = 'frontface_call_device';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
```

### 4.2 Config + register

```dart
final config = FrontFaceChatConfig(
  projectId: projectId,
  publishableKey: pk,
  visitorId: accountVisitorIdFromBackend, // recommended for logged-in users
  callDeviceStore: SecureCallDeviceStore(),
  enableCalls: true,
);

final chat = FrontFaceChat.createProvider(config: config);
await chat.initialize();
await FrontFaceChat.identify(provider: chat, identityToken: jwt);

// Android: FCM. iOS: PushKit VoIP only (64 hex) — never FCM on iPhone.
final pushToken = await resolvePushTokenForCalls();
if (pushToken == null) return; // iOS: wait for VoIP; do not fall back to FCM
await chat.registerCallDevice(
  pushToken: pushToken,
  apnsEnvironment: ApnsEnvironment.production, // .sandbox for Xcode builds
);

// Call again on every launch while signed in, and when the token refreshes.
// The package skips the network call if nothing changed (24h freshness).
```

**Logout:**

```dart
await chat.unregisterCallDevice();
await FrontFaceChat.resetUser(chat);
```

### 4.2.1 iOS VoIP token vs Android FCM (required)

Firebase **cannot** deliver Apple VoIP pushes. If an iPhone registers with an FCM
token (`…:APA91b…`), support calls only show a banner-style notify — **no CallKit
ring** when the app is closed or locked.

| | Firebase (FCM) | VoIP (PushKit) |
|---|---|---|
| Shape | `cXk2…:APA91b…` (~140 chars, has `:`) | **64 hex chars**, e.g. `3f5a09…c21e` |
| Source | `FirebaseMessaging.instance.getToken()` | `FlutterCallkitIncoming.getDevicePushTokenVoIP()` after PushKit in `AppDelegate` |
| Use for `registerDevice` | **Android only** | **iPhone only** |

```dart
Future<String?> resolvePushTokenForCalls() async {
  if (Platform.isIOS) {
    final voip = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    final token = voip?.toString().trim() ?? '';
    if (!looksLikeIosVoipPushToken(token)) return null; // not ready — do NOT use FCM
    return token;
  }
  return FirebaseMessaging.instance.getToken();
}
```

```dart
FlutterCallkitIncoming.onEvent.listen((event) {
  if (event?.event == Event.actionDidUpdateDevicePushTokenVoip) {
    unawaited(registerForCalls()); // read VoIP again, then registerDevice
  }
  // … accept / decline …
});
```

- Keep normal FCM for **marketing / order** notifications.
- On iOS, **do not** pass FCM `onTokenRefresh` into `registerDevice` (that overwrites VoIP).
- `FrontFaceCalls.registerDevice` on iOS throws [CallsErrorCode.invalidPushToken] if the token is not 64-hex VoIP-shaped.
- Apple dashboard: production APNs key for TestFlight/store; Sandbox & Production if testing from Xcode.

**AppDelegate (PushKit):** after plugin registration, set up `PKPushRegistry`:

- `didUpdate credentials` → `setDevicePushTokenVoIP(token)`
- `didInvalidatePushToken` → clear VoIP token
- `didReceiveIncomingPushWith` → **always** `showCallkitIncoming(..., fromPushKit: true)` then `completion()`  
  (iOS stops VoIP delivery if a push is not reported to CallKit)

Reference: `mobile-sdk/flutter/frontface_calls/example/ios/Runner/AppDelegate.swift` (local) or CALLS sample hosts.

Self-test: after sign-in, logs should show VoIP `len=64` on iPhone. If you see FCM registration on iOS, ringing when killed will fail.

### 4.3 Parse pushes (ignore FrontFace call payloads in your own handlers)

```dart
Future<bool> handleFrontFaceCallPush(Map<String, dynamic> data) async {
  // Always check this first — leave FrontFace call pushes alone in your marketing/order handlers.
  if (!FrontFaceChatProvider.isCallPush(data)) return false;

  final push = FrontFaceChatProvider.parseCallPush(data);
  switch (push) {
    case IncomingCallPush(:final callId, :final agentName, :final ringDeadline):
      // Show system incoming UI (CallKit / ConnectionService).
      // Use callId as the system call id (UUID).
      await showSystemIncomingCall(
        callId: callId,
        callerName: agentName ?? 'Support',
        ringUntil: ringDeadline,
      );
      return true;

    case CallEndedPush(:final callId):
      // Android: dismiss the system ring UI. iOS learns this via stoppedRinging.
      await endSystemCall(callId);
      return true;

    case null:
      // FrontFace call push of an unknown version — still not your app's push.
      return true;
  }
}
```

**Android:** register an FCM background handler and foreground listener that call `handleFrontFaceCallPush(message.data)`.

**iOS:** VoIP payload uses the **same keys** at the top level (`v`, `type`, `callId`, …). Report to CallKit immediately in native / CallKit plugin, then handle Accept / Decline in Dart.

### 4.3.1 Incoming call branding (logo)

Without these params the ring UI shows **no app logo**. Cold-start VoIP rings go through **native PushKit → CallKit**, so a Dart-only logo fix is **not** enough on iPhone — set `iconName` in `AppDelegate` too.

```dart
Future<void> showSystemIncomingCall({
  required String callId,
  required String callerName,
  DateTime? ringUntil,
}) async {
  final durationMs = ringUntil == null
      ? 45000
      : ringUntil.difference(DateTime.now()).inMilliseconds.clamp(5000, 120000);

  await FlutterCallkitIncoming.showCallkitIncoming(
    CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Support',
      type: 0, // audio
      duration: durationMs,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true, // required — default in many samples is false
        logoUrl: 'assets/images/call_logo.png', // pubspec asset, or https://…
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo', // Xcode asset catalog name, no extension
        handleType: 'generic',
      ),
    ),
  );
}
```

| Platform | What to set |
|---|---|
| **Android** | `isShowLogo: true` + `logoUrl` (Flutter asset in `pubspec.yaml`, or `https://…`) |
| **iOS (Dart)** | `IOSParams.iconName: 'CallKitLogo'` |
| **iOS (VoIP / killed)** | Same name on the PushKit path: `data.iconName = "CallKitLogo"` before `showCallkitIncoming(..., fromPushKit: true)` |

**iOS asset:** add an imageset under `ios/Runner/Assets.xcassets/` (conventional name **`CallKitLogo`**). Prefer a **template** image (alpha / silhouette) — CallKit tints it; full-color photos look wrong. If `iconName` is missing or the asset is not in the bundle, the plugin logs `Unable to load icon …` and CallKit shows no custom logo.

```swift
// AppDelegate — didReceiveIncomingPushWith (required when app is killed)
data.iconName = "CallKitLogo"
plugin.showCallkitIncoming(data, fromPushKit: true) { … }
```

Package example ships `CallKitLogo.imageset` and `assets/images/call_logo.png` as a reference; replace with your brand mark before shipping.

### 4.4 Answer / decline (works with chat closed)

Use `FrontFaceCalls` with the **same** `clientKey`, `visitorId`, and `deviceStore`. No chat session is required to answer.

```dart
final calls = FrontFaceCalls(
  baseUrl: 'https://api.frontface.app',
  clientKey: pk,
  visitorId: visitorId,
  deviceStore: SecureCallDeviceStore(),
  // Prefer false on Android until Krisp is stable; package also retries without it.
  noiseCancellation: false,
  speakerOnAtStart: false,
);

final navigatorKey = GlobalKey<NavigatorState>(); // root MaterialApp.navigatorKey

// When the user accepts on the system call UI:
Future<void> onAccept(String callId, {String? agentName}) async {
  // Close any stoppedRinging watcher for this call first (do not endCall mid-join).
  activeCallIds.add(callId);

  // Keep CallKit / ConnectionService alive for the audio session (esp. iOS).
  await FlutterCallkitIncoming.setCallConnected(callId);

  // Cold start: Accept can fire before the first frame — wait for UI.
  final context = await frontFaceWaitForNavigatorContext(navigatorKey);
  if (context == null) {
    await endSystemCall(callId);
    activeCallIds.remove(callId);
    return;
  }

  final mic = await Permission.microphone.request();
  if (!mic.isGranted) {
    await (await calls.incomingCall(callId)).decline();
    await endSystemCall(callId);
    activeCallIds.remove(callId);
    return;
  }

  // Android FGS needs an Activity — only after navigator exists.
  await frontFaceKeepCallAliveInBackground(true);
  try {
    final incoming = await calls.incomingCall(callId, agentName: agentName);
    final session = await incoming.answer();

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => FrontFaceCallScreen(session: session),
      ),
    );
    // Only end CallKit after the call is fully over.
    await session.done;
  } on CallsException catch (e) {
    // CALL_ANSWERED_ELSEWHERE, CALL_ENDED, DEVICE_NOT_REGISTERED, …
  } finally {
    await endSystemCall(callId);
    await frontFaceKeepCallAliveInBackground(false);
    activeCallIds.remove(callId);
  }
}

// When the user declines:
Future<void> onDecline(String callId) async {
  try {
    await (await calls.incomingCall(callId)).decline();
  } on CallsException {
    // Already ended elsewhere — ignore
  }
  await endSystemCall(callId);
}
```

While ringing (especially on iOS), watch for cancel / answered-elsewhere.
**Do not** treat `answeredHere == null` as “dismiss” — that ends CallKit while Accept is still joining LiveKit:

```dart
final incoming = await calls.incomingCall(callId);
final stopped = await incoming.stoppedRinging;
// Skip dismiss while this phone is accepting / already in the call.
if (handlingAccept || activeCallIds.contains(callId)) return;
if (stopped.answeredHere == true) {
  await FlutterCallkitIncoming.setCallConnected(callId);
  return;
}
if (stopped.status == 'active') return; // ambiguous — leave CallKit alone
await endSystemCall(callId);
// Call incoming.close() if you tear down early.
```

If the customer taps **Call** in chat while support is already calling them:

```dart
try {
  await chat.startAudioCall();
} on CallsException catch (e) {
  if (e.code == CallsErrorCode.callInProgress && e.callId != null) {
    await onAccept(e.callId!); // answer that inbound call instead
  }
}
```

### 4.5 Inbound Accept: app open vs app killed

`incomingCall` → `answer()` → LiveKit is the same in both cases. Failures when the
app was **terminated** are almost always host lifecycle: CallKit Accept runs in
native before Dart has a listener, navigator, or Android Activity.

| App state | What the host must do |
|---|---|
| App open | CallKit `actionCallAccept` → `onAccept` (below) |
| App killed / background | Same `onAccept`, plus **recover** Accept if Dart missed the event |

**Clarify:** “If the app is killed, the call ends” means killing the app **during an
already-connected call** (media drops). It does **not** mean the customer cannot
Accept while the app was terminated. Inbound Accept from terminated **must** wake
the app, use the stored `CallDeviceStore` credential, and join.

**A. Attach the CallKit listener early** — after `dotenv` / keys, **before or right
around** `runApp`. Do not wait for a late async FCM `init()` after the first frame;
Accept from a killed app may already have fired.

```dart
await dotenv.load();
FrontFaceCallsHost.init(); // listens to FlutterCallkitIncoming.onEvent
runApp(MyApp(navigatorKey: navigatorKey));
```

**B. Recover Accept from `activeCalls()`** (cold start + resume) — when the Dart
listener was late, native still holds an accepted call:

```dart
Future<void> recoverAcceptedCallIfNeeded() async {
  final calls = await FlutterCallkitIncoming.activeCalls();
  for (final raw in calls) {
    if (raw is! Map) continue;
    final callId = raw['id']?.toString() ?? '';
    final accepted = raw['isAccepted'] == true || '${raw['isAccepted']}' == 'true';
    if (callId.isEmpty || !accepted) continue;
    if (activeCallIds.contains(callId)) continue;
    await onAccept(callId, agentName: /* from raw['extra'] */);
    return;
  }
}

// After first frame:
WidgetsBinding.instance.addPostFrameCallback((_) {
  unawaited(recoverAcceptedCallIfNeeded());
});
// And on AppLifecycleState.resumed
```

**C. Accept order (open or killed)**

```text
Accept (CallKit event or activeCalls recovery)
  → setCallConnected(callId)                    // keep system audio session
  → frontFaceWaitForNavigatorContext(...)       // up to a few seconds
  → Permission.microphone
  → frontFaceKeepCallAliveInBackground(true)    // Android: Activity must be up
  → incomingCall(callId).answer()
  → push FrontFaceCallScreen(session)
  → await session.done
  → endCall(callId)
  → frontFaceKeepCallAliveInBackground(false)
```

**Do not** call `endCall` until the session is over. Ending CallKit mid-join kills
the audio session (especially iOS) and looks like “no voice” / failed connect.

---

## 5. Recommended app wiring

```text
main()
  └─ dotenv.load()
  └─ CallKit onEvent listener (early)          ← before/around runApp
  └─ runApp
       └─ post-frame + on resume:
            recoverAcceptedCallIfNeeded()     ← activeCalls() → onAccept

Login / each launch while signed in
  └─ identify(jwt)
  └─ registerCallDevice(pushToken)

Push arrives (FCM / VoIP)
  └─ isCallPush? → parseCallPush → show CallKit
  └─ Accept (event or activeCalls recovery)
       → setCallConnected → wait navigator → mic → FGS → answer → CallScreen
  └─ Decline → incomingCall → decline
  └─ call.ended / stoppedRinging → dismiss only if not answering here

Logout
  └─ unregisterCallDevice()
  └─ resetUser()
```

**Important:** `FrontFaceChat.open()` creates a **scoped** provider that is disposed when chat closes. For inbound registration and answering with the app closed, keep either:

- a **global** `FrontFaceChatProvider` (`createProvider` + `MultiProvider`), or  
- a standalone `FrontFaceCalls` instance that only needs `deviceStore` + keys for answer/decline.

---

## 6. Push payload reference

All values may arrive as strings (FCM data).

| Key | Incoming | Ended |
|---|---|---|
| `v` | `"1"` | `"1"` |
| `type` | `call.incoming` | `call.ended` |
| `callId` | UUID | UUID |
| `agentName` | optional | — |
| `ringDeadlineAt` | optional ISO-8601 | — |
| `detail` | — | e.g. `answered_elsewhere`, `agent_cancelled`, `declined`, `no_answer` |

Helpers:

- `FrontFaceChatProvider.isCallPush(data)` / `FrontFaceCalls.isCallPush(data)`
- `FrontFaceChatProvider.parseCallPush(data)` / `FrontFaceCalls.parsePush(data)`

---

## 7. Error codes (inbound)

| Code | Meaning |
|---|---|
| `NOT_VERIFIED` | Identify the customer before `registerCallDevice` |
| `DEVICE_NOT_REGISTERED` | No stored credential — register again |
| `INVALID_PUSH_TOKEN` | iOS `registerDevice` got FCM / non–64-hex — wait for PushKit VoIP |
| `DEVICE_INVALID` | Registration gone — store is cleared; register again |
| `CALL_ENDED` | Too late to answer |
| `CALL_ANSWERED_ELSEWHERE` | Another device answered |
| `CALL_IN_PROGRESS` | Support is calling; `CallsException.callId` is that call |
| `NETWORK` | Retry |

---

## 8. Theme the in-app call UI

```dart
await FrontFaceChat.open(
  context,
  config: config,
  theme: const FrontFaceChatTheme(
    callBackgroundColor: Color(0xFF0B1220),
    callSurfaceColor: Color(0xFF1E293B),
    callOnBackgroundColor: Color(0xFFF8FAFC),
    // … see FrontFaceChatTheme for all call* colors
  ),
);
```

UI-only demo (no network / mic):

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => FrontFaceCallScreen(session: CallSession.preview()),
  ),
);
```

---

## 9. Checklist

**Outbound**

- [ ] Mic usage string (iOS) + `audio` background mode  
- [ ] Android `RECORD_AUDIO` + microphone FGS  
- [ ] `identify` after login  
- [ ] `enableCalls: true`  

**Inbound**

- [ ] `CallDeviceStore` (secure storage) on config  
- [ ] `registerCallDevice` after identify / on launch / on token refresh  
- [ ] `unregisterCallDevice` on logout  
- [ ] FCM (Android) / **PushKit VoIP only on iOS** (never fall back to FCM)  
- [ ] iOS: VoIP token `len=64` hex before claiming calls work; re-register on `actionDidUpdateDevicePushTokenVoip`  
- [ ] iOS: PushKit `AppDelegate` reports every VoIP push to CallKit  
- [ ] System call UI (CallKit / ConnectionService) using `callId`  
- [ ] Incoming branding: Android `isShowLogo` + `logoUrl`; iOS `CallKitLogo` + `iconName` in Dart **and** VoIP `AppDelegate`  
- [ ] CallKit listener attached early (around `runApp`, not only late FCM init)  
- [ ] `activeCalls()` recovery after first frame + on `AppLifecycleState.resumed`  
- [ ] Accept → `setCallConnected` → wait navigator → mic → FGS → `answer` → CallScreen  
- [ ] Decline → `decline`  
- [ ] `stoppedRinging` does **not** dismiss when `answeredHere == null` / while accepting  
- [ ] `endCall` only after `session.done`  
- [ ] `frontFaceKeepCallAliveInBackground` only after Activity/UI is up (Android)  
- [ ] **App killed:** Accept → app launches → CallScreen + two-way audio  
- [ ] Self-test: VoIP `len=64` on iPhone; logo visible on ring (app open **and** killed); Accept → two-way audio  


---

## 10. Related package APIs

```dart
// Config
FrontFaceChatConfig.callDeviceStore
FrontFaceChatConfig.enableCalls
FrontFaceChatConfig.callSpeakerOnAtStart
FrontFaceChatConfig.callNoiseCancellation

// Provider (needs active conversation for register / outbound)
FrontFaceChatProvider.registerCallDevice(...)
FrontFaceChatProvider.unregisterCallDevice()
FrontFaceChatProvider.incomingCall(callId)
FrontFaceChatProvider.startAudioCall()
FrontFaceChatProvider.isCallPush / parseCallPush

// Standalone (answer with app cold-started)
FrontFaceCalls(... deviceStore: ...)
FrontFaceCalls.registerDevice / unregisterDevice / incomingCall / startCall
FrontFaceCallScreen(session: ...)
frontFaceKeepCallAliveInBackground(bool)
frontFaceWaitForNavigatorContext(navigatorKey) // cold-start Accept
```

For OpenAPI of related chat APIs, see `openapi.yaml` in this repository.
