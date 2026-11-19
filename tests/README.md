# Tests

Three layers, cheapest first.

| Command | What runs | Needs |
|---|---|---|
| `tests/run.sh` | syntax check, `luacheck`, 203 behaviour tests | any Lua 5.1–5.5 |
| `tests/vlc/run.sh` | the extension inside a real headless VLC, against the live API | VLC |
| `tools/dev.sh run` | VLC's GUI with this checkout installed and a debug log | VLC |

## 1. Offline suite — `tests/run.sh`

```bash
tests/run.sh                         # everything
lua tests/run_tests.lua download     # only tests whose name contains "download"
LUA=lua5.2 tests/run.sh              # the Lua version VLC 3 embeds
```

The extension is loaded unmodified and driven through its dialog: tests fill
in fields, pick drop-down entries and click buttons, then look at the bytes
that reached the "network" and at what the window shows.

- `lib/mock_vlc.lua` — the `vlc` API as VLC 3.0 really behaves (see
  `docs/vlc-lua-environment.md`). Sockets, `poll`, `vlc.stream` and dialogs
  have the same limits as the real ones, so code that would hang or crash in
  VLC fails here.
- `lib/fake_api.lua` — api.opensubtitles.com and the other hosts. Enforces the
  real API's rules (Api-Key, User-Agent, canonical query → 301, Bearer token).
- `fixtures/raw/*.http` — byte-exact recordings of the live API
  (`curl -i --raw`), including chunked encoding. Re-record with
  `tests/fixtures/record.sh` if the API changes.
- `lib/harness.lua` — `describe` / `it` / `known_bug`, `H.launch{...}`.
- `spec/*_spec.lua` — the tests.

### Known bugs

`known_bug(name, why, fn)` asserts the **correct** behaviour for a defect that
exists today. The runner lists it as `known bug` and the suite stays green.
When the defect is fixed the test passes and the runner fails with `FIXED?`
until `known_bug` is changed to `it` — so the list cannot go stale.

```bash
lua tests/run_tests.lua | grep -A1 "^known bug"
```

### Writing a test

```lua
it("season and episode are sent for TV searches", function()
  local env = H.launch({ config = { language = "en" } })   -- starts the extension
  local d = env.ui()                                        -- the open window
  d:_at(2, 1, "text_input"):set_text("Breaking Bad")        -- title field (col 2, row 1)
  d:_at(2, 2, "text_input"):set_text("2")
  d:_button("Search$"):_click()
  local req = env.server:last("GET api.opensubtitles.com/api/v1/subtitles")
  eq(req.query.season_number, "2")
  ok(#env.results().values > 1, "results are listed")
end)
```

`H.launch` options: `media` (URI being played), `login = false`, `config`
(saved options), `first_run = true`, `offline = true`, `server` (fake API
options or a prepared server), `env` / `popen` (environment and shell commands
seen by locale detection), `files` (pre-existing cache files).

Methods starting with `_` (`_click`, `_choose_text`, `_select`, `_at`, …) are
test helpers; everything else on a widget is VLC's real API.

## 2. Inside real VLC — `tests/vlc/run.sh`

```bash
tests/vlc/run.sh
tests/vlc/run.sh -v      # also every request, warning and error, with timings
tests/vlc/run.sh -vv     # everything the extension logs + VLC's own Lua messages
VLSUB_USER=you VLSUB_PASS=secret tests/vlc/run.sh      # adds login + download
```

Progress is printed while VLC runs, so a slow step is visible as it happens.

Starts VLC without a window (`-I luaintf`), loads `vlsubcom.lua` into VLC's own
Lua and runs activate → search by name → search by IMDb id → multi-language
search (→ login → download). Sockets, TLS, URL parsing, JSON and the Lua
version are VLC's; only the dialog is simulated, because VLC creates dialogs
only from its GUI. Settings and downloads go to a temporary folder.

The report starts with an environment section (VLC and Lua versions, which
`vlc.*` names exist, how `connect_tcp` reports failure). If VLC freezes, the
script kills it after `VLSUB_TIMEOUT` seconds (default 120) and the last `RUN`
line names the step that hung.

## 3. In the GUI — `tools/dev.sh`

```bash
tools/dev.sh link      # VLC loads this checkout (symlink); `install` copies instead
tools/dev.sh run ~/Movies/some.mkv
tools/dev.sh errors    # Lua errors from that run, exit code 1 if any
tools/dev.sh restore   # back to what was installed before
```
