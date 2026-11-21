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
    eq(rows[1].text, "CS | \240\159\164\150 AI translation from English (uses AI credits) | big_buck_bunny")
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

  -- Recorded with an account at 0 credits (live API, 2026-11-20): the POST
  -- answers 302 to /api/v1/download/preview-<id>?wait_for_translation=1&p=aj
  -- and that answers 200 with a short translated sample followed by lines
  -- telling where to add credits.
  it("without credits: the server's preview is saved and the message says it is only a preview, with buy links", function()
    local env = searched()
    env.server.ai_credits = 0
    local PREVIEW = "1\n00:00:02,000 --> 00:00:05,000\nBig Buck Bunny\nFilm\n\n"
      .. "3\n00:00:59,000 --> 00:01:02,000\nAby uzyska\196\135 pe\197\130ne t\197\130umaczenie na \197\188\196\133danie\n"
    local hops = {}
    env.server:on(DOWNLOAD, function()
      return api.response(302, "", { Location = "/api/v1/download/preview-" .. ID .. "?wait_for_translation=1&p=aj" })
    end)
    env.server:on("GET api.opensubtitles.com/api/v1/download/*", function(req)
      hops[#hops + 1] = req.target
      return api.response(200, PREVIEW, { ["Content-Type"] = "text/plain; charset=utf-8" })
    end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    eq(hops, { "/api/v1/download/preview-" .. ID .. "?wait_for_translation=1&p=aj" })
    eq(H.read_file(env.media_dir .. "/" .. H.ls(env.media_dir)[1]), PREVIEW)
    has(env.message(), "only a preview")
    has(env.message(), "not have enough AI credits")
    has(env.message(), "(you have 0)")
    has(env.message(), "500 credits - 5 USD")
    lacks(env.message(), "Success")
    for _, line in ipairs(env.vlc._messages()) do
      ok(not line:find("buy_credits", 1, true), "checkout address in the log: " .. line)
    end
  end)

  -- Recorded (0 credits, a translation that exists): POST answers 200 with
  -- "link":"https://ai.opensubtitles.com/proxy/download/preview-<id>?p=am".
  it("without credits, cached: the preview named by the link is asked for - never the full text", function()
    local env = searched()
    env.server.ai_credits = 0
    env.server:on(DOWNLOAD, function()
      return api.response(200, '{"link":"https:\\/\\/ai.opensubtitles.com\\/proxy\\/download\\/preview-' .. ID
        .. '?p=am","file_name":"","requests":"1","remaining":"99999999",'
        .. '"message":"This a on-demand translation by AI.OpenSubtitles.com (file was cached)","reset_time":"now"}')
    end)
    local asked = {}
    env.server:on("GET api.opensubtitles.com/api/v1/download/*", function(req)
      asked[#asked + 1] = req.target
      return api.response(200, "1\n00:00:02,000 --> 00:00:05,000\nsample\n", { ["Content-Type"] = "text/plain" })
    end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    eq(asked, { "/api/v1/download/preview-" .. ID .. "?wait_for_translation=1&p=am" })
    has(env.message(), "only a preview")
    lacks(env.message(), "Success")
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

  it("balance and every package fit the three message lines: three packages per line", function()
    -- (one long line was cut off at the edge of the window on macOS, hiding
    -- the larger packages)
    local env = H.launch()
    trigger_menu(2)
    env.ui():_button("Show balance"):_click()
    local lines = {}
    for part in (env.message() .. "<br>"):gmatch("(.-)<br>") do lines[#lines + 1] = part end
    eq(#lines, 3, env.message())
    has(lines[1], "AI credits: 2019")
    has(lines[1], "Buy AI credits:")
    eq(select(2, lines[1]:gsub("<a ", "")), 0, "no package on the first line")
    eq(select(2, lines[2]:gsub("<a ", "")), 3)
    eq(select(2, lines[3]:gsub("<a ", "")), 2)
    has(lines[3], "39000 credits - 300 USD") -- all five the API offers
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

  it("exists already (cached): the text is fetched from the API, the unusable link is not tried", function()
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
    eq(env.errors(), {}, "no error on the way")
    eq(#env.server:seen("GET ai.opensubtitles.com"), 0, "link not requested")
    lacks(env.message(), "99999999") -- "remaining" of such an answer is not the daily quota
    local saved = H.ls(env.media_dir)
    eq(H.read_file(env.media_dir .. "/" .. saved[1]), TRANSLATED)
  end)

  it("cached, and the API does not hand the text out: the link is tried; its failure is reported, nothing is saved", function()
    local env = searched()
    env.server:on(DOWNLOAD, function() return api.response(200, CACHED) end)
    env.server:on(WAIT, function() return api.response(404, { message = "not found" }) end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    has(env.message(), "Failed to download")
    eq(#env.server:seen("GET ai.opensubtitles.com"), 1, "link tried as the last resort")
    eq(#H.ls(env.media_dir), 0)
  end)

  it("while the server keeps the request open the message counts the seconds and VLC is told the extension is alive", function()
    local env = searched()
    local seen = translating(env, 3)
    env.server.holds_for = 9 -- measured: each waiting request is held 9 s
    local shown = {}
    local label
    for _, w in ipairs(env.ui().widgets) do if w.kind == "label" and w.row == 10 then label = w end end
    local set = label.set_text
    rawset(label, "set_text", function(self, text) shown[#shown + 1] = text return set(self, text) end)
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    env.server.holds_for = nil
    local counted = {}
    for _, text in ipairs(shown) do
      local n = text:match("being made: (%d+) s")
      if n then counted[#counted + 1] = tonumber(n) end
    end
    ok(#counted >= 15, "the counter was shown " .. #counted .. " times")
    for i = 2, #counted do ok(counted[i] >= counted[i - 1], "the counter never goes back") end
    ok(counted[#counted] >= 20, "it reached " .. tostring(counted[#counted]) .. " s")
    ok(env.vlc._keep_alives >= 15, "vlc.keep_alive() called " .. env.vlc._keep_alives .. " times")
    eq(seen.post, 1)
    has(env.message(), "Success")
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

  -- VLC tells the extension when the playing item changes (input_changed).
  -- The extension uses two such calls in quick succession on the same
  -- selected row as a "double click" and downloads without the button.
  it("credits are never spent by itself: the automatic download skips an on-demand entry", function()
    local env = searched()
    env.server:reset()
    env.results():_select(1)
    for _ = 1, 6 do input_changed() end
    eq(#env.server:seen(DOWNLOAD), 0, "no download request")
    eq(#env.server:seen("GET api.opensubtitles.com/api/v1/ai/"), 0, "not even the balance is asked")
    eq(#H.ls(env.media_dir), 0)
    eq(env.errors(), {})
    -- the button still works
    env.ui():_button("Download"):_click()
    eq(#env.server:seen(DOWNLOAD), 1, "the Download button does download it")
  end)

  it("the automatic download still takes an ordinary entry (unchanged behaviour)", function()
    local dir = H.tmpdir()
    local env = H.launch({ media = "file://" .. dir .. "/Big.Buck.Bunny.2008.mkv" })
    local d = env.ui()
    d:_at(2, 1, "text_input"):set_text("big buck bunny")
    d:_button("Search$"):_click()
    env.server:reset()
    env.results():_select(1)
    for _ = 1, 6 do input_changed() end
    ok(#env.server:seen(DOWNLOAD) >= 1, "downloaded without the button, as before")
  end)

  it("a new search by itself (media change) lists on-demand entries but downloads nothing", function()
    local env = searched()
    env.server:reset()
    input_changed()
    eq(#env.server:seen(DOWNLOAD), 0)
  end)

  it("ordinary entries are not marked", function()
    local env = H.launch()
    local d = env.ui()
    d:_at(2, 1, "text_input"):set_text("big buck bunny")
    d:_button("Search$"):_click()
    for _, row in ipairs(env.results().values) do
      ok(not row.text:find("AI translation", 1, true), row.text)
    end
    for _, item in ipairs(openSub.itemStore) do eq(item.OnDemand, false) end
  end)
end)
