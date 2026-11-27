-- Feedback on subtitles (API since 2026-11-23): rating after watching, the
-- Rate window (rating, thanks, reports, a file by its MD5), the user's own
-- ratings in the result rows. Answers recorded from the development API
-- (tests/fixtures/raw/rating_*, thanks_*, report_*, feedback_*).
local H = ...
local describe, it, eq, ok, has, lacks = H.describe, H.it, H.eq, H.ok, H.has, H.lacks
local api, json = H.fake_api, H.json

local API = "api.opensubtitles.com/api/v1"
local BUNNY = 4224334 -- first row of the recorded search: Big Buck Bunny (2008), file 4311373

-- A video playing, a search made, the server answering the feedback calls.
-- o.routes: { ["PUT /subtitles/rating"] = fixture name or function(req) }
local function launch(o)
  o = o or {}
  local dir = H.tmpdir()
  local media = "file://" .. H.video(dir, "Big.Buck.Bunny.2008.mkv", 200000)
  local env = H.launch({ media = media, login = o.login, config = o.config })
  local sent = {}
  env.sent, env.dir_video = sent, dir
  local function route(key, fixture)
    env.server:on(key, function(req)
      sent[#sent + 1] = { key = key, path = req.path, query = req.query, raw_query = req.raw_query,
                          body = req.body and req.body ~= "" and json.decode(req.body) or nil,
                          problems = req.problems }
      if type(fixture) == "function" then return fixture(req) end
      return api.fixture(fixture)
    end)
  end
  local routes = {
    ["GET /subtitles/feedback"] = "feedback_none",
    ["PUT /subtitles/rating"] = "rating_saved",
    ["DELETE /subtitles/rating"] = "rating_deleted",
    ["PUT /subtitles/thanks"] = "thanks_saved",
    ["DELETE /subtitles/thanks"] = "thanks_deleted",
    ["POST /subtitles/reports"] = "report_flag",
    ["GET /infos/report_reasons"] = "report_reasons_en",
  }
  for key, fixture in pairs(o.routes or {}) do routes[key] = fixture end
  for key, fixture in pairs(routes) do
    local method, path = key:match("^(%u+) (.*)$")
    route(method .. " " .. API .. path, fixture)
  end
  if env.ui().title:find("Configuration") then trigger_menu(1) end
  env.ui():_at(2, 1, "text_input"):set_text("big buck bunny")
  env.ui():_button("Search$"):_click()
  return env
end

local function last(env, key)
  for i = #env.sent, 1, -1 do
    if env.sent[i].key:find(key, 1, true) then return env.sent[i] end
  end
end

local function calls(env, key)
  local n = 0
  for _, s in ipairs(env.sent) do
    if s.key:find(key, 1, true) then n = n + 1 end
  end
  return n
end

-- Download row 1 (Big Buck Bunny) into the playing video
local function download(env)
  env.results():_select(1)
  env.ui():_button("Download"):_click()
end

-- The film got this far; VLSub's window opened again
local function watched(env, position)
  env.vlc._vars.position = position
  trigger_menu(1)
end

local function question(env)
  local d = env.ui()
  local label = d:_at(1, 12, "label")
  if not label then return nil end
  return { text = label.text, rating = d:_at(1, 13, "dropdown"), sync = d:_at(2, 13, "dropdown"),
           send = d:_at(4, 13, "button"), more = d:_at(5, 13, "button"), not_now = d:_at(6, 13, "button") }
end

local function rate_window(env)
  env.ui():_button("^Rate$"):_click()
  local d = env.ui()
  return {
    target = d:_at(2, 1, "label"), path = d:_at(2, 2, "text_input"), use_file = d:_at(4, 2, "button"),
    rating = d:_at(2, 3, "dropdown"), sync = d:_at(3, 3, "dropdown"),
    send = d:_at(2, 4, "button"), remove = d:_at(3, 4, "button"),
    thank = d:_at(2, 5, "button"), unthank = d:_at(3, 5, "button"),
    reason = d:_at(2, 6, "dropdown"), comment = d:_at(2, 7, "text_input"), report = d:_at(4, 7, "button"),
    status = d:_at(1, 8, "label"), ask = d:_at(1, 10, "button"), back = d:_at(4, 10, "button"),
  }
end

describe("feedback: asked after watching", function()
  it("a film watched with a downloaded subtitle: the main window asks once, Send rates it", function()
    local env = launch()
    download(env)
    eq(question(env), nil, "not before the film is watched")
    watched(env, 0.8)
    local q = question(env)
    ok(q, "the question")
    eq(q.text, "You watched Big Buck Bunny (2008) with these subtitles - how were they?")
    q.send:_click()
    has(env.message(), "Choose a rating first.")
    eq(calls(env, "PUT"), 0)
    q.rating:_choose_text("Good")
    q.sync:_choose_text("too late")
    q.send:_click()
    local req = last(env, "PUT " .. API .. "/subtitles/rating")
    eq(req.problems, {})
    eq(req.body.subtitle, { subtitle_id = BUNNY })
    eq({ req.body.rating, req.body.sync, req.body.watched_ratio }, { 4, "late", 0.8 })
    eq(req.body.video.moviebytesize, 200000)
    eq(#req.body.video.moviehash, 16)
    has(req.body.client, "VLSub")
    has(env.message(), "Thank you! Your rating is saved.")
    eq(question(env), nil, "asked once")
    trigger_menu(1)
    eq(question(env), nil, "and not again")
  end)

  it("not watched far enough: no question", function()
    local env = launch()
    download(env)
    watched(env, 0.4)
    eq(question(env), nil)
  end)

  it("the furthest point counts, written down as the film plays", function()
    local env = launch()
    download(env)
    env.vlc._vars.position = 0.75
    playing_changed()
    env.vlc._vars.position = 0.1 -- went back to the start
    trigger_menu(1)
    ok(question(env), "75 % was reached")
    local stored = json.decode(H.read_file(env.dir .. "/vlsub_feedback.json"))
    eq(stored.records[1].subtitle_id, BUNNY)
    eq(stored.records[1].position, 0.75)
  end)

  it("another film playing: the time since loading decides (most of the film, up to 3 days)", function()
    local env = launch()
    download(env)
    env.play("file:///films/Other.Film.2001.mkv")
    local record = H.find_local("Feedback").data.records[1]
    record.loaded_at = os.time() - 300 -- the mock's films last 600 s
    trigger_menu(1)
    eq(question(env), nil, "half of it")
    record.loaded_at = os.time() - 500
    trigger_menu(1)
    ok(question(env), "most of it")
    record.loaded_at = os.time() - 4 * 24 * 3600
    trigger_menu(1)
    eq(question(env), nil, "too long ago")
  end)

  it("Not now three times: VLSub stops asking and says where to turn it back on", function()
    local env = launch()
    local Feedback = H.find_local("Feedback")
    for round = 1, 3 do
      download(env)
      watched(env, 0.9)
      ok(question(env), "round " .. round)
      question(env).not_now:_click()
      eq(question(env), nil)
      env.vlc._vars.position = 0
      Feedback.data.records[#Feedback.data.records].done = true
    end
    has(env.message(), "VLSub will not ask any more. Turn it back on in the Rate window.")
    eq(env.saved_config().askFeedback, false)
    eq(calls(env, "PUT"), 0, "nothing sent")
    download(env)
    watched(env, 0.9)
    eq(question(env), nil, "off")
    local w = rate_window(env)
    eq(w.ask.text, "Ask after watching: off")
    w.ask:_click()
    eq(w.ask.text, "Ask after watching: on")
    eq(env.saved_config().askFeedback, true)
    w.back:_click()
    ok(question(env), "asked again")
  end)

  it("More... opens the Rate window for that subtitle", function()
    local env = launch()
    download(env)
    watched(env, 0.9)
    question(env).more:_click()
    local d = env.ui()
    has(d.title, "Rate subtitles")
    eq(d:_at(2, 1, "label").text, "Big Buck Bunny (2008) - big_buck_bunny")
  end)

  it("without an account nothing is asked, and Rate says what to do", function()
    local env = launch({ login = false })
    env.server.requests = {}
    eq(question(env), nil)
    env.ui():_button("^Rate$"):_click()
    has(env.message(), "Log in to rate: enter username and password in Config, then Save.")
    eq(calls(env, "/subtitles/feedback"), 0, "no own ratings looked up without a login")
  end)

  it("an AI translation made on demand is not remembered", function()
    local env = launch()
    local note = H.find_local("Feedback")
    feedback_note_loaded({ OnDemand = true, SubtitleID = "123456789012345678901234567890123" })
    eq(note.load().records, {})
  end)
end)

describe("feedback: your own ratings in the results", function()
  it("one request for the listed subtitles; rows show ★ and ♥", function()
    local env = launch({ routes = { ["GET /subtitles/feedback"] = function()
      return api.response(200, { data = {
        { subtitle_id = BUNNY, your_rating = 4, your_thanks = true },
        { subtitle_id = 9891701, your_rating = nil, your_thanks = false } } })
    end } })
    local req = last(env, "/subtitles/feedback")
    local ids = {}
    for id in req.query.subtitle_ids:gmatch("%d+") do ids[#ids + 1] = id end
    eq(ids[1], tostring(BUNNY))
    ok(#ids <= 50, "50 at most")
    local rows = env.results().values
    has(rows[1].text, " ★4 ♥ ")
    lacks(rows[2].text, "★")
    eq(calls(env, "/subtitles/feedback"), 1)
    env.ui():_at(2, 7, "dropdown"):_choose(1) -- sorting again shows the same marks
    display_subtitles()
    eq(calls(env, "/subtitles/feedback"), 1, "asked once per search")
  end)
end)

describe("feedback: the Rate window", function()
  it("the selected result: your rating so far, then send, change, remove", function()
    local env = launch({ routes = { ["GET /subtitles/feedback"] = "feedback_rated" } })
    env.results():_select(1)
    local w = rate_window(env)
    eq(w.target.text, "Big Buck Bunny - big_buck_bunny")
    eq(w.status.text, "Your rating: ★★☆☆☆ Poor") -- recorded: your_rating 2
    eq(w.rating.values[1].text, "★★☆☆☆ Poor", "the rating given is preselected")
    w.rating:_choose(5)
    w.sync:_choose_text("right")
    w.send:_click()
    local req = last(env, "PUT " .. API .. "/subtitles/rating")
    eq({ req.body.subtitle, req.body.rating, req.body.sync }, { { subtitle_id = BUNNY }, 5, "good" })
    eq(req.body.watched_ratio, nil, "a search result: nothing known about watching")
    eq(w.status.text, "Your rating: ★★★★★ Excellent")
    w.remove:_click()
    req = last(env, "DELETE")
    eq(req.path, "/api/v1/subtitles/rating")
    eq(req.raw_query, "subtitle_id=" .. BUNNY)
    has(env.message(), "Your rating is removed.")
    eq(w.status.text, "Not rated by you yet.")
  end)

  it("thanks and taking them back (recorded answers)", function()
    local env = launch()
    env.results():_select(1)
    local w = rate_window(env)
    w.thank:_click()
    eq(last(env, "PUT " .. API .. "/subtitles/thanks").body, { subtitle = { subtitle_id = BUNNY } })
    has(env.message(), "Thanks sent to the uploader.")
    eq(w.status.text, "You thanked the uploader.")
    w.unthank:_click()
    eq(last(env, "DELETE " .. API .. "/subtitles/thanks").raw_query, "subtitle_id=" .. BUNNY)
    has(env.message(), "Thanks taken back.")
  end)

  it("nothing selected: the subtitle loaded last", function()
    local env = launch()
    download(env)
    env.results().selected = {}
    local w = rate_window(env)
    eq(w.target.text, "Big Buck Bunny (2008) - big_buck_bunny")
  end)

  it("nothing at all: says so, and offers the subtitle file next to the video", function()
    local env = launch()
    H.write_file(env.dir_video .. "/Big.Buck.Bunny.2008.cs.srt", "1\n00:00:01,000 --> 00:00:02,000\nAhoj\n")
    local w = rate_window(env)
    eq(w.target.text, "None chosen: select a search result, or enter a subtitle file below.")
    eq(w.path:get_text(), env.dir_video .. "/Big.Buck.Bunny.2008.cs.srt")
    w.send:_click()
    has(env.message(), "Choose a subtitle first")
  end)

  it("a file named by its MD5; one the server does not know is explained (recorded 404)", function()
    local env = launch({ routes = { ["PUT /subtitles/thanks"] = "thanks_unknown_md5" } })
    local path = env.dir_video .. "/mine.srt"
    local content = "1\n00:00:01,000 --> 00:00:02,000\nThere is no spoon.\n"
    H.write_file(path, content)
    local w = rate_window(env)
    w.path:set_text(path)
    w.use_file:_click()
    eq(w.target.text, "File mine.srt")
    w.rating:_choose(4)
    w.send:_click()
    local md5 = H.real_popen('md5sum "' .. path .. '"'):read("*l"):match("^%x+")
    eq(last(env, "PUT " .. API .. "/subtitles/rating").body.subtitle, { md5 = md5 })
    w.thank:_click()
    has(env.message(),
       "This file is not on OpenSubtitles, or it was changed after the download. Rate it from the search results.")
  end)

  it("the server's refusal in its own words (recorded: own upload)", function()
    local env = launch({ routes = { ["PUT /subtitles/rating"] = "rating_own_upload" } })
    env.results():_select(1)
    local w = rate_window(env)
    w.rating:_choose(5)
    w.send:_click()
    has(env.message(), "You cannot rate your own upload")
  end)
end)

describe("feedback: reporting a problem", function()
  it("the reasons come from the API; a reason is needed, 'Other' needs a comment", function()
    local env = launch()
    env.results():_select(1)
    local w = rate_window(env)
    eq(last(env, "/infos/report_reasons").query.language, "en")
    eq(#w.reason.values, 17, "'Choose a problem...' and the 16 reasons")
    w.report:_click()
    has(env.message(), "Choose a problem first.")
    w.reason:_choose_text("^Other$")
    w.report:_click()
    has(env.message(), "Describe the problem in the comment.")
    eq(calls(env, "POST " .. API .. "/subtitles/reports"), 0)
  end)

  it("a flag (recorded answer) and a report for the moderators", function()
    local env = launch()
    env.results():_select(1)
    local w = rate_window(env)
    w.reason:_choose_text("^Sync errors$")
    w.comment:set_text("  half a second late  ")
    w.report:_click()
    eq(last(env, "POST " .. API .. "/subtitles/reports").body,
       { subtitle = { subtitle_id = BUNNY }, reason = "out_of_sync", comment = "half a second late" })
    has(env.message(), "Thank you - the problem is reported.")
    eq(w.comment:get_text(), "")
    env.server:on("POST " .. API .. "/subtitles/reports", function()
      return api.response(201, { status = "received", report_id = 77, reason = "wrong_movie", kind = "report" })
    end)
    w.reason:_choose_text("^Wrong movie$")
    w.report:_click()
    has(env.message(), "Thank you - a moderator will look at it.")
  end)

  it("in the interface language (recorded Czech list); built in when the API cannot be asked", function()
    local env = launch({ config = { interfaceLanguage = "cs" },
                         routes = { ["GET /infos/report_reasons"] = "report_reasons_cs" } })
    trigger_menu(1)
    env.results():_select(1)
    env.ui():_button("Rate$"):_click()
    eq(last(env, "/infos/report_reasons").query.language, "cs")
    has(env.ui():_at(2, 6, "dropdown").values[2].text, "Chyby synchronizace")

    local other = launch({ routes = { ["GET /infos/report_reasons"] = function() return api.response(500, {}) end } })
    other.results():_select(1)
    local w = rate_window(other)
    eq(#w.reason.values, 17)
    eq(w.reason.values[17].text, "Other")
  end)
end)
