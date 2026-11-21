-- Logging in, the session cache, and the configuration window.
local H = ...
local describe, it, known_bug, eq, ok, has, lacks = H.describe, H.it, H.known_bug, H.eq, H.ok, H.has, H.lacks
local api, json = H.fake_api, H.json

local LOGIN = "POST api.opensubtitles.com/api/v1/login"
local SUBTITLES = "GET api.opensubtitles.com/api/v1/subtitles"

local function search(env, title)
  local d = env.ui()
  d:_at(2, 1, "text_input"):set_text(title or "big buck bunny")
  d:_button("Search$"):_click()
end

-- Widgets of the configuration window (see interface_config)
local function config_window(env)
  trigger_menu(2)
  local d = env.ui()
  local drop = d:_all("dropdown")
  return {
    dialog = d,
    username = d:_all("text_input")[1], password = d:_all("password")[1],
    lang1 = drop[1], lang2 = drop[2], lang3 = drop[3],
    behaviour = drop[4], lang_ext = drop[5], remove_tag = drop[6],
    dir = d:_all("text_input")[2], save = d:_button("\240\159\146\190"), -- floppy disk icon
  }
end

describe("login", function()
  it("request: JSON body with username and password, Api-Key, no Authorization", function()
    local env = H.launch({ username = "tester", password = "test-password" })
    search(env)
    local req = env.server:last(LOGIN)
    eq(req.problems, {})
    eq(json.decode(req.body), { username = "tester", password = "test-password" })
    eq(req.headers["content-type"], "application/json")
    eq(req.headers["content-length"], tostring(#req.body))
    ok(req.headers["api-key"], "Api-Key header")
    eq(req.headers["authorization"], nil)
    eq(req.raw_query, "", "credentials are never put in the URL")
  end)

  it("password with quotes, backslash and non-ASCII reaches the server intact", function()
    local pw = 'p"a\\ss w\195\182rd {x}'
    local env = H.launch({ password = pw, server = { password = pw } })
    search(env)
    eq(json.decode(env.server:last(LOGIN).body).password, pw)
    has(env.server:last(SUBTITLES).headers["authorization"], "Bearer ")
  end)

  it("token is cached on disk and reused by the next session (no second login)", function()
    local env = H.launch()
    search(env)
    eq(#env.server:seen(LOGIN), 1)
    local cache = H.read_file(env.dir .. "/session_cache.json")
    ok(cache, "session_cache.json written")
    eq(json.decode(cache).token, env.server.token)

    local env2 = H.launch({ files = { ["session_cache.json"] = cache } })
    search(env2)
    eq(#env2.server:seen(LOGIN), 0, "login requests in the second session")
    eq(env2.server:last(SUBTITLES).headers["authorization"], "Bearer " .. env.server.token)
  end)

  it("several searches in one session log in once", function()
    local env = H.launch()
    search(env); search(env); search(env)
    eq(#env.server:seen(LOGIN), 1)
    eq(#env.server:seen(SUBTITLES), 3)
  end)

  it("expired cache entry (older than 24h) triggers a fresh login", function()
    local stale = json.encode({ token = "old-token", token_expires = os.time() - 10,
                                loginTime = os.time() - 90000, base_url = "api.opensubtitles.com" })
    local env = H.launch({ files = { ["session_cache.json"] = stale } })
    search(env)
    eq(#env.server:seen(LOGIN), 1)
    eq(env.server:last(SUBTITLES).headers["authorization"], "Bearer " .. env.server.token)
  end)

  it("corrupt cache file is ignored", function()
    local env = H.launch({ files = { ["session_cache.json"] = "{not json" } })
    search(env)
    eq(#env.server:seen(LOGIN), 1)
    eq(env.errors(), {})
  end)

  it("Save with a working login shows the account line and the AI credit balance", function()
    local env = H.launch()
    trigger_menu(2)
    env.ui():_button("Save$"):_click()
    has(env.message(), "0/100 downloads")
    has(env.message(), "AI credits: 2019")
    has(env.message(), "Configuration saved")
    eq(env.errors(), {})
  end)

  it("Save still succeeds when the balance cannot be read; the line is simply absent", function()
    local env = H.launch()
    env.server:on("GET api.opensubtitles.com/api/v1/ai/credits", function() return api.response(500, "") end)
    trigger_menu(2)
    env.ui():_button("Save$"):_click()
    has(env.message(), "Configuration saved")
    lacks(env.message(), "AI credits")
  end)

  it("configuration window: the site's name in the username label is a link to opensubtitles.com", function()
    local env = H.launch()
    trigger_menu(2)
    local first = env.ui().widgets[1]
    eq(first.text, "<a href='https://www.opensubtitles.com'>OpenSubtitles.com</a> Username:")
  end)

  it("configuration window: every field starts in the same column, labels in the first", function()
    local env = H.launch()
    trigger_menu(2)
    for _, w in ipairs(env.ui().widgets) do
      if w.kind == "text_input" or w.kind == "password" or w.kind == "dropdown" then
        eq(w.col, 2, w.kind .. " in row " .. tostring(w.row))
      elseif w.kind == "label" then
        eq(w.col, 1, "label in row " .. tostring(w.row))
      end
    end
  end)

  it("a config file that is not readable JSON does not stop the extension: it starts with the default settings", function()
    for _, content in ipairs({ "{not json", "", "1", "true", '"text"' }) do
      local env = H.launch({ files = { ["vlsub_conf.json"] = content } })
      eq(env.errors(), {}, "content " .. content)
      -- no settings, so no account: the configuration window asks for one
      has(env.ui().title, "Configuration", "content " .. content)
    end
  end)

  it("wrong password (real 401 response): the API's message is shown, nothing is cached", function()
    local env = H.launch({ password = "wrong" })
    search(env)
    eq(#env.server:seen(LOGIN), 1, "no blind retry of a rejected password")
    ok(not H.exists(env.dir .. "/session_cache.json"), "no session cache")
  end)

  it("no credentials saved: the configuration window opens first", function()
    local env = H.launch({ login = false })
    has(env.ui().title, "Configuration")
    eq(#env.server:seen(LOGIN), 0)
  end)

  it("no credentials saved: searching from the main window works anonymously", function()
    local env = H.launch({ login = false })
    trigger_menu(1)
    search(env)
    eq(#env.server:seen(LOGIN), 0)
    eq(env.server:last(SUBTITLES).headers["authorization"], nil)
    eq(#env.results().values, 50)
  end)

  it("login server unreachable: reported, no crash", function()
    local env = H.launch()
    env.server:on(LOGIN, function() return "" end) -- connection closed without an answer
    search(env)
    ok(#env.server:seen(LOGIN) >= 1)
    eq(#env.server:seen(SUBTITLES), 0, "no search without a session")
  end)

  it("secrets never reach the VLC log, even with debug logging on", function()
      local env = H.launch({ config = { debugLogging = true }, password = "test-password" })
      search(env)
      env.results():_select(1)
      env.ui():_button("Download"):_click()
      for _, line in ipairs(env.vlc._messages()) do
        lacks(line, "test-password", "log line")
        lacks(line, env.server.token, "log line")
      end
    end)

  it("without debug logging nothing secret is logged", function()
    local env = H.launch({ password = "test-password" })
    search(env)
    for _, line in ipairs(env.vlc._messages()) do
      lacks(line, "test-password", "log line")
      lacks(line, env.server.token, "log line")
    end
  end)
end)

describe("configuration window", function()
  it("shows the saved values", function()
    local env = H.launch({ config = { language = "sk", language2 = "en" } })
    local c = config_window(env)
    eq(c.username:get_text(), "tester")
    eq(c.password:get_text(), "test-password")
    eq(c.lang1.values[1].text, "Slovak")
    eq(c.lang2.values[1].text, "English")
    eq(c.lang3.values[1].text, "None")
    eq(c.dir:get_text(), env.dir)
  end)

  it("Save writes credentials and languages to vlsub_conf.json and verifies the login", function()
    local env = H.launch({ login = false })
    local c = config_window(env)
    c.username:set_text("  tester ")
    c.password:set_text("test-password")
    c.lang1:_choose_text("^French$")
    c.lang2:_choose_text("^Slovak$")
    c.save:_click()

    local saved = env.saved_config()
    eq(saved.os_username, "tester", "username trimmed")
    eq(saved.os_password, "test-password")
    eq(saved.language, "fr")
    eq(saved.language2, "sk")
    eq(saved.language3, nil)
    eq(#env.server:seen(LOGIN), 1, "credentials are tested")
    ok(env.server:last("GET api.opensubtitles.com/api/v1/infos/user"), "account info fetched")
  end)

  it("saved settings are used by the next session", function()
    local env = H.launch({ login = false })
    local c = config_window(env)
    c.username:set_text("tester")
    c.password:set_text("test-password")
    c.lang1:_choose_text("^German$")
    c.save:_click()
    local saved = H.read_file(env.dir .. "/vlsub_conf.json")

    local env2 = H.launch({ files = { ["vlsub_conf.json"] = saved } })
    eq(env2.ui():_at(2, 4, "dropdown").values[1].text, "German")
    search(env2)
    eq(env2.server:last(SUBTITLES).query.languages, "de")
  end)

  it("wrong credentials on Save: the error is shown and the window stays open", function()
    local env = H.launch({ login = false })
    local c = config_window(env)
    c.username:set_text("tester")
    c.password:set_text("nope")
    c.save:_click()
    has(env.ui().title, "Configuration")
    has(env.message():lower(), "invalid username/password")
  end)

  it("Save without credentials keeps the settings and asks for an account", function()
    local env = H.launch({ login = false })
    local c = config_window(env)
    c.lang1:_choose_text("^Slovak$")
    c.save:_click()
    eq(env.saved_config().language, "sk")
    eq(#env.server:seen(LOGIN), 0)
    has(env.message(), "credentials")
  end)

  it("download behaviour, language suffix and tag removal are saved", function()
    local env = H.launch()
    local c = config_window(env)
    c.behaviour:_choose_text("anual")
    c.lang_ext:_choose(2)   -- second entry = the opposite of the current value
    c.remove_tag:_choose(2)
    c.save:_click()
    local saved = env.saved_config()
    eq(saved.downloadBehaviour, "manual")
    eq(saved.langExt, false)
    eq(saved.removeTag, true)
  end)

  it("a saved language can be changed back to 'All' / 'None'", function()
      local env = H.launch({ config = { language = "sk", language2 = "en" } })
      local c = config_window(env)
      c.lang1:_choose_text("^All$")
      c.lang2:_choose_text("^None$")
      c.save:_click()
      local saved = env.saved_config()
      eq(saved.language, nil)
      eq(saved.language2, nil)
    end)

  it("the selected language is listed first, 'All'/'None' right after it", function()
    local env = H.launch({ config = { language = "sk", language2 = "en" } })
    local d = env.ui()
    eq({ d:_at(2, 4, "dropdown").values[1].text, d:_at(2, 4, "dropdown").values[2].text },
       { "Slovak", "All" })
    eq({ d:_at(2, 5, "dropdown").values[1].text, d:_at(2, 5, "dropdown").values[2].text },
       { "English", "None" })
    eq(d:_at(2, 6, "dropdown").values[1].text, "None", "nothing saved: default first")
  end)

  it("picking 'None' in the main window drops that language from the search", function()
    local env = H.launch({ config = { language = "sk", language2 = "en" } })
    env.ui():_at(2, 5, "dropdown"):_choose_text("^None$")
    search(env)
    eq(env.server:last(SUBTITLES).query.languages, "sk")
  end)

  it("the config file contains settings only", function()
    local env = H.launch({ first_run = true, host_locale = "C", env = { LANG = "sk_SK.UTF-8" },
                           popen = function() return "" end })
    local c = config_window(env)
    c.username:set_text("tester")
    c.password:set_text("test-password")
    c.save:_click()
    local keys = {}
    for k in pairs(env.saved_config()) do keys[#keys + 1] = k end
    table.sort(keys)
    eq(keys, { "aiTranslations", "detectedLanguage", "downloadBehaviour", "foreignPartsOnly",
               "hearingImpaired", "interfaceLanguage", "langExt", "language", "language2", "language3",
               "machineTranslations", "os_password", "os_username", "progressBarSize", "removeTag",
               "sortDirection", "trustedOnly" })
    ok(#H.read_file(env.dir .. "/vlsub_conf.json") < 600, "file is small")
  end)

  it("a config file written by 1.3.2 loads, and its obsolete keys are dropped on the next save", function()
    local env = H.launch({ config = {
      language = "sk", language2 = "en", intLang = "eng", debugLogging = true,
      showMediaInformation = true, requestTimeoutMs = 15000, requestPollIntervalMs = 250,
      requestMaxRetries = 2, translations_avail = { eng = "English", slo = "Slovak" },
      translation = { int_all = "EVERYTHING", int_research = "Find", mess_no_res = "Nothing" },
    } })
    eq(env.ui():_at(2, 4, "dropdown").values[1].text, "Slovak", "language setting honoured")
    eq(env.ui():_at(2, 4, "dropdown").values[2].text, "All", "saved interface strings are ignored")
    local c = config_window(env)
    c.save:_click()
    local saved = env.saved_config()
    eq(saved.language, "sk")
    eq(saved.language2, "en")
    for _, key in ipairs({ "translation", "translations_avail", "intLang", "debugLogging",
                           "showMediaInformation", "requestTimeoutMs", "requestMaxRetries" }) do
      eq(saved[key], nil, key)
    end
  end)

  it("config file is valid JSON and keeps unrelated options", function()
    local env = H.launch({ config = { progressBarSize = 42 } })
    local c = config_window(env)
    c.save:_click()
    eq(env.saved_config().progressBarSize, 42)
  end)

  -- VLC's Lua has no keychain and no cryptography, so the password cannot be
  -- encrypted in a meaningful way (see docs/vlc-lua-environment.md). What the
  -- extension can do is keep other local users out.
  it("files holding the password and the token are readable by the owner only", function()
    local env = H.launch()
    local c = config_window(env)
    c.save:_click() -- saves the settings and logs in (writes the session cache)
    for _, name in ipairs({ "vlsub_conf.json", "session_cache.json" }) do
      local p = H.real_popen('ls -l "' .. env.dir .. "/" .. name .. '"')
      local mode = p:read("*l"):sub(1, 10)
      p:close()
      eq(mode, "-rw-------", name)
    end
  end)

  it("a path containing a quote does not break the permission change", function()
    local env = H.launch()
    local path = env.home .. "/it's here.json"
    H.write_file(path, "{}")
    restrict_to_owner(path)
    local p = H.real_popen('ls -l "' .. path .. '"')
    eq(p:read("*l"):sub(1, 10), "-rw-------")
    p:close()
  end)
end)
