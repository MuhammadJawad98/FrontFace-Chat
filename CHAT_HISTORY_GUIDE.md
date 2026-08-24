# Chat History — Implementation & Fix Guide (Mobile SDK)

How to load and display a customer's chat history in the app, and how to fix the
most common cause of a **blank history screen**. Pairs with `INTEGRATION_GUIDE.md`
(§2.2 Visitor id, §3 Session lifecycle, §5.3 Fetch messages).

- **Base URL:** `https://api.frontface.app`
- **Every request:** `X-FrontFace-Key: pk_…` and `X-Visitor-Id: <visitorId>`
- **Chat/conversation requests:** `source: "mobile"`

---

## TL;DR — the fix

History is keyed to the **`visitorId`**. The server only returns conversations
created under the **same `visitorId`** you query with. If history is blank, 99%
of the time the app is **not sending the same `visitorId` across launches** —
it's generating a new one each time the app starts (or not persisting it).

**Fix:** generate the `visitorId` **once**, store it in persistent storage, and
send the **identical** value on every request forever (SDK `INTEGRATION_GUIDE.md`
§2.2). Then load history with `ensure-conversation` + `messages/public`.

This Flutter SDK already:

1. Persists a stable `mob_*` visitor id in `SharedPreferences` (never regenerates
   unless you call `resetUser()`).
2. On chat open, calls `POST /api/chat/ensure-conversation` when no local
   `sessionId` is stored, then loads `GET …/messages/public` (full transcript).
3. Supports an **account-keyed** visitor id for logged-in users (see below).

---

## Why history is blank (root cause)

`INTEGRATION_GUIDE.md` §2.2 says, verbatim:

> You generate a **stable, per-install** visitor id **once, persist it, and reuse
> it forever**… Generate it on first launch; **never regenerate it**.

If the id is regenerated per app launch / per session (or held only in memory),
then on every launch the backend sees a brand-new visitor with **zero prior
conversations**, so `messages/public` returns an empty list. It looks exactly
like "history won't load."

**Checklist — do this first:**

1. Print the `visitorId` on app start (`provider.visitorId`, or enable
   `debugLogging: true` on `FrontFaceChatConfig`). Kill the app, reopen it.
   **Is it the same string?** If not → that's the bug.
2. Confirm it's read from persistent storage, not generated fresh each launch.
3. Confirm the **same** value goes out as both the `X-Visitor-Id` header **and**
   the body `visitorId` on every call.

---

## The history API (what the SDK calls)

### 1. Resolve the conversation — `POST /api/chat/ensure-conversation`

Returns the visitor's current conversation id **without sending a message**.

```
→ 200 { "conversationId": "<uuid>", "sessionToken": "<token>" }
```

Persist `conversationId` (this is the `sessionId`) and `sessionToken`.

### 2. Load the messages — `GET …/messages/public`

Full transcript when no `?after=`; incremental with `?after=<ISO timestamp>`.
Requires `X-FrontFace-Session` (or matching `X-Visitor-Id` as fallback).

---

## Logged-in users (Freshhouse) — history across devices

The default per-install `mob_*` id ties history to the **device**. On reinstall
or a new phone, a new id is generated and past history is stranded.

For logged-in users, key the identity to the **account**:

1. Freshhouse backend issues **one stable, unguessable `visitorId` per user**
   (store against the account, or `HMAC_SHA256(secret, userId)` server-side —
   never the raw user id).
2. App sets it after login, then opens chat:

```dart
final provider = FrontFaceChat.createProvider(
  config: FrontFaceChatConfig(
    projectId: projectId,
    publishableKey: pk,
    visitorId: accountVisitorIdFromBackend, // optional — same as setVisitorId
  ),
);

// Or at runtime:
await FrontFaceChat.setVisitorId(
  provider: provider,
  visitorId: accountVisitorIdFromBackend,
);

await FrontFaceChat.identify(
  provider: provider,
  identityToken: frontfaceJwtFromBackend,
);

await FrontFaceChat.open(context, config: config);
```

3. On logout: `await FrontFaceChat.resetUser(provider);`

Also call `identify` with the tenant-signed JWT (see
`IDENTITY_VERIFICATION_GUIDE.md`) so agents see a verified contact.

---

## Important limitation

These endpoints show the **one active conversation** for the visitor. There is
**no mobile endpoint that lists multiple past conversations**.
