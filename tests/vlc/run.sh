#!/bin/sh
# Run the extension inside a real, headless VLC against the live API.
#
#   tests/vlc/run.sh                         search only (no account needed)
#   VLSUB_USER=me VLSUB_PASS=secret tests/vlc/run.sh     + login and download
#   VLC=/path/to/vlc tests/vlc/run.sh        use a specific VLC binary
#   tests/vlc/run.sh -v                      also show every request, warning and error
#   tests/vlc/run.sh -vv                     everything the extension logs (debug on),
#                                            plus VLC's own Lua messages at the end
#
# Progress is printed while VLC runs.
#
# Nothing of yours is touched: settings, caches and the downloaded subtitle go
# to a temporary folder. One file is copied into VLC's user script folder
# (lua/intf/vlsub_realvlc.lua) and removed again afterwards.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERBOSE="${VLSUB_VERBOSE:-0}"
for arg in "$@"; do
  case "$arg" in
    -v) VERBOSE=1 ;;
    -vv) VERBOSE=2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
TIMEOUT="${VLSUB_TIMEOUT:-120}"

case "$(uname -s)" in
  Darwin)
    VLC="${VLC:-/Applications/VLC.app/Contents/MacOS/VLC}"
    USERDIR="$HOME/Library/Application Support/org.videolan.vlc"
    ;;
  *)
    VLC="${VLC:-$(command -v vlc || command -v cvlc || true)}"
    USERDIR="${XDG_DATA_HOME:-$HOME/.local/share}/vlc"
    ;;
esac

if [ -z "$VLC" ] || [ ! -x "$VLC" ]; then
  echo "VLC not found. Set VLC=/path/to/vlc" >&2
  exit 2
fi

SANDBOX="$(mktemp -d 2>/dev/null || mktemp -d -t vlsub)"
REPORT="$SANDBOX/report.txt"
INTF_DIR="$USERDIR/lua/intf"
INTF="$INTF_DIR/vlsub_realvlc.lua"
mkdir -p "$INTF_DIR"
cp "$ROOT/tests/vlc/vlsub_realvlc.lua" "$INTF"
TAIL_PID=""
trap '[ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null; rm -f "$INTF"; rm -rf "$SANDBOX"' EXIT

echo "VLC:      $VLC"
echo "checkout: $ROOT ($(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null))"
echo "timeout:  ${TIMEOUT}s   verbosity: $VERBOSE (-v, -vv for more)"
echo

# Translations are fetched from the repository. On a branch, fetch that
# branch's locale/ folder (it must be pushed); on main this is the real URL.
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
: "${VLSUB_LOCALE_URL:=https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/$BRANCH/locale/}"
export VLSUB_LOCALE_URL
echo "locale:   $VLSUB_LOCALE_URL"

VLC_FLAGS=""
[ "$VERBOSE" -ge 2 ] && VLC_FLAGS="--verbose=2"

: > "$REPORT"
VLSUB_ROOT="$ROOT" VLSUB_OUT="$REPORT" VLSUB_HOME="$SANDBOX/home" VLSUB_VERBOSE="$VERBOSE" \
  "$VLC" -I luaintf --lua-intf vlsub_realvlc --no-media-library $VLC_FLAGS \
  >"$SANDBOX/vlc.log" 2>&1 &
PID=$!

# Show the report as it is written, so a slow or hung step is visible live.
tail -f "$REPORT" 2>/dev/null &
TAIL_PID=$!

# Portable timeout (macOS has no `timeout`): VLC freezing is a result, not an error.
SECONDS_WAITED=0
while kill -0 "$PID" 2>/dev/null; do
  if [ "$SECONDS_WAITED" -ge "$TIMEOUT" ]; then
    kill -9 "$PID" 2>/dev/null || true
    HUNG=1
    break
  fi
  sleep 1
  SECONDS_WAITED=$((SECONDS_WAITED + 1))
done

sleep 1 # let tail print the last lines
kill "$TAIL_PID" 2>/dev/null || true
wait "$TAIL_PID" 2>/dev/null || true # reap it here so the shell prints no "Terminated"
TAIL_PID=""
if [ ! -s "$REPORT" ]; then
  echo "no report was written - VLC output follows:"
  tail -30 "$SANDBOX/vlc.log"
fi

if [ "${HUNG:-0}" = "1" ]; then
  echo
  echo "VLC DID NOT RETURN within ${TIMEOUT}s and was killed: the last RUN line above is where it hung."
  exit 1
fi
if grep -q "lua interface error" "$SANDBOX/vlc.log" 2>/dev/null || [ "$VERBOSE" -ge 2 ]; then
  echo
  echo "== VLC's own messages about Lua =="
  grep -i "lua" "$SANDBOX/vlc.log" | grep -v "\[VLSub\]\|\[VLsub\]" | tail -30
fi
grep -q "^ALL OK$" "$REPORT" 2>/dev/null
