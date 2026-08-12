# FrontFace Mobile SDK — Support Package

This folder is the contract for building a **Flutter chat support SDK** on top of the FrontFace
public API. It is self-contained and safe to share with the mobile developer.

## Contents

| File                                             | What it is                                                                                                                                           |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`INTEGRATION_GUIDE.md`](./INTEGRATION_GUIDE.md) | The technical guide — architecture, auth, session lifecycle, ticket actions, realtime handoff, lead capture, and security do/don'ts. **Start here.** |
| [`openapi.yaml`](./openapi.yaml)                 | OpenAPI 3 spec of the in-scope endpoints. Use it to generate a typed Dart client + models.                                                           |

## Base URL

```
https://api.frontface.app
```

## What you'll be given to start

1. A **test `projectId`** (the FrontFace agent to embed).
2. A **publishable client key** (`pk_…`) scoped to that project.

Both come from the FrontFace dashboard (project → **Mobile SDK** section). The key is publishable
(safe in the app binary) and revocable. Send it as `X-FrontFace-Key` on every request.

## v1 scope

- ✅ AI chat (`POST /api/chat/message`, `source: "mobile"`)
- ✅ Support tickets (structured creation/contact actions + secure browser tracking)
- ✅ Live human handoff (Realtime channel `conversation:<id>` + 2s polling fallback)
- ✅ Lead capture (forms + qualifying questions)
- ✅ Customer identify — identity verification via a signed JWT minted by the tenant's backend (guide §8); shows a verified contact in the FrontFace inbox
- ❌ Voice, push notifications, attachments — see "Open questions" in the guide.

## Generating a Dart client (optional)

```bash
# Lint the spec
npx @redocly/cli lint openapi.yaml

# Generate Dart models/client (one option)
npx @openapitools/openapi-generator-cli generate \
  -i openapi.yaml -g dart-dio -o ./generated
```

The Realtime/WebSocket part of handoff is **not** in the OpenAPI spec (it's a Supabase Realtime
broadcast channel) — implement it per §6 and §12 of the guide using `supabase_flutter`.

## A 30-second smoke test

```bash
curl -sS https://api.frontface.app/api/chat/message \
  -H 'Content-Type: application/json' \
  -H "X-FrontFace-Key: $PK_KEY" \
  -H "X-Visitor-Id: mob_smoketest" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"message\":\"hello\",\"visitorId\":\"mob_smoketest\",\"source\":\"mobile\"}"
```

A `200` with a `response` and a `sessionId` means your key + project are wired up correctly.

## Questions

Anything ambiguous in the contract, or a parity gap you hit while building — raise it with the
FrontFace team rather than guessing. The guide's §14 lists the known open items.
