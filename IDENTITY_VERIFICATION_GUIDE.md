# FrontFace — Customer Identity Verification (Backend Integration Guide)

> **Audience:** Your backend / server-side team.
> **Purpose:** Generate signed identity tokens so your mobile app can link logged-in
> users to their FrontFace support profile — agents see verified contact details with
> a trust badge in the inbox.

---

## How it works

```
┌──────────────┐         ┌──────────────────┐         ┌──────────────────┐
│  Your mobile │  login   │  Your backend    │  signed  │  FrontFace API   │
│  app (SDK)   │ ───────▶ │  (server-side)   │  JWT     │  (api.frontface  │
│              │          │                  │ ───────▶ │   .app)          │
│              │ ◀─────── │ return JWT in    │          │                  │
│              │  token    │ login response   │          │ verifies sig,    │
│              │          │ or dedicated     │          │ links identity   │
│              │          │ endpoint         │          │ to visitor       │
└──────────────┘          └──────────────────┘          └──────────────────┘
```

1. Your user logs into your app (your normal auth flow).
2. Your **backend** mints a short-lived, signed JWT (the "identity token") using the
   FrontFace verification secret we will provide you.
3. Your mobile app receives the token and passes it to the FrontFace SDK.
4. The SDK calls `POST /api/customers/identify` — FrontFace verifies the signature,
   links the identity to the chat visitor, and shows verified contact info in the inbox.

**The secret never leaves your server.** The mobile app only receives and forwards the
signed token — it never sees or stores the secret itself.

---

## What you need from us

| Item                       | Example                                  | Where to find it                                       |
| -------------------------- | ---------------------------------------- | ------------------------------------------------------ |
| **Verification secret**    | `whsec_abc123...` (will be shared separately) | Dashboard → Project → Settings → Widget → Identity verification |
| **Project ID**             | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`   | Provided with the SDK integration package               |

---

## JWT specification

| Property    | Value                            |
| ----------- | -------------------------------- |
| Algorithm   | **HS256** (HMAC-SHA256)          |
| Secret      | The verification secret (above)  |
| Max size    | ≤ 4096 characters                |
| Max lifetime| ≤ **15 minutes** (`exp − iat`)   |
| Usage       | **Single-use** (each token needs a unique `jti`) |

### Payload claims

| Claim                | Required | Type   | Rules                                                                |
| -------------------- | -------- | ------ | -------------------------------------------------------------------- |
| `user_id`            | **Yes**  | string | Your stable user ID for this customer (≤255 chars). Alternatively use `sub` — if both are present, they must be equal. |
| `name`               | **Yes**  | string | Customer display name (≤200 chars, non-empty). The inbox shows this next to the verified badge. |
| `exp`                | **Yes**  | number | Expiration time (Unix seconds). Must be ≤ 15 min after `iat`.       |
| `iat`                | **Yes**  | number | Issued-at (Unix seconds). Must not be in the future.                 |
| `jti`                | **Yes**  | string | Unique token ID (e.g. UUID v4). Each token must have a unique `jti`. A replayed `jti` with a different visitor is rejected. An identical retry from the same visitor returns the original result. |
| `email`              | No       | string | Customer email (≤255 chars, valid format). Omit to preserve existing; set to `null` to delete. |
| `phonenumber`        | No       | string | Phone number (≤50 chars). Omit to preserve; `null` to delete.       |
| `visitor_id`         | No       | string | If set, must match the visitor ID the mobile app sends. Extra binding for defense-in-depth. |
| `nbf`                | No       | number | Not-before (Unix seconds). Honored with ~60 second leeway.          |
| `custom_attributes`  | No       | object | Key-value metadata (≤50 keys, ≤8 KB total). Values are shallow-merged per key. Set a key to `null` to delete it; set the entire field to `null` to wipe all attributes. |

### Contact-sync semantics

- Claim **present** with a value → upserts that field.
- Claim **omitted** entirely → the stored value is preserved (no change).
- Claim explicitly set to **`null`** → the stored value is deleted.

This means you can update just the email by sending only `user_id`, `name`, `email`,
and the required timing claims — everything else stays as-is.

---

## Implementation options

You have two choices for when and how to generate the token. Pick whichever fits your
architecture.

### Option A: Return the token in your login response

Add a `frontfaceToken` field to your existing login/session endpoint response. The mobile
app picks it up right after login — no extra network call.

```
POST /api/auth/login
→ 200 {
  "accessToken": "your-normal-auth-token",
  "user": { ... },
  "frontfaceToken": "<signed-jwt>"   // ← add this
}
```

### Option B: Dedicated endpoint

Create a small endpoint the mobile app calls after login. Useful if you want to
decouple the FrontFace integration from your auth flow.

```
GET /api/integrations/frontface/identity-token
Authorization: Bearer <your-auth-token>
→ 200 { "token": "<signed-jwt>" }
```

Either way, generate a **fresh token** (new `jti`, new `iat`/`exp`) on every call.
Tokens are single-use and short-lived — never cache or reuse them.

---

## Code examples

### Node.js (zero dependencies)

```js
const crypto = require("crypto");

const FRONTFACE_SECRET = process.env.FRONTFACE_VERIFICATION_SECRET;

function createFrontFaceToken(user) {
  const now = Math.floor(Date.now() / 1000);

  const header = toBase64Url({ alg: "HS256", typ: "JWT" });
  const payload = toBase64Url({
    user_id: user.id,              // required — your stable user ID
    name: user.displayName,        // required — shown in the inbox
    email: user.email,             // optional — syncs to FrontFace contact
    phonenumber: user.phone,       // optional
    custom_attributes: {           // optional — any metadata for your agents
      plan: user.plan,
      company: user.company,
    },
    iat: now,
    exp: now + 600,                // 10 minutes (must be ≤ 900)
    jti: crypto.randomUUID(),      // unique per token
  });

  const signature = crypto
    .createHmac("sha256", FRONTFACE_SECRET)
    .update(`${header}.${payload}`)
    .digest("base64url");

  return `${header}.${payload}.${signature}`;
}

function toBase64Url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString("base64url");
}
```

### Python

```python
import hmac, hashlib, json, time, uuid, base64, os

FRONTFACE_SECRET = os.environ["FRONTFACE_VERIFICATION_SECRET"]

def create_frontface_token(user: dict) -> str:
    now = int(time.time())

    header = _b64url({"alg": "HS256", "typ": "JWT"})
    payload = _b64url({
        "user_id": user["id"],
        "name": user["display_name"],
        "email": user.get("email"),
        "phonenumber": user.get("phone"),
        "custom_attributes": {
            "plan": user.get("plan"),
        },
        "iat": now,
        "exp": now + 600,
        "jti": str(uuid.uuid4()),
    })

    sig = hmac.new(
        FRONTFACE_SECRET.encode(),
        f"{header}.{payload}".encode(),
        hashlib.sha256,
    ).digest()
    signature = base64.urlsafe_b64encode(sig).rstrip(b"=").decode()

    return f"{header}.{payload}.{signature}"

def _b64url(obj: dict) -> str:
    return base64.urlsafe_b64encode(
        json.dumps(obj, separators=(",", ":")).encode()
    ).rstrip(b"=").decode()
```

### PHP

```php
function createFrontFaceToken(array $user): string {
    $secret = getenv('FRONTFACE_VERIFICATION_SECRET');
    $now = time();

    $header = base64url_encode(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
    $payload = base64url_encode(json_encode([
        'user_id' => $user['id'],
        'name'    => $user['display_name'],
        'email'   => $user['email'] ?? null,
        'iat'     => $now,
        'exp'     => $now + 600,
        'jti'     => bin2hex(random_bytes(16)),
    ]));

    $signature = base64url_encode(
        hash_hmac('sha256', "$header.$payload", $secret, true)
    );

    return "$header.$payload.$signature";
}

function base64url_encode(string $data): string {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}
```

### Ruby

```ruby
require "openssl"
require "json"
require "base64"
require "securerandom"

FRONTFACE_SECRET = ENV.fetch("FRONTFACE_VERIFICATION_SECRET")

def create_frontface_token(user)
  now = Time.now.to_i

  header  = base64url({ alg: "HS256", typ: "JWT" })
  payload = base64url({
    user_id: user[:id],
    name:    user[:display_name],
    email:   user[:email],
    iat:     now,
    exp:     now + 600,
    jti:     SecureRandom.uuid,
  })

  sig = OpenSSL::HMAC.digest("SHA256", FRONTFACE_SECRET, "#{header}.#{payload}")
  signature = Base64.urlsafe_encode64(sig, padding: false)

  "#{header}.#{payload}.#{signature}"
end

def base64url(obj)
  Base64.urlsafe_encode64(obj.to_json, padding: false)
end
```

---

## What the mobile app does with the token

The mobile developer receives the token and calls the FrontFace SDK's identify method.
You do **not** need to implement this part — it's handled by the SDK. For reference:

```
POST https://api.frontface.app/api/customers/identify
Headers:
  X-FrontFace-Key: pk_…
  X-Visitor-Id: <device-visitor-id>
  Content-Type: application/json

Body: {
  "projectId": "<project-id>",
  "visitorId": "<device-visitor-id>",
  "token": "<the-jwt-you-generated>"
}
```

---

## Security rules

1. **The verification secret is a server-side secret.** Never embed it in the mobile app,
   expose it in client-side code, commit it to a public repository, or send it over an
   insecure channel.

2. **Generate a fresh token per login/session.** Each token must have a unique `jti`,
   a fresh `iat`, and `exp` within 15 minutes. Never cache or reuse tokens.

3. **Keep lifetimes short.** 5–10 minutes is ideal. The maximum is 15 minutes.
   Shorter lifetimes reduce the window if a token is intercepted.

4. **Tokens are single-use.** A `jti` that has already been consumed by a different
   visitor is rejected (`TOKEN_REPLAYED`). An identical retry from the same visitor
   returns the original result (safe for retries on network failure).

5. **Only sign tokens for authenticated users.** The token asserts "this user is who
   they say they are" — only generate it after your own authentication succeeds.

---

## Error codes the mobile app may see

These come from FrontFace when the token is invalid. If your mobile developer reports
one of these, check the corresponding issue in your token generation:

| Error code              | Meaning                                                        | Fix                                            |
| ----------------------- | -------------------------------------------------------------- | ---------------------------------------------- |
| `TOKEN_INVALID`         | Bad signature, wrong algorithm, malformed JWT                  | Verify you're using HS256 and the correct secret |
| `TOKEN_EXPIRED`         | `exp` is in the past                                           | Ensure `exp` is set at generation time, not cached |
| `TOKEN_CLAIMS_INVALID`  | Missing required claim, `name` empty, `exp − iat` > 15 min    | Check all required claims are present and valid |
| `TOKEN_REPLAYED`        | Same `jti` used by a different visitor                         | Ensure `jti` is unique per call (use UUID v4)  |
| `IDENTITY_NOT_CONFIGURED` | No verification secret set on this project                  | Contact us to confirm the secret is configured |

---

## Testing

To test during development:

1. Generate a token using one of the examples above with your test secret.
2. Verify the structure at [jwt.io](https://jwt.io) (paste the token, select HS256,
   enter the secret — the signature should show as verified).
3. Have the mobile developer call identify with the token — a successful `200` response
   with a `verifiedIdentity` object confirms everything is wired correctly.

---

## Quick checklist

- [ ] Received the verification secret from us (stored in environment variable,
      **not** in source code)
- [ ] Token generation implemented (HS256, all required claims)
- [ ] Token returned to mobile app (via login response or dedicated endpoint)
- [ ] Tested with a real identify call — `200` with `verifiedIdentity` in response
- [ ] Secret is not exposed in client code, logs, or public repositories
