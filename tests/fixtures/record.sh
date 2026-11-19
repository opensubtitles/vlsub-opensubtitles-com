#!/bin/sh
# Re-record tests/fixtures/raw/*.http from the live API (byte-exact, including
# chunked transfer encoding). Run from anywhere; needs curl and python3.
# The API allows 5 requests per second, hence the pauses.
set -eu
cd "$(dirname "$0")/../.."
KEY=$(grep -o 'api_key = "[^"]*"' vlsubcom.lua | cut -d'"' -f2)
VERSION=$(grep -o 'local app_version = "[^"]*"' vlsubcom.lua | cut -d'"' -f2)
UA="VLSub OpenSubtitles.com v$VERSION"
API=http://api.opensubtitles.com/api/v1
OUT=tests/fixtures/raw
mkdir -p "$OUT"

rec() {
  name=$1; shift
  curl -s -i --raw --http1.1 -m 30 -H "Api-Key: $KEY" -H "User-Agent: $UA" \
       -H "Accept: */*" -H "Connection: close" "$@" > "$OUT/$name.http"
  printf '%-22s %s\n' "$name" "$(head -1 "$OUT/$name.http" | tr -d '\r')"
  sleep 1
}

rec languages         "$API/infos/languages"
rec search_name_en    "$API/subtitles?languages=en&query=big+buck+bunny"
rec search_name_multi "$API/subtitles?languages=en,fr,sk&query=big+buck+bunny"
rec search_imdb       "$API/subtitles?imdb_id=1254207&languages=en"
rec search_hash       "$API/subtitles?languages=en&moviebytesize=12909756&moviehash=8e245d9679d31e12"
rec search_episode    "$API/subtitles?episode_number=5&languages=en&query=breaking+bad&season_number=2"
rec search_none       "$API/subtitles?languages=en&query=zzzqqxxnoresultsxx12345"
rec search_unsorted   "$API/subtitles?query=big+buck+bunny&languages=en"
rec guessit           "$API/utilities/guessit?filename=Breaking.Bad.S02E05.720p.BluRay.x264-DEMAND.mkv"
rec login_bad         -X POST -H "Content-Type: application/json" \
                      -d '{"username":"vlsub_test_nonexistent_user","password":"wrong"}' "$API/login"
rec download_noauth   -X POST -H "Content-Type: application/json" -d '{"file_id":1}' "$API/download"
# rate_limited.http (429) is kept from an earlier burst; record one by removing the sleep.

# Keep only the headers the tests care about (drops cookies, CDN ids, ...).
python3 - <<'PY'
import glob, re
keep = re.compile(rb'^(content-type|transfer-encoding|content-length|connection|location|'
                  rb'retry-after|ratelimit-[a-z]+|x-ratelimit-[a-z-]+|date):', re.I)
for f in glob.glob('tests/fixtures/raw/*.http'):
    head, body = open(f, 'rb').read().split(b'\r\n\r\n', 1)
    lines = head.split(b'\r\n')
    out = [lines[0]] + [l for l in lines[1:] if keep.match(l)]
    open(f, 'wb').write(b'\r\n'.join(out) + b'\r\n\r\n' + body)
PY
echo "done - run tests/run.sh; counts in the specs may need updating"
