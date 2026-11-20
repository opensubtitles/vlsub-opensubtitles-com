-- Downloading: POST /download, fetch the returned link, save next to the
-- video, load into the player.
local H = ...
local describe, it, known_bug, eq, ok, has, lacks = H.describe, H.it, H.known_bug, H.eq, H.ok, H.has, H.lacks
local api, json = H.fake_api, H.json

local DOWNLOAD = "POST api.opensubtitles.com/api/v1/download"
local LINK = "GET www.opensubtitles.com/download/"

-- Launch with a video playing, search by name, return env + the video folder.
local function searched(o)
  o = o or {}
  local dir = H.tmpdir()
  if o.media == nil then
    o.media = "file://" .. H.video(dir, o.video or "Big.Buck.Bunny.2008.mkv", 200000)
  elseif o.media == false then
    o.media = nil
  end
  local env = H.launch(o)
  if env.ui().title:find("Configuration") then trigger_menu(1) end
  env.ui():_at(2, 1, "text_input"):set_text("big buck bunny")
  env.ui():_button("Search$"):_click()
  env.server:reset()
  env.vlc._subtitles = {}
  return env, dir
end

local function download(env, row)
  if row then env.results():_select(row) end
  env.ui():_button("Download"):_click()
end

describe("download", function()
  it("asks the API for the selected file, with the session token", function()
    local env = searched()
    local expected = api.fixture_json("search_name_en").data
    download(env, 3)
    local req = env.server:last(DOWNLOAD)
    eq(req.problems, {})
    eq(json.decode(req.body), { file_id = expected[3].attributes.files[1].file_id })
    eq(req.headers["content-type"], "application/json")
    eq(req.headers["authorization"], "Bearer " .. env.server.token)
    ok(req.headers["api-key"], "Api-Key")
  end)

  it("fetches the link over https, saves '<video>.<lang>.srt' next to the video, byte for byte", function()
    local env, dir = searched()
    download(env, 1)
    eq(#env.server:seen(LINK), 1)
    eq(env.server:last(LINK).scheme, "https")
    eq(H.ls(dir), { "Big.Buck.Bunny.2008.en.srt", "Big.Buck.Bunny.2008.mkv" })
    eq(H.read_file(dir .. "/Big.Buck.Bunny.2008.en.srt"), api.SUBTITLE_TEXT)
  end)

  it("loads the saved file into the player and selects it", function()
    local env, dir = searched()
    download(env, 1)
    eq(env.vlc._subtitles, { { path = dir .. "/Big.Buck.Bunny.2008.en.srt", autoselect = true } })
  end)

  it("shows success with the remaining quota", function()
    local env = searched()
    download(env, 1)
    has(env.message(), "Success")
    has(env.message(), "1/100")
    has(env.message(), "23 hours and 59 minutes")
    eq(env.errors(), {})
  end)

  it("language suffix follows the subtitle's language, not the search language", function()
    local env, dir = searched()
    env.server:on("GET api.opensubtitles.com/api/v1/subtitles", function()
      return api.response(200, { data = { { id = "9", type = "subtitle", attributes = {
        subtitle_id = "9", language = "pt-BR", release = "r",
        files = { { file_id = 77, file_name = "r.srt" } } } } } }, nil, { chunked = 80 })
    end)
    env.ui():_button("Search$"):_click()
    download(env, 1)
    ok(H.exists(dir .. "/Big.Buck.Bunny.2008.pt-BR.srt"), "files: " .. table.concat(H.ls(dir), ", "))
  end)

  it("langExt off: saved as '<video>.srt'", function()
    local env, dir = searched({ config = { langExt = false } })
    download(env, 1)
    ok(H.exists(dir .. "/Big.Buck.Bunny.2008.srt"), "files: " .. table.concat(H.ls(dir), ", "))
  end)

  it("removeTag on: {...} override tags are stripped from the saved file", function()
    local env, dir = searched({ config = { removeTag = true } })
    download(env, 1)
    local saved = H.read_file(dir .. "/Big.Buck.Bunny.2008.en.srt")
    lacks(saved, "{\\an8}")
    has(saved, "Second line with")
  end)

  it("downloading twice overwrites the file instead of failing", function()
    local env, dir = searched()
    download(env, 1)
    download(env, 1)
    eq(#H.ls(dir), 2)
    eq(#env.server:seen(DOWNLOAD), 2)
  end)

  it("nothing selected: says so, no request", function()
    local env = searched()
    download(env)
    eq(#env.server:seen(DOWNLOAD), 0)
    ok(env.message() ~= "", "a message is shown")
  end)

  it("no search yet: says so, no request", function()
    local env = H.launch()
    env.ui():_button("Download"):_click()
    eq(#env.server:seen(DOWNLOAD), 0)
    has(env.message(), "search first")
  end)

  it("manual mode: shows a link to the subtitle page instead of downloading", function()
    local env = searched({ config = { downloadBehaviour = "manual" } })
    local first = api.fixture_json("search_name_en").data[1]
    download(env, 1)
    eq(#env.server:seen(DOWNLOAD), 0)
    has(env.message(), "https://www.opensubtitles.com/subtitles/" .. first.attributes.subtitle_id)
  end)

  it("no video playing: saved to ~/Downloads and not loaded", function()
    local env = searched({ media = false })
    os.execute('mkdir -p "' .. env.home .. '/Downloads"')
    download(env, 1)
    local files = H.ls(env.home .. "/Downloads")
    eq(#files, 1, "files in Downloads: " .. table.concat(files, ", "))
    has(files[1], ".srt")
    eq(env.vlc._subtitles, {})
    has(env.message(), "Downloads")
  end)

  it("video folder is read-only: falls back to ~/Downloads and still loads the subtitle", function()
    local env, dir = searched()
    os.execute('mkdir -p "' .. env.home .. '/Downloads"')
    os.execute('chmod a-w "' .. dir .. '"')
    download(env, 1)
    os.execute('chmod u+w "' .. dir .. '"')
    eq(H.ls(env.home .. "/Downloads"), { "Big.Buck.Bunny.2008.en.srt" })
    eq(#env.vlc._subtitles, 1)
  end)

  it("network stream with a very long URL: a short, valid file name is used (issue #50)", function()
    local url = "http://cdn.example/live/stream.m3u8?token=" .. string.rep("a1B2c3D4", 60)
    local env = searched({ media = url })
    os.execute('mkdir -p "' .. env.home .. '/Downloads"')
    download(env, 1)
    local files = H.ls(env.home .. "/Downloads")
    eq(#files, 1)
    ok(#files[1] <= 200, "name length " .. #files[1])
    ok(not files[1]:find('[<>:"/\\|?*]'), "forbidden character in " .. files[1])
    has(env.message(), "Success")
  end)
end)

describe("download: failures", function()
  it("not logged in: explains that an account is needed, no download request", function()
    local env = searched({ login = false })
    download(env, 1)
    eq(#env.server:seen(DOWNLOAD), 0)
    ok(env.message():lower():find("authenticat") or env.message():lower():find("credential"),
       "message: " .. env.message())
  end)

  for status, expected in pairs({ [403] = "403", [404] = "404",
                                  [429] = "429", [500] = "500", [503] = "503" }) do
    it("HTTP " .. status .. " from /download: message names the problem, nothing is saved", function()
      local env, dir = searched()
      env.server:on(DOWNLOAD, function() return api.response(status, { message = "x" }) end)
      download(env, 1)
      has(env.message(), expected)
      eq(#H.ls(dir), 1, "only the video is in the folder")
      eq(env.vlc._subtitles, {})
    end)
  end

  it("token rejected by /download (401): logs in again and downloads", function()
    local env, dir = searched()
    env.server.token = "rotated-server-side"
    download(env, 1)
    eq(#env.server:seen("POST api.opensubtitles.com/api/v1/login"), 1)
    eq(#env.server:seen(DOWNLOAD), 2, "rejected request + one retry")
    eq(#H.ls(dir), 2, "subtitle saved")
    has(env.message(), "Success")
  end)

  it("daily quota used up (406): the API's explanation is shown", function()
    local env, dir = searched()
    env.server.downloads_used = 100
    download(env, 1)
    has(env.message(), "allowed 100 subtitles")
    eq(#H.ls(dir), 1)
  end)

  it("API says 'Invalid file_id' with status 200 (real response): nothing is saved", function()
      local env, dir = searched()
      env.server:on(DOWNLOAD, function() return api.fixture("download_noauth") end)
      download(env, 1)
      eq(#H.ls(dir), 1, "files: " .. table.concat(H.ls(dir), ", "))
      has(env.message(), "Invalid file_id")
    end)

  it("/download answering with JSON that is not an object does not raise",
    function()
      local env = searched()
      env.server:on(DOWNLOAD, function() return api.response(200, "1") end)
      download(env, 1)
      ok(env.message() ~= "", "a message is shown")
    end)

  it("the link cannot be fetched: error shown, nothing saved", function()
    local env, dir = searched()
    env.server.down["www.opensubtitles.com"] = true
    download(env, 1)
    has(env.message(), "Failed to download")
    eq(#H.ls(dir), 1)
  end)

  it("the link returns an empty body: error shown, nothing saved", function()
    local env, dir = searched()
    env.server:on("GET www.opensubtitles.com/download/*", function()
      return api.response(200, "", { ["Content-Type"] = "text/plain" })
    end)
    download(env, 1)
    eq(#H.ls(dir), 1)
    lacks(env.message(), "Success")
  end)

  it("no answer from /download: error shown, no crash", function()
    local env, dir = searched()
    env.server:on(DOWNLOAD, function() return "" end)
    download(env, 1)
    has(env.message(), "No response")
    eq(#H.ls(dir), 1)
  end)

  it("nowhere writable: error shown, no crash", function()
    local env, dir = searched()
    os.execute('chmod a-w "' .. dir .. '" "' .. env.dir .. '"')
    download(env, 1)
    os.execute('chmod u+w "' .. dir .. '" "' .. env.dir .. '"')
    has(env.message(), "Cannot write")
  end)
end)


-- AI on-demand translation. Built on a recorded search answer only
-- (tests/fixtures/raw/search_on_demand_cs.http); what the server answers to
-- the download is not recorded yet, so nothing is asserted about it.
H.describe("AI on-demand entry (recorded search answer)", function()
  local it, eq, ok, has = H.it, H.eq, H.ok, H.has
  local DOWNLOAD = "POST api.opensubtitles.com/api/v1/download"
  local ID = "431137309911500000000000000000000"

  local function searched()
    local dir = H.tmpdir()
    local env = H.launch({ config = { language = "cs" }, media = "file://" .. dir .. "/Big.Buck.Bunny.2008.mkv" })
    env.media_dir = dir
    local d = env.ui()
    d:_at(4, 3, "text_input"):set_text("1254207")
    env.server:reset()
    d:_button("Search$"):_click()
    return env
  end

  it("is listed and marked as on demand, costing credits", function()
    local env = searched()
    local rows = env.results().values
    eq(#rows, 1)
    has(rows[1].text, "AI on demand (uses credits)")
    has(rows[1].text, "CS")
  end)

  it("its 33-digit id is kept as text and sent back digit for digit", function()
    local env = searched()
    local item = openSub.itemStore[1]
    eq(item.FileID, ID)
    eq(item.OnDemand, true)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    local sent = env.server:last(DOWNLOAD)
    ok(sent, "download requested")
    eq(sent.body, '{"file_id":' .. ID .. '}')
  end)

  it("one request only: a translation is never asked for twice by itself", function()
    local env = searched()
    env.server:on(DOWNLOAD, function() return api.response(503, { message = "busy" }) end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    eq(#env.server:seen(DOWNLOAD), 1)
  end)

  it("the balance is read first; without credits nothing is asked for and the buy links are shown", function()
    local env = searched()
    env.server.ai_credits = 0
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    eq(#env.server:seen(DOWNLOAD), 0, "no download request")
    has(env.message(), "needs AI credits - your balance is 0")
    has(env.message(), "<a href='https://ai.opensubtitles.com/assets/buy_credits.php?tag=EXAMPLE'>500 credits - 5 USD</a>")
    for _, line in ipairs(env.vlc._messages()) do
      ok(not line:find("buy_credits", 1, true), "checkout address in the log: " .. line)
    end
  end)

  it("with credits the message names the balance before the request", function()
    local env = searched()
    local shown = {}
    env.server:on(DOWNLOAD, function()
      shown[#shown + 1] = env.message()
      return api.response(503, { message = "busy" })
    end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    has(shown[1], "Creating the AI translation (AI credits: 2019)")
  end)

  it("configuration window: the AI credits button shows the balance and where to buy", function()
    local env = H.launch()
    trigger_menu(2)
    env.server:reset()
    env.ui():_button("Show balance"):_click()
    has(env.message(), "AI credits: 2019")
    has(env.message(), "Buy AI credits:")
    has(env.message(), "1100 credits - 10 USD")
    eq(#env.server:seen("GET api.opensubtitles.com/api/v1/ai/credits"), 2, "the balance and the packages")
  end)

  it("opening the configuration window asks the server nothing about credits", function()
    local env = H.launch()
    env.server:reset()
    trigger_menu(2)
    eq(#env.server:seen("GET api.opensubtitles.com/api/v1/ai/credits"), 0)
  end)

  it("a checkout address that is not a plain https opensubtitles.com link is not made clickable", function()
    local env = H.launch()
    env.server:on("GET api.opensubtitles.com/api/v1/ai/credits/buy", function()
      return api.response(200, { data = {
        { name = "x", value = "1", checkout_url = "https://evil.example/buy" },
        { name = "y", value = "2", checkout_url = "https://ai.opensubtitles.com/a'><b>" },
        { name = "z", value = "3", checkout_url = "http://ai.opensubtitles.com/plain" } } })
    end)
    trigger_menu(2)
    env.ui():_button("Show balance"):_click()
    has(env.message(), "AI credits: 2019")
    ok(not env.message():find("<a ", 1, true), env.message())
  end)

  -- Recorded in real VLC (2026-11-20).
  -- New translation: POST -> 302 Location /api/v1/download/<id>?wait_for_translation=1
  -- -> 302 ...=2 -> 302 ...=3 -> 200 with the subtitle text itself as the body.
  -- Existing one: POST -> 200 with CACHED, whose link answers 404.
  local TRANSLATED = "1\n00:00:01,000 --> 00:00:04,000\nAhoj z umelej inteligencie\n"
  local DONE = TRANSLATED
  local CACHED = '{"link":"https:\\/\\/ai.opensubtitles.com\\/proxy\\/download\\/' .. ID .. '","file_name":"",'
    .. '"requests":"1","remaining":"99999999",'
    .. '"message":"This a on-demand translation by AI.OpenSubtitles.com (file was cached)",'
    .. '"reset_time":"now","reset_time_utc":"2026-11-20T00:06:50.000Z"}'
  local WAIT = "GET api.opensubtitles.com/api/v1/download/*"

  local function translating(env, hops)
    local seen = { post = 0, get = {} }
    env.server:on(DOWNLOAD, function()
      seen.post = seen.post + 1
      return api.response(302, "", { Location = "/api/v1/download/" .. ID .. "?wait_for_translation=1" })
    end)
    env.server:on(WAIT, function(req)
      local n = tonumber(req.query.wait_for_translation)
      seen.get[#seen.get + 1] = { n = n, auth = req.headers["authorization"], scheme = req.scheme }
      if n < hops then
        return api.response(302, "", { Location = "/api/v1/download/" .. ID .. "?wait_for_translation=" .. (n + 1) })
      end
      return api.response(200, DONE, { ["Content-Type"] = "text/plain; charset=utf-8" })
    end)
    return seen
  end

  it("not made yet: the trail of wait_for_translation redirects is followed to the link", function()
    local env = searched()
    local seen = translating(env, 4)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    eq(seen.post, 1, "one POST: the translation is ordered once")
    eq(#seen.get, 4)
    for i, hop in ipairs(seen.get) do
      eq(hop.n, i)
      eq(hop.scheme, "http")
      ok(hop.auth and hop.auth:find("^Bearer "), "credentials on hop " .. i)
    end
    has(env.message(), "Success")
    has(env.message(), "AI credits left: 2019")
    eq(env.errors(), {})
    local saved = H.ls(env.media_dir)
    eq(#saved, 1)
    eq(H.read_file(env.media_dir .. "/" .. saved[1]), TRANSLATED, "the text of the last answer is the subtitle")
  end)

  it("exists already (cached): the link answers 404, the text is fetched from the API instead", function()
    local env = searched()
    local posts = 0
    env.server:on(DOWNLOAD, function() posts = posts + 1 return api.response(200, CACHED) end)
    local asked = {}
    env.server:on(WAIT, function(req)
      asked[#asked + 1] = req.target
      return api.response(200, TRANSLATED, { ["Content-Type"] = "text/plain; charset=utf-8" })
    end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    eq(posts, 1)
    eq(asked, { "/api/v1/download/" .. ID .. "?wait_for_translation=1" })
    has(env.message(), "Success")
    lacks(env.message(), "99999999") -- "remaining" of such an answer is not the daily quota
    local saved = H.ls(env.media_dir)
    eq(H.read_file(env.media_dir .. "/" .. saved[1]), TRANSLATED)
  end)

  it("cached, and the API does not hand the text out either: the failure is reported, nothing is saved", function()
    local env = searched()
    env.server:on(DOWNLOAD, function() return api.response(200, CACHED) end)
    env.server:on(WAIT, function() return api.response(404, { message = "not found" }) end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    has(env.message(), "Failed to download")
    eq(#H.ls(env.media_dir), 0)
  end)

  it("a redirect to another host is not followed (the token stays with the API)", function()
    local env = searched()
    env.server:on(DOWNLOAD, function()
      return api.response(302, "", { Location = "http://evil.example/steal" })
    end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    eq(#env.server:seen("GET evil.example"), 0)
    has(env.message(), "302")
  end)

  it("a translation that never finishes: gives up after three minutes with a clear message", function()
    local env = searched()
    local seen = translating(env, 100000)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    eq(seen.post, 1)
    has(env.message(), "did not arrive in time")
  end)

  it("ordinary entries are not marked", function()
    local env = H.launch()
    local d = env.ui()
    d:_at(2, 1, "text_input"):set_text("big buck bunny")
    d:_button("Search$"):_click()
    for _, row in ipairs(env.results().values) do
      ok(not row.text:find("on demand", 1, true), row.text)
    end
    for _, item in ipairs(openSub.itemStore) do eq(item.OnDemand, false) end
  end)
end)
