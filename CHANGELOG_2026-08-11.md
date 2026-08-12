# Mobile SDK Docs — Changes Since 5 July 2026

> **Audience:** the Flutter developer.
> **Date:** 2026-08-11.
> **Files changed:** `INTEGRATION_GUIDE.md`, `openapi.yaml`.

---

## Summary

The docs are refreshed to match the current API contract after several backend changes
(verified customer identification, AI-driven escalation, CSAT, ticket contact collection,
persisted-message deduplication, and widget channel launchers). Start with
`INTEGRATION_GUIDE.md`; `BREAKING_CHANGES.md` is still the upgrade checklist for the
June 29 security hardening — nothing in it has changed.

---

## What's new

### 1. Handoff button behavior corrected (P0 — **contract change**)

**Before:** the guide said `mode:"ticket"` means the support button is available.

**Now:** `showButton` is `false` for both `ticket` and `unavailable` modes. The AI offers
tickets conversationally — there is no standing "Talk to a human" button unless `mode:"live"`
and `showButton:true`. This matches the API behavior since the AI-driven escalation change
(2026-08-07). See §6.2.

### 2. Channel launcher links documented (P0 — **new section**)

The bootstrap response can include a `channels` array with external support channel links
(WhatsApp, Instagram, Facebook, email, phone, custom). Each is a deep link — open it in the
system browser, not an in-app thread. New §4.1 documents the shape and rendering guidance.
`openapi.yaml` now includes the `ChannelButton` schema and the `channels` field on
`EmbedConfig.config`.

### 3. Message metadata added to PublicMessage (P0 — **schema change**)

`PublicMessage` in `openapi.yaml` now includes a `metadata` field (nullable object). This
carries structured data for ticket cards (`ticket_reference`), CSAT prompts
(`csat_prompt: true`), and inactivity warnings (`event: "inactivity_warning"`). Without it,
Dart codegen drops data needed for ticket cards and CSAT prompts to survive transcript reload.
The polling section (§6.5) documents the known metadata keys.

### 4. CSAT / satisfaction rating (P1 — **new section**)

New §6.7 documents the CSAT flow: the server delivers a system message with
`metadata.csat_prompt: true` after a handoff conversation ends; submit the rating via
`POST /api/widget/conversations/{id}/csat` (rating 1–5, optional feedback). `openapi.yaml`
now includes the endpoint and `CsatRequest` schema.

The status endpoint now also documents `satisfactionRating` and
`autoCloseAfterWarningMinutes` fields.

### 5. Offline messages (P1 — **new section**)

New §6.8 documents the offline contact form: `POST /api/projects/{id}/offline-messages`
with `name`, `email`, `message`, optional `visitorId`. `openapi.yaml` now includes the
endpoint and `OfflineMessageRequest` schema.

### 6. Lead capture — skip/defer intentionally excluded

The API has legacy `skip` and `defer` endpoints, but these are dead code — the skip
button was deliberately removed from the widget (mandatory lead capture), and defer
never had a client-side caller. **Do not implement skip/defer on mobile.** Lead capture
form submission is required when the project has it enabled.

### 7. Bootstrap config field reference (P2 — **new table**)

A full field-by-field table in §4 now lists every bootstrap config field and whether to
use or ignore it on mobile. Covers `starters`, `notice`, `footer`, `feedbackEnabled`,
`copyEnabled`, `hideBranding`, `localeDefault`, `avatarUrl`, `bubbleColor`, and more.
`openapi.yaml` now includes all these fields on `EmbedConfig.config`.

### 8. `conversationHistory` usage clarified

Added a note in §5 explaining that `conversationHistory` is only useful on the first
message (no `sessionId`). Once you have a session, the server loads history from the
database — sending it alongside a `sessionId` is redundant.

### 9. `accessUrl` security note strengthened

Clarified that `accessUrl` is both short-lived **and** one-time use. Do not cache or
persist it.

### 10. Out-of-scope section updated

- Removed "Theming beyond primaryColor/title" (now fully documented).
- Added explicit note that in-app WhatsApp/Instagram/Facebook threads are out of scope —
  the `channels` array is launcher-only.
- Clarified the offline message queue note (the contact *form* is in scope; client-side
  message *queueing* for flaky networks is not).

### 11. Endpoint quick reference table expanded

Added: CSAT, offline-messages. Updated descriptions for bootstrap, status, and
messages/public to reflect new fields.

---

## Files NOT changed

- `BREAKING_CHANGES.md` — no changes since June 29.
- `README.md` — no changes needed.
- React Native reference code (`src/`) — reference only, not the Flutter contract.

---

## Action items for the Flutter developer

1. **Regenerate Dart models from `openapi.yaml`** — the `PublicMessage`, `EmbedConfig`,
   and `ConversationStatusResponse` schemas have new fields.
2. **Update handoff button logic** — only show the button when `mode:"live"` AND
   `showButton:true`.
3. **Preserve `metadata` on messages** — needed for ticket cards and CSAT prompts.
4. **Implement CSAT UI** if the project uses it (check for `metadata.csat_prompt` on
   system messages).
5. **Implement channel launchers** if the project configures them (check `config.channels`
   from bootstrap).
