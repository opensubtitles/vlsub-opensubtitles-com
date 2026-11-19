# Refactor log (branch `dev`)

Progress against `docs/refactor-brief.md`. Line counts are `wc -l vlsubcom.lua`.

| Stage | Lines after | Behaviour diff |
|---|---|---|
| start (v1.3.2) | 9,173 | - |
| 0 behaviour diff tool | 9,173 | identical (90 sessions) |
| 1 dead code | 7,695 | identical |
| 2 logging | 7,272 | identical |
| 3 duplication | 7,017 | identical |
| 4 long functions | 6,686 | identical (96 sessions) |
| 5 data tables | 6,690 | identical |
| 6 config file | 6,692 | identical apart from the agreed config content |
| phase 2 step 1: strings table | 6,875 | identical |

State when the goal was reached: 6,875 lines (was 9,173, -25%). The last step adds lines on
purpose: 262 inline texts became 242 entries of the strings table.

Verified at the end on Lua 5.1, 5.2, 5.4 and 5.5: 205 tests (203 pass, 2
known bugs), luacheck clean, behaviour diff identical for all 96 sessions
(538 recorded steps); and `tests/vlc/run.sh` inside VLC 3.0.16.

## Stage 0 - behaviour diff tool

`tests/behaviour/`: `baseline/vlsubcom.lua` is the frozen v1.3.2 file,
`sessions.lua` holds 90 scripted sessions, `run.lua` records and compares.
Proved against 7 deliberate changes (message text, request parameter, header,
widget position, file suffix, file permissions, error log line); a debug-only
change is correctly not reported.

Bugs noticed and left alone (now `known_bug` tests):

- a search answer that is valid JSON but not an object (`true`, `1`,
  `"text"`) raises a Lua error
- a `/download` answer of the same kind raises a Lua error

## Stage 1 - dead code (9,173 -> 7,695 lines)

Removed, each after checking it has no caller, is not a VLC or button
callback and is not reached through a table or a string name:

- 15 unused functions: `test_headers`, `is_auto_search_enabled`,
  `get_install_instructions`, `add_update_button_to_config`,
  `force_config_until_authenticated`, `set_default_option`, `warning_tag`,
  `info_tag`, `download_tag`, `make_uri`, `trigger_action`,
  `show_auth_error_with_config_button`, `check_login_clicked`, `escape`,
  `openSub.logoutRestAPI`
- XML-RPC client: `openSub.request`, `getMethodBase`, `methods`,
  `checkSessionOLD`, `searchIMBD`, `parse_xmlrpc`, `dump_xml`
- legacy socket HTTP client: `get`, `http_req`, `http_req_once`,
  `parse_header`, `ui_yield_if_needed`, `safe_mwait`
- interface translations: `load_transl`, `apply_translation`,
  `set_translation`, `get_available_translations`, `parse_xml`, the `locale/`
  scan in `check_config`, options `intLang` and `translations_avail`,
  `list_dir`, `handle_temp_config_click`
- curl leftovers, 25 lines of commented-out code, the 45-line bettervlsub
  comparison comment, stale curl mentions in the file header

Tests removed with the code they tested: legacy socket client (3),
`parse_header`, `list_dir`. Suite: 199 tests.

Old config files containing `translation`, `translations_avail` or `intLang`
still load; those keys are skipped.

## Stage 2 - logging (7,695 -> 7,272 lines)

- One helper, `dbg(message)`. The hidden `debugLogging` config key is gone:
  VLC's verbosity (Tools > Messages, level 2) decides whether debug lines are
  shown. 63 `if debugLogging` blocks unwrapped.
- All 294 debug statements reviewed; 169 removed, 4 dumps of values deleted.
  Kept: failures, and one line per decision that explains an outcome.
- Removed lines that could expose data: header values copied into the URL of
  https requests, the rebuilt URL containing them, the first 500 bytes of a
  response body, the masked login response.
- Unchanged: the request lines (`[VLSub] GET http://...`), every warning and
  error.

## Stage 3 - duplication (7,272 -> 7,017 lines)

- Name, IMDb and hash search share `search_begin`, `search_get`,
  `search_results`. Each keeps its own status handling, because the messages
  and error-log lines differ between them and are frozen behaviour.
- `has_results` / `has_no_results` replace six copies of the same check.
- `getSelectedLanguages` is built on `getUserSelectedLanguages`.
- `searchHash`: its three copies of the name-search fallback share
  `prepare_name_fallback`.
- `map_to_opensubtitles_language`: 105 entries mapped a code to itself; the
  four real mappings remain.

## Stage 4 - long functions (7,017 -> 6,686 lines)

| Function | Before | Now |
|---|---|---|
| `downloadFromNewAPI` | 232 lines | flow + `download_failed`, `fetch_subtitle`, `quota_text`, a status table |
| `activate` | 255 | sequence of steps; three reporters replace 25 first-run guards; `apply_detected_languages` |
| `analyze_detected_locales` | 328 | two tables moved to file level, `tally` helper, decision logic alone |
| `detect_unix_locale` | 189 | `shell_output`, `read_assignments`, timezone table at file level |

Sessions added first, checked against the baseline: locale from `/etc/*`
files, from files in the home directory, from installed locales / timezone /
`printenv`, and three Windows-flavoured sessions.

## Stage 5 - data tables

Duplicate keys removed from the IP-country table and the macOS timezone
table (in Lua the last entry wins, so nothing changes). The surprising
surviving values are in `docs/refactor-open-questions.md`.

## Stage 6 - config file

The interface strings were part of the options table and so were written
into `vlsub_conf.json` on every save (about 9 kB). They are a table of their
own now; the file holds the settings only (about 300 bytes). Settings no code
reads (`showMediaInformation`, `requestTimeoutMs`, `requestPollIntervalMs`,
`requestMaxRetries`, `debugLogging`) are no longer written and disappear from
an existing file on its next save.

Files written by 1.3.2 load. One consequence: the interface strings stored in
an old file are ignored. 1.3.2 let that saved copy override the built-in
text, so reworded strings never reached people who upgraded.

## Phase 2, step 1 - strings table

262 inline string literals (status messages, labels, buttons, first-run
progress lines, update and error dialogs, status-to-message tables) moved
into the strings table as 242 `ui_*` keys, by script. 21 strings nothing
referenced were removed. `tests/spec/08_strings_spec.lua` checks that every
key used is defined, no key is duplicated, every value is a non-empty string
and no text is written inline in message or label calls.

Not yet suitable for translators as is: texts with a variable part are split
into fragments (`"Login failed with status: " .. status`), which fixes the
word order. Phase 2 step 2 should turn those into format strings.

## After the goal: leftovers and translation groundwork (6,875 -> 6,770 lines)

Done while the refactor was waiting for a test on macOS; same rules, behaviour
diff identical throughout.

- `saveAndLoadSubtitle` split into `subtitle_file_name`, `choose_save_target`
  and the saving itself; one `report_failure` helper for "log, show, return
  false".
- `checkLoginAndUserInfo`, `display_select` tidied; a few unused variables
  removed.
- **Correction to the strings step.** The scripted move had also taken eight
  literals that are not text: the window ids `"main"` and `"config"` (used in
  comparisons), HTML fragments, two install commands and a file path. Output
  was unchanged, but translating `"main"` would have broken the help window's
  back button. They are literals again and a test keeps identifiers, markup,
  commands and paths out of the table.
- **Sentences instead of fragments.** 25 messages that were glued together
  around a value, or split only because the source line was long, are single
  strings with `%s` now, filled in by `tr(key, ...)`. Tests check that every
  `tr()` key exists and gets as many values as its pattern has placeholders.
  Messages of the form "label: value" are still label + value.
- **`locale/`** (data only, the script does not load it yet):
  `en.json` generated from the script, `index.json`, `README.md` with the
  rules for translators, and `sk.json` - Slovak, 270 of 271 strings, machine
  translated and marked `review`.
  `tests/spec/09_locale_spec.lua` validates every translation file (known
  keys, placeholders, HTML tags, edge spaces) and runs the extension with the
  translation put into the strings table: all windows, a search, a download
  and a first run, without errors.
- The original VLSub's 22 human translations were not imported: only 28 of
  today's 271 strings still have the same English text.

Still to do for phase 2: the language drop-down, fetching `locale/<code>.json`
on demand, storing it, the per-key English fallback (steps 3-5 of the brief).

## Windows-only code touched (needs a check on a real Windows machine)

The Windows branches were left structurally alone. What changed in them:

- `detect_windows_locale`: debug lines removed; nothing else.
- `mkdir_p` (Windows branch): one debug line removed.
- `show_dkjson_error_dialog`, `show_update_dialog`: their texts now come from
  the strings table (same text).
- `get_downloads_folder`, `is_first_run`, `is_window_path`, `is_win_safe`,
  path handling in `getFileInfo`: not touched.
- `restrict_to_owner` does nothing on Windows (unchanged since 1.3.2).

The three Windows-flavoured behaviour sessions run these branches on Unix
with VLC reporting Windows directories; they are identical to v1.3.2. They
cannot show how a real Windows file system or `cmd.exe` behaves.

## Left for later (not done, to stay safe)

- `apply_config`, `saveAndLoadSubtitle`, `getMovieHash`, `getFileInfo`,
  `checkLoginAndUserInfo` are still long (120-160 lines each).
- About 20 unused local variables reported by luacheck.
- `lang[...]` (old keys) and `strings.x` (new keys) are two spellings for the
  same table; unifying them needs care because several functions have a
  local variable called `lang`.

## Found in the test tooling along the way

- The mock's `vlc.io.open` captured the harness's per-launch `io.open`
  wrapper, chaining every sandbox to the previous one. Memory grew with each
  session and the extension's own `collectgarbage()` calls made a full run
  four times slower (110 s instead of 25 s). Fixed in `tests/lib/mock_vlc.lua`.
- Lua 5.1/5.2 put the variable name in a different place in error messages
  than 5.3+; the diff tool now normalises both forms.
