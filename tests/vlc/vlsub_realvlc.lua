-- Runs vlsubcom.lua INSIDE A REAL VLC, headless, and reports what happened.
--
-- VLC only loads extensions from its GUI, which cannot be scripted. A Lua
-- *interface* script can be started from the command line though, and it gets
-- the same Lua interpreter, the same vlc.net / vlc.stream / vlc.strings /
-- vlc.config and the same bundled dkjson. This script makes the interface
-- environment look like the extension one and then drives the extension:
--
--   extension has        interface has        what we do
--   -----------------    -----------------    ---------------------------------
--   vlc.dialog           (nothing)            use the dialog from mock_vlc.lua
--   no vlc.misc          vlc.misc             hide it (keep a private copy)
--   vlc.deactivate       (nothing)            stub
--
-- Everything else - sockets, TLS streams, URL parsing, JSON, the Lua version -
-- is the real thing, talking to the real API.
--
-- Started by tests/vlc/run.sh. Environment:
--   VLSUB_ROOT   repository root                         (required)
--   VLSUB_OUT    report file                             (required)
--   VLSUB_HOME   sandbox for config/cache/downloads      (required)
--   VLSUB_USER / VLSUB_PASS   OpenSubtitles.com account  (optional: login + download)
--   VLSUB_QUERY  title to search                         (default "the matrix")
--   VLSUB_VERBOSE  1 = also show what the extension logs (requests, warnings,
--                  errors); 2 = everything it logs, with debug logging on

local ROOT = assert(os.getenv("VLSUB_ROOT"), "VLSUB_ROOT not set")
local OUT = assert(os.getenv("VLSUB_OUT"), "VLSUB_OUT not set")
local SANDBOX = assert(os.getenv("VLSUB_HOME"), "VLSUB_HOME not set")
local USER, PASS = os.getenv("VLSUB_USER"), os.getenv("VLSUB_PASS")
local QUERY = os.getenv("VLSUB_QUERY") or "the matrix"
local VERBOSE = tonumber(os.getenv("VLSUB_VERBOSE") or "0") or 0

local misc = vlc.misc
local out = assert(io.open(OUT, "w"))
local failed, passed = 0, 0

local function line(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  out:write(table.concat(parts, " "), "\n")
  out:flush()
end

local function finish()
  line(string.format("\nRESULT: %d passed, %d failed", passed, failed))
  line(failed == 0 and "ALL OK" or "FAILURES")
  out:close()
  misc.quit()
end

-- A step is announced before it runs: if VLC hangs inside it (the outer
-- script kills VLC after a timeout) the report ends with that step's name.
local function step(name, fn)
  line("RUN  " .. name)
  local t0 = misc.mdate()
  local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
  local ms = math.floor((misc.mdate() - t0) / 1000)
  if ok then
    passed = passed + 1
    line("PASS " .. name .. " (" .. ms .. " ms)")
  else
    failed = failed + 1
    line("FAIL " .. name .. " (" .. ms .. " ms)\n     " .. tostring(err):gsub("\n", "\n     "))
  end
  return ok
end

local function check(cond, what) if not cond then error(what, 2) end end

-- ------------------------------------------------------------ environment --
line("== environment ==")
line("VLC:", misc.version(), "| Lua:", _VERSION)
local names = {}
for k, v in pairs(vlc) do names[#names + 1] = k .. ":" .. type(v) end
table.sort(names)
line("vlc.* in an interface:", table.concat(names, " "))
local net = {}
for k in pairs(vlc.net) do net[#net + 1] = k end
table.sort(net)
line("vlc.net:", table.concat(net, " "))
line("connect_ssl:", tostring(vlc.net.connect_ssl), "| vlc.io:", tostring(vlc.io ~= nil),
     "| io.popen:", type(io.popen), "| os.execute:", type(os.execute))
line("dkjson:", tostring((pcall(require, "dkjson"))), "| unpack:", type(unpack),
     "| table.unpack:", type(table.unpack), "| loadstring:", type(loadstring))
line("userdatadir:", vlc.config.userdatadir(), "| datadir:", vlc.config.datadir())
do
  local fd = vlc.net.connect_tcp("vlsub-selftest.invalid", 80)
  line("connect_tcp(unresolvable host) ->", tostring(fd), "| send ->",
       tostring(vlc.net.send(fd, "x")), "| recv ->", tostring(vlc.net.recv(fd, 8)))
  vlc.net.close(fd)
  local u = vlc.strings.url_parse("http://api.opensubtitles.com")
  line("url_parse(no path): path =", tostring(u.path), "| host =", tostring(u.host),
       "| port =", tostring(u.port))
end

-- ------------------------------------------- make it look like an extension --
package.path = ROOT .. "/tests/lib/?.lua;" .. package.path
local mock = dofile(ROOT .. "/tests/lib/mock_vlc.lua")

local dialogs = {}
vlc.dialog = function(title)
  local d = mock.new_dialog(vlc, title)
  dialogs[#dialogs + 1] = d
  return d
end
local function ui()
  for i = #dialogs, 1, -1 do if dialogs[i].visible then return dialogs[i] end end
end
vlc.deactivate = function() end
vlc.keep_alive = function() end

-- Verbose: copy what the extension writes to VLC's log into the report, with
-- the time since start. Level 1 shows info/warn/err (every request is logged
-- as a warning: "[VLSub] GET http://..."), level 2 adds debug lines.
if VERBOSE > 0 then
  local started = misc.mdate()
  local function tee(level, original)
    return function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      local text = table.concat(parts, " "):gsub("^%[VLSub%]%s*", ""):gsub("^%[VLsub%]%s*", "")
      line(string.format("     %7.2fs %-4s %s", (misc.mdate() - started) / 1000000, level, text))
      return original(...)
    end
  end
  local msg = vlc.msg
  msg.info, msg.warn, msg.err = tee("info", msg.info), tee("warn", msg.warn), tee("ERR", msg.err)
  if VERBOSE > 1 then msg.dbg = tee("dbg", msg.dbg) end
end
vlc.misc = nil -- extensions do not have it

-- Keep the user's real VLSub settings and ~/Downloads untouched.
os.execute('mkdir -p "' .. SANDBOX .. '/Downloads"')
vlc.config.userdatadir = function() return SANDBOX end
vlc.config.datadir = function() return SANDBOX end
do
  local real_getenv = os.getenv
  os.getenv = function(name)
    if name == "HOME" then return SANDBOX end
    return real_getenv(name)
  end
end

local function message()
  for _, w in ipairs(ui().widgets) do
    if w.kind == "label" and w.row == 10 then return w.text end
  end
  return ""
end

-- ---------------------------------------------------------------- the run --
line("\n== extension ==")

if not step("load vlsubcom.lua", function() dofile(ROOT .. "/vlsubcom.lua") end) then
  return finish()
end

step("unreachable host is reported at once (no frozen VLC)", function()
  local t0 = misc.mdate()
  local data, why = socket_exchange("vlsub-selftest.invalid", 80, "GET / HTTP/1.1\r\n\r\n", 5)
  local ms = math.floor((misc.mdate() - t0) / 1000)
  line("     -> " .. tostring(data) .. ", " .. tostring(why) .. " after " .. ms .. " ms")
  check(data == nil and why == "connect", "expected nil, 'connect'")
end)

step("silent server: gives up at the deadline (no frozen VLC)", function()
  -- An unfinished request: the server waits for the rest and sends nothing.
  local t0 = misc.mdate()
  local data, why = socket_exchange("api.opensubtitles.com", 80,
    "GET / HTTP/1.1\r\nHost: api.opensubtitles.com\r\n", 3)
  local ms = math.floor((misc.mdate() - t0) / 1000)
  line("     -> " .. tostring(data and #data) .. ", " .. tostring(why) .. " after " .. ms .. " ms")
  check(ms < 8000, "took longer than the 3 s deadline allows")
end)

step("activate() (first run: network test, language list, locale detection)", function()
  if VERBOSE > 1 then openSub.option.debugLogging = true end
  activate()
  if VERBOSE > 1 then openSub.option.debugLogging = true end -- survives the config load
  check(ui(), "no window was opened")
  line("     window: " .. ui().title)
end)

step("configuration saved in the sandbox", function()
  local f = io.open(SANDBOX .. "/lua/extensions/userdata/vlsub.com/vlsub_conf.json", "rb")
  check(f, "vlsub_conf.json was not written")
  local content = f:read("*a")
  f:close()
  line("     detected languages: " .. tostring(content:match('"language":"([^"]*)"')) ..
       ", " .. tostring(content:match('"language2":"([^"]*)"')) ..
       ", " .. tostring(content:match('"language3":"([^"]*)"')))
end)

if USER and PASS then
  step("save credentials in the configuration window and log in", function()
    trigger_menu(2)
    ui():_all("text_input")[1]:set_text(USER)
    ui():_all("password")[1]:set_text(PASS)
    ui():_button("\240\159\146\190"):_click()
    line("     message: " .. message():gsub("<[^>]+>", ""))
    check(not message():lower():find("fail") and not message():lower():find("error"), "login failed")
  end)
end

-- The languages picked on first run depend on the machine's locale and IP, and
-- the API's ranking depends on the language list, so choose them explicitly.
local function choose_languages(first, second, third)
  ui():_at(2, 4, "dropdown"):_choose_text("^" .. first .. "$")
  ui():_at(2, 5, "dropdown"):_choose_text("^" .. (second or "None") .. "$")
  ui():_at(2, 6, "dropdown"):_choose_text("^" .. (third or "None") .. "$")
end

-- "EN | name ..." rows -> "en=43 fr=7"
local function languages_listed(list)
  local count, order = {}, {}
  for _, v in ipairs(list.values) do
    local code = v.text:match("^(%S+) |")
    if code then
      if not count[code] then count[code] = 0 order[#order + 1] = code end
      count[code] = count[code] + 1
    end
  end
  local parts = {}
  for _, code in ipairs(order) do parts[#parts + 1] = code:lower() .. "=" .. count[code] end
  return table.concat(parts, " "), count
end

local function show_results(list)
  line("     message: " .. message():gsub("<[^>]+>", ""))
  line("     rows: " .. #list.values .. "   languages: " .. languages_listed(list))
  for i = 1, math.min(3, #list.values) do line("       " .. list.values[i].text) end
end

step("search by name: '" .. QUERY .. "', English (plain-HTTP GET with Api-Key header)", function()
  trigger_menu(1)
  choose_languages("English")
  ui():_at(2, 1, "text_input"):set_text(QUERY)
  ui():_button("Search$"):_click()
  local list = ui():_at(1, 9, "list")
  show_results(list)
  local _, count = languages_listed(list)
  check(count.EN and count.EN >= 1, "no English results - see message above")
  check(count.EN == #list.values, "asked for English only but other languages were listed")
end)

step("search by IMDb id tt0133093, English", function()
  ui():_at(4, 3, "text_input"):set_text("tt0133093")
  ui():_button("Search$"):_click()
  local list = ui():_at(1, 9, "list")
  show_results(list)
  check(#list.values >= 1 and message():find("IMDB"), "no IMDb results")
  ui():_at(4, 3, "text_input"):set_text("")
end)

step("search in two languages: English + French", function()
  choose_languages("English", "French")
  ui():_at(2, 1, "text_input"):set_text(QUERY)
  ui():_button("Search$"):_click()
  local list = ui():_at(1, 9, "list")
  show_results(list)
  local _, count = languages_listed(list)
  check(count.EN or count.FR, "no results in either language")
  for code in pairs(count) do
    check(code == "EN" or code == "FR", "unexpected language listed: " .. code)
  end
end)

step("season + episode search: Breaking Bad S02E05, English", function()
  choose_languages("English")
  ui():_at(2, 1, "text_input"):set_text("breaking bad")
  ui():_at(2, 2, "text_input"):set_text("2")
  ui():_at(4, 2, "text_input"):set_text("5")
  ui():_button("Search$"):_click()
  local list = ui():_at(1, 9, "list")
  show_results(list)
  check(#list.values >= 1 and not list.values[1].text:find("^No "), "no results")
  ui():_at(2, 2, "text_input"):set_text("")
  ui():_at(4, 2, "text_input"):set_text("")
  ui():_at(2, 1, "text_input"):set_text(QUERY)
  ui():_button("Search$"):_click() -- leave a result list for the download step
end)

if USER and PASS then
  step("download the first result (POST with JSON body, then https link)", function()
    local list = ui():_at(1, 9, "list")
    list:_select(list.values[1].id)
    ui():_button("Download"):_click()
    line("     message: " .. message():gsub("<[^>]+>", ""))
    local p = io.popen('ls -1 "' .. SANDBOX .. '/Downloads"')
    local name = p:read("*l")
    p:close()
    check(name, "nothing was saved in the sandbox Downloads folder")
    local f = io.open(SANDBOX .. "/Downloads/" .. name, "rb")
    local size = f:seek("end")
    f:close()
    line("     saved: " .. name .. " (" .. size .. " bytes)")
    check(size > 50, "saved file is suspiciously small")
  end)
else
  line("SKIP login + download (set VLSUB_USER and VLSUB_PASS to include them)")
end

step("deactivate()", function() deactivate() end)

finish()
