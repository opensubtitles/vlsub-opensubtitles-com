-- Uploading a subtitle (VLSub 2.0). Every answer of the API used here was
-- recorded from the development server (tests/fixtures/raw/upload_*.http,
-- tools/upload_roundtrip.py); nothing is invented.
--
-- Decided by the owner: an "Upload" button in the main window; the file is
-- one of the subtitle files next to the video, or any file by its path; a
-- missing film is registered from its IMDb id; flags and a comment can be
-- set; the video's hash goes with a file that sits next to the video.
local H = ...
local describe, it, eq, ok, has, lacks = H.describe, H.it, H.eq, H.ok, H.has, H.lacks
local api, json = H.fake_api, H.json

local API = "api.opensubtitles.com/api/v1"
local VIDEO = "The.Matrix.1999.1080p.BluRay.x264"
-- the Film line links to the film's IMDb page
local MATRIX_LINK = "<a href='https://www.imdb.com/title/tt0133093/'>The Matrix (1999)</a>"
local BUNNY_LINK = "<a href='https://www.imdb.com/title/tt1254207/'>Big Buck Bunny (2008)</a>"
-- a subtitle of the size the API accepts (at least 100 bytes)
local SRT = "1\r\n00:00:01,000 --> 00:00:04,000\r\nThere is no spoon.\r\n\r\n"
  .. "2\r\n00:00:05,000 --> 00:00:08,000\r\nThen you will see that it is not the spoon that bends.\r\n"

-- What the client sent, from the raw base64 / deflate it produced
local function base64_decode(text)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out, bits, count = {}, 0, 0
  for c in text:gmatch("[^=]") do
    bits = bits * 64 + (alphabet:find(c, 1, true) - 1)
    count = count + 6
    if count >= 8 then
      count = count - 8
      local byte = math.floor(bits / 2 ^ count)
      out[#out + 1] = string.char(byte)
      bits = bits - byte * 2 ^ count
    end
  end
  return table.concat(out)
end

-- inflate a raw deflate stream that has only stored blocks; errors otherwise
local function inflate_stored(data)
  local out, p = {}, 1
  while true do
    local header = data:byte(p)
    assert(header == 0 or header == 1, "not a stored block: " .. tostring(header))
    local n = data:byte(p + 1) + data:byte(p + 2) * 256
    local inverted = data:byte(p + 3) + data:byte(p + 4) * 256
    assert(n + inverted == 65535, "bad stored block length")
    out[#out + 1] = data:sub(p + 5, p + 4 + n)
    p = p + 5 + n
    if header == 1 then break end
  end
  assert(p == #data + 1, "trailing bytes after the last block")
  return table.concat(out)
end

local function md5_of(text)
  local path = H.tmpdir() .. "/md5.bin"
  H.write_file(path, text)
  local p = H.real_popen('md5sum "' .. path .. '" 2>/dev/null || md5 -q "' .. path .. '"')
  local line = p:read("*l") or ""
  p:close()
  return line:match("^(%x+)")
end

-- A video folder with subtitle files beside the video, and a server that
-- answers the upload calls with the recorded answers.
local function setup(o)
  o = o or {}
  local dir = H.tmpdir()
  if o.subtitles then -- name -> content, in place of the two below
    for name, content in pairs(o.subtitles) do H.write_file(dir .. "/" .. name, content) end
  else
    H.write_file(dir .. "/" .. VIDEO .. ".en.srt", o.content or SRT)
    H.write_file(dir .. "/" .. VIDEO .. ".sk.srt", SRT .. "\r\n3\r\n00:00:09,000 --> 00:00:10,000\r\nSk.\r\n")
  end
  H.write_file(dir .. "/Other.Film.2001.srt", SRT)
  H.write_file(dir .. "/" .. VIDEO .. ".nfo", "not a subtitle")
  local server = api.new()
  local sent = {}
  local function route(key, fixture)
    server:on(key, function(req)
      sent[#sent + 1] = { key = key, path = req.path, query = req.query, body = req.body and json.decode(req.body) or nil, raw = req.body,
                          auth = req.headers["authorization"], api_key = req.headers["api-key"] }
      return api.fixture(type(fixture) == "function" and fixture(req) or fixture)
    end)
  end
  route("POST " .. API .. "/subtitles/upload/guess", o.guess or "upload_guess")
  route("POST " .. API .. "/subtitles/upload/check", o.check or "upload_check_new")
  route("POST " .. API .. "/subtitles/upload", o.upload or "upload_upload")
  route("POST " .. API .. "/subtitles/upload/features/from_id", o.from_id or "upload_from_id_known")
  route("POST " .. API .. "/subtitles/upload/features/stub", o.stub or "upload_stub")
  route("GET " .. API .. "/features", o.features or "upload_features_none")
  -- titles the site does not have: imdb.opensubtitles.org (recorded answers)
  route("GET imdb.opensubtitles.org/search/query-*", o.imdb or "imdb_query_none")
  -- the language of a subtitle's text (production's fastText service)
  route("POST " .. API .. "/utilities/fasttext/language/detect", o.fasttext or "fasttext_unsure")
  if o.video then H.video(dir, VIDEO .. ".mkv", 300000) end
  local env = H.launch({ server = server, media = "file://" .. dir .. "/" .. VIDEO .. ".mkv", config = o.config })
  env.sent, env.dir_video = sent, dir
  return env
end

local function upload_window(env)
  env.server:reset()
  for i = #env.sent, 1, -1 do env.sent[i] = nil end
  trigger_menu(1)
  env.ui():_button("Upload$"):_click()
  local d = env.ui()
  return {
    dialog = d, file = d:_at(2, 1, "dropdown"), path = d:_at(2, 2, "text_input"),
    language = d:_at(2, 3, "dropdown"), film = d:_at(2, 4, "label"), imdb = d:_at(2, 5, "text_input"),
    season = d:_at(2, 6, "text_input"), episode = d:_at(3, 6, "text_input"),
    hi = d:_at(2, 7, "dropdown"), foreign = d:_at(2, 8, "dropdown"), translation = d:_at(2, 9, "dropdown"),
    release = d:_at(2, 10, "text_input"), comment = d:_at(2, 11, "text_input"),
    check = d:_button("Check$"), send = d:_at(2, 13, "button"), find = d:_button("Find$"),
  }
end

local function last(env, path)
  for i = #env.sent, 1, -1 do
    if env.sent[i].key:sub(-#path) == path then return env.sent[i] end
  end
end

describe("upload: packing the file", function()
  it("MD5 is right for the RFC 1321 test vectors and for a subtitle", function()
    H.launch({ activate = false })
    local md5_hex = H.find_local("md5_hex")
    eq(md5_hex(""), "d41d8cd98f00b204e9800998ecf8427e")
    eq(md5_hex("a"), "0cc175b9c0f1b6a831c399e269772661")
    eq(md5_hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
    eq(md5_hex("message digest"), "f96b697d7cb7938d525a2f31aaf161d0")
    eq(md5_hex("abcdefghijklmnopqrstuvwxyz"), "c3fcd3d76192e4007dfb496cca67e13b")
    eq(md5_hex(string.rep("1234567890", 8)), "57edf4a22be3c955ac49da2e2107b67a")
    eq(md5_hex(SRT), md5_of(SRT))
    local big = string.rep(SRT, 900) -- crosses many blocks
    eq(md5_hex(big), md5_of(big))
  end)

  it("base64 of a stored deflate stream gives the file back byte for byte", function()
    H.launch({ activate = false })
    local b64, deflate = H.find_local("base64_encode"), H.find_local("deflate_stored")
    for _, text in ipairs({ "", "x", SRT, string.rep(SRT, 1200) }) do -- the last spans two blocks
      eq(inflate_stored(base64_decode(b64(deflate(text)))), text, #text .. " bytes")
    end
    eq(b64("Man"), "TWFu")
    eq(b64("Ma"), "TWE=")
    eq(b64("M"), "TQ==")
  end)
end)

describe("upload: the window", function()
  it("without a login: a message in the main window, nothing asked of the server", function()
    local env = setup({ config = { os_username = "", os_password = "" } })
    trigger_menu(1)
    env.server:reset()
    env.ui():_button("Upload$"):_click()
    has(env.message(), "Log in to upload")
    eq(#env.sent, 0)
    has(env.ui().title, "v")
    lacks(env.ui().title, "Upload")
  end)

  it("lists the subtitle files next to the video, preselects the language from the name, finds the film", function()
    local env = setup()
    local w = upload_window(env)
    has(w.dialog.title, "Upload subtitles")
    eq(w.file:_texts(), { VIDEO .. ".en.srt", VIDEO .. ".sk.srt", "None" })
    eq(w.language:_texts()[1], "English")
    eq(w.film.text, MATRIX_LINK)
    eq(w.release:get_text(), VIDEO)
    eq(last(env, "/upload/guess").body, { filename = VIDEO .. ".mkv" })
    ok(last(env, "/upload/guess").auth, "logged in")
    eq(env.errors(), {})
  end)

  it("Check sends the file's MD5, name, language and film - not the file, not the video's hash", function()
    local env = setup()
    local w = upload_window(env)
    w.check:_click()
    local body = last(env, "/upload/check").body
    eq(body.subhash, md5_of(SRT))
    eq(body.subfilename, VIDEO .. ".en.srt")
    eq(body.sublanguageid, "en")
    eq(body.feature_id, 163533)
    eq(body.subcontent, nil)
    eq(body.moviehash, nil)
    eq(body.moviebytesize, nil)
    has(env.message(), "Ready: this subtitle can be uploaded (50 uploads left today)")
  end)

  it("Upload sends the file packed so that the server gets it back byte for byte", function()
    local env = setup()
    local w = upload_window(env)
    w.comment:set_text("synced to the BluRay")
    w.send:_click()
    local up = last(env, "/subtitles/upload")
    ok(up and up.key:find("/subtitles/upload$"), "the upload call")
    eq(inflate_stored(base64_decode(up.body.subcontent)), SRT)
    eq(up.body.subhash, md5_of(SRT))
    eq(up.body.author_comments, "synced to the BluRay")
    eq(up.body.release_name, VIDEO)
    eq(up.body.hearing_impaired, nil, "Automatic: left to the server")
    -- (recorded answer: download_url of the new subtitle's page, a link)
    has(env.message(), "Uploaded: <a href='https://rb-dev.ngrok.dev/subtitles/the-matrix-1999-1080p-bluray-x264-en'>"
      .. "The.Matrix.1999.1080p.BluRay.x264.en</a> - thank you!")
    for _, line in ipairs(env.vlc._messages()) do
      ok(not line:find(up.body.subcontent:sub(1, 40), 1, true), "file content in the log")
    end
  end)

  it("flags and translation choices are sent as the API names them", function()
    local env = setup()
    local w = upload_window(env)
    w.file:_choose_text("%.sk%.srt$")
    w.language:_choose_text("^Slovak$")
    w.hi:_choose_text("^Yes$")
    w.foreign:_choose_text("^No$")
    w.translation:_choose_text("^By AI$")
    w.check:_click()
    local body = last(env, "/upload/check").body
    eq(body.subfilename, VIDEO .. ".sk.srt")
    eq(body.sublanguageid, "sk")
    eq(body.hearing_impaired, true)
    eq(body.foreign_parts_only, false)
    eq(body.automatic_translation, true)
    eq(body.machine_translated, nil)
  end)

  it("a typed path wins over the list", function()
    local env = setup()
    local w = upload_window(env)
    w.path:set_text(env.dir_video .. "/Other.Film.2001.srt")
    w.check:_click()
    eq(last(env, "/upload/check").body.subfilename, "Other.Film.2001.srt")
  end)

  it("already on the site: Check and Upload both say so, with a link to that subtitle", function()
    -- recorded: check 200 already_in_db / upload 409, both duplicate_of
    -- 1193045; the film's English subtitles list it with its page
    local env = setup({ check = "upload_check_known", upload = "upload_upload_duplicate" })
    env.server:on("GET " .. API .. "/subtitles", function(req)
      env.sent[#env.sent + 1] = { key = "GET /subtitles", query = req.query }
      return api.fixture("upload_duplicate_search")
    end)
    local w = upload_window(env)
    local DUPLICATE = "already on OpenSubtitles: <a href='https://rb-dev.ngrok.dev/en/subtitles/"
      .. "upload-test-6df82c8b-7bfd-4ee7-a38a-23bd7b18290e'>upload-test</a> - nothing to upload"
    w.check:_click()
    has(env.message(), DUPLICATE)
    eq(last(env, "GET /subtitles").query, { id = "163533", languages = "en" })
    w.send:_click()
    has(env.message(), DUPLICATE)
  end)

  it("already on the site, its page not found: said without a link", function()
    -- the film's subtitles do not list it (withdrawn, on a later page ...)
    local env = setup({ check = "upload_check_known", upload = "upload_upload_duplicate" })
    env.server:on("GET " .. API .. "/subtitles", function() return api.fixture("upload_features_none") end)
    local w = upload_window(env)
    w.check:_click()
    has(env.message(), "This subtitle is already on OpenSubtitles - nothing to upload.")
    lacks(env.message(), "<a ")
  end)

  it("an account without upload rank gets the server's own explanation (recorded 403)", function()
    local env = setup({ check = "upload_rank_refused", upload = "upload_rank_refused" })
    local w = upload_window(env)
    w.check:_click()
    has(env.message(), "Upload failed: Your account's rank does not allow uploading")
  end)

  it("files that are too small or too large are refused before anything is sent", function()
    local env = setup({ content = "1\n00:00:01,000 --> 00:00:02,000\nhi\n" })
    local w = upload_window(env)
    w.send:_click()
    has(env.message(), "too small")
    eq(last(env, "/subtitles/upload"), nil)
    H.write_file(env.dir_video .. "/huge.srt", string.rep(SRT, 3000))
    w.path:set_text(env.dir_video .. "/huge.srt")
    w.send:_click()
    has(env.message(), "too large")
    eq(last(env, "/subtitles/upload"), nil)
  end)
end)

describe("upload: a film the site does not have", function()
  it("Find with an IMDb id: on IMDb, not here -> registered on Upload, then uploaded to it", function()
    local env = setup({ guess = "upload_guess", from_id = "upload_from_id_new" })
    local w = upload_window(env)
    w.imdb:set_text("tt1254207")
    w.find:_click()
    eq(last(env, "/features/from_id").body, { imdb_id = "tt1254207" })
    eq(w.film.text, BUNNY_LINK, "not on the site yet: nothing said, Upload adds it")
    w.send:_click()
    local stub = last(env, "/features/stub").body
    eq(stub.source, "imdb")
    eq(stub.imdb_id, "tt1254207")
    eq(stub.tmdb_id, 10378)
    eq(stub.title, "Big Buck Bunny")
    eq(last(env, "/subtitles/upload").body.feature_id, 180494, "uploaded to the registered film")
    eq(w.film.text, BUNNY_LINK)
  end)

  it("registered meanwhile (recorded 409 duplicate): its feature_id is used", function()
    local env = setup({ from_id = "upload_from_id_new", stub = "upload_stub_again" })
    local w = upload_window(env)
    w.imdb:set_text("tt1254207")
    w.find:_click()
    w.send:_click()
    eq(last(env, "/subtitles/upload").body.feature_id, 180494)
  end)

  it("an id that is on neither IMDb nor TMDb (recorded 404)", function()
    local env = setup({ from_id = "upload_from_id_missing" })
    local w = upload_window(env)
    w.imdb:set_text("tt99999990")
    w.find:_click()
    eq(w.film.text, "No film with that id on IMDb or TMDb.")
    w.send:_click()
    has(env.message(), "Which film is it?")
    eq(last(env, "/subtitles/upload"), nil)
  end)
end)

describe("upload: the subtitle's language", function()
  local CZECH = "1\r\n00:00:01,000 --> 00:00:04,000\r\n<i>Ahoj, jak se m\195\161\197\161?</i>\r\n\r\n"
    .. "2\r\n00:00:05,000 --> 00:00:08,000\r\nNev\195\173m, co m\195\161m d\196\155lat.\r\n\r\n"
    .. "3\r\n00:00:09,000 --> 00:00:12,000\r\nTo je ale p\196\155kn\195\189 den.\r\n"
  local function chosen(env) return upload_window(env).language:_texts()[1] end
  local function fasttext_sent(env) local r = last(env, "/fasttext/language/detect") return r and r.body end

  it("every code and name a file name may use", function()
    setup()
    local read = H.find_local("upload_language_from_name")
    local cases = {
      ["Film.2020.sk.srt"] = "sk", ["Film.2020.cze.srt"] = "cs", ["Film.2020.ces.srt"] = "cs",
      ["Film.2020.Czech.srt"] = "cs", ["Film.2020.pt-BR.srt"] = "pt-br", ["Film.2020.pob.srt"] = "pt-br",
      ["Film.2020.por.srt"] = "pt-pt", ["Film.2020.ger.srt"] = "de", ["Film.2020.Deutsch.srt"] = "de",
      ["Film.2020.Espa\195\177ol.srt"] = "es", ["Film_2020_fr.srt"] = "fr", ["Film.2020.chi.srt"] = "zh-cn",
      ["Film.2020.zh-TW.srt"] = "zh-tw", ["Film.2020.Portuguese (BR).srt"] = "pt-br",
      ["Film.2020.cs.forced.srt"] = "cs", ["Film.2020.English.SDH.srt"] = "en", ["Film.2020.en.subs.srt"] = "en",
      ["Film.2020.srt"] = false, ["Up.srt"] = false, ["Film.2020.1080p.srt"] = false,
    }
    for name, want in pairs(cases) do
      eq(read(name) or false, want, name)
    end
  end)

  it("a tag the list lacks: GuessIt's reading of the name (recorded: VOSTFR -> French)", function()
    local env = setup({ subtitles = { [VIDEO .. ".VOSTFR.srt"] = CZECH } })
    env.server:on("GET " .. API .. "/utilities/guessit", function(req)
      return api.fixture(req.query.filename:find("VOSTFR") and "guessit_subtitle_vostfr" or "guessit_subtitle_plain")
    end)
    eq(chosen(env), "French")
    eq(fasttext_sent(env), nil, "the name was enough")
  end)

  it("nothing in the name: fastText reads the text (recorded: Czech 0.998)", function()
    local env = setup({ subtitles = { [VIDEO .. ".srt"] = CZECH }, fasttext = "fasttext_czech",
                        config = { language = "en" } })
    eq(chosen(env), "Czech")
    local body = fasttext_sent(env)
    eq(body.texts, "Ahoj, jak se m\195\161\197\161?\nNev\195\173m, co m\195\161m d\196\155lat.\n"
       .. "To je ale p\196\155kn\195\189 den.", "the text only: no numbers, times or tags")
    eq(body.k, 2)
    eq(last(env, "/fasttext/language/detect").api_key, "d3Sba6j6VYnty3ir5T8GXYoAuiLSBf0S",
       "production's own key: the service is there")
  end)

  it("an old code page (not UTF-8) is still sent as UTF-8", function()
    setup()
    local sample = H.find_local("subtitle_sample")
    local path = H.tmpdir() .. "/cp1250.srt"
    H.write_file(path, "1\r\n00:00:01,000 --> 00:00:02,000\r\nNev\237m, co m\225m d\236lat, to je ale p\236kn\253 den.\r\n")
    local text = sample(path)
    ok(text and not text:gsub("[\194-\244][\128-\191]+", ""):find("[\128-\255]"), "valid UTF-8")
    has(text, "co m")
  end)

  it("the dialogue of every format: SRT, WebVTT, ASS, MicroDVD, MPL2, TMP, SAMI, UTF-16", function()
    setup()
    local sample = H.find_local("subtitle_sample")
    local dir = H.tmpdir()
    local function of(name, content)
      H.write_file(dir .. "/" .. name, content)
      return sample(dir .. "/" .. name)
    end
    local WANT = "Hello there, my friend.\nHow are you today?"
    eq(of("a.vtt", "WEBVTT\n\nNOTE made by hand\n\n1\n00:01.000 --> 00:04.000 align:start\n<v Bob>Hello there, my friend.\n\n"
       .. "00:05.000 --> 00:08.000\nHow are you today?\n"), "NOTE made by hand\n" .. WANT)
    eq(of("a.ass", "[Script Info]\nTitle: Test film\nScriptType: v4.00+\n\n[V4+ Styles]\n"
       .. "Format: Name, Fontname\nStyle: Default,Arial,20\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
       .. "Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,{\\i1}Hello there,\\Nmy friend.\n"
       .. "Dialogue: 0,0:00:05.00,0:00:08.00,Default,,0,0,0,,How are you today?\n"),
       "Hello there, my friend.\nHow are you today?")
    eq(of("a.sub", "{1}{100}Hello there,|my friend.\n{120}{200}How are you today?\n"), WANT)
    eq(of("a.mpl", "[10][40]Hello there,|my friend.\n[50][80]How are you today?\n"), WANT)
    eq(of("a.txt", "00:00:01:Hello there,|my friend.\n00:00:05=How are you today?\n"), WANT)
    eq(of("a.smi", "<SAMI><HEAD><STYLE TYPE=\"text/css\">\n<!--\nP { margin-left:8pt; }\n.ENCC { Name:English; }\n-->\n"
       .. "</STYLE></HEAD><BODY>\n<SYNC Start=1000><P Class=ENCC>Hello there,<br>my friend.\n"
       .. "<SYNC Start=5000><P Class=ENCC>How are you today?\n</BODY></SAMI>\n"), WANT)
    local utf16 = "\255\254" .. ("1\r\n00:00:01,000 --> 00:00:04,000\r\nNev\237m, co m\225m d\236lat, je to tak.\r\n"):gsub(".", "%0\0")
    eq(of("b16.srt", utf16), "Nev\195\173m, co m\195\161m d\195\172lat, je to tak.")
  end)

  it("a format not known here: the start of the file as it is", function()
    setup()
    local sample = H.find_local("subtitle_sample")
    local path = H.tmpdir() .. "/odd.srt"
    H.write_file(path, "@00:00:01.5 Dobr\195\189 den\n@00:00:04.0 D\196\155kuji moc\n")
    eq(sample(path), "@ Dobr\195\189 den\n@ D\196\155kuji moc", "words kept, numbers and times left out")
    H.write_file(path, "1\n2\n3\n")
    eq(sample(path), nil, "no words: nothing to ask")
  end)

  it("Portuguese: the user's own variant when it is one (recorded: pt 1.0)", function()
    local env = setup({ subtitles = { [VIDEO .. ".srt"] = CZECH }, fasttext = "fasttext_portuguese",
                        config = { language = "pt-br" } })
    eq(chosen(env), "Portuguese (BR)")
  end)

  it("fastText unsure (recorded: Spanish 0.58) or down: the user's own language", function()
    local env = setup({ subtitles = { [VIDEO .. ".srt"] = CZECH }, config = { language = "sk" } })
    eq(chosen(env), "Slovak")
    env.server.down["api.opensubtitles.com"] = nil
    env.server:on("POST " .. API .. "/utilities/fasttext/language/detect", function()
      return api.response(503, { message = "down" })
    end)
    eq(chosen(env), "Slovak")
  end)
end)

describe("upload: TV series", function()
  -- Recorded on the development API: How I Met Your Mother (tt0460649,
  -- feature 180497, "tvshow"); its S01E02 "Purple Giraffe" is feature 180499.
  local SERIES_LINK = "<a href='https://www.imdb.com/title/tt0460649/'>How I Met Your Mother (2005)</a>"

  it("a series id: Check without season and episode asks for them, nothing sent", function()
    local env = setup({ guess = "upload_guess_none", from_id = "upload_from_id_series" })
    local w = upload_window(env)
    eq(w.season:get_text(), "", "nothing in the names: empty")
    w.imdb:set_text("tt0460649")
    w.find:_click()
    eq(w.film.text, SERIES_LINK)
    w.check:_click()
    has(env.message(), "Which episode is it? Enter season and episode.")
    eq(last(env, "/upload/check"), nil)
    w.send:_click()
    has(env.message(), "Which episode is it?")
    eq(last(env, "/subtitles/upload"), nil)
  end)

  it("a series id with season and episode: both sent, the server attaches it to the episode", function()
    local env = setup({ guess = "upload_guess_none", from_id = "upload_from_id_series",
                        check = "upload_check_episode" })
    local w = upload_window(env)
    w.imdb:set_text("tt0460649")
    w.find:_click()
    w.season:set_text("1")
    w.episode:set_text(" 02 ")
    w.check:_click()
    local body = last(env, "/upload/check").body
    eq({ body.feature_id, body.season_number, body.episode_number }, { 180497, 1, 2 })
    has(env.message(), "Ready")
  end)

  it("a film (not a series): season and episode are not sent", function()
    local env = setup()
    local w = upload_window(env)
    w.season:set_text("1")
    w.episode:set_text("2")
    w.check:_click()
    local body = last(env, "/upload/check").body
    eq(body.season_number, nil)
    eq(body.episode_number, nil)
  end)

  it("the server's episode_required (recorded) is said in plain words", function()
    -- the film's kind unknown to VLSub: the check answers episode_required
    local env = setup({ guess = "upload_guess_none", features = "upload_features_matrix",
                        check = "upload_check_episode_required" })
    local w = upload_window(env)
    w.imdb:set_text("the matrix")
    w.find:_click()
    w.check:_click()
    has(env.message(), "Which episode is it? Enter season and episode.")
    lacks(env.message(), "episode_required")
  end)

  it("season and episode come from the subtitle's name; the episode found is named with its show", function()
    local env = setup({ guess = "upload_guess_episode" })
    H.write_file(env.dir_video .. "/" .. VIDEO .. ".S01E02.cs.srt", SRT)
    local w = upload_window(env)
    eq({ w.season:get_text(), w.episode:get_text() }, { "1", "2" })
    -- recorded guess for How.I.Met.Your.Mother.S01E02: the episode itself
    eq(w.film.text, "<a href='https://www.imdb.com/title/tt0606111/'>How I Met Your Mother S01E02 - Purple Giraffe (2005)</a>")
  end)

  it("an episode's own IMDb id: that episode, season and episode filled in", function()
    -- recorded from_id for tt0606111: the show, with "preselected" episode 180499
    local env = setup({ guess = "upload_guess_none", from_id = "upload_from_id_episode",
                        check = "upload_check_episode" })
    local w = upload_window(env)
    w.imdb:set_text("https://www.imdb.com/title/tt0606111/")
    w.find:_click()
    eq(w.film.text, "<a href='https://www.imdb.com/title/tt0606111/'>How I Met Your Mother S01E02 - Purple Giraffe (2005)</a>")
    eq({ w.season:get_text(), w.episode:get_text() }, { "1", "2" })
    w.check:_click()
    local body = last(env, "/upload/check").body
    eq(body.feature_id, 180499)
    eq(body.season_number, nil, "the episode's own id needs no numbers")
  end)

  local SLUTTY_PUMPKIN = "<a href='https://www.imdb.com/title/tt0606116/'>"
    .. "How I Met Your Mother S01E06 - The Slutty Pumpkin (2005)</a>"
  local HIMYM = "<a href='https://www.imdb.com/title/tt0460649/'>How I Met Your Mother (2005)</a>"

  it("a file name typed into the field: the site's guess finds the episode (recorded)", function()
    local env = setup({ guess = "upload_guess_none" })
    local w = upload_window(env)
    env.server:on("POST " .. API .. "/subtitles/upload/guess", function()
      return api.fixture("upload_guess_typed_episode")
    end)
    w.imdb:set_text("how.i.met.your.mother.s01.e06")
    w.find:_click()
    eq(w.film.text, SLUTTY_PUMPKIN)
    eq({ w.season:get_text(), w.episode:get_text() }, { "1", "6" })
    eq(w.imdb:get_text(), "tt0606116")
  end)

  it("a file name the guess does not know: its title is searched, season and episode filled in", function()
    local env = setup({ guess = "upload_guess_none", features = "upload_features_himym" })
    local w = upload_window(env)
    w.imdb:set_text("how.i.met.your.mother.s01.e06")
    w.find:_click()
    eq(last(env, "/features").query.query, "how i met your mother")
    eq(w.film.text, HIMYM)
    eq({ w.season:get_text(), w.episode:get_text() }, { "1", "6" })
    w.check:_click()
    local body = last(env, "/upload/check").body
    eq({ body.feature_id, body.season_number, body.episode_number }, { 180497, 1, 6 })
  end)

  it("the playing video: GuessIt's title finds the series, its season and episode are filled in", function()
    local env = setup({ guess = "upload_guess_none", features = "upload_features_himym" })
    openSub.file.completeName = "how.i.met.your.mother.s01e06.mkv"
    openSub.file.last_guessit_filename = openSub.file.completeName
    openSub.file.guessit_data = { title = "How I Met Your Mother", season = 1, episode = 6, type = "episode" }
    openSub.getFileInfo = function() end -- keep the playing file above
    local w = upload_window(env)
    eq(w.film.text, HIMYM)
    eq({ w.season:get_text(), w.episode:get_text() }, { "1", "6" })
  end)

  it("names: S01E02, s1e2, 1x02, S01.E02 are read; a year or resolution is not", function()
    H.launch({ activate = false })
    local read = H.find_local("episode_from_name")
    local function both(name) local s, e = read(name) return { s, e } end
    eq(both("Show.S01E02.720p.srt"), { 1, 2 })
    eq(both("show s1e2"), { 1, 2 })
    eq(both("Show - 1x02 - Title"), { 1, 2 })
    eq(both("Show.S01.E02"), { 1, 2 })
    eq(both("Show.S10E120"), { 10, 120 })
    eq(both("Send.Help.2026.1080p"), {})
    eq(both("Film.1920x1080"), {})
  end)
end)

describe("upload: long messages", function()
  local function visible_lines(text)
    local lines = {}
    for line in (text .. "<br>"):gmatch("(.-)<br>") do
      lines[#lines + 1] = line:gsub("<[^>]*>", ""):gsub("&#?%w+;", "x")
    end
    return lines
  end

  it("are broken into lines at spaces; tags take no room and are never cut", function()
    H.launch({ activate = false })
    local wrap = H.find_local("wrap_message")
    eq(wrap("short text", 90), "short text")
    eq(wrap("aaa bbb ccc", 7), "aaa bbb<br>ccc")
    eq(wrap("<b>aaa</b> bbb ccc", 7), "<b>aaa</b> bbb<br>ccc")
    eq(wrap("x <a href='https://example.org/a b'>one two</a> three", 9),
       "x <a href='https://example.org/a b'>one two</a><br>three", "the space inside the tag is not a break")
    eq(wrap("H&#318;ada&#357; aaa", 8), "H&#318;ada&#357;<br>aaa")
    eq(wrap("\197\161\197\161\197\161 \197\161\197\161", 4), "\197\161\197\161\197\161<br>\197\161\197\161")
    eq(wrap("one<br>two three four", 9), "one<br>two three<br>four")
    eq(wrap("averyveryverylongword next", 5), "averyveryverylongword<br>next", "no space to break at")
  end)

  it("the server's long explanation in the upload window: lines of at most 90 characters", function()
    -- recorded 403: "Your account's rank does not allow uploading. Uploading is
    -- open to Trusted, Gold and Platinum members, translators and staff."
    local env = setup({ check = "upload_rank_refused" })
    local w = upload_window(env)
    w.check:_click()
    local lines = visible_lines(env.message())
    ok(#lines >= 2 and #lines <= 3, "2 or 3 lines: " .. env.message())
    for _, line in ipairs(lines) do
      ok(#line <= 90, "line of " .. #line .. ": " .. line)
    end
    has(env.message():gsub("<br>", " "), "Uploading is open to Trusted, Gold and Platinum members, translators and staff.")
  end)
end)

describe("upload: the Film line", function()
  it("links to IMDb when the id is known; a title is escaped only inside the link", function()
    H.launch({ activate = false })
    local film_text = H.find_local("film_text")
    eq(film_text({ title = "Fast & Furious", year = 2009, imdb_id = 1013752 }),
       "<a href='https://www.imdb.com/title/tt1013752/'>Fast &amp; Furious (2009)</a>")
    eq(film_text({ title = "Fast & Furious", year = 2009 }), "Fast & Furious (2009)")
  end)
end)

describe("upload: the suggested release name", function()
  -- The video's name, only when it tells more than the film's title and year
  local function suggested(name, film, guess)
    H.launch({ activate = false })
    local default = H.find_local("upload_release_default")
    openSub.file.name, openSub.file.completeName = name, name .. ".mkv"
    openSub.file.last_guessit_filename = guess and openSub.file.completeName or nil
    openSub.file.guessit_data = guess
    return default(film)
  end
  local SEND_HELP = { title = "Send Help", year = 2026 }

  it("empty when the name only repeats the film", function()
    eq(suggested("Send.Help.2026", SEND_HELP), "")
    eq(suggested("send help (2026)", SEND_HELP), "")
    eq(suggested("Send_Help-2026", nil, { title = "Send Help", year = 2026, type = "movie" }), "")
    eq(suggested("Breaking.Bad.S02E05", { title = "Breaking Bad" }), "")
    eq(suggested("Breaking Bad 2x05", { title = "Breaking Bad" }), "")
    eq(suggested("", SEND_HELP), "")
  end)

  it("the name when it adds a group, source or quality", function()
    eq(suggested("Send.Help.2026.1080p.WEB-DL", SEND_HELP), "Send.Help.2026.1080p.WEB-DL")
    eq(suggested("Send.Help.2026-GROUP", SEND_HELP), "Send.Help.2026-GROUP")
    eq(suggested(VIDEO, { title = "The Matrix" }), VIDEO)
    eq(suggested("Send.Help.2026", nil), "Send.Help.2026", "film unknown: every word is extra")
  end)

  it("GuessIt's answer for this file counts: a release group it read keeps the name", function()
    -- recorded GuessIt answer (tests/fixtures/raw/guessit.http): release_group DEMAND
    local guess = { title = "Breaking Bad", season = 2, episode = 5, release_group = "DEMAND", type = "episode" }
    eq(suggested("Breaking.Bad.S02E05.DEMAND", { title = "Breaking Bad" }, guess), "Breaking.Bad.S02E05.DEMAND")
  end)

  it("in the window: Send.Help.2026 leaves the field empty; the field is sent only when filled", function()
    local env = setup()
    local w = upload_window(env)
    eq(w.release:get_text(), VIDEO, "1080p BluRay x264: kept")
    w.release:set_text("")
    w.send:_click()
    eq(last(env, "/subtitles/upload").body.release_name, nil)
  end)
end)

describe("upload: finding the film of the playing video", function()
  local function film_window(env)
    local d = env.ui()
    return d:_at(2, 4, "label").text, d:_at(2, 5, "text_input"):get_text()
  end

  it("1. from the search just made for this video (a clear majority of its results)", function()
    local env = setup()
    trigger_menu(1)
    env.ui():_at(4, 3, "text_input"):set_text("1254207") -- recorded: Big Buck Bunny, feature 548792
    env.ui():_button("Search$"):_click()
    for i = #env.sent, 1, -1 do env.sent[i] = nil end
    env.ui():_button("Upload$"):_click()
    local film, imdb = film_window(env)
    eq(film, BUNNY_LINK)
    eq(imdb, "tt1254207")
    eq(last(env, "/upload/guess"), nil, "nothing to ask")
    env.ui():_button("Check$"):_click()
    eq(last(env, "/upload/check").body.feature_id, 548792)
  end)

  it("results of a search for another video are not used", function()
    local env = setup()
    trigger_menu(1)
    env.ui():_at(4, 3, "text_input"):set_text("1254207")
    env.ui():_button("Search$"):_click()
    env.play("file://" .. env.dir_video .. "/Another.Film.2010.mkv")
    env.ui():_button("Upload$"):_click()
    ok(last(env, "/upload/guess"), "the guess was asked instead")
  end)

  it("2. the API's guess, from the video's name and movie hash", function()
    local env = setup({ video = true })
    local w = upload_window(env)
    local body = last(env, "/upload/guess").body
    eq(body.filename, VIDEO .. ".mkv")
    ok(body.moviehash and #body.moviehash == 16, "movie hash sent with the guess")
    eq(w.film.text, MATRIX_LINK)
    eq(w.imdb:get_text(), "tt0133093", "the IMDb field is filled in")
  end)

  it("3. nothing guessed: the site's films searched with GuessIt's title and year (recorded /features)", function()
    local env = setup({ guess = "upload_guess_none", features = "upload_features_matrix_1999" })
    openSub.movie.title, openSub.movie.year = "The Matrix", "1999"
    local w = upload_window(env)
    eq(w.film.text, MATRIX_LINK)
    eq(w.imdb:get_text(), "tt0133093")
    local req = env.server:last("GET " .. API .. "/features")
    eq(req.query.query, "the matrix")
    eq(req.query.year, "1999")
    w.check:_click()
    eq(last(env, "/upload/check").body.feature_id, 163533)
  end)

  it("a title typed into the field is searched (Find), an id is looked up", function()
    local env = setup({ guess = "upload_guess_none", features = "upload_features_matrix" })
    local w = upload_window(env)
    w.imdb:set_text("Matrix")
    w.find:_click()
    eq(w.film.text, MATRIX_LINK)
    eq(w.imdb:get_text(), "tt0133093")
    eq(last(env, "/features/from_id"), nil)
  end)

  -- imdb.opensubtitles.org: titles the site does not have yet (until the API
  -- can find a film by its title itself)
  local function imdb_asked(env)
    local r = last(env, "query-*")
    return r and r.path
  end
  local RELOADED_NEW = "<a href='https://www.imdb.com/title/tt0234215/'>The Matrix Reloaded (2003)</a>"

  it("a typed title the site does not have is found on IMDb and looked up by its id", function()
    local env = setup({ guess = "upload_guess_none", imdb = "imdb_query_matrix_reloaded",
                        from_id = "upload_from_id_reloaded" })
    local w = upload_window(env)
    w.imdb:set_text("matrix reloaded")
    w.find:_click()
    eq(imdb_asked(env), "/search/query-matrix+reloaded")
    eq(last(env, "/features/from_id").body, { imdb_id = "tt0234215" })
    eq(w.film.text, RELOADED_NEW)
    eq(w.imdb:get_text(), "tt0234215")
    eq(env.errors(), {})
  end)

  it("a year typed after the title goes to both searches", function()
    local env = setup({ guess = "upload_guess_none", imdb = "imdb_query_matrix_reloaded",
                        from_id = "upload_from_id_reloaded" })
    local w = upload_window(env)
    w.imdb:set_text("Matrix Reloaded (2003)")
    w.find:_click()
    eq(last(env, "/features").query.year, "2003")
    eq(imdb_asked(env), "/search/query-Matrix+Reloaded+2003")
    eq(w.film.text, RELOADED_NEW)
  end)

  it("the site's own film with that title wins: IMDb is not asked", function()
    local env = setup({ guess = "upload_guess_none", features = "upload_features_matrix",
                        imdb = "imdb_query_the_matrix_1999" })
    local w = upload_window(env)
    w.imdb:set_text("the matrix")
    w.find:_click()
    eq(w.film.text, MATRIX_LINK)
    eq(imdb_asked(env), nil)
  end)

  it("punctuation is left out of the IMDb query, other letters are encoded", function()
    local env = setup({ guess = "upload_guess_none" })
    local w = upload_window(env)
    w.imdb:set_text("Fast & Furious")
    w.find:_click()
    eq(imdb_asked(env), "/search/query-Fast+Furious") -- "&" made the service redirect
    w.imdb:set_text("Am\195\169lie")
    w.find:_click()
    eq(imdb_asked(env), "/search/query-Am%C3%A9lie")
    has(w.film.text, "IMDb id, link or title")
  end)

  it("the IMDb service down: the field asks for an id, nothing breaks", function()
    local env = setup({ guess = "upload_guess_none" })
    env.server.down["imdb.opensubtitles.org"] = true
    local w = upload_window(env)
    w.imdb:set_text("matrix reloaded")
    w.find:_click()
    has(w.film.text, "IMDb id, link or title")
    eq(env.errors(), { "[VLSub] Request to imdb.opensubtitles.org:80 failed: connect (attempt 1)" })
    -- a side service down is not the network down: the API is still asked
    w.imdb:set_text("tt1254207")
    w.find:_click()
    ok(last(env, "/features/from_id"), "the API was asked")
    has(w.film.text, "Big Buck Bunny (2008)")
  end)

  it("found without asking: IMDb counts only for the exact title and year", function()
    -- GuessIt read "The Matrix", 1999 from the video's name; the site has nothing
    local env = setup({ guess = "upload_guess_none", imdb = "imdb_query_the_matrix_1999",
                        from_id = "upload_from_id_matrix" })
    local film, imdb = (function() local w = upload_window(env) return w.film.text, w.imdb:get_text() end)()
    eq(imdb_asked(env), "/search/query-The+Matrix+1999")
    eq(film, MATRIX_LINK)
    eq(imdb, "tt0133093")
    -- only near titles on IMDb ("The Matrix Reloaded" ...): not taken
    env = setup({ guess = "upload_guess_none", imdb = "imdb_query_matrix_reloaded" })
    local w = upload_window(env)
    has(w.film.text, "IMDb id, link or title")
    eq(last(env, "/features/from_id"), nil)
  end)

  it("nothing found anywhere: the field asks for an IMDb id, link or title", function()
    local env = setup({ guess = "upload_guess_none", features = "upload_features_none" })
    local w = upload_window(env)
    has(w.film.text, "IMDb id, link or title")
    eq(w.imdb:get_text(), "")
  end)

  it("a file next to the video goes with the video's hash; a file by path does not", function()
    local env = setup({ video = true })
    local w = upload_window(env)
    w.check:_click()
    local body = last(env, "/upload/check").body
    ok(body.moviehash and #body.moviehash == 16, "hash sent")
    eq(body.moviebytesize, 300000)
    eq(body.moviefilename, VIDEO .. ".mkv")
    w.path:set_text(env.dir_video .. "/Other.Film.2001.srt")
    w.check:_click()
    body = last(env, "/upload/check").body
    eq(body.moviehash, nil)
    eq(body.moviebytesize, nil)
  end)
end)

describe("upload: never by itself", function()
  it("opening the window registers nothing and uploads nothing", function()
    local env = setup({ from_id = "upload_from_id_new" })
    upload_window(env)
    eq(last(env, "/features/stub"), nil)
    eq(last(env, "/subtitles/upload"), nil)
  end)
end)
