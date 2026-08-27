## 1.5.4

* Fix: existing voice notes no longer remount and flash a loader when a new message is sent (stable message keys + silent background prepare).
* Docs: replace sample project UUID with a clearly fake placeholder; tighten `.gitignore` for secrets / credentials.

## 1.5.3

* Fix: enable Android Photo Picker inside the SDK before gallery pick so hosts do not need `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` or a manual `useAndroidPhotoPicker` setup (Play photo & video policy).
* Fix: example AndroidManifest no longer declares `READ_MEDIA_*` / legacy storage permissions for gallery.
* Fix: audio upload shows loader on the play button only (no full-bubble grey overlay); lighter image/location upload overlays; black “Not now” sheet actions.
* Chore: bump direct dependencies to current latest (incl. `file_picker` 12 API: `FilePicker.pickFile`).

## 1.5.2

* Add: optional Maps key — location sharing works with GPS-only confirm sheet when no Google Maps key is set; map picker + place search when a key is provided.
* Add: in-app image viewer (pinch / double-tap zoom) and in-bubble voice player (`audioplayers`).
* Add: optimistic attachment UX — show local image/audio/location immediately with full-bubble upload overlay, then promote in place when the server confirms (stable order vs agent reply).
* Add: built-in `FrontFaceChatStrings.english` / `.arabic` / `.forLanguage()` packs; professional “Add attachment” label; bundled Noto Sans Arabic (`FrontFaceArabic`) for RTL.
* Add: optional bubble colors documented on `FrontFaceChatTheme`; optional `showNewChatButton` on `FrontFaceChatConfig`.
* Fix: permissions use native system prompts first; gallery Photo Picker on Android; map my-location button above confirm sheet; attachment grid overflow; location bubble surviving history merge (string coords / incomplete parts).
* Fix: bump `record` to `^6.0.0` for iOS pod resolution.

## 1.5.1

* Docs: drop redundant root markdown (`BREAKING_CHANGES`, dated changelog snapshot, `README_SDK_PACKAGE`, `SEND_*` guides). Keep `README`, `CHANGELOG`, `INTEGRATION_GUIDE`, `CHAT_HISTORY_GUIDE`, `IDENTITY_VERIFICATION_GUIDE`. Location/image/voice contracts live in `INTEGRATION_GUIDE` §5.3–5.5.

## 1.5.0

* Breaking: attachments use the official FrontFace media APIs — remove host `uploader` / `FrontFaceUploadedAttachment`. Image & voice: reserve → signed PUT → `parts: [{ mediaAssetId }]`. Location: `location` object on `POST /api/chat/message`.
* Breaking: video attachments removed (not in the chat API). Use images or voice notes instead.
* Add: parse/render `MessagePart` (`location` / `image` / `audio`) on history reload, including voice transcript (`derivedText` / `processingStatus`).
* Add: in-chat voice note recorder (`record` + mic permission).
* Docs: align with `INTEGRATION_GUIDE.md` §5.3–5.5 / `openapi.yaml`.

## 1.4.1

* Fix: widen `geolocator` to `>=13.0.4 <15.0.0` so host apps on geolocator 14.x (e.g. Freshhouse) can resolve dependencies with `frontface_chat ^1.4.0`.

## 1.4.0

* Add: optional attachments — location (Google Maps picker), images, audio, video. All off by default via `FrontFaceChatConfig.attachments`.
* Add: professional permission flow (rationale dialog → system prompt → Settings for permanently denied).
* Add: host `uploader` callback for media (FrontFace chat API has no binary upload yet — host returns a public HTTPS URL).
* Add: `googleMapsApiKey` in attachments config for the map picker + static map previews (also configure the key in Android/iOS native projects).
* Add: all attachment / permission labels are on `FrontFaceChatStrings` (optional overrides) with `copyWith` for partial / runtime translations.
* Fix: bottom composer / actions respect SafeArea + optional `extraBottomInset` so content is not clipped by the home indicator or host bottom nav.

## 1.3.0

* Fix: blank chat history when local `sessionId` was missing — on open, call `ensure-conversation` then load full `messages/public` (history is keyed to `visitorId`).
* Fix: once lead capture is completed for a visitor, do not re-block on the lead form solely because the local session id was cleared.
* Add: account-keyed visitor id — `FrontFaceChatConfig.visitorId`, `provider.setVisitorId()` / `FrontFaceChat.setVisitorId()` so logged-in users keep history across devices (see `CHAT_HISTORY_GUIDE.md`).
* Add: public `provider.visitorId` / `provider.sessionId` getters for debugging.
* Docs: `CHAT_HISTORY_GUIDE.md`.

## 1.2.0

* Align with Aug 2026 API contract: handoff button only when `mode:"live"` AND `showButton:true` (AI-driven escalation — no standing button in `ticket`/`unavailable` modes).
* Add: message `metadata` preserved on poll/hydrate (ticket cards, CSAT prompts, inactivity events survive reload).
* Add: ticket actions from chat/handoff responses (`created`, `contact_required`, `failed`) with ticket card UI and external `accessUrl` opener.
* Add: CSAT prompt UI (`metadata.csat_prompt`) + `POST .../csat`.
* Add: offline message form when `showOfflineForm` + `POST .../offline-messages`.
* Add: bootstrap channel launcher buttons (`config.channels` → WhatsApp, email, etc.).
* Add: customer identity verification — `FrontFaceChat.identify(provider, token)` / `provider.identify()` with JWT from tenant backend; `resetUser()` on logout. See `IDENTITY_VERIFICATION_GUIDE.md` for your backend team.
* Add: `assistantMessage.id` from server used when present to prevent duplicate AI bubbles.
* Fix: `conversationHistory` only sent on the first message (no `sessionId`).

## 1.0.11

* Add: customer typing → agent dashboard (`POST .../typing`) while `agent_active` and foregrounded, with 1200ms stop debounce.
* Add: customer presence → dashboard (`POST .../presence`) on handoff: `online` + 30s heartbeat, `idle`/`offline` from app lifecycle.
* Add: agent typing indicator in the Flutter UI via Supabase Realtime (`typing:start` / `typing:stop` on private `conversation:<id>`). Cleared on disconnect / leave handoff; never faked when Realtime is down.
* Fix: Realtime credentials match RN/widget — bootstrap `realtime.apiKey` as socket apikey, `/realtime-token` JWT via `setAuth`. Polling remains for message recovery.

## 1.0.10

* Fix: asking for a human (e.g. "talk to human") no longer drops your own message from the UI. Entering handoff used to clear the local transcript and replace it with `GET /messages/public`; that GET can race the server write and omit the just-sent visitor bubble. We now **merge** server history into the existing transcript and de-dupe by sender + content.
* Fix: bot/server messages no longer duplicate when the same text arrives as a local provisional HTTP bubble and again from history/polling (`_appendMessage` reconciliation, `_pollInFlight`, stable ids when `id` is missing).
* Fix: handoff confirmation ("I'm connecting you with a human agent…") no longer appears twice. The message is returned once in the chat HTTP `response` and also stored once for `GET /messages/public` — the app was rendering both. On entering handoff we sync with the full server history (no `?after=`), bookmark the newest `createdAt`, then poll incrementally. Local provisional bubbles have no server id, so id-based de-dupe alone cannot catch this.

## 1.0.9

* Fix: lead-form field 2/3 labels (e.g. dashboard "Phone Number") can be overridden via `FrontFaceChatStrings.field2Label` / `field3Label` for English or Arabic, with automatic phone-number keyboard type when the label reads as a phone field.
* Fix: app bar back icon was double-flipped in RTL (manually swapped to `arrow_forward_ios` on top of `Directionality`'s own mirroring, pointing the wrong way). Now a single `arrow_back_ios_new` that mirrors correctly.
* Example app: added a language switcher (English/Arabic) on the home screen and live in-chat via `FrontFaceChatProvider.updateStrings()`, demonstrating phone-label override, RTL back button, and layout direction.

## 1.0.8

* Fix: Markdown links like `[View Details](https://…)` in assistant replies now open in the external browser reliably (no longer blocked by `canLaunchUrl` failing on iOS/Android). Example app Info.plist / AndroidManifest updated with the required URL query declarations.
* Fix: normalize product CTA link labels so mobile "View Listings" / Arabic equivalents render as the same `View Details` / `عرض التفاصيل` label as web (`FrontFaceChatStrings.viewDetails`).

## 1.0.7

* Fix: when lead capture is enabled, the SDK no longer shows the local greeting before the lead form (even if the dashboard `capture_mode` is `email_after`). `requireLeadCaptureBeforeChat` now defaults to `true`, so the lead form is the first step of creating a session — the conversation and `assembledGreeting` start only after form submit. Set `requireLeadCaptureBeforeChat: false` to follow the dashboard mode instead.
* Fix: on session expiry (`403 SESSION_*`) clear the chat and show the lead form again (email/phone). The new session and chatbot `assembledGreeting` are created only after form submit — no local greeting before the form, and no “session expired” error. New chat / no session follows the same lead-form-first flow when lead capture is enabled.
* Add: `FrontFaceChat.debugCorruptSessionToken(projectId)` plus an example-app button to test session-expiry recovery without waiting 24h (tampered == expired on the server).
* Fix: chat scrolling jumped too far on every message (animateTo overshoot). Switched to a WhatsApp-style reverse `ListView` so the latest message stays at the bottom smoothly, only soft-scrolls when near the bottom, and leaves position alone if the user scrolled up to read history.

## 1.0.6

* Fix: a lead-capture-required session (`requireLeadCaptureBeforeChat` or dashboard `email_first`/`email_required`) could be bypassed if a session id was already stored from before lead capture was required — `initialize()` checked for an existing session before checking whether lead capture was still needed, so it would hydrate straight past the form. `_shouldShowLeadFormBeforeChat()` is now checked first, unconditionally, so it wins over an existing session too. Removed the now-redundant `_evaluateLeadFormAfterHistory()`.

## 1.0.5

* Fix: scroll-to-bottom could land short of the last message on reload with a long conversation history, requiring a manual scroll to see it. Removed redundant `_scrollToBottom()` calls that raced the provider-listener-triggered one, gave the message `ListView` a generous `cacheExtent` so more content is measured up front, and switched to an overshoot-and-clamp `animateTo` target so a stale `maxScrollExtent` estimate can't strand the scroll.
* Docs: added a `requireLeadCaptureBeforeChat` usage reference in the example app.

## 1.0.4

* Add: `FrontFaceChatConfig.requireLeadCaptureBeforeChat` — forces the lead-capture form (email/phone/etc.) to show before the first message and before any session/conversation is created, regardless of the `capture_mode` configured on the FrontFace dashboard.
* Fix: a stale/revoked `sessionToken` (`SESSION_INVALID` / `SESSION_CONVERSATION_MISMATCH`) previously surfaced as a generic error with no recovery path. The SDK now detects this automatically (on send, on resume/hydrate, and while polling), clears the stale session, posts a `FrontFaceChatStrings.sessionExpired` system message, and — if lead capture is enabled — re-shows the lead form before the next message, so a fresh session always starts with re-verified contact info.

## 1.0.3

* Fix: links inside assistant/agent Markdown messages had no visual affordance as links — they rendered in `theme.primaryColor` (often black) with no underline. Added `FrontFaceChatTheme.linkColor` (defaults to a conventional link blue, independent of `primaryColor`) and links now render underlined, like a normal URL.

## 1.0.2

* Fix: the app bar title stayed in whatever language the FrontFace dashboard's `config.title` was set to (e.g. "Support"), with no way to translate it client-side. Added `FrontFaceChatStrings.title` — when set, it always overrides the dashboard value, so integrators can provide their own translation regardless of what language the dashboard is configured in.
* Add: `FrontFaceChatProvider.updateStrings()` swaps the active `FrontFaceChatStrings` at runtime and notifies listeners, so the host app can change the chat's language live (title, placeholder, input direction, and any already-shown status banner all update immediately) without recreating the provider or screen.
* Audited every UI string in the SDK — confirmed there are no remaining hardcoded literals bypassing `FrontFaceChatStrings`; all text is either developer-overridable or dashboard-driven with a localizable fallback.
* Verified emoji handling end-to-end (rendering, input, copy, and `detectTextDirection`'s neutral treatment of emoji — including ZWJ sequences — so a leading emoji never shadows the following strong-direction word).
* Docs: clarified in the README which strings are dashboard-driven-with-client-fallback (`typeMessage`, `talkToHuman`, `loadingChat` — used only when the dashboard value is empty) versus always-client-side-override (`title`).

## 1.0.1

* Fix: the opening assistant bubble no longer duplicates itself by concatenating `greetingIntro` with `greeting` — only `greeting` is shown, per the integration guide.
* Fix: assistant/agent messages now render Markdown (`**bold**`, lists, links) via `flutter_markdown_plus` instead of showing raw `**` syntax; links are restricted to `https`/`http`/`mailto` schemes.
* Fix: replaced the typing indicator's opacity/scale pulse with a smooth vertical wave animation.
* Fix: Arabic/RTL support — `FrontFaceChatStrings` gained `textDirection`, `typeMessage`, `talkToHuman`, `loadingChat`, and `messageCopied`, and the UI now falls back to these instead of hardcoded English when the server/embed-config value is empty (placeholder, handoff button text, loading screen). The chat screen wraps in `Directionality`, mirrors the back/send icons, and bubble alignment follows `AlignmentDirectional`.
* Fix: mixed-language messages (e.g. English typed into an Arabic-configured chat) now render with their own natural text direction instead of inheriting the app's RTL/LTR layout direction — applied to message bubbles, system messages, and the input field (which now tracks direction live as you type).
* Fix: `FrontFaceChatScreen.dispose()` no longer calls `context.read()`, which could throw "Looking up a deactivated widget's ancestor is unsafe" if the screen and its scoped provider were torn down in the same frame (e.g. popping a route pushed by `FrontFaceChat.open()`).
* Add: long-press any message bubble to copy its text to the clipboard, with a localized confirmation snackbar.
* Add: automated test suite covering English/Arabic text direction detection, localized string fallbacks, greeting de-duplication, session-token persistence, and RTL widget behavior.

## 1.0.0

* Initial release: native FrontFace AI chat, lead capture, human handoff, theme and i18n support.
* Session-token (`X-FrontFace-Session`) support: persisted alongside the session id and sent on every conversation-scoped call (continued chat messages, handoff, status, message history), per the FrontFace security-hardening update.
* Handoff can now be requested before the visitor's first message via `POST /api/chat/ensure-conversation`.
* Removed customer identify (`POST /api/customers/identify`) — disabled server-side, not part of this release.
