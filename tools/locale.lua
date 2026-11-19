-- Helper for interface translations (locale/*.json). Plain Lua 5.1 - 5.5.
--
--   lua tools/locale.lua status                 every language: coverage, problems, status
--   lua tools/locale.lua check [code ...]       detailed report (all languages if none given)
--   lua tools/locale.lua new <code> "<Name>" ["<English name>"]
--                                               start a translation: empty file + index entry
--   lua tools/locale.lua missing <code>         keys not translated yet, with the English text
--   lua tools/locale.lua ready <code>           mark as reviewed: offered to users
--   lua tools/locale.lua review <code>          mark as not reviewed: hidden from users
--   lua tools/locale.lua export                 regenerate locale/en.json from vlsubcom.lua
--
-- <code> is the OpenSubtitles language code: sk, de, pt-br, zh-cn, ...
-- The rules a translation must follow are in locale/README.md.

local here = (arg and arg[0] or "tools/locale.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = here .. "/.."
package.path = ROOT .. "/tests/vendor/?.lua;" .. package.path
local json = require("dkjson")
local LOCALE = ROOT .. "/locale/"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local function load(name)
  local raw = read(LOCALE .. name)
  if not raw then return nil, "missing" end
  local data, _, err = json.decode(raw)
  if type(data) ~= "table" then return nil, "not valid JSON: " .. tostring(err) end
  return data
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function save_translation(code, t)
  local text = next(t) and json.encode(t, { indent = true, keyorder = sorted_keys(t) }) or "{}"
  write(LOCALE .. code .. ".json", text .. "\n")
end

local function save_index(index)
  table.sort(index.languages, function(a, b) return a.code < b.code end)
  local lines = { "{", '  "format": 1,', '  "languages": [' }
  for i, l in ipairs(index.languages) do
    local parts = {}
    for _, key in ipairs({ "code", "name", "english_name", "status", "note" }) do
      if l[key] then parts[#parts + 1] = json.encode(key) .. ": " .. json.encode(l[key]) end
    end
    lines[#lines + 1] = "    { " .. table.concat(parts, ", ") .. " }" .. (i < #index.languages and "," or "")
  end
  lines[#lines + 1] = "  ]"
  lines[#lines + 1] = "}"
  write(LOCALE .. "index.json", table.concat(lines, "\n") .. "\n")
end

local function count(text, pattern) return select(2, text:gsub(pattern, "")) end

local function tags(text)
  local list = {}
  for tag in text:gmatch("<[^>]+>") do list[#list + 1] = tag end
  table.sort(list)
  return table.concat(list, " ")
end

-- The same rules the extension applies before it uses a string.
local function problems_of(english, translation)
  local problems, translated, same = {}, 0, 0
  for _, key in ipairs(sorted_keys(translation)) do
    local value, source = translation[key], english[key]
    if not source then
      problems[#problems + 1] = key .. ": unknown key (not in en.json)"
    elseif type(value) ~= "string" or value == "" then
      problems[#problems + 1] = key .. ": must be a non-empty string"
    else
      translated = translated + 1
      if value == source then same = same + 1 end
      if count(value, "%%s") ~= count(source, "%%s") then
        problems[#problems + 1] = key .. ": needs " .. count(source, "%%s") .. " x %s, has " .. count(value, "%%s")
      elseif count(source, "%%s") > 0 and value:gsub("%%s", ""):find("%", 1, true) then
        problems[#problems + 1] = key .. ": stray % (only %s is allowed here)"
      end
      if tags(value) ~= tags(source) then
        problems[#problems + 1] = key .. ": HTML tags differ\n      en: " .. tags(source) .. "\n      is: " .. tags(value)
      end
      if (source:sub(1, 1) == " ") ~= (value:sub(1, 1) == " ") then
        problems[#problems + 1] = key .. ": leading space must match the English string"
      end
      if (source:sub(-1) == " ") ~= (value:sub(-1) == " ") then
        problems[#problems + 1] = key .. ": trailing space must match the English string"
      end
      if #value > #source * 4 + 60 then
        problems[#problems + 1] = key .. ": too long (" .. #value .. " bytes; limit " .. (#source * 4 + 60) .. ")"
      end
    end
  end
  return problems, translated, same
end

local function english_strings()
  local english, err = load("en.json")
  if not english then
    io.stderr:write("locale/en.json " .. err .. " - run: lua tools/locale.lua export\n")
    os.exit(2)
  end
  return english
end

local function index_entry(index, code)
  for _, l in ipairs(index.languages) do
    if l.code == code then return l end
  end
end

local function valid_code(code)
  return type(code) == "string" and code:match("^[a-z][a-z%-]+$") and code ~= "en" and code ~= "index"
end

local commands = {}

function commands.status()
  local english, index = english_strings(), assert(load("index.json"))
  local total = #sorted_keys(english)
  print(string.format("%-7s %-26s %-8s %9s %10s %9s", "code", "name", "status", "strings", "untouched", "problems"))
  local failed = false
  for _, l in ipairs(index.languages) do
    local translation, err = load(l.code .. ".json")
    if not translation then
      print(string.format("%-7s %-26s %s", l.code, l.english_name or l.name, "FILE " .. err))
      failed = true
    else
      local problems, translated, same = problems_of(english, translation)
      if #problems > 0 then failed = true end
      print(string.format("%-7s %-26s %-8s %4d/%-4d %10d %9d", l.code, l.english_name or l.name, l.status,
        translated, total, same, #problems))
    end
  end
  print("\nuntouched = translated strings identical to English (names like 'IMDB ID' are fine)")
  return not failed
end

function commands.check(...)
  local english, index = english_strings(), assert(load("index.json"))
  local codes = { ... }
  if #codes == 0 then
    for _, l in ipairs(index.languages) do codes[#codes + 1] = l.code end
  end
  local total, failed = #sorted_keys(english), false
  for _, code in ipairs(codes) do
    local translation, err = load(code .. ".json")
    if not translation then
      print(code .. ": locale/" .. code .. ".json " .. err)
      failed = true
    else
      local problems, translated = problems_of(english, translation)
      if not index_entry(index, code) then
        problems[#problems + 1] = "not listed in index.json (lua tools/locale.lua new " .. code .. " ...)"
      end
      print(string.format("%s: %d of %d strings translated, %d problem(s)", code, translated, total, #problems))
      for _, p in ipairs(problems) do print("  - " .. p) end
      if #problems > 0 then failed = true end
    end
  end
  return not failed
end

function commands.missing(code)
  local english = english_strings()
  local translation = load(code .. ".json") or {}
  local n = 0
  for _, key in ipairs(sorted_keys(english)) do
    if translation[key] == nil then
      n = n + 1
      print(key .. "\t" .. english[key]:gsub("\n", "\\n"))
    end
  end
  io.stderr:write(n .. " string(s) not translated in " .. code .. "\n")
  return true
end

commands["new"] = function(code, name, english_name)
  if not valid_code(code) or not name or name == "" then
    io.stderr:write('usage: lua tools/locale.lua new <code> "<Name in that language>" ["<English name>"]\n')
    return false
  end
  local index = assert(load("index.json"))
  if index_entry(index, code) then
    io.stderr:write(code .. " is already in index.json\n")
    return false
  end
  if not read(LOCALE .. code .. ".json") then save_translation(code, {}) end
  index.languages[#index.languages + 1] = { code = code, name = name, english_name = english_name, status = "review" }
  save_index(index)
  print("created locale/" .. code .. ".json and added it to index.json (status: review)")
  print("next: lua tools/locale.lua missing " .. code .. "   then translate, then: lua tools/locale.lua check " .. code)
  return true
end

local function set_status(code, status)
  local index = assert(load("index.json"))
  local entry = index_entry(index, code)
  if not entry then
    io.stderr:write(tostring(code) .. " is not in index.json\n")
    return false
  end
  if status == "ready" then
    local problems = problems_of(english_strings(), assert(load(code .. ".json")))
    if #problems > 0 then
      io.stderr:write(code .. " has " .. #problems .. " problem(s); fix them first (lua tools/locale.lua check " .. code .. ")\n")
      return false
    end
    entry.note = nil
  end
  entry.status = status
  save_index(index)
  print(code .. ": " .. status .. (status == "ready" and " - offered to users once this is on the main branch" or ""))
  return true
end

function commands.ready(code) return set_status(code, "ready") end
function commands.review(code) return set_status(code, "review") end

function commands.export()
  local lua = arg[-1] or "lua"
  local ok = os.execute(lua .. ' "' .. ROOT .. '/tests/export_strings.lua"')
  return ok == true or ok == 0
end

local command = commands[arg[1] or ""]
if not command then
  local text = read(arg[0])
  io.write((text:match("^(.-)\n\nlocal"):gsub("%-%- ?", "")), "\n")
  os.exit(arg[1] and 2 or 0)
end
local unpack_args = table.unpack or unpack
os.exit(command(unpack_args(arg, 2)) and 0 or 1)
