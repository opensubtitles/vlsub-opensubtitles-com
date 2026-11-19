-- Language list, code mapping and first-run locale detection.
local H = ...
local describe, it, known_bug, eq, ok, has = H.describe, H.it, H.known_bug, H.eq, H.ok, H.has
local api, json = H.fake_api, H.json

local SUBTITLES = "GET api.opensubtitles.com/api/v1/subtitles"

local function api_codes()
  local set, list = {}, api.fixture_json("languages").data
  for _, l in ipairs(list) do set[l.language_code] = l.language_name end
  return set, list
end

-- A scripted machine for first-run locale detection.
local function machine(lang, o)
  o = o or {}
  o.first_run = true
  o.host_locale = "C" -- C library and /etc/* say nothing; only what is scripted below counts
  o.env = { LANG = lang, LC_ALL = false, LANGUAGE = false, LC_MESSAGES = false,
            LC_CTYPE = false, LC_COLLATE = false }
  o.popen = function(cmd)
    if cmd:find("uname") then return (o.uname or "Linux") .. "\n" end
    if cmd:find("^locale %-a") then return "C\nPOSIX\n" end
    if cmd:find("^locale") then return "LANG=" .. lang .. "\nLC_ALL=\n" end
    if cmd:find("printenv LANG") then return lang .. "\n" end
    if cmd:find("defaults read") and o.apple then return o.apple end
    if cmd:find("timedatectl") then return "Etc/UTC\n" end
    return ""
  end
  return o
end

describe("language list", function()
  it("is fetched once from the API and cached for later sessions", function()
    local env = H.launch()
    eq(#env.server:seen("GET api.opensubtitles.com/api/v1/infos/languages"), 1)
    local cache = H.read_file(env.dir .. "/cache_subtitle_languages.json")
    eq(json.decode(cache), api.fixture_json("languages"))

    local env2 = H.launch({ files = { ["cache_subtitle_languages.json"] = cache } })
    eq(#env2.server:seen("GET api.opensubtitles.com/api/v1/infos/languages"), 0)
    eq(#env2.ui():_at(2, 4, "dropdown").values, #api.fixture_json("languages").data + 1,
       "every API language plus the 'All' entry")
  end)

  it("API list unavailable and no cache: the built-in list is offered", function()
      local server = api.new()
      server:on("GET api.opensubtitles.com/api/v1/infos/languages", function() return "" end)
      local env = H.launch({ server = server })
      ok(#env.ui():_at(2, 4, "dropdown").values > 50, "languages offered")
      eq(env.ui():_at(2, 4, "dropdown").values[1].text, "English")
    end)

  local function builtin_list()
    H.launch({ activate = false })
    convert_sub_languages()
    return H.find_local("sub_languages")
  end

  it("every built-in language has a code and a name", function()
      for i, pair in ipairs(builtin_list()) do
        ok(type(pair[1]) == "string" and type(pair[2]) == "string",
           "entry " .. i .. ": " .. H.show(pair))
      end
    end)

  it("built-in fallback list uses the same codes as the API", function()
    local codes = api_codes()
    local unknown = {}
    for _, pair in ipairs(builtin_list()) do
      if not codes[pair[1]] then unknown[#unknown + 1] = pair[1] end
    end
    table.sort(unknown)
    eq(unknown, {}, "built-in codes the API does not know")
  end)

  it("built-in fallback list is not missing languages the API has", function()
    local builtin = {}
    for _, pair in ipairs(builtin_list()) do builtin[pair[1]] = true end
    local missing = {}
    for _, l in ipairs(api.fixture_json("languages").data) do
      if not builtin[l.language_code] then missing[#missing + 1] = l.language_code end
    end
    table.sort(missing)
    eq(missing, {}, "API languages absent from the built-in list")
  end)

  it("a saved code that is no longer in the list does not break the window", function()
    local env = H.launch({ config = { language = "xx-gone" } })
    ok(#env.ui():_at(2, 4, "dropdown").values > 50)
    eq(env.errors(), {})
  end)
end)

describe("map_to_opensubtitles_language", function()
  it("every API code maps to itself", function()
    H.launch({ activate = false })
    for code in pairs((api_codes())) do
      eq(map_to_opensubtitles_language(code), code, code)
    end
  end)

  it("bare zh / pt / az get a regional default that the API knows", function()
    H.launch({ activate = false })
    local codes = api_codes()
    for bare, expected in pairs({ zh = "zh-cn", pt = "pt-pt", az = "az-az" }) do
      eq(map_to_opensubtitles_language(bare), expected)
      ok(codes[expected], expected .. " is an API code")
    end
  end)

  it("unknown codes pass through unchanged", function()
    H.launch({ activate = false })
    eq(map_to_opensubtitles_language("xx"), "xx")
  end)
end)

describe("parse_locale_string", function()
  local cases = {
    { "en_US.UTF-8", "en", "us" }, { "sk_SK", "sk", "sk" }, { "pt_BR.UTF-8", "pt", "br" },
    { "de_DE@euro", "de", "de" }, { "fr", "fr", nil }, { "en-GB", "en", "gb" },
    { "zh_Hans_CN", "zh", "cn" }, { "C", nil, nil }, { "POSIX", nil, nil }, { "", nil, nil },
  }
  for _, c in ipairs(cases) do
    it("'" .. c[1] .. "'", function()
      H.launch({ activate = false })
      local lang, country = parse_locale_string(c[1])
      eq(lang, c[2], "language")
      eq(country, c[3], "country")
    end)
  end
end)

describe("first run: language is chosen from the system locale", function()
  for locale, expected in pairs({ ["sk_SK.UTF-8"] = "sk", ["en_US.UTF-8"] = "en",
                                  ["de_AT.UTF-8"] = "de", ["fr_FR.UTF-8"] = "fr" }) do
    it(locale .. " -> " .. expected, function()
      local env = H.launch(machine(locale))
      eq(env.saved_config().language, expected)
      has(env.ui().title, "Configuration")
    end)
  end

  it("only codes the API knows are ever saved", function()
    local codes = api_codes()
    for _, locale in ipairs({ "sk_SK.UTF-8", "en_US.UTF-8", "ja_JP.UTF-8", "es_MX.UTF-8" }) do
      local c = H.launch(machine(locale)).saved_config()
      for _, key in ipairs({ "language", "language2", "language3" }) do
        ok(c[key] == nil or codes[c[key]], locale .. ": " .. key .. " = " .. tostring(c[key]))
      end
    end
  end)

  for locale, expected in pairs({ ["pt_BR.UTF-8"] = "pt-br", ["pt_PT.UTF-8"] = "pt-pt",
                                  ["zh_TW.UTF-8"] = "zh-tw", ["zh_CN.UTF-8"] = "zh-cn" }) do
    it(locale .. " -> " .. expected, function()
        eq(H.launch(machine(locale)).saved_config().language, expected)
      end)
  end

  it("LANG=C / POSIX never ends up as the subtitle language", function()
    local codes = api_codes()
    for _, locale in ipairs({ "C", "POSIX" }) do
      local language = H.launch(machine(locale)).saved_config().language
      ok(language == nil or codes[language], locale .. " -> " .. tostring(language))
    end
  end)

  it("a second run does not repeat the detection or the network tests", function()
    local env = H.launch(machine("sk_SK.UTF-8"))
    local saved = H.read_file(env.dir .. "/vlsub_conf.json")
    local env2 = H.launch({ files = { ["vlsub_conf.json"] = saved }, login = false })
    eq(#env2.server:seen("GET api.myip.com/"), 0)
    eq(#env2.server:seen("GET www.google.com/"), 0)
    for _, cmd in ipairs(env2.commands) do
      ok(not cmd:find("locale"), "ran locale detection again: " .. cmd)
    end
  end)

  it("first run works when google.com is unreachable (offline, or blocked networks)", function()
      local o = machine("sk_SK.UTF-8")
      local server = api.new()
      server.down["www.google.com"] = true
      o.server = server
      local env = H.launch(o)
      ok(env.ui(), "a window is shown")
    end)

  it("system locale known: no IP geolocation request (it can block VLC for half a minute)", function()
    local env = H.launch(machine("sk_SK.UTF-8"))
    eq(#env.server:seen("GET api.myip.com/"), 0)
    eq(env.saved_config().language, "sk")
  end)

  it("no locale information at all: IP geolocation is the fallback", function()
    local o = machine("")
    o.env.LANG = false
    o.popen = function(cmd)
      if cmd:find("uname") then return "Linux\n" end
      return ""
    end
    local env = H.launch(o)
    eq(#env.server:seen("GET api.myip.com/"), 1)
    eq(env.saved_config().language, "sk", "country SK from the fake geolocation service")
  end)

  it("the detected language is used by the first search", function()
    local env = H.launch(machine("fr_FR.UTF-8"))
    trigger_menu(1)
    env.ui():_at(2, 1, "text_input"):set_text("big buck bunny")
    env.ui():_button("Search$"):_click()
    has(env.server:last(SUBTITLES).query.languages, "fr")
  end)
end)
