#!/bin/sh
# Developer helper for trying the working copy in a real VLC (macOS / Linux).
#
#   tools/dev.sh link        use this checkout as the installed extension (symlink)
#   tools/dev.sh install     copy vlsubcom.lua into VLC instead of linking
#   tools/dev.sh run [file]  start VLC with a debug log, optionally playing a file
#   tools/dev.sh errors      show VLSub's Lua errors from the last run (exit 1 if any)
#   tools/dev.sh requests    list the API requests made during the last run
#   tools/dev.sh log         follow the VLSub lines of the log (Ctrl-C to stop)
#   tools/dev.sh test        offline test suite (tests/run.sh)
#   tools/dev.sh realvlc [-v|-vv]  run the extension headless inside VLC against the
#                            live API; -v shows each request, -vv everything
#   tools/dev.sh restore     put back the extension that was installed before
#   tools/dev.sh status      show what VLC will load
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vlsubcom.lua"
LOG="${VLSUB_LOG:-${TMPDIR:-/tmp}/vlsub-vlc.log}"

case "$(uname -s)" in
  Darwin)
    VLC="${VLC:-/Applications/VLC.app/Contents/MacOS/VLC}"
    EXT_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
    ;;
  *)
    VLC="${VLC:-$(command -v vlc || true)}"
    EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/vlc/lua/extensions"
    ;;
esac
DEST="$EXT_DIR/vlsubcom.lua"
BACKUP="$EXT_DIR/vlsubcom.lua.before-dev"

backup() {
  # Keep the first non-dev copy we find, once.
  if [ -f "$DEST" ] && [ ! -L "$DEST" ] && [ ! -e "$BACKUP" ]; then
    cp "$DEST" "$BACKUP"
    echo "saved the installed extension as $BACKUP"
  fi
}

case "${1:-help}" in
  link)
    mkdir -p "$EXT_DIR"
    backup
    rm -f "$DEST"
    ln -s "$SRC" "$DEST"
    echo "linked: $DEST -> $SRC"
    echo "Restart VLC to load changes (VLC reads extensions at start)."
    ;;
  install)
    mkdir -p "$EXT_DIR"
    backup
    rm -f "$DEST"
    cp "$SRC" "$DEST"
    echo "copied to $DEST ($(grep -o 'local app_version = "[^"]*"' "$SRC"))"
    echo "Restart VLC to load it."
    ;;
  restore)
    if [ -e "$BACKUP" ]; then
      rm -f "$DEST"
      mv "$BACKUP" "$DEST"
      echo "restored $DEST"
    else
      echo "no backup at $BACKUP - nothing changed"
    fi
    ;;
  status)
    if [ -L "$DEST" ]; then
      echo "VLC loads: $DEST -> $(readlink "$DEST")"
    elif [ -f "$DEST" ]; then
      echo "VLC loads a copy: $DEST ($(grep -o 'local app_version = "[^"]*"' "$DEST"))"
      cmp -s "$DEST" "$SRC" && echo "identical to this checkout" || echo "DIFFERS from this checkout"
    else
      echo "not installed: $DEST"
    fi
    echo "branch: $(git -C "$ROOT" rev-parse --abbrev-ref HEAD) @ $(git -C "$ROOT" rev-parse --short HEAD)"
    ;;
  run)
    shift
    [ -x "$VLC" ] || { echo "VLC not found, set VLC=/path/to/vlc" >&2; exit 2; }
    : > "$LOG"
    echo "VLC log: $LOG   (tools/dev.sh errors | tools/dev.sh log)"
    echo "Open the extension from the menu: VLC > Extensions (macOS) / View (Linux, Windows)."
    exec "$VLC" --verbose=2 --file-logging --logfile="$LOG" "$@"
    ;;
  errors)
    [ -f "$LOG" ] || { echo "no log yet - start VLC with: tools/dev.sh run"; exit 1; }
    # What a Lua failure looks like in VLC's log. The extension's own
    # "[VLSub] GET http://..." lines are logged at warning level too and are
    # not errors, so "lua warning" alone is not a match.
    PATTERN='Error while running script|Error loading script|attempt to |stack traceback|Could not translate|Could not activate|lua[a-z ]* error'
    OURS="$(grep -n -i -E "$PATTERN" "$LOG" | grep -i "vlsub" || true)"
    OTHERS="$(grep -n -i -E "$PATTERN" "$LOG" | grep -v -i "vlsub" || true)"
    REQUESTS="$(grep -c -E "\[VLSub\] (GET|POST|PUT|DELETE) " "$LOG" || true)"
    if [ -n "$OTHERS" ]; then
      echo "Not VLSub (other scripts in VLC's folders) - ignore or clean up:"
      echo "$OTHERS" | sed 's/^/  /'
      echo
    fi
    if [ -n "$OURS" ]; then
      echo "VLSub Lua errors:"
      echo "$OURS" | sed 's/^/  /'
      exit 1
    fi
    echo "no VLSub Lua errors in $LOG ($REQUESTS API requests logged; see them with: tools/dev.sh requests)"
    ;;
  requests)
    [ -f "$LOG" ] || { echo "no log yet - start VLC with: tools/dev.sh run"; exit 1; }
    grep -E "\[VLSub\] (GET|POST|PUT|DELETE) " "$LOG" | sed 's/.*\[VLSub\] //' | cut -c1-160
    ;;
  log)
    [ -f "$LOG" ] || { echo "no log yet - start VLC with: tools/dev.sh run"; exit 1; }
    tail -f "$LOG" | grep --line-buffered -i -E "vlsub|lua"
    ;;
  test)
    exec "$ROOT/tests/run.sh"
    ;;
  realvlc)
    shift
    exec "$ROOT/tests/vlc/run.sh" "$@"
    ;;
  *)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
