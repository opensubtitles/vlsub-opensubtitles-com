#!/usr/bin/env python3
"""Upload round trip against the DEVELOPMENT API, the way VLSub packs a file.

  python3 tools/upload_roundtrip.py /tmp/out

Reads VLSUB_DEV_API_KEY, VLSUB_AI_USER, VLSUB_AI_PASS from ~/.vlsub-test.env
(an account with upload rank on the development server). Uploads a tiny
test subtitle to The Matrix (feature 163533), checks the duplicate answers,
lists "my uploads" and WITHDRAWS the upload again. Every answer is written
to the given folder (token masked) - that is where tests/fixtures/raw/
upload_*.http came from. Never point it at the production API.
"""
env = dict(l.strip().split('=', 1) for l in open(os.path.expanduser('~/.vlsub-test.env')) if '=' in l)
KEY, HOST = env['VLSUB_DEV_API_KEY'], 'rb-dev.ngrok.dev'
UA = 'VLSub OpenSubtitles.com v2.0.0'
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
token = None
def call(name, method, path, body=None, auth=True):
    h = {'Api-Key': KEY, 'User-Agent': UA, 'Accept': 'application/json', 'ngrok-skip-browser-warning': '1'}
    if body is not None: h['Content-Type'] = 'application/json'
    if auth and token: h['Authorization'] = 'Bearer ' + token
    c = http.client.HTTPSConnection(HOST, timeout=60)
    data = json.dumps(body).encode() if body is not None else None
    t = time.time(); c.request(method, '/api/v1' + path, body=data, headers=h); r = c.getresponse(); raw = r.read()
    txt = raw.decode('utf-8', 'replace')
    masked = re.sub(r'"token":"[^"]*"', '"token":"<TOKEN>"', txt)
    keep = [(k, v) for k, v in r.getheaders() if k.lower() in ('content-type', 'location', 'ratelimit-remaining', 'retry-after')]
    with open(os.path.join(OUT, name + '.http'), 'w') as f:
        f.write('HTTP/1.1 %d %s\r\n' % (r.status, r.reason) + ''.join('%s: %s\r\n' % kv for kv in keep) + 'Connection: close\r\n\r\n' + masked)
    print('%-22s %-6s %-40s %d %.2fs  %s' % (name, method, path[:40], r.status, time.time() - t, masked[:300].replace('\n', ' ')))
    time.sleep(1.2)
    try: return r.status, json.loads(txt)
    except Exception: return r.status, None

def stored_deflate(data):  # raw deflate, stored blocks only: what plain Lua can make
    out, i = b'', 0
    while True:
        chunk = data[i:i + 65535]; i += len(chunk); final = 1 if i >= len(data) else 0
        out += bytes([final]) + struct.pack('<HH', len(chunk), 0xFFFF ^ len(chunk)) + chunk
        if final: return out

st, j = call('login', 'POST', '/login', {'username': env['VLSUB_AI_USER'], 'password': env['VLSUB_AI_PASS']}, auth=False)
token = j['token']
stamp = time.strftime('%Y-%m-%d %H:%M:%S')
srt = ('1\r\n00:00:01,000 --> 00:00:04,000\r\nVLSub upload test %s\r\n\r\n'
       '2\r\n00:00:05,000 --> 00:00:08,000\r\nThis file is withdrawn right after the test.\r\n\r\n'
       '3\r\n00:00:09,000 --> 00:00:12,000\r\nThere is no spoon.\r\n' % stamp).encode()
md5 = hashlib.md5(srt).hexdigest()
packed = base64.b64encode(stored_deflate(srt)).decode()
print('file: %d bytes, md5 %s, packed %d chars' % (len(srt), md5, len(packed)))
call('guess', 'POST', '/subtitles/upload/guess', {'filename': 'The.Matrix.1999.1080p.BluRay.x264.mkv'})
fields = {'subhash': md5, 'subfilename': 'The.Matrix.1999.1080p.BluRay.x264.en.srt', 'sublanguageid': 'en', 'feature_id': 163533,
          'moviefilename': 'The.Matrix.1999.1080p.BluRay.x264.mkv', 'moviebytesize': 123456789, 'moviehash': '0123456789abcdef'}
call('check_new', 'POST', '/subtitles/upload/check', fields)
up = dict(fields, subcontent=packed, author_comments='VLSub API test - withdrawn right after')
st, j = call('upload', 'POST', '/subtitles/upload', up)
sid = j and j.get('subtitle_id')
call('check_known', 'POST', '/subtitles/upload/check', fields)
call('upload_duplicate', 'POST', '/subtitles/upload', up)
call('my_uploads', 'GET', '/my/uploads')
if sid:
    call('withdraw', 'DELETE', '/my/uploads/%s' % sid)
    call('my_uploads_after', 'GET', '/my/uploads')
