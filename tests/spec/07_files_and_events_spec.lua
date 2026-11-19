-- File naming, pure helpers, window plumbing, VLC callbacks, update check.
local H = ...
local describe, it, known_bug, eq, ok, has = H.describe, H.it, H.known_bug, H.eq, H.ok, H.has
local api, json = H.fake_api, H.json

local function save(env, name, item, content)
  openSub.file.hasInput = true
  openSub.file.name = name
  return openSub.saveAndLoadSubtitle(content or "content", item or { SubFormat = "srt", SubLanguageID = "en" })
end

describe("subtitle file names", function()
  local function saved_name(name, o)
    local dir = H.tmpdir()
    local env = H.launch(o)
    env.play("file://" .. dir .. "/x.mkv")
    openSub.file.dir = dir .. "/"
    ok(save(env, name) ~= false, "saveAndLoadSubtitle returned false")
    local files = H.ls(dir)
    eq(#files, 1, "files written")
    return files[1]
  end

  it("plain name: '<name>.<lang>.srt'", function()
    eq(saved_name("My.Movie.2020"), "My.Movie.2020.en.srt")
  end)

  it("characters Windows forbids are replaced (regression: v1.3.1 crash, issue #50)", function()
    local name = saved_name('a<b>c:d"e/f\\g|h?i*j')
    ok(not name:find('[<>:"/\\|?*]'), name)
    eq(name, "a_b_c_d_e_f_g_h_i_j.en.srt")
  end)

  it("very long names are cut to 180 bytes plus suffix", function()
    local name = saved_name("token=" .. string.rep("a1B2", 100))
    eq(#name, 180 + #".en.srt")
  end)

  it("a multi-byte UTF-8 name is never cut in the middle of a character", function()
    local name = saved_name(string.rep("\195\169", 200)) -- 200 x e-acute, 400 bytes
    local stem = name:gsub("%.en%.srt$", "")
    ok(#stem <= 180, "stem length " .. #stem)
    eq(stem, string.rep("\195\169", #stem / 2))
  end)

  it("trailing dots and spaces are removed; an empty result becomes 'subtitle'", function()
    eq(saved_name("Movie. . ."), "Movie.en.srt")
    eq(saved_name("???"), "subtitle.en.srt")
  end)

  it("empty subtitle content is refused", function()
    local env = H.launch()
    eq(openSub.saveAndLoadSubtitle("", { SubFormat = "srt" }), false)
  end)
end)

describe("helpers", function()
  it("build_sorted_url: sorted, lower-cased, ids without leading zeros or 'tt'", function()
    H.launch({ activate = false })
    eq(build_sorted_url("http://h/p", { query = "The Matrix", year = 1999, languages = "EN,fr" }),
       "http://h/p?languages=en%2Cfr&query=the+matrix&year=1999")
    eq(build_sorted_url("http://h/p", { imdb_id = "tt0133093" }), "http://h/p?imdb_id=133093")
    eq(build_sorted_url("http://h/p", { season_number = "02", episode_number = "010" }),
       "http://h/p?episode_number=10&season_number=2")
    eq(build_sorted_url("http://h/p", {}), "http://h/p")
    eq(build_sorted_url("http://h/p?a=1", { b = 2 }), "http://h/p?a=1&b=2")
  end)

  it("build_sorted_url output is what the API accepts without a redirect", function()
    H.launch({ activate = false })
    local mock = H.mock
    for _, params in ipairs({
      { query = "Am\195\169lie 2001", languages = "pt-BR,zh-CN", year = "2001" },
      { moviehash = "8E245D9679D31E12", moviebytesize = "0012909756", languages = "en" },
      { imdb_id = "TT0096697", season_number = "01", episode_number = "0" },
    }) do
      local url = build_sorted_url("http://api.opensubtitles.com/api/v1/subtitles", params)
      local req = mock.parse_request("GET " .. url:gsub("^http://[^/]+", "") ..
        " HTTP/1.1\r\nHost: api.opensubtitles.com\r\n\r\n", "api.opensubtitles.com", 80)
      ok(api.is_canonical(req), "not canonical, the API would answer 301: " .. req.raw_query)
    end
  end)

  it("url_encode / url_decode round-trip", function()
    H.launch({ activate = false })
    for _, s in ipairs({ "plain", "a b+c", "50% & more=?", "\195\169\195\188", "x/y:z#w" }) do
      eq(url_decode(url_encode(s)), s)
    end
    eq(url_encode("a b"), "a+b")
  end)

  it("extractIMDBId", function()
    H.launch({ activate = false })
    eq(extractIMDBId("tt1254207"), "1254207")
    eq(extractIMDBId("1254207"), "1254207")
    eq(extractIMDBId("https://www.imdb.com/title/tt0096697/?ref=x"), "0096697")
    eq(extractIMDBId("hello"), nil)
    eq(extractIMDBId(""), nil)
  end)

  it("compare_versions", function()
    H.launch({ activate = false })
    eq(compare_versions("1.3.1", "1.3.1"), 0)
    ok(compare_versions("1.3.2", "1.3.1") > 0)
    ok(compare_versions("1.10.0", "1.9.9") > 0, "numeric, not string comparison")
    ok(compare_versions("1.3.0", "1.3.1") < 0)
    ok(compare_versions("v2.0.0", "1.9.9") > 0, "leading v")
  end)

  it("trim, is_window_path", function()
    H.launch({ activate = false })
    eq(trim("  a b \t\n"), "a b")
    ok(is_window_path("C:\\Users\\x"))
    ok(not is_window_path("/home/x"))
  end)

end)

describe("windows and VLC callbacks", function()
  it("menu entries open main, configuration and help windows", function()
    local env = H.launch()
    eq(#menu(), 3)
    for id, expect in ipairs({ "", "Configuration", "Help" }) do
      trigger_menu(id)
      local d = env.ui()
      ok(#d.widgets > 0, "window " .. id .. " has widgets")
      if expect ~= "" then has(d.title, expect) end
    end
  end)

  it("only one window is visible at a time", function()
    local env = H.launch()
    trigger_menu(2); trigger_menu(1); trigger_menu(3)
    eq(env.vlc._visible_dialogs(), 1)
  end)

  it("every button in every window has a working callback", function()
    local env = H.launch()
    for id = 1, 3 do
      trigger_menu(id)
      for _, b in ipairs(env.ui():_all("button")) do
        eq(type(b.func), "function", "callback of '" .. b.text .. "'")
      end
    end
  end)

  it("Config and Help buttons switch windows; Close on help returns", function()
    local env = H.launch()
    env.ui():_button("Config"):_click()
    has(env.ui().title, "Configuration")
    env.ui():_button("Help"):_click()
    has(env.ui().title, "Help")
    env.ui():_button("Close"):_click()
    ok(not env.ui().title:find("Help"), "left the help window: " .. env.ui().title)
  end)

  it("close() and deactivate() do not raise", function()
    local env = H.launch()
    close()
    deactivate()
  end)

  it("input_changed: fields follow a new media item, typed text survives the same item", function()
    local env = H.launch()
    local title = env.ui():_at(2, 1, "text_input")
    env.play("file:///videos/Big.Buck.Bunny.2008.mkv")
    input_changed()
    eq(title:get_text(), "Big Buck Bunny")
    eq(env.ui():_at(2, 3, "text_input"):get_text(), "2008")

    title:set_text("typed by user")
    input_changed()
    eq(title:get_text(), "typed by user")

    env.play("file:///videos/Breaking.Bad.S02E05.720p.mkv")
    input_changed()
    eq(title:get_text(), "Breaking Bad")
    eq(env.ui():_at(2, 2, "text_input"):get_text(), "2")
    eq(env.ui():_at(4, 2, "text_input"):get_text(), "5")
  end)

  it("input_changed with no media and with the configuration window open", function()
    local env = H.launch()
    input_changed()
    trigger_menu(2)
    env.play("file:///videos/Big.Buck.Bunny.2008.mkv")
    input_changed()
    has(env.ui().title, "Configuration")
  end)

  it("meta_changed is harmless", function()
    H.launch()
    meta_changed()
  end)

  it("Link button shows the subtitle page of the selected result", function()
    local env = H.launch()
    env.ui():_at(2, 1, "text_input"):set_text("big buck bunny")
    env.ui():_button("Search$"):_click()
    env.results():_select(1)
    env.ui():_button("Link"):_click()
    has(env.message(), "opensubtitles.com")
  end)
end)

describe("update check", function()
  local RELEASES = "GET api.github.com/repos/opensubtitles/vlsub-opensubtitles-com/releases/latest"

  it("runs at most once a day", function()
    local env = H.launch()
    eq(#env.server:seen(RELEASES), 1)
    local stamp = H.read_file(env.dir .. "/last_update_check.json")
    ok(stamp, "last_update_check.json written")
    local env2 = H.launch({ files = { ["last_update_check.json"] = stamp } })
    eq(#env2.server:seen(RELEASES), 0)
  end)

  it("same or older release: nothing is offered", function()
    local env = H.launch({ server = { latest_version = "0.0.1" } })
    ok(not env.ui().title:find("Update"), env.ui().title)
  end)

  it("newer release: an update window is offered", function()
    local env = H.launch({ server = { latest_version = "99.0.0" } })
    local found = false
    for _, d in ipairs(env.vlc._dialogs) do
      for _, w in ipairs(d.widgets) do
        if w.text:find("99.0.0", 1, true) then found = true end
      end
    end
    ok(found, "the new version number is shown somewhere")
  end)

  it("GitHub unreachable: startup is unaffected", function()
    local server = api.new()
    server.down["api.github.com"] = true
    local env = H.launch({ server = server })
    ok(env.ui():_button("Search$"))
  end)
end)
