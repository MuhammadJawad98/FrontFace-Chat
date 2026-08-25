# FrontFace Chat for Flutter

Native Flutter SDK for [FrontFace](https://frontface.app) AI chat with optional human handoff. No WebView required.

## Features

- AI chat powered by the FrontFace Mobile SDK API
- Lead capture form (configurable from the FrontFace dashboard)
- Human agent handoff with live message polling, agent typing (Realtime), and customer typing/presence for the dashboard
- Support tickets (structured actions + ticket cards), CSAT ratings, offline contact form
- Channel launcher buttons (WhatsApp, email, phone, etc.) from dashboard config
- Customer identity verification via backend-signed JWT (`identify` / `resetUser`)
- Optional attachments: location (Google Maps), images, voice notes (config-gated; uploaded via FrontFace signed URLs)
- Session restore across app restarts (session id + session token persisted automatically)
- Customizable theme and localized strings
- One-line `FrontFaceChat.open()` integration

## Requirements

- Flutter 3.22+
- Dart 3.8+
- A FrontFace account with **Mobile SDK** enabled

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  frontface_chat: ^1.5.0
```

For local development (this repo lives next to your app):

```yaml
dependencies:
  frontface_chat:
    path: ../frontface_chat
```

Then run:

```bash
flutter pub get
```

## Get your credentials

1. Sign in to the [FrontFace dashboard](https://frontface.app).
2. Open your project → **Mobile SDK**.
3. Copy:
   - **Project ID** — UUID (e.g. `92b2d515-0000-45a7-8b0a-df20a33ceb2a`)
   - **Publishable key** — starts with `pk_`

> Do not confuse `projectId` with `publishableKey`. They are different values.

## Quick start

The fastest way to add chat is a floating action button or a button tap:

```dart
import 'package:frontface_chat/frontface_chat.dart';

const config = FrontFaceChatConfig(
  projectId: 'YOUR_PROJECT_UUID',
  publishableKey: 'pk_YOUR_KEY',
);

// Open chat from anywhere
await FrontFaceChat.open(context, config: config);

// Or use the built-in FAB
floatingActionButton: FrontFaceChat.fab(context, config: config),
```

## Integration patterns

### 1. One-shot (recommended for most apps)

`FrontFaceChat.open()` creates a scoped provider, pushes the chat screen, and cleans up when the user closes it. No global setup needed.

### 2. Global Provider

If you already use `provider` and want chat state shared or custom navigation:

```dart
// In main.dart / app setup
MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) => FrontFaceChat.createProvider(config: config),
    ),
  ],
  child: MyApp(),
)

// Navigate manually
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const FrontFaceChatScreen(),
  ),
);
```

### 3. Custom FAB / button

```dart
IconButton(
  icon: const Icon(Icons.support_agent),
  onPressed: () => FrontFaceChat.open(context, config: config),
)
```

### 4. Multiple projects (white-label / multi-tenant apps)

Each `FrontFaceChatConfig` is scoped to one FrontFace project. Pass a different `projectId` + `publishableKey` per tenant — session, session token, and lead-form state are stored **per projectId**, so multiple configs can coexist in one app:

```dart
final supportConfig = FrontFaceChatConfig(
  projectId: tenantAProjectId,
  publishableKey: tenantAPublishableKey,
);

final salesConfig = FrontFaceChatConfig(
  projectId: tenantBProjectId,
  publishableKey: tenantBPublishableKey,
);

// Open the right chat for the active tenant
await FrontFaceChat.open(context, config: supportConfig);
```

Visitor id is shared device-wide (one `mob_*` id) by default. For **logged-in** users, pass a stable account-keyed `visitorId` from your backend so history follows the user across reinstalls/devices (see [`CHAT_HISTORY_GUIDE.md`](./CHAT_HISTORY_GUIDE.md)). Then call `identify` so agents see a verified contact.

```dart
final provider = FrontFaceChat.createProvider(
  config: FrontFaceChatConfig(
    projectId: projectId,
    publishableKey: pk,
    visitorId: accountVisitorIdFromBackend, // from Freshhouse backend
  ),
);
await provider.initialize();

// After your login API returns `frontfaceToken`:
try {
  await FrontFaceChat.identify(
    provider: provider,
    identityToken: frontfaceToken,
  );
} on FrontFaceIdentifyException catch (e) {
  // Never block chat — log and retry with a fresh token on next login
  debugPrint('Identify failed: ${e.code}');
}
```

On logout:

```dart
await FrontFaceChat.resetUser(provider);
```

## Customization

### Attachments (optional)

All attachment types are **off by default**. Enable only what you need.
Images and voice notes upload through FrontFace (`POST /api/media/uploads` →
signed `PUT` → `parts` on `POST /api/chat/message`) — **no host uploader**.
Location is sent as a structured `location` object (not a Maps URL in text).

```dart
final config = FrontFaceChatConfig(
  projectId: projectId,
  publishableKey: pk,
  attachments: FrontFaceAttachmentsConfig(
    enableLocation: true,
    enableImages: true,
    enableAudio: true,
    // Required when enableLocation is true (map picker + static previews).
    googleMapsApiKey: 'YOUR_GOOGLE_MAPS_API_KEY',
  ),
);
```

See `SEND_LOCATION_GUIDE.md`, `SEND_IMAGE_GUIDE.md`, and `SEND_VOICE_GUIDE.md`.

**Native setup (host app):**

- **Android** `AndroidManifest.xml`: location / camera / media / mic permissions, and
  `com.google.android.geo.API_KEY` meta-data with the same Maps key.
- **iOS** `Info.plist`: `NSLocationWhenInUseUsageDescription`,
  `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
  `NSMicrophoneUsageDescription`, and set the Maps key via
  `GMSServices.provideAPIKey` in `AppDelegate`.

Permissions are requested only when the user taps an attachment action, with an
in-app rationale first. If permanently denied, the SDK offers to open Settings.

### Theme

Match chat colors to your brand:

```dart
await FrontFaceChat.open(
  context,
  config: config,
  theme: const FrontFaceChatTheme(
    primaryColor: Color(0xFF000000),
    userBubbleColor: Color(0xFF000000),
    onlineIndicatorColor: Color(0xFF17B26A),
  ),
);
```

Available theme properties: `primaryColor`, `onPrimaryColor`, `backgroundColor`, `inputBackgroundColor`, bubble colors, `subtitleColor`, `errorColor`, `onlineIndicatorColor`, `agentNameColor`.

### Bottom safe area / host bottom navigation

The composer and action buttons always clear the system home indicator. If your
app embeds chat under a bottom nav bar, pass its height as `extraBottomInset`:

```dart
await FrontFaceChat.open(
  context,
  config: config,
  extraBottomInset: 80, // your BottomNavigationBar height
);

// Or when using the screen directly:
FrontFaceChatScreen(theme: theme, extraBottomInset: 80);
```

### Strings (i18n) and RTL

Every user-visible label (including **attachments**, permissions, tickets, CSAT,
and the offline form) lives on [FrontFaceChatStrings] with English defaults.
Pass only the fields you want to translate — the rest stay optional/default:

```dart
const arabicStrings = FrontFaceChatStrings(
  textDirection: TextDirection.rtl,
  online: 'متصل',
  typeMessage: 'اكتب رسالة...',
  talkToHuman: 'تحدث مع شخص',
  // Attachments (only needed if you enabled them in config)
  attach: 'إرفاق',
  shareLocation: 'مشاركة الموقع',
  sendLocation: 'إرسال هذا الموقع',
  attachPhoto: 'مكتبة الصور',
  takePhoto: 'التقاط صورة',
  permissionLocationTitle: 'الوصول إلى الموقع',
  permissionContinue: 'متابعة',
  openSettings: 'فتح الإعدادات',
  title: 'الدعم',
);

await FrontFaceChat.open(
  context,
  config: config,
  strings: arabicStrings,
);
```

Partial updates at runtime:

```dart
provider.updateStrings(
  provider.strings.copyWith(attach: 'إرفاق', shareLocation: 'مشاركة الموقع'),
);
```

**What's client-side vs. dashboard-driven:** `greeting`, `placeholder`, and the chat
`title` normally come from the FrontFace dashboard (`config.title`, etc.) — whatever
language the project owner configured there. Lead-form field 2/3 labels (e.g. "Phone
Number") also come from the dashboard — override them with `strings.field2Label` /
`strings.field3Label` for English or Arabic. If the dashboard value is empty, the SDK
falls back to `strings.typeMessage` / `strings.talkToHuman` / `strings.loadingChat`. The
one exception is `strings.title`: since the dashboard title is almost never empty (it
usually says something like "Support"), set `strings.title` explicitly to force a
client-side translation that always wins over the dashboard value.

Message bubbles and the input field also auto-detect their own text direction from
content, so English typed into an Arabic-configured chat (or vice versa) renders
correctly regardless of the chat's overall `textDirection`.

#### Changing language at runtime

`strings` is normally fixed for the lifetime of a `FrontFaceChatProvider`, but if your
app supports switching language while the chat is already open (e.g. a language toggle
in settings), call `updateStrings()` on the provider you're using with `createProvider()`
or `context.read<FrontFaceChatProvider>()`:

```dart
provider.updateStrings(arabicStrings);
```

This swaps every string immediately — title, placeholder, input direction, and any
already-shown status banner (e.g. "Waiting for an agent...") all re-render in the new
language without recreating the provider or screen.

### Debug logging

Enable HTTP request logs during development:

```dart
const config = FrontFaceChatConfig(
  projectId: '...',
  publishableKey: 'pk_...',
  debugLogging: true,
);
```

## Configuration reference

| Parameter | Required | Description |
|-----------|----------|-------------|
| `projectId` | Yes | Project UUID from FrontFace dashboard |
| `publishableKey` | Yes | Mobile SDK key (`pk_…`) |
| `baseUrl` | No | API base URL (default: `https://api.frontface.app`) |
| `debugLogging` | No | Log API requests to console |
| `requireLeadCaptureBeforeChat` | No | Defaults to `true`: show the lead form before any greeting or session. Set `false` to follow the dashboard `capture_mode` instead. See [Lead capture timing](#lead-capture-timing). |

## Lead capture timing

When lead capture is enabled on the FrontFace dashboard, the Mobile SDK by default
shows the lead form **first** (`requireLeadCaptureBeforeChat: true`):

1. Lead form
2. Form submit creates the session
3. API `assembledGreeting` (or the dashboard greeting) appears

No local greeting is shown before the form, and no conversation/session is created
until the form is submitted.

Dashboard `capture_mode` still matters when you opt out:

```dart
const config = FrontFaceChatConfig(
  projectId: '...',
  publishableKey: 'pk_...',
  requireLeadCaptureBeforeChat: false, // follow dashboard mode
);
```

- `email_after` — greeting first; form appears **after** the visitor's first message.
- `email_first` / `email_required` — form before chatting (same as the default).

This only takes effect if lead capture itself is enabled on the dashboard — it changes
*when* the form shows, not whether it's collected at all.

**Session expiry:** `sessionToken` expires after 24h of inactivity (expired and
tampered tokens both return `403 SESSION_*`). On expiry the SDK **clears the chat**,
drops the stale session, and shows the **lead form** again (when lead capture is
enabled). Submitting the form creates a new session and shows the API
`assembledGreeting` — never a local greeting before the form, and never a
“session expired” error toast. Use `FrontFaceChat.debugCorruptSessionToken(projectId)`
(or the example app button) to test without waiting 24h.

## How it works

```
Your app
  └── FrontFaceChat.open()
        └── FrontFaceChatScreen
              └── FrontFaceChatProvider
                    ├── FrontFaceApiService
                    │     └── FrontFaceApiManager  →  api.frontface.app
                    └── FrontFaceVisitorStore      →  SharedPreferences
```

1. **Bootstrap** — Creates or restores a visitor ID, loads embed config from the API.
2. **Lead form** — Shown when enabled in the dashboard and not yet completed.
3. **AI chat** — Messages sent via `POST /api/chat/message`.
4. **Handoff** — User can request a human (creating a conversation first via `ensure-conversation` if none exists yet); provider polls for agent messages every 2 seconds.
5. **Session** — Conversation id and its session token are persisted together so returning users see their history and continued requests stay authorized.

## Example app

Run the bundled example, then enter your **Project ID** and **Publishable key** in the two fields on the home screen:

```bash
cd example
flutter pub get
flutter run
```

## Platform notes

- **Android / iOS** — Fully supported.
- **Markdown links** (e.g. `[View Details](https://…)`) open in the external browser. Host apps must allow URL queries:
  - **iOS** — add `LSApplicationQueriesSchemes`: `https`, `http`, `mailto` to `Info.plist`
  - **Android** — add `<queries>` `VIEW` intents for `https` / `http` / `mailto` in `AndroidManifest.xml`
- **Web / desktop** — Should work (uses `http` + `shared_preferences`); not primary targets.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Chat is currently unavailable" | Widget disabled in FrontFace dashboard or wrong `projectId` |
| 401 / auth errors | Check `publishableKey` (`pk_…`), not the secret key |
| White screen / no messages | Ensure device has network; enable `debugLogging: true` |
| Lead form keeps showing | Clear app data or call `startNewChat` after form submit |

## License

See [LICENSE](LICENSE).

## Support

- FrontFace docs: [frontface.app](https://frontface.app)
- Package issues: open an issue in this repository
