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

### Strings (i18n)

Override any UI string:

```dart
const arabicStrings = FrontFaceChatStrings(
  online: 'متصل',
  beforeWeChat: 'قبل الدردشة',
  leadFormSubtitle: 'يرجى مشاركة بياناتك لمساعدتك بشكل أفضل.',
  continueToChat: 'متابعة',
  email: 'البريد الإلكتروني',
  emailRequired: 'البريد الإلكتروني مطلوب',
);

await FrontFaceChat.open(
  context,
  config: config,
  strings: arabicStrings,
);
```

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
