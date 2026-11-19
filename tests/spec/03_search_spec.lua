-- Searching, driven through the dialog exactly as a user would: fill the
-- fields, pick languages, click a button; then check the request that reached
-- the API and what the result list shows.
local H = ...
local describe, it, known_bug, eq, ok, has = H.describe, H.it, H.known_bug, H.eq, H.ok, H.has
local api = H.fake_api

local SUBTITLES = "GET api.opensubtitles.com/api/v1/subtitles"

-- Widgets of the main window, by grid position (see interface_main)
local function main(env)
  local d = env.ui()
  return {
    title = d:_at(2, 1, "text_input"), season = d:_at(2, 2, "text_input"),
    episode = d:_at(4, 2, "text_input"), year = d:_at(2, 3, "text_input"),
    imdb = d:_at(4, 3, "text_input"),
    lang1 = d:_at(2, 4, "dropdown"), lang2 = d:_at(2, 5, "dropdown"),
    lang3 = d:_at(2, 6, "dropdown"),
    sort_by = d:_at(2, 7, "dropdown"), sort_dir = d:_at(5, 7, "dropdown"),
    list = d:_at(1, 9, "list"),
    by_name = d:_button("Search$"), by_hash = d:_button("hash"),
  }
end

local function start(o)
  local env = H.launch(o)
  env.server:reset()
  return env, main(env)
end

describe("search by name", function()
  it("sends title, year and language; parameters sorted, lower-case, spaces as +", function()
    local env, w = start()
    w.title:set_text("The Big  Buck BUNNY")
    w.year:set_text("2008")
    w.by_name:_click()

    local req = env.server:last(SUBTITLES)
    eq(req.problems, {}, "protocol problems")
    eq(req.raw_query, "languages=en&query=the+big++buck+bunny&year=2008")
    eq(req.query, { languages = "en", query = "the big  buck bunny", year = "2008" })
    eq(req.headers["api-key"] ~= nil, true, "Api-Key sent")
    has(req.headers["authorization"], "Bearer ", "logged-in searches carry the token")
    eq(#env.server:seen(SUBTITLES), 1, "exactly one search request (no redirect round-trip)")
  end)

  it("lists every subtitle from the response, in API order, with release name and language", function()
    local env, w = start()
    w.title:set_text("big buck bunny")
    w.by_name:_click()

    local expected = api.fixture_json("search_name_en").data
    eq(#w.list.values, #expected, "rows")
    for i = 1, #expected do
      eq(w.list.values[i].id, i, "row id is the index into the result store")
    end
    has(w.list.values[1].text, "EN | ")
    has(w.list.values[1].text, expected[1].attributes.release)
    has(w.list.values[1].text, expected[1].attributes.uploader.name)
    has(w.list.values[1].text, tostring(expected[1].attributes.download_count))
    has(env.message(), "50")
    has(env.message(), "big buck bunny")
  end)

  it("season and episode are sent for TV searches; zero or empty are left out", function()
    local env, w = start()
    w.title:set_text("Breaking Bad")
    w.season:set_text("2")
    w.episode:set_text("05")
    w.by_name:_click()
    local q = env.server:last(SUBTITLES).query
    eq(q.season_number, "2")
    eq(q.episode_number, "5", "leading zero stripped (the API redirects otherwise)")
    eq(q.query, "breaking bad")

    w.season:set_text("0")
    w.episode:set_text("")
    w.by_name:_click()
    q = env.server:last(SUBTITLES).query
    eq(q.season_number, nil)
    eq(q.episode_number, nil)
  end)

  it("special characters in the title are percent-encoded", function()
    local env, w = start()
    w.title:set_text("Am\195\169lie & Fr\195\188hst\195\188ck: 50% / #1?")
    w.by_name:_click()
    local req = env.server:last(SUBTITLES)
    eq(req.problems, {})
    ok(not req.raw_query:find("[ #]"), "raw query contains no space or #: " .. req.raw_query)
    eq(req.query.query, "am\195\169lie & fr\195\188hst\195\188ck: 50% / #1?")
  end)

  it("empty title does nothing", function()
    local env, w = start()
    w.title:set_text("   ")
    w.by_name:_click()
    eq(#env.server:seen(SUBTITLES), 0)
  end)

  it("no results: placeholder row and a clear message", function()
    local env, w = start()
    w.title:set_text("zzz nothing")
    w.by_name:_click()
    eq(#w.list.values, 1)
    has(env.message(), w.list.values[1].text)
    eq(env.errors(), {})
  end)

  it("sort options become order_by / order_direction", function()
    local env, w = start()
    w.title:set_text("big buck bunny")
    w.sort_by:_choose_text("^Downloads$")
    w.sort_dir:_choose_text("^Asc")
    w.by_name:_click()
    local q = env.server:last(SUBTITLES).query
    eq(q.order_by, "download_count")
    eq(q.order_direction, "asc")
  end)

  it("default sort sends no order parameters", function()
    local env, w = start()
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    local q = env.server:last(SUBTITLES).query
    eq(q.order_by, nil)
    eq(q.order_direction, nil)
  end)
end)

describe("search languages", function()
  it("drop-down offers the API language list; saved language is preselected", function()
    local env, w = start({ config = { language = "sk" } })
    eq(w.lang1.values[1].text, "Slovak", "preselected entry")
    local names = {}
    for _, v in ipairs(w.lang1.values) do names[v.text] = true end
    for _, l in ipairs(api.fixture_json("languages").data) do
      ok(names[l.language_name], "language offered: " .. l.language_name)
    end
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    eq(env.server:last(SUBTITLES).query.languages, "sk")
  end)

  it("three languages are sent as one sorted, comma-separated list", function()
    local env, w = start()
    w.lang1:_choose_text("^Slovak$")
    w.lang2:_choose_text("^English$")
    w.lang3:_choose_text("^French$")
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    local req = env.server:last(SUBTITLES)
    eq(req.query.languages, "en,fr,sk")
    has(req.raw_query, "languages=en%2Cfr%2Csk")
    eq(#w.list.values, #api.fixture_json("search_name_multi").data, "results listed (no redirect)")
  end)

  it("the same language picked twice is sent once", function()
    local env, w = start()
    w.lang2:_choose_text("^English$")
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    eq(env.server:last(SUBTITLES).query.languages, "en")
  end)

  it("'All' sends no languages parameter", function()
    local env, w = start({ config = { language = false } })
    eq(w.lang1.values[1].text, "All")
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    eq(env.server:last(SUBTITLES).query.languages, nil)
  end)

  it("regional codes are sent as the API spells them (pt-BR, zh-CN)", function()
    local env, w = start()
    w.lang1:_choose_text("Portuguese %(BR%)")
    w.lang2:_choose_text("Chinese %(simplified%)")
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    eq(env.server:last(SUBTITLES).query.languages, "pt-br,zh-cn")
    ok(#w.list.values > 1, "results listed (no redirect)")
  end)

  it("results are grouped by the selected language order, other languages last", function()
    local env, w = start()
    local data = {}
    for i, lang in ipairs({ "fr", "en", "de", "sk", "en", "fr" }) do
      data[i] = { id = tostring(i), type = "subtitle", attributes = {
        subtitle_id = tostring(i), language = lang, release = "rel-" .. i,
        download_count = i, files = { { file_id = 100 + i, file_name = "f" .. i } } } }
    end
    env.server:on(SUBTITLES, function() return api.response(200, { data = data }, nil, { chunked = 500 }) end)
    w.lang1:_choose_text("^Slovak$")
    w.lang2:_choose_text("^English$")
    w.title:set_text("x")
    w.by_name:_click()
    local order = {}
    for i, v in ipairs(w.list.values) do order[i] = v.id end
    eq(order, { 4, 2, 5, 1, 3, 6 }, "row ids: sk first, then en, then the rest in API order")
    has(w.list.values[1].text, "SK | f4")
  end)
end)

describe("search by IMDb id", function()
  for input, expected in pairs({
    ["tt1254207"] = "1254207", ["1254207"] = "1254207", ["tt0096697"] = "96697",
    ["https://www.imdb.com/title/tt1254207/"] = "1254207",
  }) do
    it("accepts '" .. input .. "'", function()
      local env, w = start()
      w.title:set_text("ignored title")
      w.imdb:set_text(input)
      w.by_name:_click()
      local q = env.server:last(SUBTITLES).query
      eq(q.imdb_id, expected)
      eq(q.query, nil, "title is not sent together with an IMDb id")
      eq(#w.list.values, 1, "the one recorded result is listed (no redirect)")
      has(w.list.values[1].text, "big_buck_bunny")
      has(env.message(), "IMDB ID")
    end)
  end

  it("rejects text that is not an IMDb id", function()
    local env, w = start()
    w.imdb:set_text("not-an-id")
    w.by_name:_click()
    eq(#env.server:seen(SUBTITLES), 0)
    has(env.message(), "Invalid IMDB ID")
  end)
end)

describe("search by hash", function()
  -- Expected values computed with an independent implementation of the
  -- OpenSubtitles hash (64-bit sum of the first and last 64 KiB + file size).
  for size, hash in pairs({ [200000] = "e6ed0e283146465f", [131072] = "bfc8d9f70b1c06e5",
                            [196613] = "8fa0bcd6dff3edcd", [1000000] = "fe0f2c404e6e9f72" }) do
    it("hash of a " .. size .. " byte file is " .. hash, function()
      local dir = H.tmpdir()
      local env, w = start({ media = "file://" .. H.video(dir, "clip.mkv", size) })
      w.by_hash:_click()
      local req = env.server:seen(SUBTITLES)[1]
      eq(req.query.moviehash, hash)
      eq(req.query.moviebytesize, tostring(size))
      eq(req.query.query, nil)
    end)
  end

  it("hash hit: results shown, no name search needed", function()
    local dir = H.tmpdir()
    local env, w = start({ media = "file://" .. H.video(dir, "clip.mkv", 200000) })
    env.server:on(SUBTITLES, function(req)
      if req.query.moviehash then return api.fixture("search_hash") end
      error("unexpected name search")
    end)
    w.by_hash:_click()
    eq(#env.server:seen(SUBTITLES), 1)
    eq(#w.list.values, #api.fixture_json("search_hash").data)
    has(env.message(), "moviehash e6ed0e283146465f")
  end)

  it("hash miss falls back to a name search using the GuessIt title and year", function()
    local dir = H.tmpdir()
    local env, w = start({ media = "file://" .. H.video(dir, "Big.Buck.Bunny.2008.1080p.BluRay.mkv", 200000) })
    w.by_hash:_click()
    local reqs = env.server:seen(SUBTITLES)
    eq(#reqs, 2)
    eq(reqs[1].query.moviehash, "e6ed0e283146465f")
    eq(reqs[2].query, { languages = "en", query = "big buck bunny", year = "2008" })
    has(env.message(), "found via name search")
    eq(w.title:get_text(), "Big Buck Bunny")
  end)

  it("TV episode file: GuessIt season and episode are used in the fallback", function()
    local dir = H.tmpdir()
    local env, w = start({ media = "file://" .. H.video(dir, "Breaking.Bad.S02E05.720p.BluRay.x264-DEMAND.mkv", 200000) })
    eq(w.title:get_text(), "Breaking Bad")
    eq(w.season:get_text(), "2")
    eq(w.episode:get_text(), "5")
    w.by_hash:_click()
    local q = env.server:last(SUBTITLES).query
    eq(q.query, "breaking bad")
    eq(q.season_number, "2")
    eq(q.episode_number, "5")
  end)

  it("network stream: no hashing, goes straight to name search", function()
    local env, w = start({ media = "http://stream.example/live/Some.Movie.2019.mkv?token=abc" })
    w.by_hash:_click()
    for _, r in ipairs(env.server:seen(SUBTITLES)) do
      eq(r.query.moviehash, nil, "no hash for a stream")
    end
  end)

  it("nothing playing and no title: explains instead of searching", function()
    local env, w = start()
    w.by_hash:_click()
    eq(#env.server:seen(SUBTITLES), 0)
    ok(env.message() ~= "Ready for search", "a message is shown: " .. env.message())
  end)

  it("when GuessIt is unavailable the fallback does not mistake '1080p' for the year", function()
      local dir = H.tmpdir()
      local server = api.new()
      server:on("GET api.opensubtitles.com/api/v1/utilities/guessit", function()
        return api.response(503, { message = "down" })
      end)
      local env, w = start({ server = server,
        media = "file://" .. H.video(dir, "Big.Buck.Bunny.2008.1080p.mkv", 200000) })
      ok(w.year:get_text() == "2008" or w.year:get_text() == "", "year field: " .. w.year:get_text())
    end)

  it("GuessIt is asked once per file, not on every action", function()
      local dir = H.tmpdir()
      local server = api.new()
      server:on("GET api.opensubtitles.com/api/v1/utilities/guessit", function()
        return api.response(503, { message = "down" })
      end)
      local env = H.launch({ server = server,
        media = "file://" .. H.video(dir, "Big.Buck.Bunny.2008.mkv", 200000) })
      eq(#env.server:seen("GET api.opensubtitles.com/api/v1/utilities/guessit"), 1)
    end)
end)

describe("title parsing without GuessIt", function()
  local cases = {
    { "Big.Buck.Bunny.2008.1080p.BluRay.mkv", "2008" },
    { "Movie.1080p.x264.mkv", "" },
    { "2001.A.Space.Odyssey.1968.2160p.mkv", "1968" },
    { "Some.Show.S01E02.720p.mkv", "" },
    { "Old.Film.(1931).avi", "1931" },
    { "Clip.20240131.mkv", "" },
  }
  for _, c in ipairs(cases) do
    it("year of '" .. c[1] .. "' is '" .. c[2] .. "'", function()
      local server = api.new()
      server:on("GET api.opensubtitles.com/api/v1/utilities/guessit", function()
        return api.response(503, { message = "down" })
      end)
      local _, w = start({ server = server, media = "file:///videos/" .. c[1] })
      eq(w.year:get_text(), c[2])
    end)
  end
end)

describe("search: API errors", function()
  local function failing(status, body, headers)
    local env, w = start()
    env.server:on(SUBTITLES, function() return api.response(status, body or { message = "x" }, headers) end)
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    return env, w
  end

  it("token rejected by the server (401): logs in again and repeats the search once", function()
      local env, w = start()
      w.title:set_text("big buck bunny")
      w.by_name:_click()                      -- logs in, token cached on disk
      env.server.token = "rotated-server-side" -- e.g. password changed elsewhere
      env.server:reset()
      env.server.rate_limit = 6                -- stop a runaway loop like the real API would
      env.server:on(SUBTITLES, function(req, srv)
        if req.headers["authorization"] ~= "Bearer " .. srv.token then
          return api.response(401, { message = "Unauthorized", status = 401 })
        end
        return api.fixture("search_imdb")
      end)
      w.by_name:_click()
      eq(#env.server:seen("POST api.opensubtitles.com/api/v1/login"), 1, "one fresh login")
      eq(#env.server:seen(SUBTITLES), 2, "rejected search + one retry")
      eq(#w.list.values, 1)
    end)

  it("rate limited (real 429 response): no crash, no results", function()
    local env, w = start()
    env.server:on(SUBTITLES, function() return api.fixture("rate_limited") end)
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    eq(#w.list.values, 1, "placeholder row")
  end)

  it("rate limited (429): the user is told to wait", function()
      local env = failing(429, { message = "API rate limit exceeded" })
      ok(env.message():lower():find("rate") or env.message():lower():find("wait")
         or env.message():find("429"), "message: " .. env.message())
    end)

  it("rate limited on an IMDb search: the user is told to wait", function()
    local env, w = start()
    env.server:on(SUBTITLES, function() return api.fixture("rate_limited") end)
    w.imdb:set_text("tt1254207")
    w.by_name:_click()
    has(env.message(), "429")
  end)

  it("credentials no longer valid (login refused after a 401): says so, no request loop", function()
    local env, w = start()
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    env.server:reset()
    env.server.password = "changed-on-the-website"
    env.server:on(SUBTITLES, function() return api.response(401, { message = "Unauthorized" }) end)
    w.by_name:_click()
    eq(#env.server:seen(SUBTITLES), 1, "search requests")
    eq(#env.server:seen("POST api.opensubtitles.com/api/v1/login"), 1, "login attempts")
    has(env.message(), "401")
  end)

  it("server error: the user is told it is the server", function()
    local env = failing(503)
    has(env.message(), "503")
  end)

  it("server error (500/503): no crash, placeholder row", function()
    for _, status in ipairs({ 500, 503 }) do
      local env, w = failing(status)
      eq(#w.list.values, 1)
    end
  end)

  it("redirect (302 from a captive portal): explains that the network intercepts requests", function()
    local env = failing(302, "<html>login</html>", { Location = "http://portal.example/login" })
    has(env.message():lower(), "redirect")
  end)

  it("malformed JSON body: no crash, no results", function()
    local env, w = start()
    env.server:on(SUBTITLES, function()
      return api.response(200, '{"data":[{"id":"1","type":"subtitle","attributes":{', nil, { chunked = 20 })
    end)
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    eq(#w.list.values, 1)
  end)

  known_bug("a JSON body that is not an object (true, 1, \"text\") does not raise",
    "the search code indexes the decoded value without checking that it is a table; found by the behaviour sessions, left as is during the refactor",
    function()
      for _, body in ipairs({ "true", "1", '"text"' }) do
        local env, w = start()
        env.server:on(SUBTITLES, function() return api.response(200, body) end)
        w.title:set_text("big buck bunny")
        w.by_name:_click()
        eq(#w.list.values, 1, "placeholder row for body " .. body)
      end
    end)

  it("unexpected shapes: missing files / attributes / uploader do not crash", function()
    local env, w = start()
    env.server:on(SUBTITLES, function()
      return api.response(200, { data = {
        { id = "1", type = "subtitle", attributes = { language = "en", release = "no files" } },
        { id = "2", type = "subtitle" },
        { id = "3", type = "feature", attributes = {} },
        { id = "4", type = "subtitle", attributes = { files = {}, uploader = {} } },
      } }, nil, { chunked = 100 })
    end)
    w.title:set_text("big buck bunny")
    w.by_name:_click()
    eq(#w.list.values, 2, "only well-formed subtitle entries are listed")
  end)
end)
