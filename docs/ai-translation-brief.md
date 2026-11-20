# AI subtitles in VLSub - brief (branch `dev`)

Goal: when no good subtitle exists in the user's language, VLSub offers an
AI-made one, paid with the AI credits of the user's OpenSubtitles account.

Status: **decided 2026-11-19, ready to implement** (see "Decisions" and
"Stages"). Nothing is implemented yet.

API reference: `private/opensubtitles_openapi.json` (local only, excluded
from git). Reference client: Kodi addon `service.subtitles.opensubtitles-com`,
branch `develop` (version 2.0.0), studied 2026-11-19.

## What the Kodi addon really does

It does **not** call `/ai/translate`. It has two AI features:

1. **On-demand AI translation, through the ordinary download.** The server
   itself adds entries to `GET /subtitles` results (with the default
   `ai_translated=include`) for translations that do not exist yet:
   - recognised by `attributes.comments` containing "will be created on
     demand" ("This subtitle file will be created on demand in czech language
     as AI translation from polish language."), or by a `file_id` of more
     than 10 digits (pseudo ids have 34 digits; real ones 7-8);
   - shown with a badge `[AI on demand]`; ranked below human subtitles;
   - picking it is a normal `POST /download {"file_id": <id>}`. The server
     translates while the request is open (20 s or more) or answers with a
     redirect to `/download/{id}?wait_for_translation=N` and no `link`; the
     addon then waits 5 s and posts again, at most 3 times;
   - no price, no engine choice, no confirmation; credits are taken by the
     server. An empty answer plus a balance of 0 means "no credits";
   - automatic download never picks such an entry.
   This server behaviour is not in the OpenAPI file; the addon's own comments
   call it new and untested.
2. **AI transcription** (experimental, off by default): extract the audio,
   upload it to `/ai/transcribe`, poll, download the result. Not possible in
   VLC's Lua (no way to extract or upload audio) - **out of scope**.

Credits: `GET /ai/credits` -> `data.credits`; `GET /ai/credits/buy` -> list
of `{name, value, discount_percent, checkout_url}`; the addon shows the
checkout URL as a QR code (not needed here: VLSub shows a link).

## What the API offers besides that

`POST /ai/translate` + `GET /ai/translate/{correlation_id}`: translate a
given subtitle (uploaded content, or perhaps a `file_id`) from one language to
another with a chosen engine. Asynchronous: `CREATED` -> `PENDING` ->
`COMPLETED` / `ERROR` / `TIMEOUT`. The result names the file URL
(`/ai/files/<id>/<name>`, needs Api-Key + Bearer), the characters counted,
price, credits left and a quality report (`quality.valid`).

`GET /ai/info/translation` (no login), live on 2026-11-19:

| engine | name | credits per character | languages |
|---|---|---|---|
| `aws` | Amazon Translate | 0.0054 | 75 |
| `deepl2` | DeepL2 | 0.0009 | 29 |
| `gemini3-1-flash` | Gemini 3.1 Flash | 0.001556 | 79 |
| `gemini3-5-flash` | Gemini 3.5 Flash | 0.004668 | 79 |

A typical film subtitle has 40-60 thousand characters: about 40-55 credits
with DeepL2, 60-95 with Gemini 3.1, 220-320 with Amazon. (500 credits = 5 USD.)

Unclear in the specification, to be measured before coding:
- parameters are declared as query parameters, `file` (content) as required
  and `file_id` as optional; for the sibling `/ai/transcribe` the Kodi
  authors measured that they must be multipart form fields. Whether
  `file_id` alone is enough is not stated;
- no error answers are documented (no credits, unsupported language pair).

## Limits of VLC's Lua that shape the design

From `docs/vlc-lua-environment.md`:

- **The window is frozen while a request runs**, and a request cannot be
  interrupted. A download that the server holds open for 20-60 s freezes VLC
  for that long. Polling (`/ai/translate/{id}`) has the same problem unless
  each poll is a separate click or the wait is cut into short requests.
- **API requests go over plain HTTP** with a hand-written client
  (`socket_exchange`, deadline 15 s today). POST with a JSON body and custom
  headers works; multipart upload of a subtitle (some 60 kB) is possible but
  new code. `vlc.stream` (https) can only GET without headers, so the
  `/ai/files/...` result (needs Bearer) must come over plain HTTP too.
- **Numbers**: Lua numbers are doubles; a 34-digit `file_id` is destroyed by
  JSON decode/encode. It has to be taken from the raw response text and sent
  back as text.
- No timers, no background work, no browser launch: a checkout URL can only
  be shown as a link in a label.
- Every new text goes into the strings table and all 61 translations.

## Decisions (user, 2026-11-19)

- **Same mechanism as Kodi**: on-demand entries in the search results, the
  ordinary download creates the translation. `/ai/translate` is not used.
- **The server inserts on-demand entries only for whitelisted User-Agents**
  (through a proxy on the API side). VLSub's User-Agent gets a **2.x**
  version: this feature ships as **v2.0.0**, and the User-Agent
  `VLSub OpenSubtitles.com v2.` is what the API whitelists. The format of
  the User-Agent does not change (plain-HTTP access depends on its prefix).
- **Spending credits**: the entry is clearly marked; clicking Download
  spends. The balance is shown before and after. No second click.
- **Live testing**: the CI test account gets AI credits
  (`VLSUB_USER` / `VLSUB_PASS`).
- Transcription and QR codes: out of scope.

## Hard rules

1. Everything that is not AI-related behaves exactly as v1.4.0: the
   behaviour diff (baseline moved to v1.4.0 for this work, with the version
   number neutral) reports `identical` for every existing session. New
   sessions cover the new feature.
2. **Credits are never spent without the user clicking Download on an entry
   marked as AI on demand.** Not by auto-search, not by auto-download on
   media change, not by a retry the user did not see announced, not when
   the user is not logged in.
3. A 34-digit id is never passed through a Lua number: it is read from the
   raw response text and written back as the same digits.
4. No request or response bodies, tokens or passwords in the log; the
   checkout URL (it carries a per-user tag) is shown to the user, never
   logged.
5. One file; Lua 5.1 / 5.2 / 5.4, compiles on 5.5; only the VLC API of
   `docs/vlc-lua-environment.md`; nothing read at load time; labels through
   `new_dialog()`; every new text in the strings table and in all 61
   `locale/*.json` (no fragments).
6. VLC's window is frozen during a request. Before a long one a message is
   shown ("Translating with AI, this can take a minute..."); a dead network
   is still tried once only.
7. The API specification stays local (`private/`, excluded from git).
   Credentials only through environment variables / CI secrets.
8. Work on `dev`. No merge to `main` and no release without an explicit
   instruction.

## Stages

0. **Measure first** (needs the User-Agent whitelisted and credits on the
   test account). With `curl`, as the extension would ask - plain HTTP,
   User-Agent `VLSub OpenSubtitles.com v2.0.0`: a search that returns an
   on-demand entry; `/ai/credits`; `/ai/credits/buy`; the on-demand
   `/download` (how long it is held, the `wait_for_translation` redirect,
   the final answer, what `remaining` and the credits do); the same with an
   account without credits; the same without login. Record every answer as a
   fixture (`tests/fixtures/raw/`), with tokens and the checkout tag
   replaced. Write what was found into this file; where the server differs
   from the Kodi addon's assumptions, follow the server.
1. **Baseline**: freeze v1.4.0 as the behaviour baseline; `app_version`
   becomes `2.0.0` on `dev`.
2. **Search**: recognise on-demand entries (comment text or id longer than
   10 digits), keep the id as text, mark them in the list ("AI on demand"),
   list them after the existing subtitles of the same language. Existing
   AI-translated uploads keep their current marking.
3. **Download**: logged in only (otherwise a message that says so and
   offers the configuration window); balance before (`/ai/credits`); the
   long request with the wait / re-post rule (at most 3, 5 s apart, each
   announced in the message line); result saved and loaded like any
   subtitle; balance after. No credits: message with the balance and a link
   to buy.
4. **Account**: the configuration window shows the AI credit balance and a
   "Buy AI credits" link when logged in (packages from `/ai/credits/buy`;
   shown as links, cheapest first).
5. **Never by itself**: auto-search may list on-demand entries; automatic
   download skips them.
6. **Texts**: strings table, 61 translations, help window line.
7. **Tests**: fixtures from stage 0; the fake API plays: held request,
   redirect-and-wait, success after re-post, no credits, not logged in,
   401 during the wait, network dying mid-wait, id with 34 digits surviving
   the round trip (asserted on the bytes sent); credits never spent in the
   "never by itself" cases; macOS mock for the new labels; real-VLC run
   (`tests/vlc/run.sh`) with the test account: search, on-demand download,
   credits decrease.
8. **Docs**: README section, CHANGELOG, `docs/vlc-lua-environment.md` if
   VLC taught us something new.

**Unattended rule**, as in the refactor: when something is unclear and the
answer changes what a user pays or sees, it is not decided alone. It goes to
"Open questions" below with the options, and the work continues with the
rest.

## Done when

- stage 0 answers are written down here and recorded as fixtures
- all tests pass on Lua 5.1 / 5.2 / 5.4 / 5.5, luacheck is clean
- the behaviour diff against v1.4.0 is `identical` for every existing
  session
- `tests/vlc/run.sh` in real VLC gets an on-demand translation with the
  test account and sees the credits go down
- the user has tried it on macOS

## Proposed design (decided: phase A)


Phase A - **on-demand entries, as Kodi does**
1. Search: recognise on-demand entries; keep the id as text; show them marked
   ("AI on demand") and listed after existing subtitles of the same language.
2. Download of such an entry: only when logged in; first a line "AI
   translation, uses credits - you have N" (one `GET /ai/credits`); then the
   normal download with a long deadline and the wait/retry rule above, with a
   message before the window freezes ("Translating, this can take a
   minute...").
3. No credits: message with the balance and a link to buy credits
   (`/ai/credits/buy`, cheapest package or the list).
4. Configuration window: a line with the AI credit balance and a "Buy
   credits" link, shown when logged in.
5. Automatic download on media change never spends credits.

Phase B - **explicit translation** (`/ai/translate`), only if wanted
- "Translate with AI" for a selected, existing subtitle into the user's
  language: choose engine, see the estimated price, confirm, wait, get the
  quality verdict. Needs the unclear points measured first.

Tests, as for everything else: recorded real answers as fixtures, the fake
API plays the wait/redirect/no-credit cases, the behaviour diff must stay
identical when the feature is not used, real-VLC run with a test account.

## Answers and measurements (2026-11-19)

- An on-demand translation is paid **with credits only**; the daily download
  quota is not touched.
- When the server offers no on-demand entry, VLSub says nothing.
- `GET /subtitles` over plain HTTP answers with the header
  `X-AI-Proxy: true` (through `kong/3.9.1`) for the User-Agents
  `VLSub OpenSubtitles.com v2.0` and `v2.0.0`. (At first also for `v1.4.0`;
  corrected on the server, see below.)
- No on-demand entry was returned yet (six anonymous searches, among them a
  language without any subtitle for the film).

### Languages that can be translated

`GET /ai/info/translation`, live. An on-demand entry can only exist for a
target language some engine supports.

| engine | languages |
|---|---|
| `aws` (75) | af am ar az bg bn bs ca cs cy da de el en es es-MX et fa fa-AF fi fr fr-CA ga gu ha he hi hr ht hu hy id is it ja ka kk kn ko lt lv mk ml mn mr ms mt nl no pa pl ps pt pt-PT ro ru si sk sl so sq sr sv sw ta te th tl tr uk ur uz vi zh zh-TW |
| `deepl2` (29) | bg cs da de el en es et fi fr hu id it ja ko lt lv nl no pl pt ro ru sk sl sv tr uk zh |
| `gemini3-1-flash`, `gemini3-5-flash` (79 each) | af am ar as az be bg bn bs ca cs da de el en en-GB en-US es es-419 es-ES es-MX et eu fa fi fil fr gl gu he hi hr hu hy id is it ja ka kk km kn ko lo lt lv mk ml mn mr ne nl no or pa pl pt pt-BR pt-PT ro ru si sk sl sq sr sv sw ta te th tr uk ur uz vi zh-CN zh-TW zu |

Of the 105 subtitle languages of the API, **no engine** covers 25:
Abkhazian, Aragonese, Asturian, Breton, Esperanto, Extremaduran, Gaelic,
Interlingua, Igbo, Kurdish, Luxembourgish, Manipuri, Montenegrin, Burmese,
Navajo, Occitan, Portuguese (MZ), Sindhi, Northern Sami, Santali, Syriac,
Turkmen, Tetum, Toki Pona, Tatar, and "Chinese bilingual". (Spanish LA / EU,
Dari and Tagalog have other codes on the engines: es-419 / es-ES, fa-AF,
fil.) Which engine and which source language are used is the server's
choice; VLSub does not filter by language - it shows what the server offers.

### A real on-demand entry (live API, 2026-11-19)

`GET http://api.opensubtitles.com/api/v1/subtitles?imdb_id=1254207&languages=cs`
(Big Buck Bunny; no Czech subtitle exists), anonymous, User-Agent
`VLSub OpenSubtitles.com v2.0.0`. Recorded as
`tests/fixtures/raw/search_on_demand_cs.http`. One row:

| field | value |
|---|---|
| `id`, `attributes.subtitle_id` | `"422433409911500000000000000000000"` |
| `attributes.files[0].file_id` | `"431137309911500000000000000000000"` |
| `attributes.files[0].file_name` | `big_buck_bunny.eng` (the source file's name) |
| `attributes.language` | `cs` |
| `attributes.ai_translated` | `true` |
| `attributes.machine_translated` | `true` |
| `attributes.comments` | `This subtitle file will be created on demand in czech language as AI translation from english language.` |
| `attributes.uploader` | `{"uploader_id":null,"name":"AI.OpenSubtitles.com","rank":"anonymous"}` |
| `attributes.download_count` | `0` |
| `attributes.upload_date`, `release`, `fps`, `feature_details` | those of the English source subtitle |

What this settles:

- **The ids are 33 digits and they are JSON strings**, not numbers (ordinary
  ids are numbers: `"file_id":4311373`). The digits start with the id of the
  source (file 4311373, subtitle 4224334). Kept as the string it arrives as,
  nothing is lost in Lua; what must not happen is `tonumber()` on it.
  Whether `/download` wants it back as a string or as bare digits is still
  to be measured (needs a login).
- An on-demand entry is offered **without login**, for searches by
  `imdb_id` and by `query`. It was **not** offered for a `moviehash` search
  of the same film, nor for Georgian (`ka`) although engines list it.
- It appears when the film has **no subtitle in the asked language**
  (`cs`, `sk`: one on-demand row each; `en`: only the real subtitle).
- With two languages asked (`languages=cs,sk`) only **one** on-demand row
  came back (`cs`).
- Recognising one: the comment text, the uploader name
  `AI.OpenSubtitles.com`, or an id that is a string of more than 10 digits.
  There is no dedicated field.

Not measured yet (needs a logged-in account with credits): the download.

### Several languages asked: only the first one is served (2026-11-19)

Same film (`imdb_id=1254207`, has an English subtitle, none in cs/sk/de/fr):

| `languages=` | rows returned |
|---|---|
| `en` | en |
| `sk` | sk (on demand) |
| `cs,sk` / `cs,de,sk` | cs (on demand) only |
| `de,sk` | de (on demand) only |
| `en,sk` | en only - no on-demand row for sk |
| **`cs,en`** / `cs,en,sk` | **cs (on demand) only - the real English subtitle is missing** |

The proxy looks at the first language of the list only (the list is always
sorted alphabetically - canonical form). When that language has no subtitle,
the answer is one on-demand row **and the existing subtitles of the other
languages are gone**. `languages=cs,en&query=big+buck+bunny` returns 1 row
instead of about 50.

For a short time this also reached the User-Agents `v1.3.2` and `v1.4.0`.
**Fixed on the server the same day**: re-measured, 1.x gets no
`X-AI-Proxy` header and its normal results (50 rows for `cs,en`); only
`VLSub OpenSubtitles.com v2.` is proxied.

Still open for 2.x, on the server: with several languages the real rows of
the other languages are missing (`languages=cs,en&query=big+buck+bunny`:
1 on-demand row instead of 50 rows), and only the first language gets an
on-demand row. VLSub 2.0 must not ship before that is settled - or it must
work around it (e.g. one extra request per language without results).

### No simulation

A simulated on-demand server in the test suite was tried and removed on the
user's instruction (2026-11-19): tests are built from real examples only.

## First cut on `dev` (2026-11-19) - to try it, not finished

So that the feature can be seen in VLC before the download is measured:

- `app_version` is `2.0.0` (the User-Agent the API proxies).
- An on-demand entry is recognised (string id longer than 10 digits, or the
  comment text) and listed as `... 🤖 AI on demand (uses credits)`.
- Download of one: the 33 digits go back as a JSON number; **one** request,
  allowed to take 120 s, never repeated by itself; before it the message
  "Creating the AI translation - this can take a minute, VLC will not
  respond meanwhile...". What comes back is handled like any download answer.
- `tools/dev.sh run -v` also prints the raw `/download` answer
  (`VLSUB_TRACE_HTTP=1`), to learn what the server really says.

Measured on the user's Mac the same day: `POST /download` for an on-demand
id is answered with **HTTP 302** and an empty body. Added after that:

- the redirect is followed: `GET` of the `Location` (only on
  `api.opensubtitles.com`, over plain HTTP, with the same credentials); an
  answer without a link is taken as "still translating": wait 5 s and post
  again, at most 3 more times, saying so each time;
- credits: read before an on-demand download (balance 0: nothing is asked
  for, a message with links to the credit packages instead) and after it
  ("AI credits left: N"); the configuration window has an "AI credits" row
  with a button that shows the balance and the packages on click (no request
  for merely opening the window). Checkout links are shown, never logged,
  and only made clickable when they are plain `https://…opensubtitles.com/`
  addresses.

Still missing: what the redirect target really answers (first while
translating, then when done) as fixtures and tests; translations of the new
texts; help text; README / CHANGELOG.

### The download, measured in real VLC (user's Mac, 2026-11-19)

`POST http://api.opensubtitles.com/api/v1/download` with
`{"file_id":431137309911500000000000000000000}` (a JSON number), logged in,
418 credits: **HTTP 200** at once,

```json
{"link":"https:\/\/ai.opensubtitles.com\/proxy\/download\/431137309911500000000000000000000",
 "file_name":"","requests":"1","remaining":"99999999",
 "message":"This a on-demand translation by AI.OpenSubtitles.com (file was cached)",
 "reset_time":"now","reset_time_utc":"2026-11-19T23:55:54.000Z"}
```

(An earlier attempt the same evening got HTTP 302 with an empty body.)

- The id is accepted as a JSON number.
- `file_name` is empty; `requests` / `remaining` are strings and not the
  daily quota (`"99999999"`): they must not be shown as quota.
- **The link cannot be fetched.** `GET https://ai.opensubtitles.com/proxy/download/<id>`
  answers **404** (HTML "Page not found"), with and without `Api-Key`;
  over plain HTTP it answers 301 to https. VLC can fetch https only without
  any header (`vlc.stream`), and plain HTTP is refused, so for VLSub this
  link has to work **anonymously over https** - like the ordinary
  `www.opensubtitles.com/download/...` links - or be served by
  `api.opensubtitles.com` over plain HTTP. To be fixed on the server.

## Open questions

1. Blocked until done on the API side: the User-Agent
   `VLSub OpenSubtitles.com v2.` whitelisted for on-demand entries, and AI
   credits on the CI test account. Stage 0 cannot start before.
2. The download of an on-demand entry, measured with a logged-in account:
   id as string or digits, how long the request is held, what a "still
   translating" answer looks like, what comes back without credits.
   Also: no on-demand entry for a `moviehash` search and only one for two
   asked languages - intended?
3. Should 1.x User-Agents get on-demand entries at all (they cannot use
   them)?
