# Refactor brief (branch `dev`)

Goal: make `vlsubcom.lua` as small and simple as is safe, **without changing
behaviour**. There is no line-count target: stop cutting where safety ends.

Starting point: v1.3.2, 9,173 lines.

## Hard rules

1. **Behaviour is frozen at v1.3.2.** Same windows, same widgets in the same
   grid positions, same labels and messages, same API requests (method, URL,
   parameter order, headers, body), same subtitle files written (names,
   locations, content).
2. **Existing user files keep loading**: `vlsub_conf.json`,
   `session_cache.json`, the language and GuessIt caches of someone upgrading
   from 1.3.2 must work unchanged.
3. VLC entry points keep their names and signatures: `descriptor`, `activate`,
   `deactivate`, `close`, `menu`, `trigger_menu`, `input_changed`,
   `meta_changed`.
4. One file. Runs on Lua 5.1, 5.2 and 5.4; compiles on 5.5. Only the VLC API
   described in `docs/vlc-lua-environment.md`.
5. Do not touch: the User-Agent string, the API key, the plain-HTTP API URLs,
   canonical query building, `socket_exchange`'s connect/poll/deadline logic.
6. No new features, no improvements, no bug fixes mixed in. A bug found on the
   way becomes a `known_bug` test; the behaviour stays as it is.
7. Windows-only branches (path handling, `USERPROFILE`, registry / `wmic`
   locale detection) cannot be run here. Change them as little as possible and
   list every one that was touched for a manual check on Windows before any
   release.

## Agreed exceptions to "frozen"

These are the only intended differences from v1.3.2. The behaviour diff must
show them and nothing else.

- **Debug log content.** Fewer debug lines (see stage 2). Error and warning
  lines and the one-line-per-request log stay.
- **`vlsub_conf.json` content.** Only real settings are written; the table of
  interface strings and the list of available translations are no longer
  dumped into it. Files written by 1.3.2 still load.
- **Interface-translation machinery is removed.** In 1.3.2 it is unreachable:
  the configuration window has no interface-language control, the download
  points at a dead `addons.videolan.org` URL, and the only way to trigger it is
  to hand-edit `intLang` in the config and place an XML file in `locale/`.
  The built-in English strings stay. A config that still contains `intLang`
  or a `translation` table loads without error and those keys are ignored.

## Stage 0 - behaviour diff tool (before any refactoring)

Build `tests/behaviour/`: runs the same scripted sessions against two copies of
the extension (v1.3.2 from git, and the working tree) and compares, per
session:

- every request: method, host, path, raw query, headers, body, in order
- every window: title, each widget's kind, position, text, drop-down and list
  entries
- the status message after each action
- every file written in the sandbox: name, content, permissions
- VLC calls: subtitles added, config values set, error-level log lines

Sessions: first run on several locales; first run offline; subsequent run; all
three search types including hash fallback, multi-language, sorting,
season/episode; each API error status; login ok / wrong / none; token
rejected; every configuration save path; download (next to video, Downloads
fallback, manual mode, quota, invalid file id); media change; update
available.

Output is `identical` or a readable diff. The agreed exceptions above are
declared in one place in the tool, each with its reason, so anything else that
differs fails. Wired into `tests/run.sh` and CI.

Prove the tool works: introduce a deliberate one-character change in a message
and in a request parameter and see both reported.

## Method

- Tests first: before removing or merging code, make sure a test or a diff
  session exercises it. If none does, add one against the current code, see it
  pass, then refactor.
- Small steps, one kind of change per commit. After each: `tests/run.sh` on Lua
  5.1 / 5.2 / 5.4 / 5.5, the behaviour diff, and `tests/vlc/run.sh` in real VLC
  must pass.
- Before deleting a function as unused, prove it: no caller, not a VLC
  callback, not a button callback, not reached through a table lookup or a
  string name.

## Stages

1. **Dead code**: XML-RPC client and methods; the legacy `http_req` client;
   curl leftovers; the interface-translation machinery; functions and
   variables nothing uses; commented-out code; the bettervlsub comparison
   essay.
2. **Logging**: one debug helper instead of the `if debugLogging` blocks.
   - Keep: one line per API request; every error and warning; one line per
     decision that explains an outcome (which search ran and why it fell back,
     where a file was saved and why, which locale was detected from which
     source, login versus session reuse).
   - Remove: banners, step-by-step narration, dumps of values, lines that
     repeat what the next line says.
   - Never log request or response bodies, passwords or tokens.
3. **Duplication**: one search-request function behind name / hash / IMDb; one
   language-selection helper; one "has results" helper; one status-to-message
   mapping.
4. **Long functions**: split `activate`, `analyze_detected_locales`,
   `downloadFromNewAPI`, `detect_unix_locale` into named steps. Same order of
   operations, same side effects.
5. **Data tables**: remove duplicate entries, keep every distinct one.
6. **Config file**: write only real settings (second agreed exception).

## Report after each stage

Lines before and after, what was removed, tests and sessions added, bugs
noticed and left alone.

**Unattended rule.** Anything outside the agreed exceptions that could change
what a user sees or what is sent to the API is **not done**: leave that code
as it is, add an entry to `docs/refactor-open-questions.md` (what, where, why
it was left, what the options are) and continue with the rest. Do not stop to
ask, and do not decide it alone.

## Done when

- all tests are green on every Lua version and in real VLC, luacheck is clean
- the behaviour diff against v1.3.2 reports `identical` for every session,
  apart from the agreed exceptions
- the list of touched Windows-only code is written down

Work stays on `dev`. No merge to `main` and no release without an explicit
instruction.

## Phase 2 - interface translations (after the refactor is verified)

Separate from the refactor on purpose: the refactor must be provably
behaviour-neutral, and translations are a visible feature. Phase 2 starts only
when the "Done when" list above is met.

Facts (checked 2026-11-19):

- The strings table has 63 keys. About 30 more messages are hard-coded in
  English outside it.
- The original VLSub project (`exebetche/vlsub`, which this extension derives
  from) has human translations of the old keys in 22 languages
  (`locale/*.xml`): baq cze dan dut ell eng fin fre ger heb hun ita pob pol por
  rum scc slo spa swe tur ukr. Strings added since then exist in English only.

Steps, each one safe on its own:

1. **Move the hard-coded messages into the strings table.** English output
   stays byte-identical, so the behaviour diff must still report `identical`.
   This step is neutral and may be done as the last stage of the refactor.
2. **Translations live in the repository, not in the script**: one file per
   language, `locale/<code>.json`, a flat `{"key": "text"}` object. The script
   ships English only and stays small; a translation can be added or corrected
   without releasing a new version.
3. **Download on demand.** When the user picks a language, the script fetches
   `https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/locale/<code>.json`
   with `vlc.stream` (HTTPS GET without headers is exactly what it can do;
   measured in VLC 3.0.16: 260 ms, and a missing file comes back as a clean
   `nil`) and stores it in `<userdata>/vlsub.com/locale/`. Later starts read
   the stored copy; it is refreshed at most once a week, in the same place the
   update check already runs.
4. **Never trust the file, never block startup.**
   - Only keys that exist in the English table are accepted, values must be
     strings of sane length, and the HTML tags and placeholders must match the
     English string; anything else is dropped and English is used for that key.
   - A string missing in a language falls back to English, per key, so an
     incomplete or broken translation can never give an empty label or a crash.
   - No download at startup and none on first run: `vlc.stream` cannot be timed
     out. The fetch happens only on the Save click that changed the language,
     and on the weekly refresh. If it fails the interface stays as it was and a
     message says so.
5. **Choosing the language**: an "Interface language" drop-down in the
   configuration window: `English` plus the languages listed in
   `locale/index.json` (bundled list as fallback), and `Auto` (use the system
   language if a translation exists). Existing installs stay on `English`
   until the user changes it; new installs get `Auto`.
6. **Content**: start from the human translations of the original VLSub
   project (GPL, reuse approved) for the old keys. Newer strings are
   machine-translated and listed per language in `locale/README.md` as
   unreviewed; a language appears in `index.json` only after someone has read
   it through. `locale/README.md` explains how to contribute a translation.
7. **Tests**: every `locale/*.json` parses, contains only known keys, and has
   matching tags and placeholders (run in CI, so a bad translation cannot be
   merged); every window builds in every language with no nil or empty label;
   a hostile file (unknown keys, non-strings, injected HTML, 1 MB of text) is
   neutralised; download failure leaves the interface unchanged; switching
   language and back restores English exactly; with English selected the
   behaviour diff is still `identical`; `tests/vlc/run.sh` fetches one real
   translation inside VLC.

Decided 2026-11-19: translations are hosted in the repository and downloaded
on demand; existing installs stay English, new installs use Auto; only
reviewed languages are listed; reuse of the original VLSub translations is
fine (GPL).
