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
  return { dialog = d, language = d:_at(3, 9, "dropdown"), save = d:_at(1, 12, "button") }
end

local function labels(d)
  local out = {}
  for _, w in ipairs(d.widgets) do
    if w.kind == "label" or w.kind == "button" then out[#out + 1] = w.text end
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
    eq(env.ui():_at(3, 9, "dropdown"):_texts()[1], "Sloven\196\141ina")
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
      for _, entry in ipairs(env.ui():_at(3, 9, "dropdown").values) do
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
