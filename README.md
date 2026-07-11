# FrontFace Chat for Flutter

Native Flutter SDK for [FrontFace](https://frontface.app) AI chat with optional human handoff. No WebView required.

## Features

- AI chat powered by the FrontFace Mobile SDK API
- Lead capture form (configurable from the FrontFace dashboard)
- Human agent handoff with live message polling
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
  frontface_chat: ^1.0.0
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

## Customization

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

### Strings (i18n) and RTL

Override any UI string, and set `textDirection` for right-to-left locales:

```dart
const arabicStrings = FrontFaceChatStrings(
  textDirection: TextDirection.rtl,
  online: 'متصل',
  beforeWeChat: 'قبل الدردشة',
  leadFormSubtitle: 'يرجى مشاركة بياناتك لمساعدتك بشكل أفضل.',
  continueToChat: 'متابعة',
  email: 'البريد الإلكتروني',
  emailRequired: 'البريد الإلكتروني مطلوب',
  typeMessage: 'اكتب رسالة...',
  talkToHuman: 'تحدث مع شخص',
  loadingChat: 'جارٍ تحميل المحادثة...',
  messageCopied: 'تم النسخ',
  title: 'الدعم', // overrides the dashboard-configured title, see note below
);

await FrontFaceChat.open(
  context,
  config: config,
  strings: arabicStrings,
);
```

**What's client-side vs. dashboard-driven:** `greeting`, `placeholder`, and the chat
`title` normally come from the FrontFace dashboard (`config.title`, etc.) — whatever
language the project owner configured there. If the dashboard value is empty, the SDK
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
| `requireLeadCaptureBeforeChat` | No | Force the lead form before the first message and before any session/conversation is created, regardless of the dashboard's `capture_mode`. See [Lead capture timing](#lead-capture-timing) below. |

## Lead capture timing

By default, *when* the lead form (email/phone/etc.) appears is controlled by `capture_mode` on
the FrontFace dashboard:

- `email_after` — the form appears **after** the visitor's first message and the AI's reply.
- `email_first` / `email_required` — the form appears **before** any message, and the session is
  only created once the form is submitted.

If you want "always ask for contact info before starting a session" regardless of what
`capture_mode` is set to on the dashboard, set the override on the client:

```dart
const config = FrontFaceChatConfig(
  projectId: '...',
  publishableKey: 'pk_...',
  requireLeadCaptureBeforeChat: true,
);
```

This only takes effect if lead capture itself is enabled on the dashboard — it changes *when*
the form shows, not whether it's collected at all.

**Session expiry:** if the backend rejects a stored session (`SESSION_INVALID` /
`SESSION_CONVERSATION_MISMATCH` — e.g. an old or revoked `sessionToken`), the SDK automatically
clears the stale session, posts a system message (`FrontFaceChatStrings.sessionExpired`), and —
if lead capture is enabled — shows the lead form again before the next message, so a fresh
session always starts with verified contact info. This happens automatically; no action is
needed from the host app.

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

Run the bundled example (update credentials in `example/lib/main.dart` first):

```bash
cd example
flutter pub get
flutter run
```

## Platform notes

- **Android / iOS** — Fully supported.
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
