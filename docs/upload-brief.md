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

## Talking to the development API from real VLC (2026-11-22)

The development API (`https://rb-dev.ngrok.dev/api/v1`) is https only;
VLSub sends headers only over plain HTTP. `tools/devproxy.py` (Python
standard library) listens on 127.0.0.1 and forwards to it; VLSub is pointed
at the proxy with two developer switches, read when used and absent in
normal use:

- `VLSUB_API_URL` - API base (default `http://api.opensubtitles.com/api/v1`)
- `VLSUB_API_KEY` - API key (default: VLSub's own)

`tools/dev.sh run --dev-api` starts the proxy and sets both (key from
`VLSUB_DEV_API_KEY` or `~/.vlsub-dev.env`). Measured with real VLC 3.0.16
on the dev box: login, search by name, IMDb id and in two languages all
worked through it. The dev database is a subset (no Breaking Bad, no Big
Buck Bunny) and has no `/ai/credits` (404).

## Uploading to a film the site does not have (measured)

`upload/check` with `idmovieimdb: tt1254207` or `tmdbid: 10378` (Big Buck
Bunny, on IMDb/TMDb, not in the database) answers
`rejection_reasons: ["feature_not_found"]`. An IMDb id alone is not enough:
the film has to be registered first (`features/from_id`, then
`features/stub` with `source: "imdb"`), then uploaded to the new
`feature_id`.

## First round trip (development API, 2026-11-22)

`tools/upload_roundtrip.py`, account `3ge` (Trusted member on dev), a
211-byte test subtitle for The Matrix (feature 163533), **packed as plain
Lua can: raw deflate in stored blocks (no compression), base64**:

| step | answer |
|---|---|
| `upload/guess` "The.Matrix.1999.1080p.BluRay.x264.mkv" | 200, The Matrix, feature 163533 |
| `upload/check` | 200, not in db, would not be rejected, quota 50/day |
| `upload` | **201**, subtitle 1193037, `subtitle_status: live`, flag `high_definition` inferred from "1080p", 0.6 s |
| `upload/check` again | `already_in_db: true`, `duplicate_of: 1193037` |
| `upload` again | 409 `duplicate` |
| `GET /my/uploads` | the upload, enabled |
| `DELETE /my/uploads/1193037` | 200 `deleted`; listed afterwards with `enabled: false` |

The stored-deflate packing is accepted: VLSub needs no compressor, only MD5
and base64 in Lua. The answers are fixtures (`tests/fixtures/raw/upload_*.http`).

## Built (2026-11-22, branch `dev`)

Decided by the owner: "Upload" button in the main window; the file is one
of the subtitle files next to the video (same name start) or any file by its
full path; a film the site does not have is registered from its IMDb / TMDb
id; hearing impaired / foreign parts (Automatic / Yes / No), translated by a
person / machine / AI, release name and comment can be set. A file next to
the video goes with the video's hash, size and name; a file by path does not.

- MD5 (RFC 1321), base64 and a stored-block deflate stream in plain Lua.
  32-bit operations: the language's own where it has them, `bit32` on 5.2,
  byte tables on Lua 5.1 (VLC for macOS): 300 kB in 0.46 s there.
- Upload window: file, path, language (from the file name, else the first
  subtitle language), film (found when the window opens: the search just
  made for this video, the API's guess from name + hash, the searched IMDb
  id, `/features` with GuessIt's title and year; Find with an IMDb id, link
  or title), flags, release name, comment; Check and Upload.
- The Film line links to the film's IMDb page.
- Release name: the video's file name only when it tells more than the
  film's title and year (a release group, source, quality - GuessIt's answer
  for the file counts); "Send.Help.2026" leaves the field empty.
- After the upload: "Uploaded: <release>" linked to the subtitle's page.
- TV series: a "Season / episode" row. Filled in from the subtitle's name,
  the video's name (S01E02, s1e2, 1x02), GuessIt, or the episode found.
  Sent only when the film is a series (`tvshow` / `Tvshow` / "tv series");
  empty for a series -> "Which episode is it? Enter season and episode."
  (also for the server's `episode_required`). An episode's own IMDb id:
  `from_id` answers with the show and `preselected`; that episode is used
  and shown as "Show S01E02 - Title". Real VLC: series without episode is
  refused locally, with 1 / 2 Check says Ready.
- Subtitle language, in this order: the name's tag (two- and three-letter
  codes, OpenSubtitles' own codes like pob / zht, English and native names,
  "pt-BR", before "forced" / "sdh" / "hi"); GuessIt's `subtitle_language`
  for the name ("VOSTFR" -> French); fastText on up to 60 text lines
  (`POST /utilities/fasttext/language/detect`, production only - the dev API
  answers 404 - with VLSub's own key; used from confidence 0.8 and about a
  sentence of text; "pt"/"zh" become the user's own variant when it is one;
  dialogue taken from SRT, WebVTT, ASS, MicroDVD, MPL2, TMP, SAMI, UTF-16;
  anything else: the first 8 KB without numbers and times);
  else the user's language from Config. Detected for the first file only:
  the file dropdown has no change event in VLC.
- A file name typed into the IMDb field ("how.i.met.your.mother.s01.e06",
  "The.Matrix.1999"): sent to `/subtitles/upload/guess` first (it finds
  episodes by name); else its title is searched and season / episode go in
  their row. The playing video: GuessIt's answer for that file (title,
  year, season, episode) is used, not the main window's search fields.
- Film not on the site yet: the Film line shows only the film; Upload adds
  it first without saying so (nothing the user has to know).
- Already on the site (check `already_in_db` / upload 409): the message
  links to that subtitle. The API gives only `duplicate_of` (a
  subtitle_id); the page address comes from `/subtitles?id=<feature_id>&
  languages=<lang>` (`id` there is the FILM's feature id), the row with
  that id. First page only; not found -> the message without a link.
  Wanted from the API: the duplicate's `url` in both answers.
- A film on IMDb / TMDb but not here: Upload registers it
  (`features/stub`, `source: imdb`) and uploads to the new `feature_id`;
  a 409 from the stub (registered meanwhile) uses its `feature_id`.
- Limits checked before sending: at least 100 bytes, at most 350 kB.
- Tests replay recorded answers only (`tests/fixtures/raw/upload_*.http`)
  and check what was sent: the MD5 against `md5sum`, the packed file
  inflated back byte for byte.
- Real VLC 3.0.16 through `tools/devproxy.py` to the development API:
  Find (The Matrix), Check ("Ready: 49 uploads left today"), Upload
  ("Uploaded: upload-test.en") - then withdrawn.

Found on the way, for the API team:

- `features/stub` with `source: "imdb"` answered `provisional: true` and
  "A moderator will review it shortly", although the documentation says a
  title from IMDb / TMDb is visible at once.
- An upload with only `idmovieimdb` of a film that is on IMDb but not in
  the database is refused (`feature_not_found`); the server could register
  it itself, as `stub` does, and save every client two calls.
- A film the site does not have yet cannot be found by its title through
  the API: `/features` knows only the site's films, `from_id` takes only
  ids, `guess` with `The.Matrix.Reloaded.2003.mkv` answers `best_guess:
  null`. Wanted: a title (+ year) in `guess` or `from_id`, answered like
  `from_id` answers for an id (`found`, `exists_in_db`, `imdb_id`).

## TODO: title search on imdb.opensubtitles.org (temporary)

Until the API can do the above, VLSub finds such a film by its title on
`http://imdb.opensubtitles.org/search/query-<words>` (plain HTTP, no key,
JSON list of up to 20 `{id, title, year, kind}`), then looks the IMDb id up
with `from_id` as if typed. Code: `upload_search_imdb` in `vlsubcom.lua`
(marked `TODO(api)`); tests: `imdb_query_*.http`.

- Order for a typed title: the site's film with that exact title, IMDb's
  exact title, the site's best match, IMDb's best match. A year typed after
  the title goes to both. Films and series before episodes.
- Found without asking (GuessIt's title from the video's name): IMDb only
  for the exact title and year; not for episodes (IMDb would give the
  series).
- Punctuation is left out of the query (`&` makes the service redirect).
  `/search/imdbid-<8 digits>` gives one title with details (fewer digits:
  302 redirect) - not used.
- A side service: its host failing does not hold back the API's requests;
  after no answer it is left alone for a minute.
- Real VLC through the proxy: "matrix reloaded" -> tt0234215; the Film
  line shows only the film - that Upload adds it to the site is not said.

Replace with the API call when it exists, and drop the fixtures.
