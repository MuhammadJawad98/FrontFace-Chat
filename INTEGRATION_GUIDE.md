# FrontFace Mobile SDK — Integration Guide

> Build a native chat support experience (AI assistant + support tickets + live human handoff) for your
> Flutter app on top of the FrontFace public API.

**Audience:** the Flutter developer building the SDK.
**Base URL:** `https://api.frontface.app`
**Transport:** HTTPS + JSON for requests/responses; a WebSocket (Supabase Realtime) for live
human-handoff streaming, with an HTTP polling fallback.

---

## 1. How it works (architecture)

FrontFace is a **server-mediated** chat platform. Your app never talks to a database or an LLM
directly — it makes plain HTTPS calls to the public API, and the server handles RAG, the LLM,
lead storage, and routing to human agents. The web chat widget and the hosted public page are
both thin clients over the exact same endpoints you'll use; this SDK is simply a third client.

```
┌────────────┐   HTTPS (JSON)        ┌──────────────────┐
│ Flutter app│ ───────────────────▶  │  api.frontface.app│ ── LLM / RAG / agents / DB
│  (this SDK)│ ◀───────────────────  │   (public API)    │
└─────┬──────┘   responses           └─────────┬────────┘
      │                                         │ server broadcasts agent replies
      │  Supabase Realtime (WebSocket)          │
      └────────────────◀───────────────────────┘
         channel "conversation:<id>"  (live human-handoff only)
```

Three support outcomes:

1. **AI chat (always):** synchronous request/response. `POST /api/chat/message` returns the
   assistant's reply in the HTTP response. No socket needed.
2. **Support ticket (when live help is unavailable):** the response carries a structured
   `ticket` action. Render it as a ticket card or contact form; do not enter live-handoff mode.
3. **Live human handoff (when the visitor asks for a human):** the conversation is routed to a
   human agent. Agent replies arrive **asynchronously**, so you subscribe to a Realtime channel
   (or poll) to receive them. This is the only part that needs the WebSocket.

---

## 2. Authentication & identity

Every request carries three things: a **publishable key**, a **visitor id**, and (for chat) a
**source**.

### 2.1 Publishable client key — `X-FrontFace-Key`

Each app gets a **publishable client key** that looks like `pk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`.
Send it on **every** request:

```
X-FrontFace-Key: pk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

- It is **publishable, not a secret.** It is safe to ship inside your app binary (same model as a
  Stripe publishable key, a Google Maps API key, or a Supabase anon key). Do not treat it like a
  password, but also don't go out of your way to leak it.
- It is **scoped to one project** and **revocable**. If a key is ever abused, the project owner
  revokes it in the dashboard and ships a new app build — the old key stops working within ~5
  minutes, and **the project's web widget is unaffected**.
- You will be handed a **test key + the matching `projectId`** to start development (see README).

> **Why a key at all?** Mobile apps send no browser `Origin` header, which the chat endpoint
> normally requires. The key is what authorizes your app instead. It also gives the project owner
> a per-app kill switch and clean analytics.

### 2.2 Visitor id — `X-Visitor-Id`

You generate a **stable, per-install** visitor id once, persist it, and reuse it forever. It
identifies the device/user to the backend across conversations (history, lead linkage, rate
limiting).

- **Format:** any opaque string ≤ 100 chars. Recommended: a UUID v4, or `mob_<uuid>`.
- **Persistence:** store in secure/persistent device storage (e.g. `flutter_secure_storage` or
  `shared_preferences`). Generate it on first launch; never regenerate it on reinstall-survival
  unless you intend a "fresh" identity.
- Send it both as the `X-Visitor-Id` header **and** in the request body field `visitorId` where
  the endpoint takes one (the backend reads both).

### 2.3 Source

Chat/lead/conversation requests take a `source` field. **Always send `"mobile"`.** This segments
your traffic in the dashboard's analytics and inbox.

### 2.4 Standard headers (every request)

| Header            | Value                  | Notes                                 |
| ----------------- | ---------------------- | ------------------------------------- |
| `Content-Type`    | `application/json`     | on POST                               |
| `X-FrontFace-Key` | `pk_…`                 | required on all requests              |
| `X-Visitor-Id`    | your stable visitor id | also mirror into the body `visitorId` |

---

## 3. Core concepts & lifecycle

| Concept        | What it is                                                                                                                                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `projectId`    | The FrontFace project (agent) you're embedding. Provided to you with the key.                                                                                                                                                         |
| `visitorId`    | Stable per-install id (§2.2).                                                                                                                                                                                                         |
| `sessionId`    | The **conversation id** (a UUID). `sessionId` and "conversation id" are the same value.                                                                                                                                               |
| `sessionToken` | An opaque token returned alongside `sessionId` that authorizes continued chat messages and per-conversation routes (`/status`, `/messages/public`, `/handoff`). Persist it with the `sessionId` and send it as `X-FrontFace-Session`. |
| `source`       | Always `"mobile"`.                                                                                                                                                                                                                    |

**Session lifecycle**

1. **First message:** call `POST /api/chat/message` with **no** `sessionId`. The response returns a
   `sessionId` **and a `sessionToken`** — persist both (per project). That is now the active conversation.
2. **Subsequent messages:** send the stored `sessionId` so the thread continues, and include
   `X-FrontFace-Session: <sessionToken>`. The response may return a refreshed `sessionToken` —
   keep the latest.
3. **Resume after app restart:** reload the stored `sessionId` and rehydrate the thread with
   `GET /api/widget/conversations/<sessionId>/messages/public` (full history when called without
   `?after=`), sending `X-FrontFace-Session: <sessionToken>`.
4. **"New chat":** drop the stored `sessionId` (and optionally call the close endpoint, §8) so the
   next message starts a fresh conversation.

> Reuse a stored session only while it is still AI-owned (`status == "ai_active"`) or in handoff.
> A `resolved`/`closed` conversation should not accept new visitor messages — start a new chat.

---

## 4. Bootstrap — fetch runtime config

Call this once on launch (and cache it). It returns branding, lead-capture configuration, and the
**Realtime configuration** you need for live handoff.

```
GET /api/embed/config/{projectId}
Headers: X-FrontFace-Key, X-Visitor-Id
```

**Response (200):**

```jsonc
{
  "projectId": "uuid",
  "enabled": true,
  "config": {
    "primaryColor": "#0a0a0a",
    "position": "bottom-right", // web-only; ignore on mobile
    "greeting": "Hi! How can I help you today?",
    "greetingIntro": "Hi there!",
    "title": "Chat with us",
    "placeholder": "Type a message...",
    "avatarUrl": "https://…/avatar.png",       // nullable — agent/bot avatar
    "launcherIconUrl": "https://…/icon.png",    // nullable — web launcher; ignore on mobile
    "bubbleColor": "#1a1a1a",                   // nullable — chat bubble accent
    "usePrimaryForHeader": true,                // use primaryColor for the header background
    "hideBranding": false,                      // hide "Powered by FrontFace"
    "feedbackEnabled": false,                   // show thumbs up/down on AI replies
    "copyEnabled": true,                        // show "copy message" action
    "starters": ["How do I reset my password?", "Pricing info"],  // suggested first messages
    "notice": { "enabled": true, "text": "We typically reply within 5 min." },
    "footer": { "text": "…", "url": "https://…" },   // nullable
    "localeDefault": "en",                      // project's default UI language
    "channels": [                               // see §4.1 — omitted when empty
      { "type": "whatsapp", "url": "https://wa.me/1234567890", "label": "WhatsApp" },
      { "type": "email", "url": "mailto:support@example.com" },
    ],
  },
  "realtime": {
    "enabled": true,
    "supabaseUrl": "https://<ref>.supabase.co",
    "tokenBased": true,
  },
  "leadCapture": {
    "enabled": true,
    "formFields": {
      "email": { "required": true },
      "field_2": { "enabled": true, "label": "Company", "required": false },
      "field_3": { "enabled": false, "label": "", "required": false },
    },
    "hasQualifyingQuestions": true,
    "capture_mode": "email_after", // "email_after" | "email_first" | "email_required"
  },
  "voice": { "enabled": false }, // voice is out of scope for v1
}
```

Use `config.greeting` for the opening assistant bubble, `config.primaryColor`/`title` for theming,
`leadCapture` to drive the form (§7), and `realtime.supabaseUrl` + token endpoint (§6.4) for live handoff.

> `proactiveEngagement` and `leadRecovery` blocks may also appear — ignore them for v1.

### 4.1 Channel launcher links

`config.channels` is an optional array of external support channel links the project owner has
configured. Each entry is an external deep link — **not** an in-app transport. Open the URL in
the system browser or platform-native handler (`url_launcher` in Flutter).

| Field     | Type   | Required | Notes                                                                    |
| --------- | ------ | -------- | ------------------------------------------------------------------------ |
| `type`    | string | ✅       | One of `whatsapp`, `instagram`, `facebook`, `email`, `phone`, `custom`   |
| `url`     | string | ✅       | `https:`, `http:`, `mailto:`, or `tel:` only (server-validated)          |
| `label`   | string | —        | Display text (e.g. "Chat on WhatsApp"); fall back to `type` if absent    |
| `iconUrl` | string | —        | Custom icon (`https:`/`http:` only); use a platform default per `type`   |

Render these as launcher buttons alongside the chat — e.g. a WhatsApp icon that opens
`wa.me/…` in the system browser, or a `tel:` link that starts a phone call. This is a
launcher/deep-link contract; there is no in-app WhatsApp or Instagram thread. If the
array is empty or absent, show nothing.

**Widget config field reference** — which bootstrap fields to use vs. ignore on mobile:

| Field               | Mobile behavior                                           |
| ------------------- | --------------------------------------------------------- |
| `primaryColor`      | Use for theming (header, accents)                         |
| `title`             | Chat window title / header text                           |
| `greeting`          | Opening assistant bubble                                  |
| `greetingIntro`     | Intro line above greeting                                 |
| `placeholder`       | Composer placeholder text                                 |
| `avatarUrl`         | Bot/agent avatar image                                    |
| `bubbleColor`       | Chat bubble accent (nullable — fall back to primaryColor) |
| `starters`          | Suggested first-message chips                             |
| `notice`            | Dismissible banner above the chat                         |
| `footer`            | Linkable footer text below the chat                       |
| `feedbackEnabled`   | Show thumbs up/down on AI replies                         |
| `copyEnabled`       | Show "copy message" action on bubbles                     |
| `hideBranding`      | Hide "Powered by FrontFace" badge                         |
| `localeDefault`     | UI language (`en`, `ar`, etc.)                            |
| `channels`          | External channel launcher buttons (§4.1)                  |
| `position`          | **Ignore** — web-only (bottom-right/left)                 |
| `launcherIconUrl`   | **Ignore** — web launcher icon                            |
| `usePrimaryForHeader` | **Ignore** — web-specific header toggle                 |

---

## 5. AI chat

```
POST /api/chat/message
Headers: Content-Type, X-FrontFace-Key, X-Visitor-Id
```

**Request body:**

```jsonc
{
  "projectId": "uuid", // required
  "message": "How do I reset my password?", // required, max 2000 chars
  "visitorId": "mob_…", // required (mirror of the header)
  "source": "mobile", // always "mobile"
  "sessionId": "uuid-or-null", // omit/null for the first message; send to continue
  "conversationHistory": [
    // optional; last ~10 turns — only needed on the FIRST message (no sessionId)
    { "role": "user", "content": "…" },
    { "role": "assistant", "content": "…" },
  ],
  "context": {
    // optional analytics metadata — see note below
    "device": "mobile",
    "os": "iOS",
    "osVersion": "17.5",
    "timezone": "Europe/London",
    "language": "en-GB",
    "appVersion": "1.2.0",
  },
}
```

> **`conversationHistory` note:** only useful on the very first message (when there is no
> `sessionId`). Once you have a `sessionId`, the server loads conversation history from the
> database — sending `conversationHistory` alongside a `sessionId` is redundant bandwidth. The
> widget sends it only for the initial anonymous exchange before a session is created.

> **Populate `device`/`os`/`osVersion` yourself — nothing on the backend derives them for you.**
> Unlike the web widget (which parses the browser's User-Agent), a native client's `context` is
> pure pass-through: whatever you send is exactly what lands in the dashboard's "By Device"
> traffic breakdown, and if you omit these fields that conversation simply won't count toward it.
> `"device"` must be `"mobile"` or `"tablet"` (no third value — this isn't a browser); `"os"` is a
> free-text label such as `"iOS"`/`"Android"`.
>
> Dependency-free Dart, mirroring what the first-party React Native SDK does automatically:
>
> ```dart
> import 'dart:io';
> import 'package:flutter/widgets.dart';
>
> String detectOS() => Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Unknown');
> String detectOSVersion() => Platform.operatingSystemVersion;
>
> // No Platform.isPad-equivalent in Dart — this is the same heuristic Android itself uses
> // (the "sw600dp" tablet breakpoint), applied on both platforms since dart:io doesn't expose
> // device idiom. Less precise than the RN SDK's exact Platform.isPad check on iOS.
> String detectDevice(BuildContext context) =>
>     MediaQuery.of(context).size.shortestSide >= 600 ? 'tablet' : 'mobile';
> ```

**Response (200):**

```jsonc
{
  "response": "To reset your password…", // assistant reply (may be "" — see handoff note)
  "sessionId": "uuid", // persist this
  "sessionToken": "…", // persist this; send as X-FrontFace-Session on continued messages and reads
  "sources": [{ "id": "…", "name": "…", "relevance": 0.8 }],
  "toolCalls": [{ "name": "…", "success": true, "duration": 123 }],
  "processingTime": 842,
  "requestId": "…", // include in bug reports
  "handoff": {
    // present only when relevant — see §6.3
    "triggered": false,
    "reason": "agent_handling",
    "queuePosition": 2,
  },
  "ticket": {
    // present only when ticketing is relevant — see §5.1
    "status": "created",
    "ticketId": "uuid",
    "reference": "FF-1042",
    "subject": "Billing issue",
    "accessUrl": "https://api.frontface.app/api/public/tickets/…?grant=…",
  },
}
```

**Errors** (shape `{ "error": { "code", "message" } }`):

| Status | code                                                   | Meaning                                   |
| ------ | ------------------------------------------------------ | ----------------------------------------- |
| 400    | `INVALID_INPUT` / `MESSAGE_TOO_LONG` / `EMPTY_MESSAGE` | Bad body / message > 2000 chars           |
| 403    | `MISSING_ORIGIN` / `DOMAIN_NOT_ALLOWED`                | Key missing/invalid (see §9)              |
| 404    | `PROJECT_NOT_FOUND`                                    | Bad `projectId`                           |
| 429    | `RATE_LIMITED`                                         | Throttled — honor `Retry-After` (§9)      |
| 504    | `TIMEOUT`                                              | Upstream LLM timeout — safe to retry once |

Render `response` as the assistant bubble. Then inspect `ticket` (§5.1) before evaluating
`handoff`. If `response` is empty and there is no ticket action, inspect `handoff` (§6.3).

**Use `assistantMessage.id` as that bubble's local id.** When the server persisted a row for
this reply it returns `assistantMessage: { id, createdAt }`. Realtime and the polling fallback
both deduplicate on message id (§6.4, §6.5), so a client-generated id makes the same reply
render a second time when it is delivered back. The field is optional — it is absent only when
no row was written, and there is then nothing to receive back, so fall back to a local id.
`POST /api/conversations/{id}/handoff` (`status:"ticket"`) and the lead-capture form response
carry the same field for the messages they persist.

### 5.1 Ticket actions

`ticket` is an exact discriminated union keyed by `status`:

| Status                               | Fields                                                  | Client behavior                                                                         |
| ------------------------------------ | ------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `created` / `existing_ticket_reused` | `ticketId`, `reference`, `subject`, `accessUrl`         | Render the returned reference and subject. Open the returned URL in the system browser. |
| `contact_required`                   | `intentId`, `allowedFields` (`email`, `phone`, or both) | Ask for an allowed contact field **in the conversation** and send the reply as a normal message (§5.2). |
| `failed`                             | `message`                                               | Show the failure. Never render or manufacture a reference.                              |

Rules:

- Treat each `ticketId` as a separate ticket; one conversation can hold multiple simultaneous
  tickets.
- Never derive a reference from `ticketId`, guess the next number, or rebuild `accessUrl` from
  `reference`. Use the server-returned strings exactly.
- Open `accessUrl` in the system browser. It contains a **short-lived, one-time** access grant —
  do not cache, persist, or log it. It expires quickly and cannot be reused.
- A ticket action wins over a handoff signal for that response: render the action and do not
  start Realtime/polling.

### 5.2 Handling `contact_required`

**Recommended: collect the contact detail conversationally.** The assistant's own `response`
already asks for the missing field, so render it like any other message and let the customer
reply in the composer. Send that reply through `POST /api/chat/message` unchanged — the server
matches the value against the pending intent and returns the committed `created` /
`existing_ticket_reused` action on that turn.

This is the path voice and WhatsApp use, and it is the one FrontFace's own widget and hosted page
use. It costs no extra UI, it survives an app restart (the exchange is part of the persisted
transcript), and it keeps a single input affordance on screen.

Two constraints worth knowing:

- The value must appear **verbatim in the customer's message**. This is an anti-hallucination
  control: the server will not accept a contact the customer did not actually type. Do not
  pre-fill, reformat, or normalize it on the client.
- If the value is malformed, the assistant simply asks again. Do not retry or "fix" it yourself.

**Alternative: a native contact form.** If your app would rather present a platform-native form,
the intent-contact endpoint remains fully supported. Submit either or both of the allowed fields:

```http
POST /api/ticket-intents/{intentId}/contact
Headers:
  X-FrontFace-Key: pk_…
  X-Visitor-Id: <the same visitor id>
  X-FrontFace-Session: <the sessionToken paired with this conversation>
Content-Type: application/json

{ "email": "customer@example.com" }
```

The response is `{ "ticket": <TicketAction> }`. Keep the existing conversation and reuse its
exact `sessionToken`; `intentId` alone does not authorize conversion. Replace the contact form
only after `created` or `existing_ticket_reused`. A non-2xx response may still include a
structured `contact_required` or `failed` action, but it never includes a usable ticket
reference unless a ticket was committed.

Note that a ticket committed this way is still recorded on the conversation: the committed
action's fields are attached to the acknowledgement message, so a reloaded transcript can redraw
the ticket card without re-fetching anything.

---

## 6. Live human handoff

When a visitor wants a person — or the AI decides to escalate — the conversation moves to a human
agent. Agent messages then arrive **asynchronously** over Realtime (or polling).

### 6.1 Status state machine

```
ai_active ──(handoff)──▶ waiting ──(agent claims)──▶ agent_active ──(ends)──▶ resolved | closed
     ▲                                                                            │
     └──────────────────── "New chat" / reopened ───────────────────────────────┘
```

| Status                | Meaning                      | UI                                           |
| --------------------- | ---------------------------- | -------------------------------------------- |
| `ai_active`           | Talking to the AI            | normal chat input                            |
| `waiting`             | Queued for a human           | show "waiting for an agent", `queuePosition` |
| `agent_active`        | A human agent is handling it | show agent name, enable typing indicators    |
| `resolved` / `closed` | Conversation ended           | show "conversation ended", offer New chat    |

"In handoff" = status is `waiting` **or** `agent_active`.

### 6.2 Triggering handoff (the "Talk to a human" button)

You need a conversation id first. If the visitor hasn't sent a message yet, create one:

```
POST /api/chat/ensure-conversation
Body: { "projectId", "visitorId", "source": "mobile" }
→ 200 { "conversationId": "uuid", "sessionToken": "…" }    // persist conversationId as sessionId; keep sessionToken for continued messages and reads
```

Then check availability and trigger:

```
GET  /api/projects/{projectId}/handoff-availability
→ 200 { "available": true, "showButton": true, "buttonText": "Talk to a human",
        "showOfflineForm": false, "reason": "…" }

POST /api/conversations/{conversationId}/handoff
Body: { "reason": "button_click" }    // or "customer_request"
→ 200 {
        "status": "agent_active" | "waiting" | "offline" | "ticket",
        "queuePosition": 3,                 // when waiting
        "estimatedWaitMinutes": 6,          // when waiting
        "assignedAgent": { "id": "…", "name": "Sara" },  // when agent_active
        "message": "Our team is offline…",  // when offline
        "showOfflineForm": true,            // when offline
        "ticket": { "status": "created", … } // when status == "ticket"; see §5.1
      }
```

- `mode:"live"` + `showButton:true` → show the "Talk to a human" button. This is the only
  state where a standing button is rendered.
- `mode:"ticket"` → `showButton` is **always `false`**. Do **not** show a standing button.
  The AI offers a ticket conversationally instead (via the `ticket` action in chat responses,
  §5.1). The project still supports tickets, but the entry point is the AI, not a button.
- `mode:"unavailable"` → `showButton` is **always `false`**. No human path right now.
  If `showOfflineForm:true`, show an offline form and submit it via the offline-message
  endpoint (§6.8). Otherwise, do nothing.
- `available:false` / `showButton:false` → don't render any handoff UI.
- `status:"ticket"` (from the handoff POST response) → render `ticket` per §5.1 and do not
  enter handoff.
- `status:"offline"` or `showOfflineForm:true` → show an offline form (§6.8).
- Otherwise enter the handoff UI and start streaming (§6.4).

### 6.3 Detecting handoff from a chat response

A normal `POST /api/chat/message` can also signal handoff (e.g. the visitor typed "I want a
human", or the thread is already owned by an agent). Use this predicate (mirrors the web client):

```
enterHandoff =
  handoff.triggered == true
  OR (response is empty AND handoff.reason in {"in_queue", "agent_handling"})

target status = (handoff.reason == "agent_handling") ? "agent_active" : "waiting"
```

When already in handoff, the AI no longer answers, so `response` comes back empty and `handoff`
carries the current state.

### 6.4 Receiving agent messages — Realtime (primary)

Realtime uses **private channels** with short-lived, conversation-bound JWTs. Before
subscribing, fetch a Realtime token from the API:

```
POST /api/widget/conversations/{conversationId}/realtime-token
Headers: X-FrontFace-Session: {sessionToken}
→ 200 { "token": "eyJ...", "expiresAt": 1751234567 }
```

Then connect to Supabase Realtime with the returned token:

- **Channel name:** `conversation:<conversationId>`
- **Connection:** Supabase Realtime endpoint `wss://<ref>.supabase.co/realtime/v1` with
  `apikey = token` (the JWT from the token endpoint). Use `setAuth(token)` on the client.
  The Dart package `supabase_flutter` (or `realtime_client`) handles this — see §12.
- **Channel config:** `broadcast: { self: false }, private: true`.
- **Subscribe only while in handoff** (`waiting`/`agent_active`); unsubscribe when you leave it.
- **Token refresh:** schedule a refresh at `expiresAt - 60` seconds. Call the token endpoint
  again, then `client.setAuth(newToken)`. If the refresh fails, fall back to polling (§6.5).

**Events** (all are `broadcast`; the useful payload is nested at `payload['payload']['data']`):

| Event                          | `data` shape                                                                             | Do                                                                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `message:new`                  | `{ message: { id, senderType, senderId?, senderName?, content, createdAt, metadata? } }` | Append the message. `senderType` ∈ `customer\|agent\|ai\|system`. Skip `customer` (your own echo). De-dupe by `id`. |
| `conversation:status_changed`  | `{ conversationId, status, queuePosition? }`                                             | Apply status transition; update queue position.                                                                     |
| `conversation:assigned`        | `{ agentId, agent: { name } }`                                                           | Set agent name; status → `agent_active`.                                                                            |
| `queue:position_updated`       | `{ position }`                                                                           | Update queue position.                                                                                              |
| `conversation:resolved`        | `{ conversationId, resolution }`                                                         | If `resolution=="ai_active"` go back to AI, else treat as `resolved`/ended.                                         |
| `typing:start` / `typing:stop` | `{ participant: { type, name? } }`                                                       | If `participant.type=="agent"`, show/hide the agent typing indicator.                                               |

**Reconnect:** exponential backoff `min(1000 * 2^attempts, 30000)` ms, up to 5 attempts; after
that, fall back to polling (§6.5). On subscribe-status `SUBSCRIBED` you're live; `CLOSED` /
`CHANNEL_ERROR` means dropped.

### 6.5 Receiving agent messages — polling (fallback)

If Realtime can't connect (or as a deliberate simpler v1), poll while in handoff:

```
GET /api/widget/conversations/{conversationId}/messages/public?after={lastCreatedAtISO}
Headers: X-FrontFace-Session: {sessionToken}
→ 200 { "messages": [ { id, senderType, senderName?, content, createdAt, metadata } ] }
```

**`metadata`** (nullable object) carries structured data for special message types:

| Key                  | Meaning                                                            |
| -------------------- | ------------------------------------------------------------------ |
| `ticket_reference`   | A ticket was created/reused — render a ticket card                 |
| `csat_prompt: true`  | Server is prompting for CSAT — show the rating UI (§6.7)           |
| `event: "inactivity_warning"` | Inactivity warning — the conversation will auto-close soon |
| `event: "auto_closed"` | The conversation was auto-closed due to inactivity               |

Always preserve `metadata` when deserializing messages. If your Dart models are generated from
`openapi.yaml`, verify that the `metadata` field is not dropped — it is required for ticket
cards and CSAT prompts to survive a transcript reload.

- Poll every **2 s**. Track the newest `createdAt` you've seen and pass it as `?after=` so you only
  fetch new messages. Without `?after=` you get the full history (use that for rehydration on
  resume).
- Send `X-FrontFace-Session: {sessionToken}` (the token returned with the `sessionId`). The token
  binds the request to this conversation; without it the route fails closed once enforcement is on.
- Every ~5th poll (~10 s), also call status to catch queue/agent/resolution changes:

```
GET /api/widget/conversations/{conversationId}/status
Headers: X-FrontFace-Session: {sessionToken}
→ 200 { "id", "status", "assignedAgent": { "id", "name" }?, "queuePosition"? }
```

When Realtime reconnects, stop polling (and vice-versa) — never run both.

### 6.6 Typing & presence (optional, only during `agent_active`)

```
POST /api/widget/conversations/{conversationId}/typing
Body: { "isTyping": true, "participantType": "customer" }
// debounce: send isTyping:true on keystroke, isTyping:false ~1200ms after the last keystroke

POST /api/widget/conversations/{conversationId}/presence
Body: { "status": "online" | "idle" | "offline", "visitorId": "mob_…" }
// send "online" on entering handoff, then a heartbeat every 30s; "offline" when backgrounding
```

Both are best-effort (ignore failures).

### 6.7 CSAT — customer satisfaction rating

After a handoff conversation ends (status transitions to `resolved` or `closed`), the server
may deliver a CSAT prompt as a system message with `metadata.csat_prompt: true` (via Realtime
`message:new` or polling). When you see this flag, show a satisfaction UI (1–5 stars/rating +
optional text feedback).

Submit the rating:

```
POST /api/widget/conversations/{conversationId}/csat
Headers: X-FrontFace-Session: {sessionToken}
Body: {
  "rating": 4,              // required, integer 1–5
  "feedback": "Very helpful" // optional, max 1000 chars
}
→ 200 { "success": true }
```

- The rating is recorded on the conversation, not on individual messages.
- A re-submit overwrites the previous rating. Absent `feedback` on a re-rate preserves
  previously submitted text.
- Ignore failures gracefully — CSAT is best-effort and must never block the user.

The status endpoint also returns `autoCloseAfterWarningMinutes` (nullable integer) — the
number of minutes after the inactivity warning before the server auto-closes the conversation.
Use it to show a countdown or adjust your poll cadence during the warning phase.

### 6.8 Offline messages

When `showOfflineForm` is `true` (from handoff availability or the handoff POST response),
show a simple offline contact form and submit it:

```
POST /api/projects/{projectId}/offline-messages
Headers: X-FrontFace-Key: pk_…, X-Visitor-Id: <visitorId>
Body: {
  "name": "Jane Doe",       // required, max 100 chars
  "email": "jane@co.com",   // required, valid email
  "message": "I need help…", // required, max 5000 chars
  "visitorId": "mob_…"      // optional, max 100 chars
}
→ 201 { "success": true, "conversationId": "uuid" }
```

The server creates a closed conversation with the message so agents can follow up from
the inbox. No further client action is needed.

---

## 7. Lead capture

Some projects collect a lead (email + optional fields), optionally followed by a qualifying
question. The shape is driven by the `leadCapture` block from bootstrap (§4).

**`capture_mode`:**

- `email_after` — show the form after the first AI exchange.
- `email_first` / `email_required` — show the form before chatting.

**Skip if already done** (cache locally; the backend also tracks it):

```
GET /api/chat/lead-capture/status?projectId={projectId}&visitorId={visitorId}
→ 200 { "hasCompletedForm": true }
```

**Submit the form:**

```
POST /api/chat/lead-capture/submit-form
Body: {
  "projectId", "visitorId",
  "sessionId": "uuid-or-null",
  "source": "mobile",
  "formData": {
    "email": "user@example.com",
    "field_2": { "label": "Company", "value": "Acme" },   // include only enabled fields
    "field_3": { "label": "…", "value": "…" }
  },
  "firstMessage": "the visitor's first message, or \"\""
}
→ 200 {
  "success": true,
  "leadId": "uuid",
  "nextAction": "qualifying_question" | "none",
  "qualifyingQuestion": "What are you trying to build?",   // when nextAction == qualifying_question
  "assembledGreeting": "Hi there!\n…\nWhat are you trying to build?",  // render this as the next assistant bubble
  "sessionId": "uuid-or-null",  // a fresh conversation id may be returned (email_first) — persist it
  "sessionToken": "…"           // persist with sessionId; send on continued messages and reads
}
```

- Validate email client-side; a bad email returns `400 INVALID_EMAIL`.
- If `nextAction == "qualifying_question"`, show `assembledGreeting` as the assistant's next
  message and let the visitor answer in chat as normal.
- If the response returns a `sessionId`, persist it (it may be newly created). If it also returns a
  `sessionToken`, persist that with the `sessionId`.

**Quick inline email** (lighter variant, optional):

```
POST /api/chat/lead-capture/submit-inline
Body: { "projectId", "visitorId", "sessionId": "uuid-or-null", "email": "…", "captureSource": "inline_email" }
```

---

## 8. Customer identify — identity verification (optional)

> ✅ **Available.** The old provisional `{ email, name }` shape is gone. Identity is
> now proven with a **signed identity token** (HS256 JWT) minted by the **tenant's own
> backend** using the project's verification secret (dashboard → project → Settings →
> Widget → Identity verification). Unverified identity claims are impossible: the API
> rejects anything not signed with the project secret.

When the app user is logged in, link their verified identity (and contact profile) to
the visitor so agents see a verified contact in the FrontFace inbox:

```
POST /api/customers/identify
Headers: X-FrontFace-Key: pk_…, X-Visitor-Id: <visitorId>
Body: {
  "visitorId": "mob_…",   // required, ≤100 chars — same id used for chat
  "projectId": "uuid",    // required
  "token": "<JWT>"        // required, ≤4096 chars — signed by the TENANT's backend
}
→ 200 {
  "contact":         { "customerId", "visitorId", "email", "name", "phone" },   // mutable
  "verifiedIdentity": { "externalId", "verifiedAt", "email", "name", "phone",   // service-managed
                        "customAttributes" } | null,
  "warnings"?: ["EMAIL_CONFLICT"]
}
```

> **Provenance:** `contact.*` is the current, mutable, agent-editable contact.
> `verifiedIdentity.*` is the immutable snapshot the signed token asserted — it is
> what the inbox shows with a "verified" badge. Verified fields are **read-only /
> service-managed**: nothing but a fresh signed token can change them.

**JWT contract** — HS256, signed with the project verification secret. Payload:

| Claim                | Required | Notes                                                                                                                                                                              |
| -------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `user_id` (or `sub`) | ✅       | The tenant's stable user id (≤255 chars). If both are present they must be equal                                                                                                   |
| `exp`                | ✅       | Unix seconds. Required; expired → `TOKEN_EXPIRED`                                                                                                                                  |
| `iat`                | ✅       | Unix seconds issued-at. Must not be in the future; `exp` must be after `iat`; total lifetime (`exp − iat`) **≤ 15 minutes**                                                        |
| `jti`                | ✅       | Unique per token (e.g. `crypto.randomUUID()`). **Single-use**: a replay with a different visitor is rejected; an identical retry from the same visitor returns the original result |
| `name`               | ✅       | ≤200 chars, non-empty. Required so the inbox always shows a name beside the verified badge                                                                                         |
| `nbf`                | —        | Unix seconds not-before, honored with ~60s leeway                                                                                                                                  |
| `visitor_id`         | —        | If present, must equal the request `visitorId` (extra binding)                                                                                                                     |
| `email`              | —        | ≤255 chars, valid email, or `null` to delete                                                                                                                                       |
| `phonenumber`        | —        | ≤50 chars, or `null` to delete                                                                                                                                                     |
| `custom_attributes`  | —        | object (≤50 keys, ≤8 KB), shallow-merged per key; `null` value deletes a key; `null` wipes all                                                                                     |

**Contact-sync semantics:** claim **present** → upsert; claim **omitted** → stored
value preserved; claim explicitly **`null`** → deleted.

**Mint a SHORT-LIVED, single-use token per login/session.** Because tokens are
single-use and ≤15 min lifetime, generate a fresh one (new `jti`) each time the app
needs to identify — do not cache and reuse.

**Server-side signing (tenant backend — the secret must NEVER ship in the app):**

```js
// Node, no external deps
const crypto = require("crypto");
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");

function mintIdentityToken(user, secret) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64({ alg: "HS256", typ: "JWT" });
  const payload = b64({
    user_id: user.id,
    email: user.email,
    name: user.name,
    custom_attributes: { plan: user.plan },
    iat: now,
    exp: now + 600, // ≤ 15 minutes
    jti: crypto.randomUUID(), // unique, single-use
  });
  const sig = crypto
    .createHmac("sha256", secret)
    .update(`${header}.${payload}`)
    .digest("base64url");
  return `${header}.${payload}.${sig}`;
}
```

**Dart (SDK side — fetch the token from the tenant backend, then call identify):**

```dart
Future<void> identify(String token) async {
  final res = await http.post(
    Uri.parse('$baseUrl/api/customers/identify'),
    headers: {
      'Content-Type': 'application/json',
      'X-FrontFace-Key': clientKey,
      'X-Visitor-Id': visitorId,
    },
    body: jsonEncode({
      'projectId': projectId,
      'visitorId': visitorId,
      'token': token, // minted by the tenant's backend after THEIR login
    }),
  );
  if (res.statusCode != 200) {
    final code = (jsonDecode(res.body)['error']?['code']) ?? 'IDENTIFY_ERROR';
    // TOKEN_INVALID / TOKEN_EXPIRED / TOKEN_REPLAYED → mint a FRESH token (new jti)
    //   from the host backend and retry. Never reuse a token.
    // IDENTITY_NOT_CONFIGURED → tenant has not generated a secret; treat as disabled.
    // Never block or crash chat on identify failures.
    throw FrontFaceIdentifyException(code);
  }
}

/// On logout ("resetUser"): rotate the stored visitor id to a fresh one and drop
/// the stored session — the device becomes a brand-new anonymous visitor.
Future<void> resetUser() async {
  await storage.delete(key: 'frontface_visitor_id');
  await storage.delete(key: 'frontface_session');
}
```

**Ordering:** identify may be called before or after the first chat message — both
converge, because identity lives on the customer record keyed by `visitorId`.
Re-identify on each app launch/login with a **fresh** token (tokens are short-lived
and single-use).

Errors: `400 VALIDATION_ERROR` / `400 TOKEN_CLAIMS_INVALID`, `401 TOKEN_INVALID`,
`401 TOKEN_EXPIRED`, `401 TOKEN_REPLAYED` (jti already used, or reused by a different
visitor), `404 PROJECT_NOT_FOUND`, `409 IDENTITY_NOT_CONFIGURED`,
`429 RATE_LIMITED` (10/min per project+IP).

---

## 9. Errors & rate limiting

**Error envelope** (all endpoints): `{ "error": { "code": "STRING", "message": "…", "details"?: {} } }`.

**Rate limiting:** on throttle you get **HTTP 429** with a `Retry-After: <seconds>` header and:

```json
{
  "error": {
    "code": "RATE_LIMITED",
    "message": "Too many messages…",
    "retryAfter": 30
  }
}
```

Successful responses also include `X-RateLimit-Remaining` and `X-RateLimit-Reset` (unix seconds).
**Always honor `Retry-After`** — back off and surface a gentle "you're sending messages too
quickly" state rather than hammering.

**A 403 on `/api/chat/message`** usually means the `X-FrontFace-Key` is missing, malformed,
revoked, or doesn't match the `projectId` in the body. If you are sending a stored `sessionId`,
also verify you are sending the matching `X-FrontFace-Session` token.

---

## 10. Client-side security guidelines

The SDK must treat **all server-provided strings as untrusted display data**:

- **Escape / never execute** server text. Project name, agent name, greetings, and message content
  originate from end users and tenants.
- **Markdown:** if you render assistant Markdown, use a renderer with a **URL scheme allow-list**
  (`https`, `http`, `mailto` only). Never allow `javascript:` (or other) schemes in links.
- **Never log the `X-FrontFace-Key`** to analytics/crash reporting.
- **Never log a ticket `accessUrl`**; it carries a short-lived one-time access grant.
- **Don't query Supabase tables directly.** The Realtime token is scoped to a single conversation
  channel and uses `role: anon` — it cannot access any table via the Data API.
- Treat the conversation id as a capability: it's an unguessable UUID that grants access to that
  thread. Don't expose it in shareable links/logs.

---

## 11. Recommended Flutter packages

| Need                    | Package                                                                          |
| ----------------------- | -------------------------------------------------------------------------------- |
| HTTP                    | `dio` or `http`                                                                  |
| Realtime (handoff)      | `supabase_flutter` (use its `RealtimeClient`/`channel` API) or `realtime_client` |
| Stable id / persistence | `uuid` + `flutter_secure_storage` (or `shared_preferences`)                      |
| Device/context metadata | `device_info_plus`, `package_info_plus` (for the optional `context` block)       |
| Markdown (allow-listed) | `flutter_markdown` with a custom/safe link handler                               |

A typed client + models can be generated from `openapi.yaml` (see README).

---

## 12. Realtime connection sketch (Dart)

```dart
// 1. Fetch a short-lived Realtime JWT from the API
final tokenRes = await dio.post(
  '$apiUrl/api/widget/conversations/$conversationId/realtime-token',
  options: Options(headers: {'X-FrontFace-Session': sessionToken}),
);
final realtimeToken = tokenRes.data['token'] as String;
final expiresAt = tokenRes.data['expiresAt'] as int;

// 2. Connect with the JWT (supabaseUrl from bootstrap config §4)
final client = RealtimeClient(
  '$supabaseUrl/realtime/v1',
  params: {'apikey': realtimeToken},
);
client.setAuth(realtimeToken);
client.connect();

// 3. Subscribe to a private channel
final channel = client.channel(
  'conversation:$conversationId',
  RealtimeChannelConfig(self: false, private: true),
);

channel.onBroadcast(event: 'message:new', callback: (payload) {
  final msg = payload['payload']?['data']?['message'];
  if (msg != null && msg['senderType'] != 'customer') appendMessage(msg);
});
channel.onBroadcast(event: 'conversation:status_changed', callback: (p) {
  applyStatus(p['payload']?['data']);
});
channel.onBroadcast(event: 'conversation:assigned', callback: (p) {
  setAgent(p['payload']?['data']?['agent']?['name']);
});
// …queue:position_updated, conversation:resolved, typing:start, typing:stop

channel.subscribe((status, [err]) {
  if (status == 'SUBSCRIBED') stopPolling();
  if (status == 'CLOSED' || status == 'CHANNEL_ERROR') startPollingWithBackoff();
});

// 4. Refresh token before expiry
Timer(Duration(seconds: expiresAt - 60 - DateTime.now().millisecondsSinceEpoch ~/ 1000), () async {
  final refreshRes = await dio.post(/* same endpoint */);
  client.setAuth(refreshRes.data['token']);
});
```

---

## 13. Quick reference — endpoints (v1 scope)

| Method | Path                                                         | Purpose                                                      |
| ------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| GET    | `/api/embed/config/{projectId}`                              | Bootstrap: branding, channels, lead-capture, realtime config |
| POST   | `/api/chat/message`                                          | Send a message, get the AI reply                             |
| POST   | `/api/chat/ensure-conversation`                              | Create a conversation before the first message (for handoff) |
| GET    | `/api/projects/{projectId}/handoff-availability`             | Can the visitor reach a human now?                           |
| POST   | `/api/conversations/{conversationId}/handoff`                | Request a human                                              |
| POST   | `/api/ticket-intents/{intentId}/contact`                     | Supply contact details and convert a pending ticket intent   |
| POST   | `/api/widget/conversations/{conversationId}/realtime-token`  | Issue short-lived JWT for private Realtime                   |
| GET    | `/api/widget/conversations/{conversationId}/status`          | Conversation status / queue / agent / autoCloseAfterWarningMinutes |
| GET    | `/api/widget/conversations/{conversationId}/messages/public` | Poll messages (`?after=ISO`) / rehydrate (includes metadata) |
| POST   | `/api/widget/conversations/{conversationId}/typing`          | Customer typing indicator                                    |
| POST   | `/api/widget/conversations/{conversationId}/presence`        | Customer presence heartbeat                                  |
| POST   | `/api/widget/conversations/{conversationId}/csat`            | Submit CSAT rating (1–5) + optional feedback (§6.7)          |
| POST   | `/api/projects/{projectId}/offline-messages`                 | Submit offline contact form (§6.8)                           |
| GET    | `/api/chat/lead-capture/status`                              | Has this visitor completed the lead form?                    |
| POST   | `/api/chat/lead-capture/submit-form`                         | Submit the lead form                                         |
| POST   | `/api/chat/lead-capture/submit-inline`                       | Inline email-only capture                                    |
| POST   | `/api/customers/identify`                                    | Verify a signed identity token and sync the contact (§8)     |

All require `X-FrontFace-Key` + `X-Visitor-Id`. Realtime uses private channel `conversation:<conversationId>` with a token from `/realtime-token`.

---

## 14. Open questions / out of scope for v1

Flagged for a later phase — **not** part of this contract:

- **Voice** (ElevenLabs) — disabled in v1.
- **Push notifications** for agent replies while the app is backgrounded (no server push contract
  yet; Realtime/polling only work in-foreground).
- **Attachments / images** in messages.
- **Offline message queue** and retry semantics beyond simple `Retry-After` (the offline
  *contact form* is documented in §6.8, but client-side message queueing for flaky networks
  is not covered).
- **Cross-device conversation history** (the recent-conversations list is currently web/public-page
  specific).
- **In-app WhatsApp / Instagram / Facebook threads** — the `channels` array (§4.1) is a
  launcher/deep-link contract only. There is no in-app transport for these channels; do not
  attempt to implement one.

Raise these with the FrontFace team before building around them.
