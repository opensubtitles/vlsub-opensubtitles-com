-- Translation files in locale/. Data only for now (see locale/README.md);
-- these checks make sure a translation can never break a window once the
-- extension starts loading them.
local H = ...
local describe, it, eq, ok = H.describe, H.it, H.eq, H.ok
local json = H.json

local LOCALE = H.ROOT .. "/locale"

local function load_json(name)
  local raw = H.read_file(LOCALE .. "/" .. name)
  ok(raw, "missing locale/" .. name)
  local data, _, err = json.decode(raw)
  ok(type(data) == "table", "locale/" .. name .. " is not valid JSON: " .. tostring(err))
  return data, raw
end

local function tags(text)
  local list = {}
  for tag in text:gmatch("<[^>]+>") do list[#list + 1] = tag end
  table.sort(list)
  return list
end

local function count(text, pattern)
  return select(2, text:gsub(pattern, ""))
end

describe("locale files", function()
  it("en.json matches the strings in vlsubcom.lua (run: lua tests/export_strings.lua)", function()
    H.launch({ activate = false })
    eq(load_json("en.json"), H.find_local("strings"))
  end)

  it("index.json lists every translation file, with a valid status", function()
    local index = load_json("index.json")
    eq(index.format, 1)
    local listed = {}
    for _, language in ipairs(index.languages) do
      ok(type(language.code) == "string" and language.code:match("^[a-z][a-z%-]+$"), "code")
      ok(language.status == "review" or language.status == "ready", language.code .. ": status")
      ok(type(language.name) == "string" and language.name ~= "", language.code .. ": name")
      ok(H.exists(LOCALE .. "/" .. language.code .. ".json"), "locale/" .. language.code .. ".json exists")
      ok(not listed[language.code], language.code .. " listed twice")
      listed[language.code] = true
    end
    for _, file in ipairs(H.ls(LOCALE)) do
      local code = file:match("^(.+)%.json$")
      if code and code ~= "en" and code ~= "index" then
        ok(listed[code], "locale/" .. file .. " is not in index.json")
      end
    end
  end)

  local index = json.decode(H.read_file(LOCALE .. "/index.json") or "{}") or {}
  for _, language in ipairs(index.languages or {}) do
    local code = language.code

    it(code .. ".json: only known keys, non-empty strings", function()
      local english, translation = load_json("en.json"), load_json(code .. ".json")
      local translated = 0
      for key, value in pairs(translation) do
        ok(english[key], code .. ": unknown key '" .. tostring(key) .. "'")
        ok(type(value) == "string" and value ~= "", code .. ": " .. key .. " must be a non-empty string")
        translated = translated + 1
      end
      ok(translated > 0, code .. ": empty translation")
    end)

    it(code .. ".json: placeholders, HTML tags and edge spaces match the English string", function()
      local english, translation = load_json("en.json"), load_json(code .. ".json")
      local problems = {}
      for key, value in pairs(translation) do
        local source = english[key]
        if source then
          if count(value, "%%s") ~= count(source, "%%s") then
            problems[#problems + 1] = key .. ": number of %s placeholders"
          end
          if count(source, "%%s") > 0 and value:gsub("%%s", ""):find("%%") then
            problems[#problems + 1] = key .. ": stray % in a pattern"
          end
          if H.show(tags(value)) ~= H.show(tags(source)) then
            problems[#problems + 1] = key .. ": HTML tags differ"
          end
          if (source:sub(1, 1) == " ") ~= (value:sub(1, 1) == " ")
             or (source:sub(-1) == " ") ~= (value:sub(-1) == " ") then
            problems[#problems + 1] = key .. ": leading/trailing space"
          end
          if #value > #source * 4 + 60 then
            problems[#problems + 1] = key .. ": suspiciously long"
          end
        end
      end
      table.sort(problems)
      eq(problems, {}, "locale/" .. code .. ".json")
    end)

    -- What phase 2 will do, done by hand: put the translation into the
    -- strings table and use the extension. Nothing may raise, and no label
    -- may come out empty.
    it(code .. ".json: the extension works with the translation applied", function()
      local translation = load_json(code .. ".json")
      local dir = H.tmpdir()
      local env = H.launch({ activate = false,
                             media = "file://" .. H.video(dir, "Big.Buck.Bunny.2008.mkv", 200000) })
      local strings = H.find_local("strings")
      for key, value in pairs(translation) do strings[key] = value end

      activate()
      for id = 1, 3 do
        trigger_menu(id)
        for _, widget in ipairs(env.ui().widgets) do
          if widget.kind == "button" then
            ok(widget.text ~= "", "window " .. id .. ": a button without a label")
          end
        end
      end
      trigger_menu(1)
      env.ui():_at(2, 1, "text_input"):set_text("big buck bunny")
      env.ui():_at(1, 11, "button") -- the row of buttons exists
      -- search by name: the button in row 2
      env.ui():_at(6, 2, "button"):_click()
      ok(#env.results().values > 1, "results listed")
      env.results():_select(1)
      env.ui():_at(1, 11, "button"):_click() -- Download
      ok(H.exists(dir .. "/Big.Buck.Bunny.2008.en.srt"), "subtitle saved; message: " .. env.message())
      env.ui():_at(2, 11, "button"):_click() -- Link
      env.ui():_at(6, 1, "button"):_click() -- search by hash
      eq(env.errors(), {}, "errors logged")
    end)

    it(code .. ".json: first run works with the translation applied", function()
      local translation = load_json(code .. ".json")
      local env = H.launch({ activate = false, first_run = true, host_locale = "C",
                             env = { LANG = "sk_SK.UTF-8" }, popen = function() return "" end })
      local strings = H.find_local("strings")
      for key, value in pairs(translation) do strings[key] = value end
      activate()
      ok(env.ui(), "a window is shown")
      eq(env.errors(), {}, "errors logged")
    end)
  end
end)
