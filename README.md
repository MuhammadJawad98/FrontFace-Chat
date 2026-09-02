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
  frontface_chat: ^1.5.6
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
   - **Project ID** — UUID (e.g. `00000000-0000-4000-8000-000000000000`)
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
    // Optional — with a key: map picker + place search + static previews.
    // Without a key: user can still share current GPS location.
    googleMapsApiKey: 'YOUR_GOOGLE_MAPS_API_KEY',
  ),
);
```

See `INTEGRATION_GUIDE.md` §5.3–5.5 for the location / image / voice API contracts.

**Native setup (host app):**

- **Android** `AndroidManifest.xml`: location / camera / mic permissions. If you
  use a Maps key, also add `com.google.android.geo.API_KEY` and enable
  **Maps SDK**, **Places API**, and **Geocoding API** on that key.
  Gallery uses the system Photo Picker (enabled by the SDK) — do **not** declare
  `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` for picking (Play photo & video policy).
  Hosts do **not** need to set `ImagePickerAndroid.useAndroidPhotoPicker`.
- **iOS** `Info.plist`: `NSLocationWhenInUseUsageDescription`,
  `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
  `NSMicrophoneUsageDescription`. With a Maps key, call
  `GMSServices.provideAPIKey` in `AppDelegate`.
- **iOS Podfile** — enable `permission_handler` macros or every request looks
  permanently denied (open Settings loop):

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_PHOTOS=1',
        'PERMISSION_MICROPHONE=1',
        'PERMISSION_LOCATION=1',
      ]
    end
  end
end
```

Then run `cd ios && pod install`.

Permissions use the **native** system dialog. An in-app popup appears only if access
is permanently denied (to open Settings) or location services are off.

### Theme

Match chat colors to your brand. Bubble colors are **optional** — override only
what you need:

```dart
await FrontFaceChat.open(
  context,
  config: config,
  theme: const FrontFaceChatTheme(
    primaryColor: Color(0xFF0F172A),
    // Optional — visitor (user) bubbles
    userBubbleColor: Color(0xFF2563EB),
    userBubbleTextColor: Colors.white,
    // Optional — agent / assistant bubbles
    assistantBubbleColor: Colors.white,
    assistantBubbleTextColor: Color(0xFF0F172A),
    assistantBubbleBorderColor: Color(0xFFE2E8F0),
    onlineIndicatorColor: Color(0xFF17B26A),
  ),
);
```

Available theme properties: `primaryColor`, `onPrimaryColor`, `backgroundColor`,
`inputBackgroundColor`, `userBubbleColor`, `userBubbleTextColor`,
`assistantBubbleColor`, `assistantBubbleTextColor`, `assistantBubbleBorderColor`,
`subtitleColor`, `errorColor`, `onlineIndicatorColor`, `agentNameColor`, `linkColor`,
`fontFamily`, `arabicFontFamily`.

For Arabic / RTL (`FrontFaceChatStrings.arabic`), the SDK uses the bundled
**Noto Sans Arabic** family (`FrontFaceArabic`) by default. Override if needed:

```dart
theme: FrontFaceChatTheme(
  arabicFontFamily: 'FrontFaceArabic', // default
  // fontFamily: 'YourLatinFont',       // optional LTR font
),
```

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

Every user-visible label (attachments, permissions, tickets, CSAT, offline form,
image viewer, etc.) lives on [FrontFaceChatStrings]. Prefer the built-in packs
so you do not re-translate every field:

```dart
// English (default)
await FrontFaceChat.open(context, config: config);

// Full Arabic pack (RTL + all labels)
await FrontFaceChat.open(
  context,
  config: config,
  strings: FrontFaceChatStrings.arabic,
);

// Or resolve from a language code (`en`, `ar`, …)
await FrontFaceChat.open(
  context,
  config: config,
  strings: FrontFaceChatStrings.forLanguage(
    Localizations.localeOf(context).languageCode,
    title: 'Support', // optional override
  ),
);
```

Override individual keys when needed:

```dart
final strings = FrontFaceChatStrings.arabic.copyWith(
  attach: 'إضافة مرفق',
  title: 'المساعدة',
);
```

Partial updates at runtime:

```dart
provider.updateStrings(
  FrontFaceChatStrings.forLanguage('ar').copyWith(title: 'الدعم'),
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
provider.updateStrings(FrontFaceChatStrings.forLanguage('ar'));
```

This swaps every string immediately — title, placeholder, input direction, and any
already-shown status banner (e.g. "Waiting for an agent...") all re-render in the new
language without recreating the provider or screen.

### Debug logging

Enable HTTP request logs during **debug builds only**:

```dart
const config = FrontFaceChatConfig(
  projectId: '...',
  publishableKey: 'pk_...',
  debugLogging: true, // ignored in release/profile — never logs in production
);
```

Secrets (`X-FrontFace-Key`, session tokens) are redacted from curl logs. Leave
`debugLogging: false` (the default) in production configs.

| Option | Required | Notes |
|--------|----------|--------|
| `requireLeadCaptureBeforeChat` | No | Defaults to `true`: show the lead form before any greeting or session. Set `false` to follow the dashboard `capture_mode` instead. See [Lead capture timing](#lead-capture-timing). |
| `showNewChatButton` | No | Defaults to `true`. Set `false` to hide the app-bar refresh / new-chat button. |

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
