# Trying AI on-demand subtitles in VLSub (for the AI service developer)

VLSub is the OpenSubtitles.com extension for VLC. Branch `dev` (version
2.0.0) uses the AI on-demand translation of the API. This page shows how to
run it on Linux and watch exactly what it sends and receives.

What is wrong with the notice inside a preview subtitle, and a proposed
text: [`ai-preview-notice.md`](ai-preview-notice.md).
Everything measured so far: [`ai-translation-brief.md`](ai-translation-brief.md).

## 1. Install the development version (Linux)

Needs VLC 3.0.x, git, and Lua (5.1 - 5.4) only for the offline tests.

```bash
git clone https://github.com/opensubtitles/vlsub-opensubtitles-com.git
cd vlsub-opensubtitles-com
git checkout dev
tools/dev.sh link      # VLC loads this checkout (symlink in ~/.local/share/vlc/lua/extensions/)
tools/dev.sh status    # shows what VLC will load
```

VLC from snap or flatpak keeps its extensions elsewhere
(`~/snap/vlc/current/.local/share/vlc/lua/extensions/`,
`~/.var/app/org.videolan.VLC/data/vlc/lua/extensions/`): copy or link
`vlsubcom.lua` there by hand. `tools/dev.sh restore` puts back what was
installed before.

## 2. Run it and see the traffic

```bash
tools/dev.sh run -v /path/to/any/video.mkv
```

VLC starts; open **View > VLSub OpenSubtitles.com**. With `-v` the terminal
shows every request the extension makes and, for downloads, the raw answer:

```
[VLSub] GET http://api.opensubtitles.com/api/v1/subtitles?imdb_id=2866360&languages=sk
[VLSub] POST http://api.opensubtitles.com/api/v1/download
[VLSub] trace POST /download -> 302 location=/api/v1/download/<id>?wait_for_translation=1 body=
[VLSub] trace GET /api/v1/download/<id>?wait_for_translation=1 -> 302 location=...=2 body=
[VLSub] trace GET ... -> 200 location=nil body=1 ...
```

Afterwards: `tools/dev.sh requests` (all requests of the last run),
`tools/dev.sh errors` (Lua errors, if any).

## 3. Get an on-demand translation

1. **Config**: OpenSubtitles.com username and password; subtitle language 1
   = the target language, languages 2 and 3 = None; **Save**. The message
   shows the account line and `AI credits: N`. The button "Show balance /
   buy" shows the balance and the credit packages.
2. Main window: empty the Title field, type an **IMDB ID**, **Search**.
3. An entry the server offers on demand is listed as
   `SK | <source name> 🤖 AI on demand (uses credits) 👤AI.OpenSubtitles.com`.
4. Select it, **Download**. The message counts the seconds while the server
   translates; the subtitle is saved next to the video (or in `~/Downloads`
   when no video is open) and loaded.

Films that had an on-demand entry on 2026-11-20:

| IMDb id | Film | Language | From |
|---|---|---|---|
| 2866360 | Coherence (2013) | Slovak | Czech |
| 2084989 | Upstream Color (2013) | Slovak, Ukrainian | Czech, Russian |
| 390384 | Primer (2004) | Ukrainian | Russian |
| 1254207 | Big Buck Bunny (2008) | sk cs hu uk pl de | English (2 cues: quick and nearly free) |

An account **with** credits gets the full translation; an account
**without enough** credits gets the preview with the notice. To see the
notice, use an account at 0 credits.

## 4. What the extension expects from the server

Plain HTTP to `api.opensubtitles.com`, User-Agent
`VLSub OpenSubtitles.com v2.0.0`, headers `Api-Key` and
`Authorization: Bearer <token>`.

| Step | Request | Answer the extension handles |
|---|---|---|
| search | `GET /subtitles?imdb_id=..&languages=sk` | on-demand row: `files[0].file_id` is a **string** of 33-34 digits, `comments` contains "will be created on demand" |
| order | `POST /download {"file_id":<digits as a JSON number>}` | `302` + `Location: /api/v1/download/<name>?wait_for_translation=1`, or `200` with `link` (translation exists) |
| wait | `GET <Location>` (API host only) | `302` to `...=2`, `...=3`, ... or `200` whose **body is the subtitle text** |
| existing | from `link` = `https://ai.opensubtitles.com/proxy/download/<name>?<query>` the extension asks `GET /api/v1/download/<name>?wait_for_translation=1&<query>` | `200`, body = subtitle text |
| credits | `GET /ai/credits`, `GET /ai/credits/buy` | `{"data":{"credits":N}}`, list with `checkout_url` |

`<name>` is the id, or `preview-<id>` for an account without enough credits;
the extension asks for exactly the name the server gave. It never repeats
the `POST` by itself and follows redirects for at most three minutes.

Limits of VLC that matter to the server:

- https requests from VLC cannot carry headers, and the extension's API
  traffic is plain HTTP. A link that needs a login must be on
  `api.opensubtitles.com` over HTTP; a link on another host must work
  without any header.
- While a request is open the extension's window does not react. Each
  waiting request is held about 9 s today; shorter holds (2 - 3 s) would let
  the progress message move more often.

## 5. Open points for the server

1. The notice in the preview (see `ai-preview-notice.md`).
2. The price is not known to the client: nothing in the search row or in
   the preview answer says what the full translation costs. With it the
   extension could say "needs about 20 AI credits, you have 12" before
   ordering.
3. `https://ai.opensubtitles.com/proxy/download/<id>` answers 404.
4. `GET /api/v1/download/<id>?wait_for_translation=1` (plain id) returns the
   full text of an existing translation to an account without credits.
5. With several languages asked (`languages=cs,en`) only the first is
   served and the real results of the others are missing.
6. No on-demand entry for a `moviehash` search (VLSub searches by hash
   first), and none for some languages the engines list (lt, lv, ka).
7. "The Man from Earth" (IMDb 756683), Ukrainian: the source is named "The
   Event - 02 - To Keep us Safe".

## 6. Tests

```bash
tests/run.sh                 # offline: 530 tests against recorded answers, no network
VLSUB_USER=.. VLSUB_PASS=.. VLSUB_AI=credits   tests/vlc/run.sh   # live, inside real VLC
VLSUB_USER=.. VLSUB_PASS=.. VLSUB_AI=nocredits tests/vlc/run.sh   # live: expects the preview
# other film: VLSUB_AI_IMDB=2866360 VLSUB_AI_LANGUAGE=Slovak
```

The live run uses Big Buck Bunny in Hungarian by default (exists already,
costs nothing). Use a throwaway account: the password travels over plain
HTTP.

Report anything odd as an issue on the repository, with the lines of
`tools/dev.sh run -v` around it.
