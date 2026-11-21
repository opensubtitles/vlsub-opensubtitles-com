# Feature request for the OpenSubtitles API: feedback on subtitles

Rating, sync, problem reports, file match, thanks and comments - as API
endpoints any client can use. Written 2026-11-21 from the work on two
clients (the Kodi addon and the VLC extension, used as examples below); the
request is for the API itself.

## 1. The gap

`api.opensubtitles.com/api/v1` (30 paths) can only *read* feedback: `votes`,
`ratings`, `points` in search results. Nothing can be written.

| | old .org XML-RPC | REST API today | what clients do |
|---|---|---|---|
| Rate a subtitle | `SubtitlesVote` (1-10) | - | Kodi 2.0 sends `POST /subtitles/rate`, gets 404, drops it |
| Was it in sync? | - | - | Kodi asks yes/no and sends it in the same call |
| Report a bad subtitle | `AddComment` + `badsubtitle` flag | - | nothing |
| Wrong / right file match | `ReportWrongMovieHash` | - | nothing |
| Delay the viewer had to set | - | - | Kodi proposes `sync-report` / `sync-hint` (not deployed) |
| Comment | `AddComment`, `GetComments` | - | nothing |
| Thanks | website only | - | nothing |
| Find a subtitle by its file hash | `CheckSubHash` (MD5) | - | nothing |

The people best placed to judge a subtitle are those who have just watched a
film with it in a player. Today none of that reaches the site.

Faults of the old methods that a new design should not repeat:

- `AddComment` answers 200 even when the comment was rejected, and still
  counts the "bad" flag;
- the "bad" flag has no reason and, over the API, no limit per user;
- `ReportWrongMovieHash` checks for an earlier report under one id and stores
  it under another, so "once per user" does not hold;
- a vote cannot be changed or withdrawn;
- the rating is a plain mean (three votes of 10 outrank three hundred of 8);
- a file match can only be denied, never confirmed.

## 2. Naming the subtitle: id, file id, or hash of the file

Every write below says which subtitle it is about with one object:

```json
"subtitle": { "subtitle_id": "4224334" }
"subtitle": { "file_id": "4311373" }
"subtitle": { "sha1": "3f786850e387550fdab836ed7e6dc881de23001b" }
```

- `subtitle_id` / `file_id`: as in search results. Accepted as number or
  string (AI on-demand ids are strings of 33-34 digits).
- **`sha1`: SHA-1 of the subtitle file's bytes.** For when the client has the
  file but not the id: a subtitle the user downloaded from the website, took
  from another program, or kept on disk for years. It also survives renaming.
  It is what lets a player rate "the subtitle that is loaded", wherever it
  came from.

What `sha1` needs from the server:

- the SHA-1 of every file **as it is served** by `/download`, stored and
  indexed (the old database has MD5 for `CheckSubHash`; keep accepting
  `md5` too if that is cheaper to start with);
- `sha1` returned by `/download` and in `files[]` of search results, so a
  client can remember it without hashing;
- a second, forgiving hash would catch more: clients and users change files
  (BOM, CRLF, "remove tags", re-encoding to UTF-8). A `sha1_normalized` -
  text decoded, BOM dropped, line ends unified, trailing space trimmed - is
  cheap on both sides. The rule has to be written down exactly, or nobody's
  hashes match;
- unknown hash: `404 {"code": "unknown_subtitle"}`, never a guess.

A look-up for clients that want to know what they have:

`GET /subtitles/lookup?sha1=...` -> the search-result row of that subtitle
(with `your_rating` when logged in).

**The video file** stays identified as today: `moviehash` + `moviebytesize`.
A SHA-1 of a whole video is not asked for - hashing 30 GB takes minutes.

## 3. Endpoints

JSON; `Api-Key` + `Authorization: Bearer`; reachable over plain HTTP for
the clients that are (VLSub), like the rest of the API.

### 3.1 Rate - `PUT /subtitles/rating`

```json
{
  "subtitle": { "subtitle_id": "4224334" },
  "rating": 4,
  "sync": "good",
  "video": { "moviehash": "8e245d9679d31e12", "moviebytesize": 6316316 },
  "watched_ratio": 0.93,
  "client": "kodi"
}
```

- `rating` 1-5: bad, poor, okay, good, excellent. Five steps are what a
  viewer answers in one click on a TV remote or in a player window; Kodi
  already asks this way. The server maps to the site's 1-10 as it likes
  (x2), and may accept `"scale": 10` from clients that want ten.
- `sync`: `good` | `early` | `late` | `drifting` | `unknown`. Optional. Kodi
  asks yes / no / skip today (`true` / `false` accepted as `good` /
  `unknown`-bad).
- `video`: what it was watched with. Optional. With a good rating it
  confirms the match, with a bad sync verdict it questions it (see 3.4).
- `watched_ratio`: share of the film played with the subtitle. Optional;
  lets the server weigh, or ignore, votes from two minutes of viewing.
- One rating per user and subtitle. **Sending again replaces it**;
  `DELETE /subtitles/rating` with the same `subtitle` object withdraws it.
- `200 {"status": "saved" | "updated", "your_rating": 4, "rating": 8.2, "votes": 131}`
- Refusals are said, never a silent 200: `403 own_upload`, `403 read_only`,
  `429 limit` (+ `retry_after`), `404 unknown_subtitle`, `422 invalid`.
- Old rules worth keeping: login required; not on one's own upload; a daily
  limit for new accounts.
- AI on-demand translations are rated the same way; a bad rating there is the
  natural trigger for the quality refund.

Alias: `POST /subtitles/rate` with `{subtitle_id, rating, sync: true|false}`
is what the shipped Kodi addon sends. Accepting it costs little.

### 3.2 Sync correction - `POST /subtitles/sync-report`, `GET /subtitles/sync-hint`

The Kodi addon's proposal (its `docs/subtitle_sync_plan.md`), unchanged in
substance:

```json
POST /subtitles/sync-report
{ "subtitle": { "file_id": "4311373" },
  "video": { "moviehash": "8e245d9679d31e12", "moviebytesize": 6316316 },
  "delay_ms": 1800, "fps_scale": 1.0 }
```

`delay_ms`: the delay the viewer ended with (+ = the subtitle was late).
The server keeps a median per (file, video).

```
GET /subtitles/sync-hint?file_id=4311373&moviehash=8e245d9679d31e12&moviebytesize=6316316
-> { "data": { "delay_ms": 1800, "fps_scale": 1.0, "samples": 7, "confidence": 0.9 } }
```

The next viewer with that file gets the subtitle already shifted. Kodi can
read the delay from its player; VLC can too (`sub-delay`). One correction by
one user fixes it for everybody - the highest value per line of code in this
whole request.

### 3.3 Report a problem - `POST /subtitles/reports`

```json
{ "subtitle": { "subtitle_id": "4224334" },
  "reason": "bad_translation",
  "comment": "names are translated differently from scene to scene",
  "video": { "moviehash": "8e245d9679d31e12", "moviebytesize": 6316316 } }
```

`reason` - a closed list, in place of the one unexplained "Sub BAD" counter:

| reason | meaning | what the server can do with it |
|---|---|---|
| `out_of_sync` | timing does not fit this video | counts against the match, not the subtitle |
| `wrong_movie` | subtitle of another film / episode | review; hides the match |
| `wrong_language` | not the language it is listed under | review |
| `bad_translation` | poor or wrong translation | lowers quality |
| `machine_translated` | machine / AI translation not marked as such | sets the flag after review |
| `incomplete` | parts of the film have no subtitles | review |
| `hearing_impaired_wrong` | SDH flag missing or wrong | fixes the flag |
| `foreign_parts_wrong` | "forced" flag missing or wrong | fixes the flag |
| `bad_formatting` | broken characters, encoding, tags, overlapping lines | review |
| `ads_or_spam` | advertising inside the subtitle | review / removal |
| `offensive` | abusive or illegal content | priority review |
| `not_a_subtitle` | empty or not a subtitle file | removal |
| `other` | `comment` required | review |

- One open report per user, subtitle and reason; a repeat answers
  `200 {"status": "already_reported"}`.
- `201 {"status": "received", "report_id": "r_8c1f"}`
- `GET /infos/report_reasons?language=sk` -> the list with translated labels,
  so clients do not hard-code it and new reasons reach old clients.
- The website's "report wrong data" form (corrected fields, admin approval)
  is a different thing and stays where it is.

### 3.4 Does it fit this video? - `PUT /subtitles/match`

```json
{ "subtitle": { "file_id": "4311373" },
  "video": { "moviehash": "8e245d9679d31e12", "moviebytesize": 6316316 },
  "fits": true }
```

`fits: false` is the old `ReportWrongMovieHash`; `fits: true` is new - it
strengthens the link, and creates one for a subtitle that was found by name,
so the next hash search finds it. Idempotent per user. Calls 3.1 and 3.2
may do this implicitly when they carry `video`.

### 3.5 Thanks - `PUT /subtitles/thanks`

`{ "subtitle": {...} }` -> `200 {"thanks": 57}`. One per user. One click for
the viewer, the thing uploaders actually see.

### 3.6 Comments

- `GET /subtitles/comments?subtitle_id=4224334&page=1` ->
  `{"total": 12, "data": [{"id", "user": {"name", "rank"}, "created_at", "language", "text", "reply_to"}]}`
- `POST /subtitles/comments` `{"subtitle": {...}, "text": "...", "language": "sk", "reply_to": null}`
  -> `201` with the stored comment, or
  `422 {"code": "too_similar" | "banned_text" | "empty"}`, `429 limit`.

Players will read more than they write: the last comments before
downloading are worth showing; typing with a remote is rare.

### 3.7 Small additions to what exists

- `GET /subtitles` rows, when logged in: `your_rating`, `your_thanks`.
- `files[]` in search rows and the `/download` answer: `sha1`.
- AI on-demand rows: `price` (credits), so a client can say what it will
  cost before the click.

## 4. Rules for all of them

- Errors are JSON with a stable `code` and a readable `message`. No HTML
  pages, no redirects.
- Writes are idempotent (`PUT`, or `POST` with a dedup rule): a retry after a
  lost answer must not count twice.
- Answers within about 2 seconds. A player extension can do nothing else
  while it waits.
- Ids accepted as numbers or strings.
- Nothing personal is needed: ids and hashes only - no titles, file names or
  paths.
- In the OpenAPI document, with real request and response examples.

## 5. Priority

1. **Rating with sync** (3.1) - with the `sha1` identity (2).
2. **Sync report and hint** (3.2).
3. **Reports with reasons** (3.3).
4. **Match** (3.4), **thanks** (3.5).
5. **Comments** (3.6), lookup by hash, the small additions (3.7).

## 6. How clients would use it

### Kodi addon (has most of it already)

- Asks after playback - film ended, or stopped after 30% - with two dialogs:
  1-5 stars, then "Were the subtitles in sync?". Sends 3.1.
- Samples the subtitle delay every second: can send 3.2 and apply the hint
  before the subtitle is shown.
- A third step "Something wrong?" with the reasons of 3.3 fits the same
  dialog style.
- Knows local subtitles it did not download (sidecar files): with `sha1` it
  can rate those too.

### VLC extension (VLSub)

VLC's Lua gives an extension no timer and no background work, and VLSub
stops when its window is closed. So:

- **Knowing a film was watched with a subtitle.** When VLSub loads a
  subtitle it notes: subtitle id, file id, SHA-1 of the saved file, the
  video's hash and length, the time. When VLC reports that the playing item
  changed, and whenever the VLSub window is opened, it reads the play
  position (or, if the video is gone, the time since loading). Watched = 70%
  of the length.
- **Asking.** No pop-up over the film. The next time the VLSub window is
  opened, one extra line:

  ```
  You watched "Coherence" with these subtitles - how were they?
  [ ★★★★☆ Good ▾ ]  Sync: [ Good ▾ ]   [ Send ]  [ Report a problem ]  [ Not now ]
  ```

  Send = one request (3.1) with rating, sync, video hash, watched ratio,
  and the subtitle delay set in VLC (3.2). "Report a problem" lists the
  reasons of 3.3 with an optional line of text. Asked once per subtitle;
  "Not now" three times, or the setting off, ends it.
- **A subtitle from disk.** "Rate the loaded subtitle" works for any
  subtitle file through its `sha1`; when the server does not know the hash,
  VLSub says so.
- **Showing.** Search rows show the rating that already arrives
  (`★ 8.2 (131)`) and the user's own. A "Comments" button lists the last
  few for the selected row.
- **Never:** anything sent without the click on Send; local files without a
  known hash; previews of AI translations; users who are not logged in.

## 7. Open questions for the API team

1. Is `POST /subtitles/rate` (Kodi's contract) final, or can the richer
   `PUT /subtitles/rating` replace it, with the old one as an alias?
2. Which file hash does the database have today (MD5 from `CheckSubHash`?),
   and of which bytes - the stored file, or what `/download` serves after
   conversion (`sub_format`, encoding)?
3. Is a normalised hash acceptable, and who writes its exact rule?
4. Should ratings from players count more than anonymous website clicks
   (they come with `watched_ratio` and a video hash)?
5. Reports: who sees them - moderators only, or the uploader too?
