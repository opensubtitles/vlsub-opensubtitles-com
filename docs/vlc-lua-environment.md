# What a VLC extension can and cannot do

VLSub runs inside VLC's embedded Lua. That environment is much smaller than a
normal Lua installation, and several things behave differently from what the
function names suggest. Everything below was checked against the VLC 3.0.x
sources (`modules/lua/extension.c`, `modules/lua/libs/*.c`) and, where marked
**measured**, by running code inside VLC 3.0.16 (`tests/vlc/run.sh`).

The test suite encodes these rules: `tests/lib/mock_vlc.lua` behaves the same
way, and `tests/spec/01_vlc_environment_spec.lua` fails if the extension starts
using something that does not exist.

## Lua itself

- Lua **5.1** in the official macOS build (VLC 3.0.24, measured: `unpack`
  exists, `table.unpack` does not) and **5.2** in Debian/Ubuntu's VLC 3.0.16
  (measured). Code must run on both. Use nothing newer: no `utf8`, integer division, bitwise operators,
  `string.pack`, `table.move`, `goto`.
- Do not assign to a `for` loop variable (`for line in ... do line = ... end`).
  Lua 5.5 rejects it at compile time; copy it into a `local` first. CI runs
  the suite on 5.5 for this reason.
- The standard libraries are loaded (`io`, `os`, `string`, `table`, `math`,
  `debug`), including `io.popen` and `os.execute`. On Windows both flash a
  console window.
- `require` only finds modules shipped with VLC (`dkjson`, `simplexml`,
  `common`, `sandbox`). No LuaSocket, no LuaFileSystem, no LuaSec.
- A `local function` is visible only **below** its declaration. Calling it from
  code further up compiles and then fails at run time with
  `attempt to call global '...' (a nil value)`. `luacheck` catches this.
- A Lua error inside a callback does not crash VLC; it is logged as
  `lua generic warning: Error while running script` and the click is lost.

## The `vlc` table

Available to extensions: `config`, `dialog`, `input`, `msg`, `net`, `object`,
`osd`, `playlist`, `sd`, `stream`, `memory_stream`, `strings`, `var`, `video`,
`vlm`, `volume`, `xml`, `io` (3.0.2+), `errno`, `deactivate`, `keep_alive`,
`win` (Windows only).

**Not available**, although easy to assume:

| Name | Reality |
|---|---|
| `vlc.misc` (`mdate`, `mwait`, `version`) | interface scripts only; `nil` in extensions. There is no sleep and no clock except `os.time()` (seconds) and `os.clock()` (CPU time). |
| `vlc.net.connect_ssl` | does not exist. Raw sockets are plain TCP. |
| `vlc.net.mkdir`, `readdir`, `closedir` | do not exist. `vlc.net.opendir(path)` returns the list of names directly; `vlc.io.mkdir` exists. |
| `dialog:get_title()` | does not exist (only `set_title`). Track the open window yourself. |

## Networking: two tools, both limited

### `vlc.stream(url)` — GET only

- Speaks http and https, follows redirects, decodes chunked encoding.
- **Cannot** send a method, a header or a body. It sends
  `User-Agent: VLC/3.0.x LibVLC/3.0.x` (measured). No `Api-Key`, no
  `Authorization`, no POST.
- Returns `nil, "Error when opening stream"` for unreachable hosts and for HTTP
  404/500 (measured). You never see the status code.
- `s:read(n)` returns up to `n` bytes, `nil` at the end.
- No timeout control. A slow or half-open host blocks VLC's interface for as
  long as VLC's own timeout takes — 39 seconds measured for one unreachable
  host. Opening `https://api.opensubtitles.com/...` without a key did not
  return at all in VLC 3.0.16.

### `vlc.net.connect_tcp(host, port)` — raw plain-text socket

This is the only way to send headers or a body, so the extension carries its
own small HTTP/1.1 client (`VLCHttpClient`).

- Plain TCP only, so only `http://`. **This is why every API URL in the
  extension is `http://api.opensubtitles.com`.**
- The API serves plain HTTP **only** to a `User-Agent` that starts with
  `VLSub OpenSubtitles.com`; any other agent gets `301` to https, which an
  extension cannot follow with headers (measured against the live API).
  Do not change that string.
- `connect_tcp` returns a **positive descriptor even when the connection
  failed** (measured). `not fd` and `fd < 0` are both useless as checks. The
  failure shows as `vlc.net.send()` returning `-1` and `vlc.net.recv()`
  returning `nil`.
- `vlc.net.recv(fd, n)` returns `nil` at end of stream or on error, never `""`.
  Default length is 1 byte.
- `vlc.net.poll(fds)` **ignores any timeout argument** and blocks until a
  descriptor is ready. Polling a dead descriptor, or a server that keeps the
  connection open without sending, freezes VLC's interface until the user
  kills the extension (measured). Always send `Connection: close`, and never
  poll before checking that `send()` succeeded.
- The way out: poll for `POLLIN + POLLOUT`. A connected socket is always
  writable, so poll returns immediately (0.02 ms measured) and reports in the
  returned events whether there is something to read. That makes a wall-clock
  deadline possible; `socket_exchange()` in `vlsubcom.lua` does exactly this.
  The cost is a busy loop while waiting (there is no sleep in an extension).
- The `POLL*` constants differ per platform (on Windows `POLLIN` is two bits),
  so test them with the constants, never with literal numbers.
- `vlc.strings.url_parse("http://host")` returns `path = nil`, not `"/"`.

### OpenSubtitles API rules that bite

Confirmed against the live API on 2026-11-19:

- `/subtitles` answers `301` unless the query is canonical: parameters in
  alphabetical order, lower-case values, spaces as `+` (not `%20`), no leading
  zeros and no `tt` in ids. `%2C` for the comma in `languages` is accepted.
  The socket client does not follow redirects, so a non-canonical URL means
  "no results".
- 5 requests per second; beyond that `429` with a JSON body.
- `POST /download` with an unknown `file_id` answers `200`
  `{"message":"Invalid file_id"}` — a 200 without `link` is an error.
- Wrong credentials: `401` `{"message":"Error, invalid username/password", "status":401}`.

## Secrets

There is no keychain API and no cryptography in VLC's Lua, so the account
password in `vlsub_conf.json` and the token in `session_cache.json` cannot be
encrypted in any way that would resist someone who can read the extension.
What the extension does: both files are `chmod 600` on Unix/macOS, the
password only ever travels in a POST body, and neither the password nor the
token is written to VLC's log, even with debug logging on. Note that the API
is reached over plain HTTP (see above), so both are visible to the local
network.

## Files and dialogs

- Paths: the extension gets URIs (`file:///...`); decode with
  `vlc.strings.decode_uri`. Windows paths may contain non-ASCII characters
  that `io.open` cannot open.
- `add_value(text, id)` and `set_text(text)` raise if `text` is not a string.
  One `nil` in a list of languages is enough to stop a window from opening.
- A drop-down has no "set selection"; whatever is added first is shown as
  selected. `get_value()` returns the id of the selected entry.
- Dialogs are updated when the callback returns; call `dlg:update()` to show
  progress during a long operation. Everything runs on one thread: while a
  callback runs, VLC's interface does not respond.
