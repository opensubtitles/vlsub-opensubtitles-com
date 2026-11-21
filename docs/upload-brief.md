# Uploading subtitles from VLSub - first look (2026-11-21)

Source: the development OpenAPI document (`private/opensubtitles_openapi_dev.json`,
local only) and read-only calls against the live API. Nothing was uploaded.

## What is new in the API

| Call | Purpose |
|---|---|
| `POST /subtitles/upload/guess` | which title a file belongs to, from file name and/or movie hash (up to 5 candidates) |
| `POST /subtitles/upload/features/from_id` | title from an IMDb / TMDb id |
| `POST /subtitles/upload/features/stub` | register a title the site does not have |
| `POST /subtitles/upload/check` | dry run without the file: known already? which title? would it be refused or held for review? quota left |
| `POST /subtitles/upload` | the upload: JSON body, file as base64 of gzip / zlib / raw deflate, MD5 of the raw bytes, language, title, movie hash |
| `GET /my/uploads`, `PATCH` / `DELETE /my/uploads/{id}`, `.../replace`, `.../restore` | list, edit, withdraw, replace, restore one's own uploads |

Gone from the document compared with the earlier one: `/ai/download*`,
`/ai/files/...`, `/ai/userinfo`, `/ai/recent_*`, `/ai/payment_history`.

## Measured with VLSub's API key

- Plain HTTP works for these paths (User-Agent `VLSub OpenSubtitles.com v2.0.0`).
- `GET /my/uploads` with a login: **200**, the account's uploads.
- `upload/guess`, `upload/check`: **403 `uploads_not_enabled`** - "Uploads are
  not enabled for this API consumer". The key needs upload permission before
  anything can be tried.

## Can VLC's Lua do it?

The request is JSON, not multipart, which suits the extension's HTTP client.
It needs three things VLC's Lua does not have, all writable in plain Lua:

- **MD5** of the file (`subhash`);
- **base64**;
- **compression container**: raw deflate is accepted, and deflate has a
  "stored" block type that needs no compression at all - a 5-byte header per
  64 kB. So no compressor has to be written.

Limit: the whole body must stay under about 500 kB. Stored (uncompressed) and
base64-encoded, that allows a subtitle file of roughly 360 kB - enough for
ordinary films (50-150 kB), not for very long or bitmap-like files; those are
refused with a message.

The movie hash, file size and file name of the playing video are already
known to the extension, so an upload from VLC records the hash: the next
person with that file finds the subtitle by hash search.

## What it would be for

1. **Upload the subtitle that is loaded in VLC** - a file the user has on disk
   (made, fixed or found elsewhere) - for the film that is playing:
   guess -> check -> confirm in a small window (title, language, flags) ->
   upload. `check` says beforehand "already in the database" (then nothing is
   sent, and the existing one can be rated / linked to this file instead).
2. **Sharing a corrected subtitle**: downloaded here, timing fixed by the
   user, uploaded as a new one for this release.
3. **My uploads**: a list with status (pending, enabled, disabled).

Never automatic: an upload is a public act under the user's name.

## Open before building

- Upload permission for VLSub's API key.
- Which account uploads in tests (a throwaway, and a way to withdraw:
  `DELETE /my/uploads/{id}` exists).
- Reading the subtitle VLC has loaded: the extension knows the file it loaded
  itself; for one the user opened by hand VLC's Lua gives no path - the user
  would pick it by typing / pasting the path, or it is found next to the
  video by name.
