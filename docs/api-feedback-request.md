# Request to the API team: feedback on subtitles (rating, sync, report, comment)

From: VLSub (VLC extension for OpenSubtitles.com), 2026-11-21.
Also affects: the Kodi addon, which already ships a client for a rating
endpoint that is not deployed.

## Why

The REST API (`api.opensubtitles.com/api/v1`, 30 paths) can only *read*
feedback: `votes`, `ratings`, `points` in search results and as sort keys.
Nothing can be written. The old opensubtitles.org XML-RPC API could
(`SubtitlesVote`, `AddComment`, `GetComments`, `ReportWrongMovieHash`,
`ReportWrongImdbMovie`, `AddRequest`), so the new clients know less about
subtitle quality than the old ones did - while the people best placed to
judge a subtitle are the ones who have just watched a film with it in a
player.

## What exists today

| | Old .org XML-RPC | New REST API | Kodi addon 2.0 |
|---|---|---|---|
| Rate | `SubtitlesVote` 1-10 | - | sends `POST /subtitles/rate` `{subtitle_id, rating 1-5, sync}`; gets 404, drops it |
| Sync verdict | - | - | yes/no, in the same call |
| Report bad subtitle | `AddComment` + `badsubtitle` | - | - |
| Report wrong file match | `ReportWrongMovieHash` | - | - |
| Comment | `AddComment`, `GetComments` | - | - |
| Thanks | website only | - | - |

Weak points of the old methods, worth not repeating:

- `AddComment` answers 200 even when the comment was rejected (limits,
  similarity, banned text), and still counts the "bad" flag.
- The "bad" flag has no reason and, over the API, no limit per user: one
  account can raise it any number of times.
- `ReportWrongMovieHash` checks for an earlier report under one id and stores
  it under another, so the "once per user" rule does not hold.
- A vote cannot be changed or withdrawn.
- The rating is a plain mean: three votes of 10 outrank three hundred of 8.
- Nothing positive can be said about a file match ("this subtitle fits this
  file"), only negative.

## What we ask for

All under `/api/v1`, JSON, `Api-Key` + `Authorization: Bearer`, reachable
over plain HTTP for the VLSub User-Agent like the rest of the API.

### 1. Rate a subtitle after watching

`PUT /subtitles/{subtitle_id}/rating`

```json
{
  "rating": 4,
  "sync": "good",
  "sync_offset_ms": 0,
  "file_id": 4311373,
  "moviehash": "8e245d9679d31e12",
  "moviebytesize": 6316316,
  "watched_ratio": 0.93,
  "client": "vlsub"
}
```

- `rating`: 1 to 5 (bad, poor, okay, good, excellent). Five steps are what a
  viewer can answer in one click; the server can map to its 1-10 scale.
- `sync`: `good` | `early` | `late` | `drifting` | `unknown`. Optional.
  `sync_offset_ms`: the delay the viewer had to set in the player, if any -
  the most useful number for fixing a subtitle. Optional.
- `file_id`, `moviehash`, `moviebytesize`: which file it was watched with.
  Optional. A good rating with a hash is a confirmed match; a bad sync
  verdict with a hash is a wrong-match report (see 3).
- `watched_ratio`: how much of the film was played with the subtitle.
  Optional; lets the server weigh or ignore votes from people who saw two
  minutes.
- **`PUT`, one rating per user and subtitle: sending again replaces it.**
  `DELETE` on the same path withdraws it.
- Answer `200`:
  `{"your_rating": 4, "rating": 8.2, "votes": 131, "status": "saved"}`
  (`status`: `saved` | `updated`).
- Rules the old API had and that should stay: login required; not on one's
  own upload; a daily limit for new accounts. A refused vote says so:
  `403 {"code": "own_upload"}` / `429 {"code": "limit", "retry_after": 3600}`
  - never a silent 200.
- The same call must work for AI on-demand translations (ids are strings of
  33-34 digits; a client sends them as the server gave them). A bad rating
  there is the natural trigger for a quality refund.

Suggested additions to existing answers, so a client need not ask twice:
`your_rating` in `GET /subtitles` rows when logged in; `price` (credits) in
an on-demand row.

### 2. Report a problem

`POST /subtitles/{subtitle_id}/reports`

```json
{ "reason": "out_of_sync", "comment": "about 2 s late from minute 40",
  "file_id": 4311373, "moviehash": "8e245d9679d31e12", "moviebytesize": 6316316 }
```

`reason`, a closed list (the old API had one unexplained "bad" counter):
`out_of_sync`, `wrong_movie`, `wrong_language`, `incomplete`,
`bad_translation`, `machine_translated`, `ads_or_spam`, `offensive`,
`not_a_subtitle`, `other` (then `comment` is required).

- One open report per user, subtitle and reason; a repeat answers
  `200 {"status": "already_reported"}`.
- Answer `201 {"status": "received", "report_id": "..."}`.
- `GET /infos/report_reasons` -> the list with translated labels, so clients
  do not hard-code it.

### 3. Does this subtitle fit this file?

`PUT /subtitles/files/{file_id}/match`

```json
{ "moviehash": "8e245d9679d31e12", "moviebytesize": 6316316, "fits": true }
```

Replaces `ReportWrongMovieHash` and adds the positive side. `fits: false`
is the old wrong-hash report; `fits: true` strengthens the link (and lets
hash search find a subtitle that was found by name). Idempotent per user.
The rating call (1) may do this implicitly when it carries a hash.

### 4. Comments

- `GET /subtitles/{subtitle_id}/comments?page=1` ->
  `{"total": 12, "data": [{"id", "user": {"name", "rank"}, "created_at", "language", "text", "reply_to"}]}`
- `POST /subtitles/{subtitle_id}/comments` `{"text": "...", "language": "sk", "reply_to": null}`
  -> `201` with the stored comment, or `422 {"code": "too_similar" | "banned_text" | "limit"}`.

Lowest priority for player clients: typing a comment with a remote control
or in a small player window is rare. Reading the last comments before
downloading would be used more than writing.

### 5. Thanks

`PUT /subtitles/{subtitle_id}/thanks` -> `200 {"thanks": 57}`. One per user.
Cheap for the viewer, motivating for uploaders.

### Across all of them

- Errors as JSON with a stable `code` and a human `message`; no HTML pages,
  no redirects.
- Answers within about 2 seconds: a player extension cannot do anything else
  while it waits.
- Idempotent writes (`PUT`), so a retry after a lost answer cannot double
  count.
- Ids accepted as numbers or as strings.
- Listed in the OpenAPI document with real request / response examples.

Priority: **1** (rating + sync), then **2** (report), **3** (match),
**5** (thanks), **4** (comments).

The Kodi addon's existing call (`POST /subtitles/rate` with
`{subtitle_id, rating, sync: true|false}`) is a subset of (1); if that
contract is already agreed, keeping it as an alias avoids breaking the
shipped addon.

## How VLSub would use it

VLC's Lua gives an extension no timer and no background work, and VLSub
stops when its window is closed. That shapes everything below.

**Knowing that a film was watched with a subtitle.** When VLSub loads a
subtitle it writes a small record next to its settings: subtitle id, file
id, title, language, the video's hash and length, the time. While VLSub is
open, VLC tells it when the playing item changes or stops; at that moment,
and whenever its window is opened, it reads the play position if the same
video is still loaded and otherwise uses the time since loading. Watched =
at least 70% of the film's length (same idea as the Kodi addon's 30% / 80%
rules, with one number).

**Asking.** Not a pop-up over the film. The next time the VLSub window is
opened and a watched, unrated subtitle is on record, the main window shows
one extra line:

```
You watched "Coherence" with these subtitles - how were they?
[ ★★★★☆ Good ▾ ]  Sync: [ Good ▾ ]   [ Send ]  [ Report a problem ]  [ Not now ]
```

- one click on Send: rating + sync + hash + watched ratio in one request (1);
- "Report a problem" opens the list of reasons (2) with an optional line of
  text;
- "Not now" asks again next time; after the third "Not now", or with the
  setting off, never for that subtitle;
- a subtitle is asked about once; the answer is remembered locally and, with
  `your_rating` from the API, across devices.

**Settings.** "Ask me to rate subtitles after watching: Yes / No" in the
filters / configuration window, default Yes; nothing is ever sent without
the click on Send.

**Not for:** subtitles the user loaded from disk (no id), previews of AI
translations, a film that was not watched far enough, a user who is not
logged in (the line then says that rating needs a login).

**What is sent:** only what the request above shows. No titles, no file
names, no paths.

**Showing ratings.** Search rows would show the rating that already arrives
(`★ 8.2 (131)`), and the user's own rating when the API returns it.

**Comments.** A "Comments" button for the selected search row that lists the
last few; writing one from VLC only if asked for.

**Cost.** Roughly 15 new texts in 61 languages, one new record file, one
extra row in the main window that appears only when there is something to
rate.
