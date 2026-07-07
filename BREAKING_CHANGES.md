# Mobile SDK — Breaking Changes from Security Hardening (2026-06-29)

> **Audience:** the Flutter developer (and Cursor) fixing the mobile app.
> **Context:** commit `bc8e531` ("Security hardening: widget session tokens, rate limiting,
> private realtime channels, and RLS policies") changed the API contract the mobile app was built
> against. This broke two things in the current app. This doc is a diff — for full endpoint
> details, see [`INTEGRATION_GUIDE.md`](./INTEGRATION_GUIDE.md) (already updated to the new
> contract).

**Priority order:**
1. Session token — **required**, do this first, fixes the core chat/handoff flow.
2. Realtime — **required**, depends on the session token.
3. `/api/customers/identify` — **not a fix, a removal**. Nothing you change client-side revives it.

---

## 1. Session token (`X-FrontFace-Session`) — required

### What broke

`POST /api/chat/message` used to accept a bare `sessionId` to continue a conversation. It now also
requires the token that was returned alongside that `sessionId`. Same for the widget
conversation-read routes. If the app isn't sending it, continued messages / status polls / message
history calls fail with `403` once a stored session is reused (first-ever message, with no
`sessionId`, is unaffected).

### The change

Every response that hands back a `sessionId` **now also returns a `sessionToken`**. Persist both
together (same local storage entry). Send the token as a header on every subsequent call for that
conversation:

```
X-FrontFace-Session: <sessionToken>
```

| Endpoint | Before | After |
|---|---|---|
| `POST /api/chat/message` (no `sessionId`, first message) | returns `{ response, sessionId, ... }` | returns `{ response, sessionId, sessionToken, ... }` — persist both |
| `POST /api/chat/message` (with stored `sessionId`, continuing) | body only | body **+** header `X-FrontFace-Session: <sessionToken>` |
| `POST /api/chat/ensure-conversation` | returns `{ conversationId }` | returns `{ conversationId, sessionToken }` — persist both |
| `POST /api/chat/lead-capture/submit-form` | returns `{ ..., sessionId }` | returns `{ ..., sessionId, sessionToken }` when a session id is present |
| `GET /api/widget/conversations/{id}/status` | no header | **requires** header `X-FrontFace-Session: <sessionToken>` |
| `GET /api/widget/conversations/{id}/messages/public` | no header | **requires** header `X-FrontFace-Session: <sessionToken>` |
| `POST /api/widget/conversations/{id}/realtime-token` | (new endpoint, see §2) | **requires** header `X-FrontFace-Session: <sessionToken>` |
| `POST /api/conversations/{id}/handoff` | no header | **requires** header `X-FrontFace-Session: <sessionToken>` |

A response may also return a **refreshed** `sessionToken` — always overwrite your stored token with
the latest one you got back, don't keep reusing the original.

### What to change in the app

- Wherever `sessionId` is persisted (secure storage / shared prefs), add a sibling field for
  `sessionToken` and always write/read them together.
- Add `X-FrontFace-Session: <sessionToken>` to the header set for every conversation-scoped call
  listed above.
- On "New chat" (dropping the stored `sessionId`), also drop the stored `sessionToken`.

### Error shape if this is missed

`403` with `{ "error": { "code": "SESSION_INVALID" | "SESSION_CONVERSATION_MISMATCH" | ... } }`.
If you see this on a call that used to work, it's a missing/stale `X-FrontFace-Session` header —
not a key or project problem.

Full lifecycle detail: `INTEGRATION_GUIDE.md` §3 and §9.

---

## 2. Realtime (live handoff) — required, and depends on §1

### What broke

The app used to connect to Supabase Realtime directly with a static anon key from the bootstrap
config and subscribe to a **public** broadcast channel. Realtime channels are now **private** and
RLS-gated — the old anon key can no longer read `conversation:<id>` broadcasts at all. Any build
still doing this will show "connected" but **silently receive nothing** (or fail to subscribe),
not an obvious error.

### The change

`GET /api/embed/config/{projectId}` response, `realtime` block:

```diff
  "realtime": {
+   "enabled": true,
    "supabaseUrl": "https://<ref>.supabase.co",
-   "supabaseAnonKey": "eyJ...",
+   "tokenBased": true,
+   "apiKey": "sb_publishable_..."
  }
```

**`apiKey` in this response is the Supabase project's publishable key — it is not, by itself, a
credential that can subscribe to a conversation channel.** Don't wire it into `setAuth()` and
expect broadcasts to arrive. It's informational (constructing the Realtime client endpoint), not
the channel credential.

The actual per-conversation channel credential is a **short-lived JWT** fetched from a new
endpoint, using the session token from §1:

```
POST /api/widget/conversations/{conversationId}/realtime-token
Headers: X-FrontFace-Session: {sessionToken}
→ 200 { "token": "eyJ...", "expiresAt": 1751234567 }
```

This endpoint **always enforces** the session token (no monitor/soft-fail mode) — a missing or
conversation-mismatched token gets a hard `403` regardless of environment.

### What to change in the app

1. Before subscribing, `POST` the `/realtime-token` endpoint with `X-FrontFace-Session` to get a
   JWT.
2. Connect with that JWT — `params: {'apikey': token}` and `client.setAuth(token)` — not the
   `apiKey` from bootstrap config.
3. Channel config must add `private: true` (in addition to the existing `self: false`).
4. Schedule a refresh at `expiresAt - 60` seconds: call `/realtime-token` again, `setAuth(newToken)`.
   If refresh fails, fall back to polling.

Dart sketch (already updated): `INTEGRATION_GUIDE.md` §6.4 and §12.

---

## 3. `POST /api/customers/identify` — disabled server-side, not fixable client-side

### What broke

This is the error in the screenshot:

```
Cannot POST /api/customers/identify
```

That's Express's default 404 page (plain HTML, not the app's JSON error envelope) — the route
handler has been **commented out entirely** on the server. It isn't gated by a header or a flag;
no client-side change makes it work again.

### Why

It was a public, unauthenticated write (create/merge customer records) reachable by anyone who
knew a `projectId` — which ships inside the public widget snippet, so it's trivially discoverable.
With no real caller yet at the time of the audit, it was disabled rather than left open. It's
tracked to come back gated behind `X-FrontFace-Key` (+ likely a signed identity token), but is not
back yet.

### What to change in the app

- **Stop calling it.** Remove/guard the identify call so it doesn't block chat init or throw on
  the plain-HTML 404 body (if any error-handling code tries to `response.data['error']['code']` on
  this response, it will crash — the body isn't JSON).
- This feature is optional for v1 — everything else (chat, handoff, lead capture) works without
  it. Treat "identify" as parked, not broken.

---

## Quick checklist for Cursor

- [ ] Persist `sessionToken` alongside `sessionId` everywhere the latter is stored.
- [ ] Add `X-FrontFace-Session: <sessionToken>` header to: continued `chat/message`, `ensure-conversation` follow-ups, `handoff`, `status`, `messages/public`, `realtime-token`.
- [ ] Always overwrite stored `sessionToken` with the latest value from any response that returns one.
- [ ] Replace the realtime connection: call `/realtime-token` first, use its `token` (not bootstrap `apiKey`) for `setAuth()`, add `private: true` to channel config, add refresh-before-expiry.
- [ ] Remove/guard the `POST /api/customers/identify` call — treat any response to it as non-JSON and don't block on it.
- [ ] Re-run the smoke test in `README.md` plus a two-message conversation (to exercise the session-token continuation path) and a handoff (to exercise realtime-token).

## Verifying the fix

```bash
# 1. First message — capture sessionId + sessionToken from the response
curl -sS https://api.frontface.app/api/chat/message \
  -H 'Content-Type: application/json' \
  -H "X-FrontFace-Key: $PK_KEY" -H "X-Visitor-Id: mob_test" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"message\":\"hello\",\"visitorId\":\"mob_test\",\"source\":\"mobile\"}"

# 2. Continue the conversation — must include X-FrontFace-Session or expect 403
curl -sS https://api.frontface.app/api/chat/message \
  -H 'Content-Type: application/json' \
  -H "X-FrontFace-Key: $PK_KEY" -H "X-Visitor-Id: mob_test" \
  -H "X-FrontFace-Session: $SESSION_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"message\":\"second message\",\"visitorId\":\"mob_test\",\"source\":\"mobile\",\"sessionId\":\"$SESSION_ID\"}"
```

A `200` on step 2 confirms the session-token wiring is correct.
