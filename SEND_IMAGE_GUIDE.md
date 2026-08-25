# Sending an Image

A customer can send an image (a photo of a delivered meal, a screenshot, etc.). Images are
uploaded **directly to storage** via a short-lived signed URL — the bytes never pass through
the chat request — and then referenced from the message. Three steps.

## Allowed images

- Types: `image/jpeg`, `image/png`, `image/webp`, `image/gif`.
- Max size: **10 MB**.

## Step 1 — Reserve an upload

`POST /api/media/uploads` (send your `X-Visitor-Id` header):

```json
{
  "projectId": "…",
  "conversationId": "…",
  "mime": "image/jpeg",
  "byteSize": 812345,
  "filename": "meal.jpg"
}
```

Response:

```json
{
  "assetId": "…",
  "uploadUrl": "https://…storage…/upload/sign/…?token=…",
  "token": "…",
  "path": "…"
}
```

## Step 2 — Upload the bytes

`PUT` the raw file bytes to `uploadUrl` with the correct `Content-Type`:

```
PUT <uploadUrl>
Content-Type: image/jpeg
<binary file body>
```

(No auth header needed — the URL is already signed. A 200 means the upload succeeded.)

## Step 3 — Send the message

`POST /api/chat/message` referencing the `assetId` in `parts`:

```json
{
  "projectId": "…",
  "visitorId": "…",
  "message": "This is how it arrived",
  "parts": [{ "mediaAssetId": "<assetId from step 1>" }]
}
```

- `message` is **optional** when `parts` is present (an image-only message is valid). You can
  also send text and one or more images together (up to 10).
- The server validates that the asset is yours, was uploaded, and hasn't already been used.

## What the backend does

1. Stores the image as a first-class part of the message.
2. Shows it to the agent as a thumbnail that opens a zoomable viewer.
3. Feeds the image to the AI: the current turn sees the **actual image**, and a short caption
   is generated so later turns and search still understand it.

## Reading images back

On transcript reload (`GET /messages/public`), an image message comes back with a `parts`
entry (`type: "image"`, see `MessagePart` in `openapi.yaml`). Its `url` is a **short-lived**
signed URL — display it, but **re-fetch the message list to refresh it** rather than caching
it; it will expire. Show `derivedText` (the caption) as the accessible alt text.
