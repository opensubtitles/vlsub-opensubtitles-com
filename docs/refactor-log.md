# Refactor log (branch `dev`)

Progress against `docs/refactor-brief.md`. Line counts are `wc -l vlsubcom.lua`.

| Stage | Lines after | Behaviour diff |
|---|---|---|
| start (v1.3.2) | 9,173 | - |
| 0 behaviour diff tool | 9,173 | identical (90 sessions, 509 steps) |
| 1 dead code | 7,695 | identical |

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
