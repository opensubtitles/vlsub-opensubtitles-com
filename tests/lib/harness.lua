-- Test framework + launcher for vlsubcom.lua. Plain Lua 5.1 - 5.4, no deps.

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
package.path = here .. "/?.lua;" .. here .. "/../vendor/?.lua;" .. package.path

local mock = require("mock_vlc")
local fake_api = require("fake_api")
local json = require("dkjson")

local H = { mock = mock, fake_api = fake_api, json = json }
H.ROOT = here .. "/../.."
H.SCRIPT = H.ROOT .. "/vlsubcom.lua"

-- ------------------------------------------------------------------ time --
-- The extension implements delays as os.clock() busy-waits and timeouts with
-- os.time(). Give it a clock that advances 50ms per call so waits end at once.
H.real_clock = os.clock
-- Wall-clock deadlines (socket timeout) use os.time(): let a second pass every
-- 50 calls so a 15 second timeout takes a few hundred loop turns, not 15 s.
H.real_time = os.time
do
  local calls = 0
  os.time = function(t)
    if t then return H.real_time(t) end
    calls = calls + 1
    return H.real_time() + math.floor(calls / 50)
  end
end
H.real_getenv = os.getenv
H.real_popen = io.popen
H.real_open = io.open
H.real_execute = os.execute
H.real_setlocale = os.setlocale
do
  local fake = 0
  os.clock = function()
    fake = fake + 0.05
    return fake
  end
end

-- ----------------------------------------------------------------- files --
local tmp_root
function H.tmpdir()
  if not tmp_root then
    local p = H.real_popen("mktemp -d 2>/dev/null || mktemp -d -t vlsub")
    tmp_root = p:read("*l")
    p:close()
    assert(tmp_root and tmp_root ~= "", "could not create temp dir")
  end
  H._n = (H._n or 0) + 1
  local d = tmp_root .. "/" .. H._n
  H.real_execute('mkdir -p "' .. d .. '"')
  return d
end
function H.tmp_root() return tmp_root end
function H.cleanup()
  if tmp_root then H.real_execute('rm -rf "' .. tmp_root .. '"') end
end
function H.read_file(path)
  local f = H.real_open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
function H.write_file(path, content)
  local f = assert(H.real_open(path, "wb"))
  f:write(content)
  f:close()
end
function H.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end
function H.ls(dir)
  local out = {}
  local p = H.real_popen('ls -1 "' .. dir .. '" 2>/dev/null')
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  return out
end

-- ------------------------------------------------------------ assertions --
local function show(v, depth)
  depth = depth or 0
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" or depth > 3 then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = tostring(k) .. "=" .. show(v[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end
H.show = show

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function H.eq(actual, expected, what)
  if not same(actual, expected) then
    error((what or "value") .. ":\n  expected " .. show(expected) ..
          "\n  got      " .. show(actual), 2)
  end
end
function H.ok(cond, what)
  if not cond then error(what or "expected a true value", 2) end
end
function H.has(text, needle, what)
  if type(text) ~= "string" or not text:find(needle, 1, true) then
    error((what or "text") .. ": expected to contain " .. show(needle) ..
          "\n  got " .. show(text), 2)
  end
end
function H.lacks(text, needle, what)
  if type(text) == "string" and text:find(needle, 1, true) then
    error((what or "text") .. ": expected NOT to contain " .. show(needle) ..
          "\n  got " .. show(text), 2)
  end
end
function H.raises(fn, pattern)
  local ok, err = pcall(fn)
  if ok then error("expected an error" .. (pattern and (" matching " .. pattern) or ""), 2) end
  if pattern and not tostring(err):find(pattern) then
    error("error did not match " .. show(pattern) .. ": " .. tostring(err), 2)
  end
  return err
end

-- ------------------------------------------------------------- registry --
H.tests = {}
local current_group = ""
function H.describe(name, fn)
  local outer = current_group
  current_group = (outer ~= "" and (outer .. " > ") or "") .. name
  fn()
  current_group = outer
end
function H.it(name, fn)
  H.tests[#H.tests + 1] = { name = current_group .. ": " .. name, fn = fn }
end
-- A defect that exists today. The body asserts the CORRECT behaviour, so it
-- fails now; the runner reports it as a known bug instead of a failure. Once
-- the code is fixed the test starts passing and the runner flags it so it can
-- be turned into a normal `it`.
function H.known_bug(name, why, fn)
  H.tests[#H.tests + 1] = { name = current_group .. ": " .. name, fn = fn, known_bug = why }
end

-- --------------------------------------------------------------- launch --

-- Options the extension would have saved after a normal first run.
local function default_config(o)
  local c = {
    language = "en", downloadBehaviour = "save", langExt = true, removeTag = false,
    showMediaInformation = true, progressBarSize = 80, intLang = "eng",
    debugLogging = false, sortDirection = "desc",
  }
  if o.login ~= false then
    c.os_username = o.username or "tester"
    c.os_password = o.password or "test-password"
  end
  for k, v in pairs(o.config or {}) do
    if v == false and (k == "language" or k == "os_username") then c[k] = nil else c[k] = v end
  end
  return c
end

-- Start the extension the way VLC does: load the file, call activate().
--   media      URI of the playing item (nil = nothing playing)
--   login      false = no credentials saved            (default: valid ones)
--   config     overrides for the saved vlsub_conf.json
--   first_run  true = no config on disk at all
--   server     table of fake_api options, or a prepared server
--   activate   false = load only, do not call activate()
function H.launch(o)
  o = o or {}
  local env = { home = H.tmpdir() }
  env.dir = env.home .. "/lua/extensions/userdata/vlsub.com"
  env.server = (o.server and o.server.handle) and o.server or fake_api.new(o.server)
  env.vlc = mock.new({ dir = env.home, server = env.server, config = o.vlc_config })
  if o.offline then env.server.offline = true end

  if not o.first_run then
    H.real_execute('mkdir -p "' .. env.dir .. '"')
    H.write_file(env.dir .. "/vlsub_conf.json", json.encode(default_config(o)))
    for name, content in pairs(o.files or {}) do
      H.write_file(env.dir .. "/" .. name, content)
    end
  end
  if o.media then env.vlc._item = mock.item(o.media, o.metas) end

  -- Keep the extension inside the sandbox: $HOME (used to find ~/Downloads)
  -- points at the temp dir, and tests can script the environment/commands
  -- used for locale detection.
  local vars = { HOME = env.home, USERPROFILE = env.home }
  for k, v in pairs(o.env or {}) do vars[k] = v end
  os.getenv = function(name)
    local v = vars[name]
    if v == false then return nil end
    if v ~= nil then return v end
    return H.real_getenv(name)
  end
  env.commands = {}
  env.executed = {}
  os.execute = function(cmd)
    if cmd then env.executed[#env.executed + 1] = cmd end
    return H.real_execute(cmd)
  end
  io.popen = function(cmd, mode)
    env.commands[#env.commands + 1] = cmd
    if o.popen then
      local out = o.popen(cmd)
      if out ~= nil then
        local done = false
        return { read = function() if done then return nil end done = true return out end,
                 lines = function() return out:gmatch("[^\n]+") end,
                 close = function() return true end }
      end
    end
    return H.real_popen(cmd, mode)
  end

  -- Locale detection also asks the C library and reads /etc/default/locale,
  -- /etc/locale.conf, ...: answers that differ on every machine. A test that
  -- scripts the environment (o.host_locale) gets a fixed answer for both.
  os.setlocale = function(locale, category)
    if o.host_locale ~= nil and locale == nil then return o.host_locale end
    return H.real_setlocale(locale, category)
  end
  io.open = function(path, mode)
    if o.host_locale ~= nil and type(path) == "string" and path:match("^/etc/") then
      return nil, path .. ": No such file or directory", 2
    end
    return H.real_open(path, mode)
  end

  _G.vlc = env.vlc
  assert(loadfile(o.script or H.SCRIPT))()

  function env.ui() return env.vlc._dialog() end
  function env.message()
    local d = env.ui()
    -- The status line is the label on the row above the bottom button row.
    local best
    for _, w in ipairs(d.widgets) do
      if w.kind == "label" and w.row == 10 then best = w end
    end
    return best and best.text or ""
  end
  function env.results() return env.ui():_all("list")[1] end
  function env.saved_config()
    local raw = H.read_file(env.dir .. "/vlsub_conf.json")
    return raw and json.decode(raw) or nil
  end
  function env.play(uri, metas)
    env.vlc._item = uri and mock.item(uri, metas) or nil
  end
  function env.errors() return env.vlc._messages("err") end

  if o.activate ~= false then activate() end
  return env
end

-- Read a file-local variable of the extension (e.g. `Curl`, `config`, `json`,
-- `input_table`) without changing the extension: every function that uses a
-- local keeps it as an upvalue, so look through the upvalues of the global
-- functions and of the openSub.* functions.
function H.find_local(name)
  local seen = {}
  local function search(fn, depth)
    if seen[fn] then return nil end
    seen[fn] = true
    local i = 1
    while true do
      local n, v = debug.getupvalue(fn, i)
      if not n then break end
      if n == name then return true, v end
      i = i + 1
    end
    if depth < 2 then
      i = 1
      while true do
        local n, v = debug.getupvalue(fn, i)
        if not n then break end
        if type(v) == "function" then
          local found, value = search(v, depth + 1)
          if found then return found, value end
        end
        i = i + 1
      end
    end
  end
  local pools = { _G, rawget(_G, "openSub") or {} }
  for _, pool in ipairs(pools) do
    local keys = {}
    for k, v in pairs(pool) do
      if type(k) == "string" and type(v) == "function" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local found, value = search(pool[k], 0)
      if found then return value end
    end
  end
  error("no function of the extension uses a local named '" .. name .. "'", 2)
end

-- A local "video" file with deterministic content, for hash searches.
-- Returns its path. Content is byte i -> (i * 7 + 3) % 251.
function H.video(dir, name, size)
  local path = dir .. "/" .. name
  local block = {}
  for i = 0, 250 do block[#block + 1] = string.char((i * 7 + 3) % 251) end
  block = table.concat(block)
  local f = assert(io.open(path, "wb"))
  local written = 0
  while written + #block <= size do f:write(block) written = written + #block end
  f:write(block:sub(1, size - written))
  f:close()
  return path
end

-- ---------------------------------------------------------------- runner --
function H.run(filter)
  local failed, known, fixed, ran = {}, {}, {}, 0
  for _, t in ipairs(H.tests) do
    if not filter or t.name:lower():find(filter:lower(), 1, true) then
      ran = ran + 1
      local t0 = H.real_clock()
      local passed, err = xpcall(t.fn, function(e)
        return debug.traceback(tostring(e), 2)
      end)
      local secs = string.format("%.2fs", H.real_clock() - t0)
      if t.known_bug then
        if passed then
          fixed[#fixed + 1] = t.name
          print("FIXED?    " .. t.name .. "\n          known bug no longer reproduces - change known_bug() to it()")
        else
          known[#known + 1] = t.name
          print("known bug " .. t.name .. "\n          " .. t.known_bug)
        end
      elseif passed then
        print("ok        " .. t.name .. " (" .. secs .. ")")
      else
        failed[#failed + 1] = t.name
        print("FAIL      " .. t.name)
        print("          " .. tostring(err):gsub("\n", "\n          "))
      end
    end
  end
  H.cleanup()
  print(string.format("\n%d tests on %s: %d passed, %d failed, %d known bugs%s",
    ran, _VERSION, ran - #failed - #known - #fixed, #failed, #known,
    #fixed > 0 and (", " .. #fixed .. " known bugs unexpectedly passing") or ""))
  return #failed == 0 and #fixed == 0
end

return H
