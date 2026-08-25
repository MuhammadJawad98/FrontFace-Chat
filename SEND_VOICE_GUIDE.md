# Sending a Voice Note

A customer can send a voice note. The flow is identical to sending an image (upload directly
to storage via a signed URL, then reference the asset from the message) — the only
differences are the audio mime types and that the AI understands the note via a
**transcript**, not the audio itself.

## Allowed audio

- Types: `audio/webm`, `audio/mp4`, `audio/mpeg`, `audio/ogg`, `audio/wav`.
- Max size: **25 MB**.
- Record in the device's natural format (e.g. `audio/mp4`/AAC on iOS, `audio/webm`/Opus on
  Android/web). No transcoding needed.

## Three steps

1. **Reserve** — `POST /api/media/uploads` with `{ projectId, conversationId, mime, byteSize?, filename? }` → `{ assetId, uploadUrl, token, path }`.
2. **Upload** — `PUT` the raw audio bytes to `uploadUrl` with the matching `Content-Type`.
3. **Send** — `POST /api/chat/message` with `parts: [{ mediaAssetId }]` (a voice-only
   message is valid — `message` may be empty).

## How the AI understands it

The backend transcribes the note (tuned for **Arabic, English, and
Arabic↔English code-switching**). The transcript becomes the message's AI-visible text, so
the assistant can answer the customer's spoken request. This transcription **gates** the AI:
the reply is produced only after the transcript is ready.

## Reading it back

On transcript reload, a voice message comes back with a `parts` entry (`type: "audio"`, see
`MessagePart` in `openapi.yaml`):

- `url` — a **short-lived** signed URL to play the audio (re-fetch to refresh; it expires).
- `processingStatus` — `"pending"` (transcribing), `"ready"`, or `"failed"`.
- `derivedText` — the transcript (once `"ready"`); show it under the player.
- `payload.duration_ms`, `payload.languages` — length and detected languages (e.g. `["ar","en"]`).

The audio is playable as soon as `url` is present, even while `processingStatus` is `"pending"`.
