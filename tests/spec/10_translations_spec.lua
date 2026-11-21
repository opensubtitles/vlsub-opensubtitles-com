-- Interface translations: choosing a language, fetching it from the
-- repository, storing it, and never letting a translation break a window.
local H = ...
local describe, it, eq, ok, has, lacks = H.describe, H.it, H.eq, H.ok, H.has, H.lacks
local api, json = H.fake_api, H.json

local LOCALE = "GET raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/locale/"
local SLOVAK = json.decode(H.read_file(H.ROOT .. "/locale/sk.json"))
local ENGLISH = json.decode(H.read_file(H.ROOT .. "/locale/en.json"))

-- A server whose repository offers Slovak as a reviewed translation
local function server_with(status, translation)
  local server = api.new()
  server.locale["index.json"] = json.encode({ format = 1, languages = {
    { code = "sk", name = "Sloven\196\141ina", english_name = "Slovak", status = status or "ready" } } })
  if translation then server.locale["sk.json"] = json.encode(translation) end
  return server
end

local function config_window(env)
  trigger_menu(2)
  local d = env.ui()
  return { dialog = d, language = d:_at(2, 9, "dropdown"), save = d:_at(1, 13, "button") }
end

local function labels(d)
  local out = {}
  for _, w in ipairs(d.widgets) do
    -- (links are not part of what a label says)
    if w.kind == "label" or w.kind == "button" then out[#out + 1] = (w.text:gsub("</?a[^>]*>", "")) end
  end
  return table.concat(out, "\n")
end

local function locale_requests(env) return env.server:seen(LOCALE) end

local function first_run(lang, o)
  o = o or {}
  o.first_run = true
  o.host_locale = "C"
  o.env = { LANG = lang, LC_ALL = false, LANGUAGE = false }
  o.popen = function(cmd)
    if cmd:find("uname") then return "Linux\n" end
    return ""
  end
  return H.launch(o)
end

describe("interface language: defaults", function()
  it("an existing installation stays English", function()
    local env = H.launch({ server = server_with("ready") })
    eq(env.saved_config().interfaceLanguage, nil)
    local c = config_window(env)
    has(labels(c.dialog), "Interface language:")
    has(labels(c.dialog), ENGLISH.int_os_username)
    for _, r in ipairs(locale_requests(env)) do
      ok(not r.path:find("sk.json"), "no translation is downloaded unasked")
    end
  end)

  it("the drop-down offers English, Automatic and the reviewed translations", function()
    local env = H.launch({ server = server_with("ready") })
    local c = config_window(env)
    eq(c.language:_texts(), { "English", "Automatic (system language)", "Sloven\196\141ina" })
  end)

  it("a translation that is not reviewed is not offered", function()
    local env = H.launch({ server = server_with("review") })
    eq(config_window(env).language:_texts(), { "English", "Automatic (system language)" })
  end)

  it("reviewers can see unreviewed translations with translationPreview", function()
    local env = H.launch({ server = server_with("review"), config = { translationPreview = true } })
    eq(config_window(env).language:_texts(),
       { "English", "Automatic (system language)", "Sloven\196\141ina (not reviewed)" })
  end)

  it("an install without any list fetches it at start, even when today's update check is done", function()
    local first = H.launch({ server = server_with("ready") })
    local stamp = H.read_file(first.dir .. "/last_update_check.json")
    local env = H.launch({ server = server_with("ready"), files = { ["last_update_check.json"] = stamp } })
    eq(#locale_requests(env), 1, "the list")
    eq(config_window(env).language:_texts(),
       { "English", "Automatic (system language)", "Sloven\196\141ina" })
  end)

  it("the list of languages is fetched at most once a week", function()
    local env = H.launch({ server = server_with("ready") })
    eq(#locale_requests(env), 1, "first start: the list")
    local files = { ["last_update_check.json"] = H.read_file(env.dir .. "/last_update_check.json") }
    local index = H.read_file(env.dir .. "/locale/index.json")
    ok(index, "list stored in the VLSub folder")

    local env2 = H.launch({ server = server_with("ready"), files = { ["locale/index.json"] = index } })
    eq(#locale_requests(env2), 0, "fresh list: no request")

    local old = json.decode(index)
    old.fetched = os.time() - 8 * 24 * 3600
    local env3 = H.launch({ server = server_with("ready"), files = { ["locale/index.json"] = json.encode(old) } })
    eq(#locale_requests(env3), 1, "list older than a week: refreshed")
    ok(files, "kept")
  end)
end)

describe("interface language: after an update of the extension", function()
  -- Seen on a Mac after the update to 2.0: Slovak window, the new AI texts in
  -- English. The stored translation was of the old version and would only be
  -- refreshed a week later.
  local function stored(version)
    local old = {}
    for key, value in pairs(SLOVAK) do old[key] = value end
    old.ui_ai_buy_credits = nil -- a text the old version did not have
    return {
      ["locale/index.json"] = json.encode({ format = 1, fetched = os.time(), languages = {
        { code = "sk", name = "Sloven\196\141ina", english_name = "Slovak", status = "ready" } } }),
      ["locale/sk.json"] = json.encode({ fetched = os.time(), version = version, strings = old }),
    }
  end

  it("a translation stored by another version is fetched again at start, so new texts are translated", function()
    for _, version in ipairs({ "1.4.0", false }) do
      local files = stored(version or nil)
      local first = H.launch({ server = server_with("ready") })
      files["last_update_check.json"] = H.read_file(first.dir .. "/last_update_check.json")
      local env = H.launch({ server = server_with("ready"), config = { interfaceLanguage = "sk" }, files = files })
      ok(env.server:last(LOCALE .. "sk.json"), "translation fetched again (stored version " .. tostring(version) .. ")")
      eq(H.find_local("strings").ui_ai_buy_credits, SLOVAK.ui_ai_buy_credits, "the new text is translated")
      local kept = json.decode(H.read_file(env.dir .. "/locale/sk.json"))
      ok(kept.version and kept.version ~= "1.4.0", "stored with the current version")
    end
  end)

  it("a translation stored by this version is not fetched again", function()
    local first = H.launch({ server = server_with("ready"), config = { interfaceLanguage = "sk" } })
    local files = {
      ["last_update_check.json"] = H.read_file(first.dir .. "/last_update_check.json"),
      ["locale/index.json"] = H.read_file(first.dir .. "/locale/index.json"),
      ["locale/sk.json"] = H.read_file(first.dir .. "/locale/sk.json"),
    }
    ok(files["locale/sk.json"], "stored by the first start")
    local env = H.launch({ server = server_with("ready"), config = { interfaceLanguage = "sk" }, files = files })
    eq(#locale_requests(env), 0)
  end)
end)

describe("interface language: choosing one", function()
  local function switch_to_slovak(o)
    o = o or {}
    o.server = o.server or server_with("ready")
    local env = H.launch(o)
    env.server:reset()
    local c = config_window(env)
    c.language:_choose_text("^Sloven")
    c.save:_click()
    return env
  end

  it("Save downloads the translation and rebuilds the window in that language", function()
    local env = switch_to_slovak()
    eq(env.saved_config().interfaceLanguage, "sk")
    ok(env.server:last(LOCALE .. "sk.json"), "translation requested")
    eq(env.server:last(LOCALE .. "sk.json").scheme, "https")
    local d = env.ui()
    has(d.title, SLOVAK.int_configuration)
    has(labels(d), SLOVAK.int_os_username)
    has(labels(d), SLOVAK.ui_interface_language .. ":")
    has(labels(d), SLOVAK.int_save)
    lacks(labels(d), ENGLISH.int_os_username)
    ok(env.message() ~= "", "the result message survived the rebuild: " .. env.message())
    eq(env.errors(), {})
  end)

  it("the chosen language is listed first in the rebuilt drop-down", function()
    local env = switch_to_slovak()
    eq(env.ui():_at(2, 9, "dropdown"):_texts()[1], "Sloven\196\141ina")
  end)

  it("every window is translated: main, help, messages", function()
    local env = switch_to_slovak()
    trigger_menu(1)
    has(labels(env.ui()), SLOVAK.int_title .. ":")
    has(labels(env.ui()), SLOVAK.ui_search_results)
    env.ui():_at(2, 1, "text_input"):set_text("zzz nothing")
    env.ui():_at(6, 2, "button"):_click()
    has(env.message(), SLOVAK.mess_no_res)
    trigger_menu(3)
    has(labels(env.ui()), SLOVAK.ui_search_methods)
    eq(env.errors(), {})
  end)

  it("search and download work in the translated interface, quota message included", function()
    local dir = H.tmpdir()
    local env = switch_to_slovak({ media = "file://" .. H.video(dir, "Big.Buck.Bunny.2008.mkv", 200000) })
    trigger_menu(1)
    env.ui():_at(2, 1, "text_input"):set_text("big buck bunny")
    env.ui():_at(6, 2, "button"):_click()
    env.results():_select(1)
    env.ui():_at(1, 11, "button"):_click()
    ok(H.exists(dir .. "/Big.Buck.Bunny.2008.en.srt"), "subtitle saved")
    has(env.message(), SLOVAK.ui_loaded_with_video)
    has(env.message(), "1/100")
    eq(select(2, env.message():gsub(SLOVAK.mess_success, "")), 1, "the success prefix appears once")
  end)

  it("the next session uses the stored translation without any request", function()
    local env = switch_to_slovak()
    local files = {
      ["vlsub_conf.json"] = H.read_file(env.dir .. "/vlsub_conf.json"),
      ["locale/index.json"] = H.read_file(env.dir .. "/locale/index.json"),
      ["locale/sk.json"] = H.read_file(env.dir .. "/locale/sk.json"),
    }
    ok(files["locale/sk.json"], "translation stored in the VLSub folder")
    local env2 = H.launch({ files = files, offline = true })
    has(labels(env2.ui()), SLOVAK.int_title .. ":")
    eq(#env2.server.requests, 0)
  end)

  it("English after Slovak: the window is English again", function()
    local env = switch_to_slovak()
    local c = config_window(env)
    c.language:_choose(1)
    c.save:_click()
    has(labels(env.ui()), ENGLISH.int_os_username)
    has(labels(env.ui()), "Interface language:")
    lacks(labels(env.ui()), SLOVAK.int_os_username)
    trigger_menu(1)
    has(labels(env.ui()), ENGLISH.ui_search_results)
  end)

  it("download fails: the interface stays as it was and says why", function()
    local server = server_with("ready")
    server.locale["sk.json"] = nil -- listed, but the file answers 404
    local env = H.launch({ server = server })
    local c = config_window(env)
    c.language:_choose_text("^Sloven")
    c.save:_click()
    has(labels(env.ui()), ENGLISH.int_os_username)
    has(env.message(), "could not be downloaded")
    eq(env.errors(), {})
  end)

  it("GitHub unreachable: the interface stays as it was, no crash", function()
    local server = server_with("ready")
    local env = H.launch({ server = server })
    server.down["raw.githubusercontent.com"] = true
    local c = config_window(env)
    c.language:_choose_text("^Sloven")
    c.save:_click()
    has(labels(env.ui()), ENGLISH.int_os_username)
    has(env.message(), "could not be downloaded")
  end)
end)

describe("interface language: first run", function()
  it("follows the detected language when a reviewed translation exists", function()
    local env = first_run("sk_SK.UTF-8", { server = server_with("ready") })
    local saved = env.saved_config()
    eq(saved.interfaceLanguage, "auto")
    eq(saved.detectedLanguage, "sk")
    has(env.ui().title, SLOVAK.int_configuration)
    has(labels(env.ui()), SLOVAK.int_os_username)
    eq(env.errors(), {})
  end)

  it("stays English when the translation is not reviewed yet", function()
    local env = first_run("sk_SK.UTF-8", { server = server_with("review") })
    eq(env.saved_config().interfaceLanguage, "auto")
    has(labels(env.ui()), ENGLISH.int_os_username)
    for _, r in ipairs(locale_requests(env)) do ok(not r.path:find("sk.json")) end
  end)

  it("the published index offers every language of locale/, and a first run uses it", function()
    local index = json.decode(H.read_file(H.ROOT .. "/locale/index.json"))
    ok(#index.languages >= 61, "languages listed")
    for _, language in ipairs(index.languages) do
      eq(language.status, "ready", language.code)
      ok(H.read_file(H.ROOT .. "/locale/" .. language.code .. ".json"), language.code .. ".json exists")
    end
    for locale, code in pairs({ ["sk_SK.UTF-8"] = "sk", ["de_DE.UTF-8"] = "de", ["ja_JP.UTF-8"] = "ja" }) do
      local server = api.new()
      server:publish_real_index()
      local env = first_run(locale, { server = server })
      local translation = json.decode(H.read_file(H.ROOT .. "/locale/" .. code .. ".json"))
      has(labels(env.ui()), translation.int_os_username)
      eq(env.errors(), {})
    end
  end)

  it("an English system still gets the list: the first configuration window offers every language", function()
    -- (seen on a Mac set to English: only "Automatic" and "English" were offered)
    local env = first_run("en_US.UTF-8", { server = server_with("ready") })
    ok(env.server:last(LOCALE .. "index.json"), "list requested on first run")
    eq(#env.server:seen(LOCALE .. "sk.json"), 0, "no translation fetched for English")
    has(env.ui().title, "Configuration")
    eq(env.ui():_at(2, 9, "dropdown"):_texts(),
       { "Automatic (system language)", "English", "Sloven\196\141ina" })
    has(labels(env.ui()), ENGLISH.int_os_username)
  end)

  it("stays English for a language without a translation", function()
    local env = first_run("ja_JP.UTF-8", { server = server_with("ready") })
    eq(env.saved_config().detectedLanguage, "ja")
    has(labels(env.ui()), ENGLISH.int_os_username)
  end)

  it("English system: nothing but the list is fetched", function()
    local env = first_run("en_US.UTF-8", { server = server_with("ready") })
    for _, r in ipairs(locale_requests(env)) do has(r.path, "index.json") end
    has(labels(env.ui()), ENGLISH.int_os_username)
  end)

  it("offline: no request for translations, English window", function()
    local env = first_run("sk_SK.UTF-8", { server = server_with("ready"), offline = true })
    eq(#locale_requests(env), 0)
    ok(env.ui(), "a window is shown")
  end)
end)

describe("interface language: a translation file is not trusted", function()
  local function with_translation(translation)
    local env = H.launch({ server = server_with("ready", translation) })
    local c = config_window(env)
    c.language:_choose_text("^Sloven")
    c.save:_click()
    return env, H.find_local("strings")
  end

  it("good strings are used, bad ones fall back to English one by one", function()
    local env, strings = with_translation({
      int_title = "N\195\161zov",                                -- fine
      int_save = 42,                                             -- not a string
      int_help = "",                                             -- empty
      int_close = { "x" },                                       -- not a string
      no_such_key = "x",                                         -- unknown key
      ui_quota_downloads = "Limit: %s",                          -- one placeholder missing
      ui_reset_in = ", o: %s %d",                                -- stray format directive
      ui_subtitle_link = "<b>Odkaz:</b><script>alert(1)</script>", -- extra markup
      ui_current_version = "<i>Verzia:</i> ",                    -- different markup
      int_season = string.rep("x", 5000),                        -- absurd length
      ui_for_imdb_id = "pre IMDB ID",                            -- lost the edge spaces
      mess_no_res = "Ni\196\141",                                -- fine
    })
    eq(strings.int_title, "N\195\161zov")
    eq(strings.mess_no_res, "Ni\196\141")
    for _, key in ipairs({ "int_save", "int_help", "int_close", "ui_quota_downloads", "ui_reset_in",
                           "ui_subtitle_link", "ui_current_version", "int_season", "ui_for_imdb_id" }) do
      eq(strings[key], ENGLISH[key], key .. " kept in English")
    end
    eq(strings.no_such_key, nil)
    eq(env.errors(), {})
  end)

  it("no label is ever empty or missing, whatever the file contains", function()
    local hostile = {}
    for key in pairs(ENGLISH) do hostile[key] = false end
    hostile.int_title = "<img src=x onerror=alert(1)>"
    local env = with_translation(hostile)
    for id = 1, 3 do
      trigger_menu(id)
      for _, w in ipairs(env.ui().widgets) do
        if w.kind == "button" then ok(w.text ~= "", "button without label in window " .. id) end
      end
      lacks(labels(env.ui()), "onerror")
    end
  end)

  it("a file that is not a JSON object is ignored", function()
    for _, body in ipairs({ "[1,2,3]", "true", "not json", '"text"', "" }) do
      local server = server_with("ready")
      server.locale["sk.json"] = body
      local env = H.launch({ server = server })
      local c = config_window(env)
      c.language:_choose_text("^Sloven")
      c.save:_click()
      has(labels(env.ui()), ENGLISH.int_os_username)
      eq(env.errors(), {}, "body " .. body)
    end
  end)

  it("entries of the language list with odd codes or names are dropped", function()
    local server = api.new()
    server.locale["index.json"] = json.encode({ format = 1, languages = {
      { code = "../../etc", name = "Evil", status = "ready" },
      { code = "de", name = "<b>Deutsch</b>", status = "ready" },
      { code = "fr", name = string.rep("F", 200), status = "ready" },
      { code = "es", status = "ready" },
      "nonsense",
      { code = "sk", name = "Sloven\196\141ina", status = "ready" },
    } })
    local env = H.launch({ server = server })
    eq(config_window(env).language:_texts(), { "English", "Automatic (system language)", "Sloven\196\141ina" })
  end)

  it("a hand-edited interfaceLanguage cannot point outside the locale folder", function()
    local env = H.launch({ server = server_with("ready"), config = { interfaceLanguage = "../../vlsub_conf" } })
    has(labels(env.ui()), ENGLISH.int_title .. ":")
    for _, r in ipairs(locale_requests(env)) do has(r.path, "index.json") end
    eq(env.errors(), {})
  end)

  it("an oversized download is refused", function()
    local server = server_with("ready")
    server.locale["sk.json"] = '{"int_title":"' .. string.rep("a", 300000) .. '"}'
    local env = H.launch({ server = server })
    local c = config_window(env)
    c.language:_choose_text("^Sloven")
    c.save:_click()
    ok(not H.exists(env.dir .. "/locale/sk.json"), "nothing stored")
    has(labels(env.ui()), ENGLISH.int_os_username)
  end)
end)

describe("interface language: shipped translations", function()
  local index = json.decode(H.read_file(H.ROOT .. "/locale/index.json"))

  it("the extension accepts every string of every translation in locale/", function()
    H.launch()
    local rejected = {}
    for _, language in ipairs(index.languages) do
      local translation = json.decode(H.read_file(H.ROOT .. "/locale/" .. language.code .. ".json"))
      local expected = 0
      for _ in pairs(translation) do expected = expected + 1 end
      local used = apply_interface_strings(translation)
      if used ~= expected then
        rejected[#rejected + 1] = language.code .. ": " .. (expected - used) .. " string(s) rejected"
      end
    end
    apply_interface_strings(nil)
    eq(rejected, {}, "the checker (tools/locale.lua) and the extension must agree")
  end)

  it("every language can be chosen in the configuration window when marked ready", function()
    local ready = { format = 1, languages = {} }
    for i, language in ipairs(index.languages) do
      ready.languages[i] = { code = language.code, name = language.name, status = "ready" }
    end
    local server = api.new()
    server.locale["index.json"] = json.encode(ready)
    local env = H.launch({ server = server })
    local offered = config_window(env).language:_texts()
    eq(#offered, #index.languages + 2, "English, Automatic and every language")

    -- pick three very different ones in turn
    for _, code in ipairs({ "ja", "ar", "de" }) do
      local c = config_window(env)
      local translation = json.decode(H.read_file(H.ROOT .. "/locale/" .. code .. ".json"))
      for _, entry in ipairs(env.ui():_at(2, 9, "dropdown").values) do
        if openSub.conf.interfaceLanguages[entry.id] and openSub.conf.interfaceLanguages[entry.id][1] == code then
          c.language:_choose(entry.id)
        end
      end
      c.save:_click()
      eq(env.saved_config().interfaceLanguage, code)
      has(labels(env.ui()), translation.int_os_username)
      eq(env.errors(), {}, code)
    end
  end)
end)


-- Everything the user can read in a dialog: { kind, text as shown }
local function visible_texts(d)
  local out = {}
  for _, w in ipairs(d.widgets) do
    if w.kind == "label" or w.kind == "html" or w.kind == "button" then
      out[#out + 1] = { kind = w.kind, raw = w.text, shown = w:_shown() }
    elseif w.kind == "dropdown" then
      for _, v in ipairs(w.values) do out[#out + 1] = { kind = "dropdown", raw = v.text, shown = v.text } end
    end
  end
  return out
end

local function with_translation(code, translation, o)
  o = o or {}
  local server = api.new()
  server.locale["index.json"] = json.encode({ format = 1, languages = {
    { code = code, name = "Test", english_name = "Test", status = "ready" } } })
  server.locale[code .. ".json"] = json.encode(translation)
  o.server = server
  o.config = { interfaceLanguage = code }
  o.files = { ["locale/index.json"] = json.encode({ format = 1, fetched = os.time(), languages = {
                { code = code, name = "Test", english_name = "Test", status = "ready" } } }),
              ["locale/" .. code .. ".json"] = json.encode({ fetched = os.time(), strings = translation }) }
  return H.launch(o)
end

describe("interface language: nothing is left in English", function()
  -- A pseudo-translation: every string of the table marked with "~". Any
  -- text on screen without the mark did not come from the table, so no
  -- translation can ever reach it ("Ready for search", "Default", "Desc"
  -- were found this way, on a Mac, by a user).
  local MARK = "~"
  local pseudo = {}
  for key, value in pairs(ENGLISH) do
    if key ~= "int_no_support_mess" then pseudo[key] = MARK .. value end
  end

  -- Text that is rightly not translated
  local function exempt(text, env)
    return text == "" or text:find("^%s*$")
      or text:find("^<[^>]*>%s*$")                 -- markup only (spacers, rules)
      or text:find("^VLSub OpenSubtitles.com v")   -- product name and version
      or text:find("^curl ") or text:find("^iwr ") -- install commands
      or text:find(env.dir, 1, true)               -- a path
      or text == "Test"                            -- the pseudo language's own name
  end

  local function unmarked(env, d, allowed)
    local offenders = {}
    for _, item in ipairs(visible_texts(d)) do
      if not item.raw:find(MARK, 1, true) and not exempt(item.raw, env) and not (allowed and allowed[item.raw]) then
        offenders[#offenders + 1] = item.kind .. ": " .. item.raw
      end
    end
    return offenders
  end

  -- names of subtitle languages come from the API, in English
  local function language_names()
    local names = {}
    for _, l in ipairs(api.fixture_json("languages").data) do names[l.language_name] = true end
    return names
  end

  it("main window: every label, button and drop-down entry comes from the strings table", function()
    local env = with_translation("xx", pseudo)
    eq(unmarked(env, env.ui(), language_names()), {})
  end)

  it("configuration window: the same", function()
    local env = with_translation("xx", pseudo)
    trigger_menu(2)
    eq(unmarked(env, env.ui(), language_names()), {})
  end)

  it("help window: the same", function()
    local env = with_translation("xx", pseudo)
    trigger_menu(3)
    eq(unmarked(env, env.ui()), {})
  end)

  it("search filters window: the same", function()
    local env = with_translation("xx", pseudo)
    trigger_menu(4)
    eq(unmarked(env, env.ui()), {})
    env.ui():_button("Save$"):_click()
    has(env.message(), MARK)
  end)

  it("after a search and a download: the messages too", function()
    local dir = H.tmpdir()
    local env = with_translation("xx", pseudo, { media = "file://" .. dir .. "/Big.Buck.Bunny.2008.mkv" })
    local d = env.ui()
    d:_at(2, 1, "text_input"):set_text("big buck bunny")
    d:_button("Search$"):_click()
    has(env.message(), MARK)
    eq(unmarked(env, env.ui(), language_names()), {})
    env.results():_select(1)
    env.ui():_button("Download"):_click()
    has(env.message(), MARK)
    eq(env.errors(), {})
  end)
end)

describe("interface language: VLC for macOS", function()
  -- macOS VLC shows a label whose text has any character outside Latin-1 as
  -- an empty label (found by a user: half of the Slovak labels were blank,
  -- the whole help window empty). See new_dialog() in the extension.
  local index = json.decode(H.read_file(H.ROOT .. "/locale/index.json"))

  local function windows(env)
    local list = { { "main", env.ui() } }
    trigger_menu(2) list[#list + 1] = { "configuration", env.ui() }
    trigger_menu(3) list[#list + 1] = { "help", env.ui() }
    trigger_menu(4) list[#list + 1] = { "filters", env.ui() }
    return list
  end

  it("the mock renders labels as macOS does: non-Latin-1 text is blank unless written as &#N;", function()
    local env = H.launch({ macos = true })
    local d = env.vlc.dialog("x")
    eq(d:add_label("N\195\161zov", 1, 1):_shown(), "N\195\161zov", "Latin-1 survives")
    eq(d:add_label("H\196\190ada\197\165", 1, 2):_shown(), "", "beyond Latin-1: blank")
    eq(d:add_label("H&#318;ada&#357;", 1, 3):_shown(), "H\196\190ada\197\165", "references are decoded")
    eq(d:add_button("H\196\190ada\197\165", function() end, 1, 4):_shown(), "H\196\190ada\197\165", "buttons are fine")
  end)

  it("no label is blank and every label reads as translated, in every language and window", function()
    for _, language in ipairs(index.languages) do
      local translation = json.decode(H.read_file(H.ROOT .. "/locale/" .. language.code .. ".json"))
      local env = with_translation(language.code, translation, { macos = true })
      has(env.ui().widgets[1]:_shown(), translation.int_title, language.code .. ": first label of the main window")
      for _, window in ipairs(windows(env)) do
        for _, item in ipairs(visible_texts(window[2])) do
          if (item.kind == "label" or item.kind == "html") and item.raw ~= "" then
            ok(item.shown ~= "", language.code .. " " .. window[1] .. ": blank label for " .. item.raw)
            ok(not item.shown:find("&#%d+;"), language.code .. " " .. window[1] .. ": reference left in " .. item.shown)
          end
        end
      end
      eq(env.errors(), {}, language.code)
    end
  end)

  it("search and download in Slovak on macOS: messages are readable, the script still reads its own labels", function()
    local dir = H.tmpdir()
    local env = with_translation("sk", SLOVAK, { macos = true, media = "file://" .. dir .. "/Big.Buck.Bunny.2008.mkv" })
    local d = env.ui()
    d:_at(2, 1, "text_input"):set_text("big buck bunny")
    d:_button(SLOVAK.int_search_name .. "$"):_click()
    env.results():_select(1)
    env.ui():_button(SLOVAK.ui_download:gsub("^[^%w]+", "")):_click()
    local message
    for _, w in ipairs(env.ui().widgets) do
      if w.kind == "label" and w:_shown():find(SLOVAK.mess_success, 1, true) then message = w:_shown() end
    end
    ok(message, "success message shown")
    has(message, SLOVAK.ui_loaded_with_video)
    eq(env.errors(), {})
  end)

  it("changing the language: the old window gets no label update in the click that closes it", function()
    -- VLC 3.0.24 on macOS quit at this point (twice, for a user): Save wrote
    -- "Testing login..." and the result to the message label, then replaced
    -- the window. Label updates go through a slow helper process there, and
    -- closing the window with one still on its way took VLC down. The window
    -- is now replaced first, and the messages go to the new one.
    local server = api.new()
    server:publish_real_index()
    local env = H.launch({ server = server, macos = true })
    for _, name in ipairs({ "^\196\140e\197\161tina", "^Sloven", "^English", "^Deutsch" }) do
      local c = config_window(env)
      c.language:_choose_text(name)
      c.save:_click()
      eq(env.unsafe_closes(), {}, "after choosing " .. name)
      eq(env.errors(), {})
      ok(env.message() ~= "", "the result of Save is shown in the new window")
    end
    has(env.ui().title, "Einstellungen")
  end)

  it("the mock notices a window closed in the click that changed its label", function()
    local env = H.launch({ macos = true })
    local d = env.vlc.dialog("x")
    local label = d:add_label("a", 1, 1)
    d:add_button("go", function() label:set_text("b") d:hide() end, 1, 2):_click()
    eq(env.unsafe_closes(), { "x" })
  end)

  it("configuration window on macOS keeps room for a three-line message (the first row was pushed out)", function()
    local env = H.launch({ macos = true })
    trigger_menu(2)
    local message
    for _, w in ipairs(env.ui().widgets) do
      if w.kind == "label" and w.row == 12 then message = w end
    end
    eq(select(2, message.text:gsub("<br>", "")), 2, "two line breaks = three lines reserved")
    eq((message:_shown():gsub("[%s\194\160]", ""):gsub("&nbsp;", ""):gsub("<br>", "")), "", "and nothing to read in them")
    local other = H.launch()
    trigger_menu(2)
    for _, w in ipairs(other.ui().widgets) do
      if w.kind == "label" and w.row == 12 then eq(w.text, "", "Qt sizes the window itself") end
    end
  end)

  it("the way back: 'English' is offered under that name in every interface language", function()
    -- (it was translated - "Angličtina", "英語" - so someone who had picked a
    -- language they cannot read could not find English again)
    for _, code in ipairs({ "sk", "ja", "ru", "ar" }) do
      local translation = json.decode(H.read_file(H.ROOT .. "/locale/" .. code .. ".json"))
      local env = with_translation(code, translation)
      local texts = config_window(env).language:_texts()
      local found = false
      for _, text in ipairs(texts) do if text == "English" then found = true end end
      ok(found, code .. ": " .. table.concat(texts, " | "))
    end
  end)

  it("help window: no line is wider than the window can show (long lines are wrapped)", function()
    local function widest(text) -- in columns, per visible line
      local most = 0
      for part in (text:gsub("<br>", "\n") .. "\n"):gmatch("(.-)\n") do
        local plain = part:gsub("<[^>]*>", "")
        local columns = 0
        for char in plain:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
          local first = char:byte()
          columns = columns + ((first >= 227 and first <= 237) and 2 or 1)
        end
        if columns > most then most = columns end
      end
      return most
    end
    for _, language in ipairs(index.languages) do
      local translation = json.decode(H.read_file(H.ROOT .. "/locale/" .. language.code .. ".json"))
      local env = with_translation(language.code, translation, { macos = true })
      trigger_menu(3)
      for _, item in ipairs(visible_texts(env.ui())) do
        if item.kind == "label" then
          ok(widest(item.shown) <= 66, language.code .. ": " .. widest(item.shown) .. " columns: " .. item.shown)
          ok(not item.shown:find("<br>%s*$"), "ends with a break: " .. item.shown)
        end
      end
    end
    -- nothing is lost by wrapping
    local env = with_translation("sk", SLOVAK, { macos = true })
    trigger_menu(3)
    local all = {}
    for _, item in ipairs(visible_texts(env.ui())) do all[#all + 1] = (item.shown:gsub("<br>", " ")) end
    has(table.concat(all, "\n"), SLOVAK.ui_free_opensubtitles_com_account_required_for_down:gsub("<[^>]+>", ""))
  end)

  it("help window stays short enough for a laptop screen, in every language", function()
    -- it cannot scroll: at 24 rows plus wrapping it was taller than the screen
    local worst, worst_code = 0, nil
    for _, language in ipairs(index.languages) do
      local translation = json.decode(H.read_file(H.ROOT .. "/locale/" .. language.code .. ".json"))
      local env = with_translation(language.code, translation, { macos = true })
      trigger_menu(3)
      local lines, labels_count = 0, 0
      for _, item in ipairs(visible_texts(env.ui())) do
        if item.kind == "label" then
          labels_count = labels_count + 1
          lines = lines + 1 + select(2, item.shown:gsub("<br>", ""))
        end
      end
      ok(labels_count <= 14, language.code .. ": " .. labels_count .. " rows")
      if lines > worst then worst, worst_code = lines, language.code end
    end
    ok(worst <= 26, "tallest help window: " .. worst .. " text lines (" .. tostring(worst_code) .. ")")
  end)

  it("help window on Linux / Windows is not wrapped: Qt sizes the window to the text", function()
    local env = with_translation("sk", SLOVAK)
    trigger_menu(3)
    for _, item in ipairs(visible_texts(env.ui())) do
      if item.kind == "label" then ok(not item.raw:find("<br>", 1, true) or SLOVAK[item.raw], item.raw) end
    end
  end)

  it("Linux / Windows: label text is passed through untouched", function()
    local env = with_translation("sk", SLOVAK)
    for _, item in ipairs(visible_texts(env.ui())) do
      ok(not item.raw:find("&#%d+;"), "reference in " .. item.raw)
    end
    has(labels(env.ui()), SLOVAK.int_title)
  end)
end)
