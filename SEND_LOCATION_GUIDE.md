# Sending a Location

A customer can share a location as part of a message — for example, to change a
delivery destination for a specific day. Two properties define how FrontFace treats it:

- **Explicit** — send a location only in response to a deliberate user action (a
  "Share location" tap), never from silent background GPS.
- **Transactional** — the location is used for the *current* request, not saved as the
  customer's permanent address. It is never written to the customer profile.

## Request

Send a location on the existing `POST /api/chat/message` call by adding a `location`
object alongside the usual fields:

```json
{
  "projectId": "…",
  "visitorId": "…",
  "message": "Please deliver my Aug 26 order here",
  "location": {
    "latitude": 24.7136,
    "longitude": 46.6753,
    "accuracy_m": 12,
    "label": "Al Olaya, Riyadh",
    "captured_at": "2026-08-24T18:20:00Z"
  }
}
```

- `latitude` and `longitude` are **required** (`-90..90` and `-180..180`).
- `label` is optional. Supply it from the device's native reverse geocoding if you
  have it; the dashboard falls back to the raw coordinates when it is absent, so you do
  not need a geocoding service to ship this.
- `message` is **optional** when a `location` is present — a location-only message is
  valid. You may also send text *and* a location together.
- `accuracy_m` and `captured_at` are optional but recommended.

## What the backend does

1. **Stores** the location as a first-class part of the message (not embedded in text).
2. **Shows** it to the agent as a location card — label / coordinates / "Open in Maps".
3. **Feeds** it to the AI as text, and when a data connector needs coordinates, binds
   them **server-side**. The model can decide *which day/scope* to act on; it can never
   invent or alter the coordinates you sent.

## After a location is used

Once the AI or agent completes a location-changing action with the shared pin, that
location is **consumed**. A later, unrelated location change will not silently reuse the
old pin — the assistant asks the customer to share a fresh location. This prevents a pin
shared on Monday from being reused for an unrelated change on Wednesday.

## Reading it back

On transcript reload (`GET /messages/public`), a message that carried a location comes back
with a **`parts`** array (see `MessagePart` in `openapi.yaml`). Render it the same way as the
dashboard — the `label` (or `latitude, longitude`) with a map link — so the shared location
survives re-opening the app. A message may have `parts` and empty `content`.

## Permissions & UX (native side)

- Request the OS location permission only when the user taps "Share location".
- Show the user what will be shared before sending (a confirmation sheet is good UX).
- If you can reverse-geocode on-device (both iOS and Android expose this), include the
  resulting `label`; otherwise omit it.
