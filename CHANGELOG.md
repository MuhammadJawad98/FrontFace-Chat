## 1.0.0

* Initial release: native FrontFace AI chat, lead capture, human handoff, theme and i18n support.
* Session-token (`X-FrontFace-Session`) support: persisted alongside the session id and sent on every conversation-scoped call (continued chat messages, handoff, status, message history), per the FrontFace security-hardening update.
* Handoff can now be requested before the visitor's first message via `POST /api/chat/ensure-conversation`.
* Removed customer identify (`POST /api/customers/identify`) — disabled server-side, not part of this release.
