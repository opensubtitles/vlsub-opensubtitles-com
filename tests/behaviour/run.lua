-- Behaviour diff: proves that the working copy of vlsubcom.lua behaves like
-- the frozen baseline (tests/behaviour/baseline/vlsubcom.lua = v1.4.0).
--
--   lua tests/behaviour/run.lua                 all sessions
--   lua tests/behaviour/run.lua download        sessions whose name contains "download"
--   CANDIDATE=/path/to/other.lua lua tests/behaviour/run.lua    compare another file
--
-- Every session in sessions.lua is a scripted use of the extension (start it,
-- click, type, ...). It is run twice, once per version, and everything a user
-- or the outside world can observe is recorded after each step:
--
--   * every request: transport, method, URL, headers, body, in order
--   * every window: title and each widget's kind, position, text and entries
--   * the status message
--   * every file under the sandbox: name, permissions, content
--   * what VLC was told: subtitles added, config values, variables
--   * info / warning / error log lines, shell commands, Lua errors
--
-- The two recordings must be equal. The only tolerated differences are the
-- ones declared in EXCEPTIONS below (see docs/refactor-brief.md).

local here = (arg and arg[0] or "tests/behaviour/run.lua"):match("^(.*)[/\\][^/\\]*$") or "."
package.path = here .. "/../lib/?.lua;" .. here .. "/?.lua;" .. package.path
local H = require("harness")
local json = H.json

local BASELINE = here .. "/baseline/vlsubcom.lua"
local CANDIDATE = os.getenv("CANDIDATE") or (here .. "/../../vlsubcom.lua")

-- --------------------------------------------------------------- exceptions --
-- Agreed differences from the baseline (tests/behaviour/baseline/vlsubcom.lua,
-- v1.4.0 since the AI work started; v1.3.2 before). Each one is applied to
-- BOTH recordings, so it can only hide the difference it names.
local EXCEPTIONS = {
  {
    name = "debug log content",
    why = "stage 2 reduces debug output; debug lines are not recorded at all",
  },
  {
    name = "vlsub_conf.json no longer stores interface strings",
    why = "only real settings are written; old files still load",
    -- interface-translation machinery (removed, was unreachable), and the
    -- hidden debugLogging switch (VLC's own verbosity is the switch now)
    -- and settings no code reads (the last one since the first release, the
    -- request* ones since the legacy socket client was removed)
    drop_config_keys = { translation = true, translations_avail = true, intLang = true,
                         debugLogging = true, showMediaInformation = true,
                         requestTimeoutMs = true, requestPollIntervalMs = true,
                         requestMaxRetries = true },
  },
}
EXCEPTIONS[3] = {
  name = "interface translations (phase 2)",
  why = "new feature: an 'Interface language' row in the configuration window, the "
     .. "interfaceLanguage / detectedLanguage settings, the stored locale/ files and the "
     .. "requests that fetch them. With English in use everything else must be unchanged.",
}
EXCEPTIONS[4] = {
  name = "answers that made v1.3.2 raise a Lua error",
  why = "bug fix: a response body that is valid JSON but not an object (a number, true, "
     .. "or a raw subtitle starting with its cue number) was indexed and raised 'attempt "
     .. "to index a number/boolean value', leaving the window stuck on its progress bar. "
     .. "From the step where v1.3.2 raised that error and the current code does not, the "
     .. "rest of the session is not compared: v1.3.2 was broken from there on.",
  -- (Lua 5.1/5.2 word the first differently, and their ipairs refuses a
  -- string where 5.3+ walks it as an empty list)
  baseline_errors = { "attempt to index %(?a %a+ value", "bad argument #1 to 'ipairs'" },
}
EXCEPTIONS[5] = {
  name = "an unreachable network is tried once",
  why = "bug fix: every connection attempt on a dead network blocks VLC's window until "
     .. "the system gives up, and v1.3.2 made up to three per request and went on with "
     .. "the next request. Now a failed connection is not retried and requests in the "
     .. "following 10 seconds are refused at once. Only these log lines are left out of "
     .. "the comparison; windows, messages and files must still be the same.",
  log_lines = { "failed: connect %(attempt %d+%)", "Not sent: the network was unreachable" },
}
EXCEPTIONS[6] = {
  name = "configuration window: fields aligned",
  why = "asked for by the user: the drop-downs started one column to the right of the "
     .. "username / password fields (labels were two columns wide). Every field starts in "
     .. "column 2 now. In the configuration window a drop-down's column is not compared.",
}
EXCEPTIONS[7] = {
  name = "AI on-demand subtitles (2.0)",
  why = "new feature: an 'AI credits' row in the configuration window, the balance in "
     .. "the message after Save (one request to /ai/credits); the help window "
     .. "rewritten (shorter, with an AI section); entries the API "
     .. "offers only to 2.x User-Agents are marked and paid with credits. Nothing else "
     .. "may change: the row is left out of the comparison.",
}
local DROP_CONFIG_KEYS = EXCEPTIONS[2].drop_config_keys
DROP_CONFIG_KEYS.interfaceLanguage = true
DROP_CONFIG_KEYS.detectedLanguage = true
DROP_CONFIG_KEYS.aiTranslations = true -- exception 7

local LOCALE_REQUEST = "raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/locale/"
-- exception 7: requests about AI credits, and the balance in the Save message
local function is_ai_request(text)
  return text:find("/api/v1/ai/", 1, true) ~= nil
end

local function is_locale_request(text)
  return text:find(LOCALE_REQUEST, 1, true) ~= nil
end

-- ------------------------------------------------------------ normalisation --
local function canonical(v, indent)
  indent = indent or ""
  if type(v) ~= "table" then
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "number" and v > 1.6e9 and v < 2.1e9 then return "<EPOCH>" end
    return tostring(v)
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) < type(b)
  end)
  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = indent .. "  " .. tostring(k) .. " = " .. canonical(v[k], indent .. "  ")
  end
  if #out == 0 then return "{}" end
  return "{\n" .. table.concat(out, "\n") .. "\n" .. indent .. "}"
end

-- The version number is the one difference a release always has.
local VERSIONS = {}
for _, script in ipairs({ BASELINE, CANDIDATE }) do
  local version = (H.read_file(script) or ""):match('local app_version = "([^"]+)"')
  if version then VERSIONS[#VERSIONS + 1] = version:gsub("%p", "%%%0") end
end

local function make_normaliser(env)
  local root = H.tmp_root():gsub("%p", "%%%0")
  local home_index = env.home:match("(%d+)$")
  return function(text)
    if type(text) ~= "string" then return text end
    -- sandbox directories are numbered per launch
    text = text:gsub(root .. "/(%d+)", function(n)
      return n == home_index and "<HOME>" or "<DIR>"
    end)
    for _, version in ipairs(VERSIONS) do
      text = text:gsub("%f[%d]" .. version .. "%f[%D]", "<VERSION>")
    end
    -- wall-clock values: epoch seconds, and durations the extension measures
    text = text:gsub("%f[%d]1[6-9]%d%d%d%d%d%d%d%d%f[%D]", "<EPOCH>")
    text = text:gsub("%(%d+ms%)", "(<N>ms)"):gsub("in %d+ms", "in <N>ms")
    text = text:gsub("%d+%.%d+ seconds", "<N> seconds")
    text = text:gsub("%[%d%d:%d%d:%d%d%]", "[<CLOCK>]")
    -- Lua errors: where they happen and what the local was called may change
    -- in a refactor; that they happen, and why, may not.
    -- (guarded by a plain search: the first pattern is slow on long texts)
    if text:find(".lua:", 1, true) then
      text = text:gsub("[%w_%.%-]+%.lua:%d+:", "<SCRIPT>:<LINE>:")
      -- Lua 5.3+: "attempt to index a number value (local 'x')"
      text = text:gsub(" %((%a+) '[^']*'%)", "")
      -- Lua 5.1/5.2: "attempt to index local 'x' (a number value)"
      text = text:gsub("(attempt to %a+) %a+ '[^']*' %(", "%1 (")
    end
    return text
  end
end

-- ----------------------------------------------------------------- recorder --
local function snapshot(env, norm, cursor)
  local snap = {}

  -- requests since the previous step
  snap.requests = {}
  for i = cursor.requests + 1, #env.server.requests do
    local r = env.server.requests[i]
    if not is_locale_request(r.host .. r.path) and not is_ai_request(r.host .. r.path) then
    local headers = {}
    for _, h in ipairs(r.header_list) do headers[#headers + 1] = h[1] .. ": " .. h[2] end
    table.sort(headers) -- custom headers are emitted in table order, which is not behaviour
    snap.requests[#snap.requests + 1] = norm(table.concat({
      r.via .. " " .. r.method .. " " .. r.scheme .. "://" .. r.host .. ":" .. r.port .. r.target,
      table.concat(headers, "\n"),
      "body: " .. r.body,
      #r.problems > 0 and ("PROBLEMS: " .. table.concat(r.problems, "; ")) or "",
    }, "\n"))
    end
  end
  cursor.requests = #env.server.requests

  -- windows
  snap.windows = {}
  for index, d in ipairs(env.vlc._dialogs) do
    local w = { "#" .. index .. " " .. norm(d.title) .. (d.visible and " [visible]" or " [hidden]") }
    -- Exception 3: the configuration window has one more row. Leave that row
    -- out and number the remaining rows consecutively, in both recordings.
    local is_config = d.title:find("Configuration", 1, true) ~= nil
    local is_help = d.title:find(": Help", 1, true) ~= nil
    local skip, rows, row_number = {}, {}, {}
    if is_config then
      for _, x in ipairs(d.widgets) do
        -- rows the baseline did not have: interface language (if it predates
        -- it) and AI credits
        if x.kind == "label" and (x.text == "Interface language:" or x.text == "AI translations:") then
          skip[x.row] = true
        end
      end
    end
    -- The help window was rewritten for 2.0 (shortened to fit a laptop
    -- screen, AI section added): only that it opens is compared.
    if is_config then
      for _, x in ipairs(d.widgets) do
        if x.row and not skip[x.row] and not row_number[x.row] then
          row_number[x.row] = true
          rows[#rows + 1] = x.row
        end
      end
      table.sort(rows)
      for position, row in ipairs(rows) do row_number[row] = position end
    end
    for _, x in ipairs(d.widgets) do
      if not (is_config and skip[x.row]) and not is_help then
        local row = is_config and row_number[x.row] or x.row
        local col = (is_config and x.kind == "dropdown") and "*" or tostring(x.col) -- exception 6
        local text = norm(x.text or "")
        if is_config then text = text:gsub("<br>AI credits: %d+", "") end -- exception 7
        -- the site's name in the username label is a link since 2.0
        if is_config then text = text:gsub("<a href='https://www%.opensubtitles%.com'>OpenSubtitles%.com</a>", "OpenSubtitles.com") end
        local line = string.format("%s @%s,%s %q", x.kind, col, tostring(row), text)
        if x.kind == "check_box" then line = line .. " checked=" .. tostring(x.checked) end
        w[#w + 1] = line
        for _, v in ipairs(x.values) do
          w[#w + 1] = "    " .. tostring(v.id) .. " " .. norm(v.text)
        end
      end
    end
    snap.windows[index] = table.concat(w, "\n")
  end

  -- files
  snap.files = {}
  local p = H.real_popen('cd "' .. env.home .. '" && find . -type f | LC_ALL=C sort')
  for path in p:lines() do
    if not path:find("/vlsub.com/locale/", 1, true) then
    local full = env.home .. "/" .. path:sub(3)
    local ls = H.real_popen('ls -l "' .. full .. '"')
    local mode = (ls:read("*l") or ""):sub(1, 10)
    ls:close()
    local content = H.read_file(full) or ""
    if path:match("%.json$") then
      local decoded = json.decode(content)
      if type(decoded) == "table" then
        if path:match("vlsub_conf%.json$") then
          for k in pairs(DROP_CONFIG_KEYS) do decoded[k] = nil end
        end
        content = canonical(decoded)
      end
    elseif #content > 4096 then
      -- the test videos: identify, do not dump
      content = "<" .. #content .. " bytes>"
    end
    snap.files[#snap.files + 1] = norm(path) .. " " .. mode .. "\n" .. norm(content)
    end
  end
  p:close()

  -- what VLC was told
  snap.vlc = norm(canonical({
    subtitles = env.vlc._subtitles, config = env.vlc._config, vars = env.vlc._vars,
    deactivated = env.vlc._deactivated, open_sockets = env.vlc._open_sockets(),
  }))

  -- log (debug level excluded: agreed exception 1), shell commands
  snap.log = {}
  for i = cursor.log + 1, #env.vlc._log do
    local l = env.vlc._log[i]
    local unreachable = false
    for _, pattern in ipairs(EXCEPTIONS[5].log_lines) do
      if l.msg:find(pattern) then unreachable = true end
    end
    if l.level ~= "dbg" and not is_locale_request(l.msg) and not is_ai_request(l.msg) and not unreachable then
      snap.log[#snap.log + 1] = l.level .. " " .. norm(l.msg)
    end
  end
  cursor.log = #env.vlc._log
  snap.commands = {}
  for i = cursor.commands + 1, #env.commands do snap.commands[#snap.commands + 1] = norm(env.commands[i]) end
  cursor.commands = #env.commands
  for i = cursor.executed + 1, #env.executed do
    -- creating the folder for stored translations is part of exception 3
    if not env.executed[i]:find("vlsub.com[/\\]locale", 1, false) then
      snap.commands[#snap.commands + 1] = "exec " .. norm(env.executed[i])
    end
  end
  cursor.executed = #env.executed

  return snap
end

-- Run one session against one script; returns { {label=..., snap=...}, ... }
local function record(session, script)
  local trace = {}
  local env, norm, cursor
  local S = { H = H, api = H.fake_api }

  function S.launch(o)
    o = o or {}
    o.script = script
    local launched, err = pcall(function() env = H.launch(o) end)
    if not launched then
      trace[#trace + 1] = { label = "launch", error = tostring(err):gsub("^[^:]*:%d+: ", "") }
      error({ aborted = true })
    end
    norm = make_normaliser(env)
    cursor = { requests = 0, log = 0, commands = 0, executed = 0 }
    S.env = env
    S.step("launch")
    return env
  end

  -- Perform an action and record the state after it. A Lua error inside the
  -- action is part of the behaviour (VLC logs it and carries on).
  function S.step(label, action)
    local entry = { label = label }
    if action then
      local done, err = pcall(action)
      if not done then
        entry.error = norm(tostring(err):gsub("^[^:]*/", ""))
      end
    end
    entry.snap = snapshot(env, norm, cursor)
    trace[#trace + 1] = entry
  end

  local finished, err = pcall(session.run, S)
  if not finished and not (type(err) == "table" and err.aborted) then
    trace[#trace + 1] = { label = "SESSION SCRIPT ERROR", error = tostring(err) }
  end
  return trace
end

-- ------------------------------------------------------------------ compare --
local function first_difference(a, b)
  local la, lb = {}, {}
  for line in (a .. "\n"):gmatch("(.-)\n") do la[#la + 1] = line end
  for line in (b .. "\n"):gmatch("(.-)\n") do lb[#lb + 1] = line end
  for i = 1, math.max(#la, #lb) do
    if la[i] ~= lb[i] then
      return "      line " .. i .. "\n        baseline: " .. tostring(la[i]) ..
             "\n        current: " .. tostring(lb[i])
    end
  end
end

local function compare(old, new)
  local diffs = {}
  local function differ(where, a, b)
    diffs[#diffs + 1] = "    " .. where .. "\n" .. (first_difference(a or "<nothing>", b or "<nothing>") or "")
  end
  for i = 1, math.max(#old, #new) do
    local o, n = old[i], new[i]
    local label = (o and o.label) or (n and n.label)
    if not o or not n then
      differ("step " .. i .. " '" .. label .. "': present in only one version", o and "present" or "absent", n and "present" or "absent")
    else
      local was_broken = false
      for _, pattern in ipairs(EXCEPTIONS[4].baseline_errors) do
        if o.error and not n.error and o.error:find(pattern) then was_broken = true end
      end
      if was_broken then break end
      if (o.error or "") ~= (n.error or "") then
        differ("step '" .. label .. "': Lua error", o.error or "<none>", n.error or "<none>")
      end
      if o.snap and n.snap then
        for _, section in ipairs({ "requests", "windows", "files", "log", "commands" }) do
          local A, B = o.snap[section], n.snap[section]
          for j = 1, math.max(#A, #B) do
            if A[j] ~= B[j] then
              differ("step '" .. label .. "': " .. section .. " #" .. j, A[j], B[j])
            end
          end
        end
        if o.snap.vlc ~= n.snap.vlc then differ("step '" .. label .. "': vlc state", o.snap.vlc, n.snap.vlc) end
      end
    end
  end
  return diffs
end

-- --------------------------------------------------------------------- main --
local sessions = dofile(here .. "/sessions.lua")
local filter = arg and arg[1]
local failed, ran, steps = 0, 0, 0

for _, session in ipairs(sessions) do
  if not filter or session.name:lower():find(filter:lower(), 1, true) then
    ran = ran + 1
    local started = H.real_clock()
    local old = record(session, BASELINE)
    local new = record(session, CANDIDATE)
    local seconds = H.real_clock() - started
    steps = steps + #old
    local diffs = compare(old, new)
    if #diffs == 0 then
      print(string.format("identical  %-62s %2d steps %5.1fs", session.name, #old, seconds))
    else
      failed = failed + 1
      print("DIFFERENT  " .. session.name)
      for i = 1, math.min(#diffs, 8) do print(diffs[i]) end
      if #diffs > 8 then print("    ... and " .. (#diffs - 8) .. " more differences") end
    end
  end
end

H.cleanup()
print(string.format("\n%d sessions, %d steps compared on %s: %d identical, %d different",
  ran, steps, _VERSION, ran - failed, failed))
-- Exceptions 2 to 6 were differences from v1.3.2. The baseline is v1.4.0 now,
-- which has them all, so their rules no longer hide anything; they stay for
-- comparing against an older script (CANDIDATE / baseline swapped by hand).
print("baseline: v" .. tostring((H.read_file(BASELINE) or ""):match('local app_version = "([^"]+)"'))
  .. "   agreed exceptions: " .. EXCEPTIONS[1].name .. "; " .. EXCEPTIONS[7].name)
os.exit(failed == 0 and 0 or 1)
