#!/bin/sh
# Developer helper for trying the working copy in a real VLC (macOS / Linux).
#
#   tools/dev.sh link        use this checkout as the installed extension (symlink)
#   tools/dev.sh install     copy vlsubcom.lua into VLC instead of linking
#   tools/dev.sh run [file]  start VLC with a debug log, optionally playing a file
#   tools/dev.sh errors      show VLSub's Lua errors from the last run (exit 1 if any)
#   tools/dev.sh requests    list the API requests made during the last run
#   tools/dev.sh log         follow the VLSub lines of the log (Ctrl-C to stop)
#   tools/dev.sh locale      interface translations: where they are fetched from, what
#                            the last run fetched, what is stored, what the config says
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
    # Translations come from the repository: on a branch, from that branch
    # (it must be pushed); the released extension reads them from main.
    BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
    : "${VLSUB_LOCALE_URL:=https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/$BRANCH/locale/}"
    export VLSUB_LOCALE_URL
    echo "Translations from: $VLSUB_LOCALE_URL"
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
  locale)
    BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
    URL="${VLSUB_LOCALE_URL:-https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/$BRANCH/locale/}"
    echo "== source (what 'tools/dev.sh run' uses): $URL"
    if command -v curl >/dev/null 2>&1; then
      echo "   index.json reachable: HTTP $(curl -s -o /dev/null -w '%{http_code}' "${URL}index.json")"
    fi
    echo "== locale requests in the last run ($LOG):"
    if [ -f "$LOG" ]; then
      grep -E "\[VLSub\].*locale/" "$LOG" | sed 's/.*\[VLSub\] //' | cut -c1-200 || true
      grep -c -E "\[VLSub\].*locale/" "$LOG" | sed 's/^/   count: /'
    else
      echo "   no log yet - start VLC with: tools/dev.sh run"
    fi
    echo "== VLSub folders (config and stored translations):"
    for base in "$HOME/Library/Application Support/org.videolan.vlc" "${XDG_DATA_HOME:-$HOME/.local/share}/vlc" "$HOME/.config/vlc"; do
      [ -d "$base" ] || continue
      find "$base" -type d -name "vlsub.com" 2>/dev/null | while IFS= read -r dir; do
        echo "   $dir"
        if [ -f "$dir/vlsub_conf.json" ]; then
          for key in interfaceLanguage detectedLanguage language; do
            printf '     %s = %s\n' "$key" "$(grep -o "\"$key\":\"[^\"]*\"" "$dir/vlsub_conf.json" | head -1 | cut -d: -f2)"
          done
        else
          echo "     no vlsub_conf.json"
        fi
        if [ -d "$dir/locale" ]; then
          ls -l "$dir/locale" | sed 's/^/     /'
          [ -f "$dir/locale/index.json" ] && echo "     languages in stored index: $(grep -o '"code"' "$dir/locale/index.json" | wc -l | tr -d ' ')"
        else
          echo "     no locale/ folder: nothing was stored yet"
        fi
      done
    done
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
