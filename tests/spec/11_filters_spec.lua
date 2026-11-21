-- The "Search filters" window: what the API can leave out of, or limit, a
-- search. Decided by the owner: its own window (the configuration window is
-- full), defaults = the API's defaults, "AI translations: No" hides ALL AI
-- subtitles (on-demand and uploaded), a hint when a search finds nothing
-- while a filter is set.
local H = ...
local describe, it, eq, ok, has, lacks = H.describe, H.it, H.eq, H.ok, H.has, H.lacks
local api = H.fake_api

local SUBTITLES = "GET api.opensubtitles.com/api/v1/subtitles"

-- rows of the window, in order
local ROW = { ai = 1, machine = 2, hearing = 3, foreign = 4, trusted = 5 }

local function filters_window(env)
  trigger_menu(4)
  local d = env.ui()
  local w = { dialog = d }
  for name, row in pairs(ROW) do w[name] = d:_at(2, row, "dropdown") end
  return w
end

local function search(env, title)
  trigger_menu(1)
  env.server:reset()
  local d = env.ui()
  d:_at(2, 1, "text_input"):set_text(title or "big buck bunny")
  d:_button("Search$"):_click()
  return env.server:last(SUBTITLES)
end

describe("search filters: the window", function()
  it("is opened from the configuration window and leads back to it", function()
    local env = H.launch()
    trigger_menu(2)
    env.ui():_button("Set filters"):_click()
    has(env.ui().title, "Search filters")
    env.ui():_button("Back"):_click()
    has(env.ui().title, "Configuration")
  end)

  it("lists five filters, each showing the API's default first", function()
    local env = H.launch()
    local w = filters_window(env)
    local labels = {}
    for _, x in ipairs(w.dialog.widgets) do if x.kind == "label" and x.text ~= "" then labels[#labels + 1] = x.text end end
    eq(labels, { "AI translations:", "Machine translations:", "For hearing impaired (SDH / CC):",
                 "Foreign parts only (forced):", "Trusted uploaders only:" })
    eq(w.ai:_texts(), { "Yes", "No" })
    eq(w.machine:_texts(), { "No", "Yes" })
    eq(w.hearing:_texts(), { "Include", "Exclude", "Only these" })
    eq(w.foreign:_texts(), { "Include", "Exclude", "Only these" })
    eq(w.trusted:_texts(), { "No", "Yes" })
  end)

  it("with the defaults a search sends none of the filter parameters", function()
    local env = H.launch()
    local req = search(env)
    for _, name in ipairs({ "ai_translated", "machine_translated", "hearing_impaired", "foreign_parts_only", "trusted_sources" }) do
      eq(req.query[name], nil, name)
    end
  end)

  it("Save stores the choices, shows them again, and says they apply from the next search", function()
    local env = H.launch()
    local w = filters_window(env)
    w.hearing:_choose_text("^Exclude$")
    w.trusted:_choose_text("^Yes$")
    w.dialog:_button("Save$"):_click()
    has(env.message(), "Filters saved")
    local saved = env.saved_config()
    eq(saved.hearingImpaired, "exclude")
    eq(saved.trustedOnly, true)
    eq(saved.aiTranslations, true)
    eq(saved.foreignPartsOnly, "include")
    w = filters_window(env)
    eq(w.hearing:_texts(), { "Exclude", "Include", "Only these" })
    eq(w.trusted:_texts(), { "Yes", "No" })
  end)

  it("Save twice without touching anything changes nothing", function()
    local env = H.launch({ config = { hearingImpaired = "only" } })
    for _ = 1, 2 do
      local w = filters_window(env)
      w.dialog:_button("Save$"):_click()
    end
    eq(env.saved_config().hearingImpaired, "only")
    eq(env.saved_config().aiTranslations, true)
  end)
end)

describe("search filters: what a search asks the API", function()
  local cases = {
    { { aiTranslations = false }, "ai_translated", "exclude" },
    { { machineTranslations = true }, "machine_translated", "include" },
    { { hearingImpaired = "exclude" }, "hearing_impaired", "exclude" },
    { { hearingImpaired = "only" }, "hearing_impaired", "only" },
    { { foreignPartsOnly = "exclude" }, "foreign_parts_only", "exclude" },
    { { foreignPartsOnly = "only" }, "foreign_parts_only", "only" },
    { { trustedOnly = true }, "trusted_sources", "only" },
  }
  for _, case in ipairs(cases) do
    it(case[2] .. "=" .. case[3], function()
      local env = H.launch({ config = case[1] })
      local req = search(env)
      eq(req.query[case[2]], case[3])
      eq(req.problems, {}, "still a canonical request (sorted parameters)")
    end)
  end

  it("all at once, by hash, name and IMDb id alike", function()
    local dir = H.tmpdir()
    local env = H.launch({ media = "file://" .. dir .. "/Big.Buck.Bunny.2008.mkv",
      config = { aiTranslations = false, hearingImpaired = "exclude", foreignPartsOnly = "exclude", trustedOnly = true } })
    for _, req in ipairs(env.server:seen(SUBTITLES)) do
      eq(req.query.ai_translated, "exclude")
      eq(req.query.hearing_impaired, "exclude")
      eq(req.query.foreign_parts_only, "exclude")
      eq(req.query.trusted_sources, "only")
      eq(req.problems, {})
    end
    ok(#env.server:seen(SUBTITLES) >= 1, "the automatic search ran")
    trigger_menu(1)
    env.server:reset()
    env.ui():_at(4, 3, "text_input"):set_text("1254207")
    env.ui():_button("Search$"):_click()
    eq(env.server:last(SUBTITLES).query.trusted_sources, "only")
  end)

  it("a value the settings file should not hold is treated as the default", function()
    local env = H.launch({ config = { hearingImpaired = "sometimes", trustedOnly = "yes", aiTranslations = "no" } })
    local req = search(env)
    eq(req.query.hearing_impaired, nil)
    eq(req.query.trusted_sources, nil)
    eq(req.query.ai_translated, nil)
    eq(env.errors(), {})
  end)
end)

describe("search filters: AI translations off", function()
  it("an AI entry the server sends anyway is not listed", function()
    local env = H.launch({ config = { language = "cs", aiTranslations = false } })
    local d = env.ui()
    d:_at(4, 3, "text_input"):set_text("1254207") -- answered with the recorded on-demand row
    d:_button("Search$"):_click()
    for _, row in ipairs(env.results().values) do
      ok(not row.text:find("AI translation", 1, true), row.text)
    end
    for _, item in ipairs(openSub.itemStore or {}) do
      eq(item.OnDemand, false)
      eq(item.AITranslated, false)
    end
  end)

  it("switched back on in the filters window, the on-demand entry is listed again", function()
    local env = H.launch({ config = { language = "cs", aiTranslations = false } })
    local w = filters_window(env)
    w.ai:_choose_text("^Yes$")
    w.dialog:_button("Save$"):_click()
    eq(env.saved_config().aiTranslations, true)
    trigger_menu(1)
    local d = env.ui()
    d:_at(4, 3, "text_input"):set_text("1254207")
    d:_button("Search$"):_click()
    has(env.results().values[1].text, "AI translation from English")
  end)

  it("the balance button stays in the configuration window", function()
    local env = H.launch({ config = { aiTranslations = false } })
    trigger_menu(2)
    ok(env.ui():_button("AI credits: balance"), "button present")
  end)
end)

describe("search filters: nothing found", function()
  it("with a filter set the message says that filters may be the reason", function()
    local env = H.launch({ config = { hearingImpaired = "only" } })
    search(env, "zzz nothing here zzz")
    has(env.message(), "No result")
    has(env.message(), "Search filters are set")
  end)

  it("without filters there is no such hint", function()
    local env = H.launch()
    search(env, "zzz nothing here zzz")
    has(env.message(), "No result")
    lacks(env.message(), "filters")
  end)

  it("with results there is no hint either", function()
    local env = H.launch({ config = { trustedOnly = true } })
    search(env)
    lacks(env.message(), "filters")
  end)
end)
