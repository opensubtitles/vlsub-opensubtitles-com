-- Scripted sessions for the behaviour diff (see run.lua). Each session gets
-- S.launch(options) -> env, and S.step(label, action) which runs the action
-- and records everything observable afterwards.
--
-- Keep sessions about WHAT a user does, not how the extension does it: they
-- must run unchanged against v1.3.2 and against any refactored version.

local sessions = {}
local function session(name, run) sessions[#sessions + 1] = { name = name, run = run } end

local SUBTITLES = "GET api.opensubtitles.com/api/v1/subtitles"
local DOWNLOAD = "POST api.opensubtitles.com/api/v1/download"
local LOGIN = "POST api.opensubtitles.com/api/v1/login"
local GUESSIT = "GET api.opensubtitles.com/api/v1/utilities/guessit"
local LANGUAGES = "GET api.opensubtitles.com/api/v1/infos/languages"

-- ----------------------------------------------------------------- helpers --
local function ui(S) return S.env.ui() end
local function field(S, col, row, kind) return ui(S):_at(col, row, kind or "text_input") end
local function click(S, pattern) return function() ui(S):_button(pattern):_click() end end
local function set(S, col, row, text) return function() field(S, col, row):set_text(text) end end
local function choose(S, col, row, pattern)
  return function() field(S, col, row, "dropdown"):_choose_text(pattern) end
end
local function video(S, name, size)
  local dir = S.H.tmpdir()
  return "file://" .. S.H.video(dir, name, size or 200000), dir
end
local function type_and_search(S, title)
  S.step("type title", set(S, 2, 1, title))
  S.step("search by name", click(S, "Search$"))
end
local function select_row(S, id) return function() field(S, 1, 9, "list"):_select(id) end end

-- A scripted machine for first-run locale detection
local function machine(lang, extra)
  local o = extra or {}
  o.first_run = true
  o.host_locale = "C"
  o.env = { LANG = lang or false, LC_ALL = false, LANGUAGE = false, LC_MESSAGES = false,
            LC_CTYPE = false, LC_COLLATE = false }
  local uname = o.uname or "Linux"
  local scripted = o.shell or {}
  o.popen = function(cmd)
    for pattern, output in pairs(scripted) do
      if cmd:find(pattern) then return output end
    end
    if cmd:find("uname") then return uname .. "\n" end
    if cmd:find("^locale %-a") then return "C\nPOSIX\n" end
    if cmd:find("^locale") then return lang and ("LANG=" .. lang .. "\nLC_ALL=\n") or "" end
    if cmd:find("printenv LANG") then return lang and (lang .. "\n") or "" end
    if cmd:find("timedatectl") then return (o.timezone or "Etc/UTC") .. "\n" end
    return ""
  end
  return o
end

local function config_widgets(S)
  local d = ui(S)
  local drop = d:_all("dropdown")
  return { username = d:_all("text_input")[1], password = d:_all("password")[1],
           lang1 = drop[1], lang2 = drop[2], lang3 = drop[3], behaviour = drop[4],
           lang_ext = drop[5], remove_tag = drop[6], dir = d:_all("text_input")[2] }
end

-- --------------------------------------------------------------- first run --
for _, locale in ipairs({ "en_US.UTF-8", "sk_SK.UTF-8", "pt_BR.UTF-8", "zh_TW.UTF-8",
                          "de_AT.UTF-8", "ja_JP.UTF-8", "es_MX.UTF-8", "C" }) do
  session("first run: locale " .. locale, function(S)
    S.launch(machine(locale))
    S.step("open main window", function() trigger_menu(1) end)
  end)
end

session("first run: no locale information (IP geolocation fallback)", function(S)
  S.launch(machine(nil))
end)

session("first run: timezone hints at the country", function(S)
  S.launch(machine("en_US.UTF-8", { timezone = "Europe/Bratislava" }))
end)

session("first run: macOS", function(S)
  S.launch(machine("en_US.UTF-8", { uname = "Darwin", shell = {
    ["AppleLocale"] = "sk_SK\n", ["AppleLanguages"] = '(\n    "sk-SK",\n    "en-SK"\n)\n',
  } }))
end)

session("first run: locale from system files", function(S)
  for path, content in pairs({
    ["/etc/default/locale"] = '# comment\nLANG="sk_SK.UTF-8"\nLC_TIME = de_DE.UTF-8\nFOO=bar\nLC_ALL=C\n',
    ["/etc/locale.conf"] = "LANG=fr_FR.UTF-8\n",
    ["/etc/sysconfig/i18n"] = 'LANG="pt_BR.UTF-8"\nSYSFONT="latarcyrheb-sun16"\n',
    ["/etc/environment"] = "PATH=/usr/bin\nLANGUAGE=es_ES:en\n",
  }) do
    local o = machine(nil)
    o.etc = { [path] = content }
    S.launch(o)
  end
end)

session("first run: locale from files in the home directory", function(S)
  for name, content in pairs({
    [".locale"] = "LANG=ja_JP.UTF-8\n",
    [".config/locale.conf"] = '# mine\n  LANG = "it_IT.UTF-8"  \nlocale=C\n',
    [".dmrc"] = "[Desktop]\nLanguage=pl_PL.utf8\nSession=gnome\n",
  }) do
    local o = machine(nil)
    o.home_files = { [name] = content }
    S.launch(o)
  end
end)

session("first run: installed locales and timezone are the only hints", function(S)
  for _, shell in ipairs({
    { ["^locale %-a"] = "C\nC.UTF-8\nde_DE.utf8\nen_US.utf8\nPOSIX\n" },
    { ["timedatectl"] = "Europe/Berlin\n" },
    { ["timedatectl"] = "Asia/Tokyo\n" },
    { ["timedatectl"] = "Antarctica/Troll\n" },
    { ["printenv LANGUAGE"] = "nl_NL:en\n" },
    { ["printenv LC_ALL"] = "sv_SE.UTF-8\n" },
  }) do
    S.launch(machine(nil, { shell = shell }))
  end
end)

session("first run: completely offline", function(S)
  S.launch(machine("fr_FR.UTF-8", { offline = true }))
  S.step("open main window", function() trigger_menu(1) end)
end)

session("first run: google unreachable, API reachable", function(S)
  local server = S.api.new()
  server.down["www.google.com"] = true
  S.launch(machine("sk_SK.UTF-8", { server = server }))
end)

session("first run: with a video playing", function(S)
  local o = machine("en_US.UTF-8")
  o.media = video(S, "Big.Buck.Bunny.2008.1080p.mkv")
  S.launch(o)
end)

session("first run: enter credentials and save", function(S)
  S.launch(machine("sk_SK.UTF-8"))
  S.step("fill in account", function()
    local c = config_widgets(S)
    c.username:set_text("tester")
    c.password:set_text("test-password")
  end)
  S.step("save", click(S, "\240\159\146\190"))
  S.step("open main window", function() trigger_menu(1) end)
  type_and_search(S, "big buck bunny")
end)

-- A Windows-flavoured run on a Unix test machine: VLC reports a Windows data
-- directory, so the extension takes its Windows branches (backslash paths,
-- USERPROFILE, cmd.exe command lines). File names with backslashes are legal
-- on Unix, so the files really get written; shell commands are swallowed.
local function windows(o)
  o = o or {}
  o.datadir = "C:\\Program Files\\VideoLAN\\VLC"
  o.userdatadir = "C:\\Users\\tester\\AppData\\Roaming\\vlc"
  o.env = o.env or {}
  o.env.USERPROFILE = "C:\\Users\\tester"
  o.host_locale = "C"
  o.env = o.env or {}
  o.env.LANG = false
  o.env.LC_ALL = false
  o.env.HOMEDRIVE = "C:"
  o.env.HOMEPATH = "\\Users\\tester"
  o.env.APPDATA = "C:\\Users\\tester\\AppData\\Roaming"
  o.env.LOCALAPPDATA = "C:\\Users\\tester\\AppData\\Local"
  o.execute = function() return true end
  o.popen = function() return "" end
  return o
end

session("windows flavour: first run", function(S)
  local o = windows({ first_run = true })
  o.env.LANG = "sk_SK"
  S.launch(o)
  S.step("open main window", function() trigger_menu(1) end)
end)

session("windows flavour: first run without any hint", function(S)
  S.launch(windows({ first_run = true }))
end)

session("windows flavour: search, download, save settings", function(S)
  S.launch(windows({ first_run = true }))
  S.step("fill in account", function()
    local c = config_widgets(S)
    c.username:set_text("tester")
    c.password:set_text("test-password")
  end)
  S.step("save", click(S, "\240\159\146\190"))
  S.step("main", function() trigger_menu(1) end)
  type_and_search(S, "big buck bunny")
  S.step("select", select_row(S, 1))
  S.step("download", click(S, "Download"))
  S.step("play a windows path", function()
    S.env.play("file:///C:/Users/tester/Videos/Big.Buck.Bunny.2008.mkv") input_changed()
  end)
  S.step("search by hash", click(S, "hash"))
  S.step("download", click(S, "Download"))
  S.step("unc path", function()
    S.env.play("file://nas/share/Movies/Some.Movie.2019.mkv") input_changed()
  end)
  S.step("search by hash", click(S, "hash"))
end)

-- ---------------------------------------------------------- subsequent runs --
session("start: no media", function(S)
  S.launch()
end)

session("start: no credentials saved", function(S)
  S.launch({ login = false })
  S.step("go to main window", function() trigger_menu(1) end)
  type_and_search(S, "big buck bunny")
end)

session("start: local movie (auto search by hash, fallback to name)", function(S)
  S.launch({ media = video(S, "Big.Buck.Bunny.2008.1080p.BluRay.mkv") })
end)

session("start: TV episode", function(S)
  S.launch({ media = video(S, "Breaking.Bad.S02E05.720p.BluRay.x264-DEMAND.mkv") })
  S.step("search by hash again", click(S, "hash"))
end)

session("start: network stream", function(S)
  S.launch({ media = "http://stream.example/live/Some.Movie.2019.mkv?token=abc" })
  S.step("search by hash", click(S, "hash"))
end)

session("start: file with spaces, accents and brackets", function(S)
  S.launch({ media = video(S, "Am\195\169lie [2001] (Director's Cut).mkv") })
end)

session("start: offline with caches from an earlier session", function(S)
  local env = S.H.launch({ script = nil })
  ui({ env = env }):_at(2, 1, "text_input"):set_text("big buck bunny")
  ui({ env = env }):_button("Search$"):_click()
  local files = {}
  for _, name in ipairs({ "cache_subtitle_languages.json", "session_cache.json", "last_update_check.json" }) do
    files[name] = S.H.read_file(env.dir .. "/" .. name)
  end
  S.launch({ files = files, offline = true })
  type_and_search(S, "big buck bunny")
end)

session("start: offline, nothing cached", function(S)
  S.launch({ offline = true })
  type_and_search(S, "big buck bunny")
  S.step("search by hash", click(S, "hash"))
end)

session("start: language list unavailable (built-in list)", function(S)
  local server = S.api.new()
  server:on(LANGUAGES, function() return "" end)
  S.launch({ server = server, config = { language = "pl", language2 = "he" } })
  type_and_search(S, "big buck bunny")
end)

session("start: saved configuration written by 1.3.2 (with interface strings)", function(S)
  S.launch({ config = {
    language = "sk", language2 = "en", intLang = "eng",
    translations_avail = { eng = "English", slo = "Slovak" },
    translation = { int_all = "All", int_research = "Search", mess_no_res = "No result" },
    downloadBehaviour = "save", langExt = true, removeTag = false, progressBarSize = 80,
  } })
  type_and_search(S, "big buck bunny")
end)

session("start: unusual saved options", function(S)
  S.launch({ config = { language = "xx-gone", language2 = "en", language3 = "en",
                        progressBarSize = 20, sortBy = "download_count", sortDirection = "asc",
                        removeTag = true, langExt = false, showMediaInformation = false } })
  type_and_search(S, "big buck bunny")
end)

session("start: stale and corrupt cache files", function(S)
  S.launch({ files = {
    ["session_cache.json"] = "{not json",
    ["cache_subtitle_languages.json"] = '{"data":"oops"}',
    ["last_update_check.json"] = "",
  } })
  type_and_search(S, "big buck bunny")
end)

session("start: session cache of another user", function(S)
  S.launch({ files = { ["session_cache.json"] = S.H.json.encode({
    token = "someone-elses-token", token_expires = os.time() + 3600, username = "other",
    loginTime = os.time(), base_url = "api.opensubtitles.com" }) } })
  type_and_search(S, "big buck bunny")
end)

-- ------------------------------------------------------------------- search --
session("search by name: title, year, then season and episode", function(S)
  S.launch()
  S.step("title", set(S, 2, 1, "The Big  Buck BUNNY"))
  S.step("year", set(S, 2, 3, "2008"))
  S.step("search", click(S, "Search$"))
  S.step("tv fields", function()
    field(S, 2, 1):set_text("Breaking Bad")
    field(S, 2, 3):set_text("")
    field(S, 2, 2):set_text("2")
    field(S, 4, 2):set_text("05")
  end)
  S.step("search", click(S, "Search$"))
  S.step("zero season", function() field(S, 2, 2):set_text("0") field(S, 4, 2):set_text("x") end)
  S.step("search", click(S, "Search$"))
end)

session("search by name: special characters, empty title, no results", function(S)
  S.launch()
  type_and_search(S, "Am\195\169lie & Fr\195\188hst\195\188ck: 50% / #1?")
  type_and_search(S, "   ")
  type_and_search(S, "zzz nothing here")
  type_and_search(S, "tab\tand \"quotes\" 'single' <b>html</b>")
end)

session("search: languages and sorting", function(S)
  S.launch()
  S.step("three languages", function()
    field(S, 2, 4, "dropdown"):_choose_text("^Slovak$")
    field(S, 2, 5, "dropdown"):_choose_text("^English$")
    field(S, 2, 6, "dropdown"):_choose_text("^French$")
  end)
  type_and_search(S, "big buck bunny")
  S.step("same language twice", choose(S, 2, 6, "^English$"))
  S.step("search", click(S, "Search$"))
  S.step("regional codes", function()
    field(S, 2, 4, "dropdown"):_choose_text("Portuguese %(BR%)")
    field(S, 2, 5, "dropdown"):_choose_text("Chinese %(simplified%)")
    field(S, 2, 6, "dropdown"):_choose_text("^None$")
  end)
  S.step("search", click(S, "Search$"))
  S.step("all languages", function()
    field(S, 2, 4, "dropdown"):_choose_text("^All$")
    field(S, 2, 5, "dropdown"):_choose_text("^None$")
  end)
  S.step("search", click(S, "Search$"))
  for _, sort in ipairs({ "^Downloads$", "^Language$", "^Votes$", "^Default$" }) do
    S.step("sort by " .. sort, choose(S, 2, 7, sort))
    S.step("ascending", choose(S, 5, 7, "^Asc"))
    S.step("search", click(S, "Search$"))
    S.step("descending", choose(S, 5, 7, "^Desc"))
    S.step("search", click(S, "Search$"))
  end
end)

session("search: results grouped by selected languages", function(S)
  local server = S.api.new()
  local data = {}
  for i, lang in ipairs({ "fr", "en", "de", "sk", "en", "fr", "pt-BR" }) do
    data[i] = { id = tostring(i), type = "subtitle", attributes = {
      subtitle_id = tostring(i), language = lang, release = "rel-" .. i, download_count = i * 1000,
      new_download_count = i, hearing_impaired = i % 2 == 0, hd = i % 3 == 0, fps = 23.976,
      votes = i, ratings = i / 2, from_trusted = i == 2, ai_translated = i == 3,
      machine_translated = i == 4, moviehash_match = i == 5, upload_date = "2020-01-0" .. i .. "T00:00:00Z",
      uploader = { name = "user" .. i, rank = i == 2 and "Trusted" or "" },
      feature_details = { movie_name = "Movie", year = 2020, imdb_id = 123 },
      files = { { file_id = 100 + i, file_name = "f" .. i } } } }
  end
  server:on(SUBTITLES, function() return S.api.response(200, { data = data }, nil, { chunked = 300 }) end)
  S.launch({ server = server, config = { language = "sk", language2 = "en" } })
  type_and_search(S, "x")
  S.step("select a row", select_row(S, 4))
  S.step("link", click(S, "Link"))
end)

session("search by IMDb id", function(S)
  S.launch()
  for _, input in ipairs({ "tt1254207", "1254207", "tt0096697", "https://www.imdb.com/title/tt1254207/",
                           "not-an-id", "  tt0133093  ", "" }) do
    S.step("imdb '" .. input .. "'", set(S, 4, 3, input))
    S.step("title", set(S, 2, 1, "ignored title"))
    S.step("search", click(S, "Search$"))
  end
end)

for size, label in pairs({ [200000] = "200 kB", [131072] = "exactly 128 KiB", [1000000] = "1 MB", [70000] = "70 kB" }) do
  session("search by hash: " .. label .. " file", function(S)
    S.launch({ media = video(S, "clip.mkv", size), activate = true })
    S.step("search by hash", click(S, "hash"))
  end)
end

session("search by hash: hit", function(S)
  local server = S.api.new()
  server:on(SUBTITLES, function(req)
    if req.query.moviehash then return S.api.fixture("search_hash") end
    return S.api.fixture("search_none")
  end)
  S.launch({ server = server, media = video(S, "clip.mkv") })
  S.step("search by hash", click(S, "hash"))
end)

session("search by hash: nothing playing, with and without a title", function(S)
  S.launch()
  S.step("search by hash", click(S, "hash"))
  S.step("title", set(S, 2, 1, "big buck bunny"))
  S.step("search by hash", click(S, "hash"))
end)

session("search: GuessIt unavailable (filename parsing)", function(S)
  for _, name in ipairs({ "Big.Buck.Bunny.2008.1080p.mkv", "Some.Show.S01E02.720p.mkv",
                          "Show 3x07 title.avi", "2001.A.Space.Odyssey.1968.2160p.mkv", "plain.mp4" }) do
    local server = S.api.new()
    server:on(GUESSIT, function() return S.api.response(503, { message = "down" }) end)
    S.launch({ server = server, media = video(S, name) })
    S.step("search by name", click(S, "Search$"))
  end
end)

session("search: GuessIt answer cached on disk", function(S)
  local media = video(S, "Big.Buck.Bunny.2008.mkv")
  S.launch({ media = media })
  S.step("search by hash", click(S, "hash"))
  S.step("another file", function() S.env.play("file:///videos/Breaking.Bad.S02E05.720p.mkv") input_changed() end)
  S.step("search by name", click(S, "Search$"))
end)

for _, status in ipairs({ 301, 302, 400, 401, 403, 404, 406, 429, 500, 502, 503 }) do
  session("search: API answers " .. status, function(S)
    local server = S.api.new()
    server:on(SUBTITLES, function()
      return S.api.response(status, { message = "error " .. status, status = status },
        status < 400 and { Location = "http://portal.example/login" } or nil)
    end)
    S.launch({ server = server, media = video(S, "clip.mkv") })
    type_and_search(S, "big buck bunny")
    S.step("imdb", set(S, 4, 3, "tt1254207"))
    S.step("search", click(S, "Search$"))
  end)
end

session("search: malformed and unexpected API bodies", function(S)
  local bodies = {
    '{"data":[{"id":"1","type":"subtitle","attributes":{',
    '{"data":"not a list"}', '{"total":0}', '[]', 'null', '<html>proxy error</html>', '',
    S.H.json.encode({ data = {
      { id = "1", type = "subtitle", attributes = { language = "en", release = "no files" } },
      { id = "2", type = "subtitle" }, { id = "3", type = "feature", attributes = {} },
      { id = "4", type = "subtitle", attributes = { files = {}, uploader = {} } } } }),
  }
  local server = S.api.new()
  local n = 0
  server:on(SUBTITLES, function()
    n = n + 1
    return S.api.response(200, bodies[n] or "{}", nil, { chunked = 40 })
  end)
  S.launch({ server = server })
  S.step("title", set(S, 2, 1, "big buck bunny"))
  for i = 1, #bodies do S.step("search " .. i, click(S, "Search$")) end
end)

session("search: real rate-limit and unsorted-redirect responses", function(S)
  local server = S.api.new()
  local replies = { "rate_limited", "search_unsorted", "search_none" }
  local n = 0
  server:on(SUBTITLES, function() n = n + 1 return S.api.fixture(replies[n] or "search_none") end)
  S.launch({ server = server, media = video(S, "clip.mkv") })
  S.step("title", set(S, 2, 1, "big buck bunny"))
  for i = 1, 3 do S.step("search " .. i, click(S, "Search$")) end
end)

-- -------------------------------------------------------------------- login --
session("login: wrong password", function(S)
  S.launch({ password = "wrong", media = video(S, "clip.mkv") })
  type_and_search(S, "big buck bunny")
  S.step("select", select_row(S, 1))
  S.step("download", click(S, "Download"))
end)

session("login: special characters in the password", function(S)
  local pw = 'p"a\\ss w\195\182rd {x}'
  S.launch({ password = pw, server = { password = pw } })
  type_and_search(S, "big buck bunny")
end)

session("login: server gives no answer / error statuses", function(S)
  for _, reply in ipairs({ "", 302, 403, 429, 500 }) do
    local server = S.api.new()
    server:on(LOGIN, function()
      if reply == "" then return "" end
      return S.api.response(reply, { message = "login " .. reply, status = reply },
        reply == 302 and { Location = "http://portal.example/" } or nil)
    end)
    S.launch({ server = server })
    type_and_search(S, "big buck bunny")
  end
end)

session("login: odd login responses", function(S)
  for _, body in ipairs({ '{"status":200}', '{"token":"t","status":401,"message":"nope"}', 'not json',
                          '{"token":"abc","user":{"level":"VIP"},"base_url":"vip-api.opensubtitles.com","status":200}' }) do
    local server = S.api.new()
    server:on(LOGIN, function() return S.api.response(200, body) end)
    S.launch({ server = server })
    type_and_search(S, "big buck bunny")
  end
end)

session("login: token rejected later (401), password still valid", function(S)
  S.launch({ media = video(S, "clip.mkv") })
  type_and_search(S, "big buck bunny")
  S.step("server rotates the token", function() S.env.server.token = "rotated" end)
  S.step("search", click(S, "Search$"))
  S.step("search by hash", click(S, "hash"))
  S.step("imdb", set(S, 4, 3, "tt1254207"))
  S.step("search", click(S, "Search$"))
  S.step("rotate again", function() S.env.server.token = "rotated-twice" end)
  S.step("select", select_row(S, 1))
  S.step("download", click(S, "Download"))
end)

session("login: token rejected and password changed", function(S)
  S.launch()
  type_and_search(S, "big buck bunny")
  S.step("account changed on the website", function()
    S.env.server.token = "rotated"
    S.env.server.password = "changed"
    S.env.server:on(SUBTITLES, function(req, srv)
      if req.headers["authorization"] ~= "Bearer " .. srv.token then
        return S.api.response(401, { message = "Unauthorized", status = 401 })
      end
      return S.api.fixture("search_imdb")
    end)
  end)
  S.step("search", click(S, "Search$"))
end)

-- ------------------------------------------------------------ configuration --
session("config: open, change everything, save, reopen", function(S)
  S.launch()
  S.step("open config", click(S, "Config"))
  S.step("change", function()
    local c = config_widgets(S)
    c.lang1:_choose_text("^French$")
    c.lang2:_choose_text("^Slovak$")
    c.lang3:_choose_text("^German$")
    c.behaviour:_choose_text("anual")
    c.lang_ext:_choose(2)
    c.remove_tag:_choose(2)
  end)
  S.step("save", click(S, "\240\159\146\190"))
  S.step("open config again", function() trigger_menu(2) end)
  S.step("back to main", function() trigger_menu(1) end)
  type_and_search(S, "big buck bunny")
end)

session("config: clear languages back to All / None", function(S)
  S.launch({ config = { language = "sk", language2 = "en", language3 = "fr" } })
  S.step("open config", function() trigger_menu(2) end)
  S.step("clear", function()
    local c = config_widgets(S)
    c.lang1:_choose_text("^All$")
    c.lang2:_choose_text("^None$")
    c.lang3:_choose_text("^None$")
  end)
  S.step("save", click(S, "\240\159\146\190"))
  S.step("main", function() trigger_menu(1) end)
end)

session("config: wrong credentials, then none, then correct", function(S)
  S.launch({ login = false })
  for _, pair in ipairs({ { "tester", "nope" }, { "", "" }, { "  tester ", "test-password" } }) do
    S.step("fill " .. pair[1], function()
      local c = config_widgets(S)
      c.username:set_text(pair[1])
      c.password:set_text(pair[2])
    end)
    S.step("save", click(S, "\240\159\146\190"))
  end
end)

session("config: account info endpoint fails", function(S)
  for _, status in ipairs({ 401, 403, 500 }) do
    local server = S.api.new()
    server:on("GET api.opensubtitles.com/api/v1/infos/user", function()
      return S.api.response(status, { message = "user " .. status })
    end)
    S.launch({ server = server })
    S.step("open config", function() trigger_menu(2) end)
    S.step("save", click(S, "\240\159\146\190"))
  end
end)

session("config: change the working directory", function(S)
  S.launch()
  S.step("open config", function() trigger_menu(2) end)
  S.step("new dir", function() config_widgets(S).dir:set_text(S.env.home .. "/elsewhere/vlsub") end)
  S.step("save", click(S, "\240\159\146\190"))
  S.step("empty dir", function() config_widgets(S).dir:set_text("   ") end)
  S.step("save", click(S, "\240\159\146\190"))
end)

session("config: help window and back, close", function(S)
  S.launch()
  S.step("config", click(S, "Config"))
  S.step("help", click(S, "Help"))
  S.step("close help", click(S, "Close"))
  S.step("close config", click(S, "Close"))
  S.step("help from main", click(S, "Help"))
  S.step("close help", click(S, "Close"))
  S.step("menu 3", function() trigger_menu(3) end)
  S.step("close()", function() close() end)
  S.step("deactivate()", function() deactivate() end)
end)

-- ----------------------------------------------------------------- download --
local function searched(S, o)
  o = o or {}
  local dir
  if o.media == nil then o.media, dir = video(S, o.video or "Big.Buck.Bunny.2008.mkv") end
  if o.media == false then o.media = nil end
  S.launch(o)
  if ui(S).title:find("Configuration") then S.step("main", function() trigger_menu(1) end) end
  type_and_search(S, "big buck bunny")
  return dir
end

session("download: next to the video", function(S)
  searched(S)
  S.step("select 3", select_row(S, 3))
  S.step("download", click(S, "Download"))
  S.step("download again", click(S, "Download"))
  S.step("select 1", select_row(S, 1))
  S.step("download", click(S, "Download"))
end)

session("download: nothing selected, then before any search", function(S)
  searched(S)
  S.step("download", click(S, "Download"))
  S.step("link", click(S, "Link"))
  S.launch()
  S.step("download", click(S, "Download"))
  S.step("link", click(S, "Link"))
end)

session("download: options (no language suffix, tags removed, manual)", function(S)
  for _, config in ipairs({ { langExt = false }, { removeTag = true }, { downloadBehaviour = "manual" } }) do
    searched(S, { config = config })
    S.step("select", select_row(S, 1))
    S.step("download", click(S, "Download"))
  end
end)

session("download: no video playing (Downloads folder)", function(S)
  searched(S, { media = false })
  S.step("create ~/Downloads", function() S.H.real_execute('mkdir -p "' .. S.env.home .. '/Downloads"') end)
  S.step("select", select_row(S, 1))
  S.step("download", click(S, "Download"))
end)

session("download: no video and no Downloads folder", function(S)
  searched(S, { media = false })
  S.step("select", select_row(S, 1))
  S.step("download", click(S, "Download"))
end)

session("download: video folder read-only", function(S)
  local dir = searched(S)
  S.step("prepare", function()
    S.H.real_execute('mkdir -p "' .. S.env.home .. '/Downloads"')
    S.H.real_execute('chmod a-w "' .. dir .. '"')
  end)
  S.step("select", select_row(S, 1))
  S.step("download", click(S, "Download"))
  S.step("downloads read-only too", function() S.H.real_execute('chmod a-w "' .. S.env.home .. '/Downloads"') end)
  S.step("download", click(S, "Download"))
  S.step("nothing writable", function() S.H.real_execute('chmod a-w "' .. S.env.dir .. '"') end)
  S.step("download", click(S, "Download"))
  S.step("cleanup", function()
    S.H.real_execute('chmod u+w "' .. dir .. '" "' .. S.env.home .. '/Downloads" "' .. S.env.dir .. '"')
  end)
end)

session("download: stream with a very long URL (issue #50)", function(S)
  searched(S, { media = "http://cdn.example/live/stream.m3u8?token=" .. string.rep("a1B2c3D4", 60) })
  S.step("create ~/Downloads", function() S.H.real_execute('mkdir -p "' .. S.env.home .. '/Downloads"') end)
  S.step("select", select_row(S, 1))
  S.step("download", click(S, "Download"))
end)

session("download: awkward video names", function(S)
  for _, name in ipairs({ 'we<ir>d:na"me|?*.mkv', string.rep("\195\169", 100) .. ".mkv",
                          "trailing dots....mkv", "a  b__c.mkv" }) do
    searched(S, { video = name })
    S.step("select", select_row(S, 1))
    S.step("download", click(S, "Download"))
  end
end)

session("download: not logged in", function(S)
  searched(S, { login = false })
  S.step("select", select_row(S, 1))
  S.step("download", click(S, "Download"))
end)

for _, status in ipairs({ 401, 403, 404, 406, 429, 500, 503 }) do
  session("download: API answers " .. status, function(S)
    searched(S)
    S.step("api breaks", function()
      S.env.server:on(DOWNLOAD, function()
        return S.api.response(status, { message = "download " .. status, status = status })
      end)
    end)
    S.step("select", select_row(S, 1))
    S.step("download", click(S, "Download"))
  end)
end

session("download: quota used up, invalid file id, odd answers", function(S)
  searched(S)
  S.step("select", select_row(S, 1))
  S.step("quota", function() S.env.server.downloads_used = 100 end)
  S.step("download", click(S, "Download"))
  for label, body in pairs({
    a_invalid_id = '{"message":"Invalid file_id"}', b_error = '{"error":"boom"}',
    c_content = '{"content":"1\\n00:00:01,000 --> 00:00:02,000\\ninline\\n"}',
    d_not_json = "1\n00:00:01,000 --> 00:00:02,000\nraw body\n", e_empty = "",
    f_no_quota = '{"link":"https://www.opensubtitles.com/download/X/subfile/y.srt"}' }) do
    S.step("answer " .. label, function()
      S.env.server:on(DOWNLOAD, function() return S.api.response(200, body) end)
    end)
    S.step("download", click(S, "Download"))
  end
end)

session("download: link cannot be fetched / empty / redirect", function(S)
  searched(S)
  S.step("select", select_row(S, 1))
  S.step("link host down", function() S.env.server.down["www.opensubtitles.com"] = true end)
  S.step("download", click(S, "Download"))
  S.step("link returns nothing", function()
    S.env.server.down["www.opensubtitles.com"] = nil
    S.env.server:on("GET www.opensubtitles.com/download/*", function()
      return S.api.response(200, "", { ["Content-Type"] = "text/plain" })
    end)
  end)
  S.step("download", click(S, "Download"))
  S.step("link is plain http", function()
    S.env.server:on(DOWNLOAD, function()
      return S.api.response(200, { link = "http://dl.example/sub.srt", requests = 1, remaining = 9 })
    end)
    S.env.server:on("GET dl.example/sub.srt", function()
      return S.api.response(200, "1\r\n00:00:01,000 --> 00:00:02,000\r\n{\\an8}over http\r\n",
        { ["Content-Type"] = "text/plain" }, { chunked = 9 })
    end)
  end)
  S.step("download", click(S, "Download"))
end)

-- ------------------------------------------------------------ events, update --
session("events: media changes while windows are open", function(S)
  S.launch()
  S.step("no media", function() input_changed() end)
  S.step("movie starts", function() S.env.play("file:///videos/Big.Buck.Bunny.2008.mkv") input_changed() end)
  S.step("user types", set(S, 2, 1, "typed by user"))
  S.step("same media event", function() input_changed() end)
  S.step("episode starts", function() S.env.play("file:///videos/Breaking.Bad.S02E05.720p.mkv") input_changed() end)
  S.step("meta_changed", function() meta_changed() end)
  S.step("config window", function() trigger_menu(2) end)
  S.step("media changes in config", function() S.env.play("file:///videos/Other.Movie.1999.mkv") input_changed() end)
  S.step("media stops", function() S.env.play(nil) input_changed() end)
  S.step("main window", function() trigger_menu(1) end)
end)

session("events: menu and descriptor", function(S)
  S.launch({ activate = false })
  S.step("descriptor", function()
    local d = descriptor()
    vlc.msg.info("descriptor: " .. tostring(d.title) .. " | " .. tostring(d.version) .. " | " ..
                 tostring(d.shortdesc) .. " | " .. table.concat(d.capabilities or {}, ","))
  end)
  S.step("activate", function() activate() end)
  S.step("menu", function() vlc.msg.info("menu: " .. table.concat(menu(), " | ")) end)
  S.step("activate twice", function() activate() end)
end)

for _, version in ipairs({ "0.0.1", "1.3.2", "99.0.0" }) do
  session("update check: latest release is " .. version, function(S)
    S.launch({ server = { latest_version = version } })
    S.step("click every button of the newest window", function()
      for _, b in ipairs(ui(S):_all("button")) do
        if b.text:find("Skip") or b.text:find("Later") or b.text:find("Remind") then b:_click() return end
      end
    end)
  end)
end

session("update check: GitHub unreachable or answering nonsense", function(S)
  local server = S.api.new()
  server.down["api.github.com"] = true
  S.launch({ server = server })
  local server2 = S.api.new()
  server2:on("GET api.github.com/repos/opensubtitles/vlsub-opensubtitles-com/releases/latest", function()
    return S.api.response(200, "<html>rate limited</html>", { ["Content-Type"] = "text/html" })
  end)
  S.launch({ server = server2 })
end)

return sessions
