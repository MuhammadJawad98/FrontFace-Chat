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
