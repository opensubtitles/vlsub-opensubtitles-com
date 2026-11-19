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
  `VLSub OpenSubtitles.com v2.0`, `v2.0.0` **and `v1.4.0`**. If only 2.x is
  meant to get on-demand entries, the whitelist is wider than intended: the
  released 1.4.0 would show such an entry as an ordinary subtitle and fail
  on its id (see the simulation below).
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

### No simulation

A simulated on-demand server in the test suite was tried and removed on the
user's instruction (2026-11-19): tests are built from real examples only.
Until one exists, nothing about the shape of an on-demand entry or of its
download is assumed in code.

## Open questions

1. Blocked until done on the API side: the User-Agent
   `VLSub OpenSubtitles.com v2.` whitelisted for on-demand entries, and AI
   credits on the CI test account. Stage 0 cannot start before.
2. How to make the live API return an on-demand entry (login needed?
   search by `imdb_id` / `moviehash`? a switch on the server?).
3. Should 1.x User-Agents get on-demand entries at all (they cannot use
   them)?
