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

// Android: FCM token. iOS: PushKit VoIP token (not the normal APNs token).
await chat.registerCallDevice(
  pushToken: pushToken,
  apnsEnvironment: ApnsEnvironment.production, // or .sandbox for Xcode builds
);

// Call again on every launch while signed in, and when the token refreshes.
// The package skips the network call if nothing changed (24h freshness).
```

**Logout:**

```dart
await chat.unregisterCallDevice();
await FrontFaceChat.resetUser(chat);
```

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

### 4.4 Answer / decline (works with chat closed)

Use `FrontFaceCalls` with the **same** `clientKey`, `visitorId`, and `deviceStore`. No chat session is required to answer.

```dart
final calls = FrontFaceCalls(
  baseUrl: 'https://api.frontface.app',
  clientKey: pk,
  visitorId: visitorId,
  deviceStore: SecureCallDeviceStore(),
  // Prefer false on Android if Krisp still misbehaves; package retries without it.
  noiseCancellation: true,
  speakerOnAtStart: false,
);

// When the user accepts on the system call UI:
Future<void> onAccept(String callId, {String? agentName}) async {
  // Close any stoppedRinging watcher for this call first (do not endCall mid-join).
  final mic = await Permission.microphone.request();
  if (!mic.isGranted) {
    await (await calls.incomingCall(callId)).decline();
    await endSystemCall(callId);
    return;
  }

  await frontFaceKeepCallAliveInBackground(true);
  try {
    // Keep CallKit / ConnectionService alive for the audio session (esp. iOS).
    // Ending it here kills mic/speaker and the call drops with no voice.
    await FlutterCallkitIncoming.setCallConnected(callId);

    final incoming = await calls.incomingCall(callId, agentName: agentName);
    final session = await incoming.answer();

    await Navigator.of(context).push(
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

---

## 5. Recommended app wiring

```text
App start
  └─ MultiProvider → FrontFaceChat.createProvider(config with callDeviceStore)
       └─ initialize()

Login / each launch while signed in
  └─ identify(jwt)
  └─ registerCallDevice(pushToken)

Push arrives (FCM / VoIP)
  └─ isCallPush? → parseCallPush → show CallKit
  └─ Accept → incomingCall → answer → FrontFaceCallScreen
  └─ Decline → incomingCall → decline
  └─ call.ended / stoppedRinging → dismiss CallKit

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
- [ ] FCM (Android) / VoIP PushKit (iOS)  
- [ ] System call UI (CallKit / ConnectionService) using `callId`  
- [ ] Accept → mic → `incomingCall` → `answer` → `FrontFaceCallScreen`  
- [ ] Decline → `decline`  
- [ ] `stoppedRinging` / `call.ended` dismisses the system UI  
- [ ] `frontFaceKeepCallAliveInBackground` while answered on Android  

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
```

For OpenAPI of related chat APIs, see `openapi.yaml` in this repository.
