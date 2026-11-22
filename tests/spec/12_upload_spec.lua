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
  H.write_file(dir .. "/" .. VIDEO .. ".en.srt", o.content or SRT)
  H.write_file(dir .. "/" .. VIDEO .. ".sk.srt", SRT .. "\r\n3\r\n00:00:09,000 --> 00:00:10,000\r\nSk.\r\n")
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
    hi = d:_at(2, 6, "dropdown"), foreign = d:_at(2, 7, "dropdown"), translation = d:_at(2, 8, "dropdown"),
    release = d:_at(2, 9, "text_input"), comment = d:_at(2, 10, "text_input"),
    check = d:_button("Check$"), send = d:_at(2, 12, "button"), find = d:_button("Find$"),
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
