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
