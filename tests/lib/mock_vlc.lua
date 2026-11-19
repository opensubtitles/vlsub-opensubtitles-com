-- Stand-in for the `vlc` table that VLC 3.0.x gives to Lua *extensions*.
--
-- The goal is fidelity, not convenience: behaviour is taken from the VLC
-- 3.0.x sources (modules/lua/extension.c and modules/lua/libs/*.c), so that
-- code which only works in a friendlier environment fails here too.
--
-- Things real VLC does that this mock reproduces on purpose:
--   * vlc.misc does not exist in extensions (interfaces only): no mdate/mwait
--   * there is no vlc.net.connect_ssl - raw sockets are plain TCP only
--   * vlc.net.connect_tcp returns a positive descriptor even when the
--     connection FAILED (checked on VLC 3.0.16); the failure only shows as
--     send() returning -1 and recv() returning nil
--   * vlc.net.recv returns nil at EOF/error, never ""; default length is 1
--   * vlc.net.poll IGNORES any timeout argument and blocks until an fd is
--     ready. Polling something that will never become ready hangs VLC's UI;
--     here it raises "would block forever" instead
--   * vlc.stream can only GET: no method, no headers, no body. It follows
--     redirects, speaks TLS, decodes chunked encoding, sends
--     "User-Agent: VLC/x.y.z LibVLC/x.y.z", and returns nil for HTTP error
--     statuses (checked on VLC 3.0.16 for 404 and 500)
--   * names that do not exist read as nil (so feature detection works) and
--     are recorded in vlc._unknown so tests can assert nothing unexpected
--     was touched
--
-- Networking is delegated to a server object (see fake_api.lua):
--   server:resolve(host, port)        -> true if a TCP connection succeeds
--   server:handle(request)            -> raw HTTP response bytes, keep_open
--   server.segment                    -> max bytes handed out per recv()

local M = {}
local real_popen = io.popen -- tests may replace io.popen for the extension

-- ------------------------------------------------------------ namespaces --

-- Table whose missing keys read as nil (like real VLC) but are recorded.
local function namespace(vlc, name, t)
  return setmetatable(t, {
    __index = function(_, k)
      local full = name .. "." .. tostring(k)
      vlc._unknown[#vlc._unknown + 1] = full
      return nil
    end,
  })
end

-- --------------------------------------------------------------- strings --

local function decode_uri(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function encode_uri_component(s)
  return (s:gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- vlc.strings.url_parse: fields protocol, username, password, host, port,
-- path, option. Missing parts are nil; port is 0 when absent.
local function url_parse(url)
  local out = { port = 0 }
  local rest = url
  local proto, after = rest:match("^(%a[%w+.-]*)://(.*)$")
  if proto then
    out.protocol = proto
    rest = after
    local authority, tail = rest:match("^([^/?#]*)(.*)$")
    rest = tail
    local userinfo, hostport = authority:match("^(.*)@(.*)$")
    if userinfo then
      out.username, out.password = userinfo:match("^([^:]*):?(.*)$")
      if out.password == "" then out.password = nil end
    else
      hostport = authority
    end
    local host, port = hostport:match("^(.*):(%d+)$")
    if host then
      out.host, out.port = host, tonumber(port)
    elseif hostport ~= "" then
      out.host = hostport
    end
  end
  local path, option = rest:match("^([^?]*)%??(.*)$")
  if path ~= "" then out.path = path end
  if option ~= "" then out.option = option end
  return out
end
M.url_parse = url_parse

local xml_entities = { ["&lt;"] = "<", ["&gt;"] = ">", ["&quot;"] = '"',
                       ["&apos;"] = "'", ["&amp;"] = "&" }

-- ---------------------------------------------------------------- dialog --

-- Widget constructors and the positional arguments they take before the
-- common (col, row, col_span, row_span, width, height) tail.
local WIDGET_ARGS = {
  button = { "text", "func" }, label = { "text" }, html = { "text" },
  text_input = { "text" }, password = { "text" },
  check_box = { "text", "state" }, dropdown = {}, list = {},
  image = { "path" }, spin_icon = { "loops" },
}

local WIDGET_METHODS = {
  set_text = { button = 1, label = 1, html = 1, text_input = 1, password = 1, check_box = 1 },
  get_text = { button = 1, label = 1, html = 1, text_input = 1, password = 1, check_box = 1 },
  set_checked = { check_box = 1 }, get_checked = { check_box = 1 },
  add_value = { dropdown = 1, list = 1 }, get_value = { dropdown = 1 },
  clear = { dropdown = 1, list = 1 }, get_selection = { list = 1 },
  animate = { spin_icon = 1 }, stop = { spin_icon = 1 },
}

local function new_widget(kind, dialog)
  local w = { kind = kind, text = "", values = {}, selected = {}, dialog = dialog }
  local api = {}
  function api.set_text(self, t)
    assert(type(t) == "string", "set_text() needs a string, got " .. type(t))
    self.text = t
  end
  function api.get_text(self) return self.text end
  function api.set_checked(self, b) self.checked = b and true or false end
  function api.get_checked(self) return self.checked or false end
  function api.add_value(self, text, id)
    assert(type(text) == "string", "add_value() text must be a string, got " .. type(text))
    self.values[#self.values + 1] = { id = id or 0, text = text }
  end
  -- Qt shows the first entry of a drop-down as selected until the user
  -- picks another one; get_value() returns that entry's id (-1 if empty).
  function api.get_value(self)
    if self.chosen then return self.chosen end
    return self.values[1] and self.values[1].id or -1
  end
  function api.clear(self) self.values = {}; self.selected = {}; self.chosen = nil end
  function api.get_selection(self)
    local out = {}
    for _, v in ipairs(self.values) do
      if self.selected[v.id] then out[v.id] = v.text end
    end
    return out
  end
  function api.animate() end
  function api.stop() end

  -- Test-only helpers (prefixed so they cannot be mistaken for VLC API)
  function w:_choose(id) self.chosen = id end          -- drop-down: user picks id
  function w:_choose_text(pattern)
    for _, v in ipairs(self.values) do
      if v.text:find(pattern) then self.chosen = v.id return v.id end
    end
    error("no drop-down entry matching '" .. pattern .. "'")
  end
  function w:_select(id) self.selected = { [id] = true } end -- list: user clicks row
  function w:_click() return self.func() end                -- button
  function w:_texts()
    local out = {}
    for i, v in ipairs(self.values) do out[i] = v.text end
    return out
  end

  return setmetatable(w, {
    __index = function(_, k)
      local allowed = WIDGET_METHODS[k]
      if not allowed then return nil end
      if not allowed[kind] then
        error("widget:" .. k .. "() does not apply to a " .. kind, 2)
      end
      return api[k]
    end,
  })
end

local function new_dialog(vlc, title)
  assert(type(title) == "string", "vlc.dialog() needs a title string")
  -- VLC shows a dialog by itself once the calling function returns.
  local d = { title = title, widgets = {}, updates = 0, deleted = false, visible = true }
  local api = {}
  for kind, names in pairs(WIDGET_ARGS) do
    api["add_" .. kind] = function(self, ...)
      assert(not self.deleted, "dialog used after delete()")
      local args = { ... }
      local w = new_widget(kind, self)
      for i, name in ipairs(names) do w[name] = args[i] end
      if w.text ~= nil and type(w.text) ~= "string" then
        error("add_" .. kind .. "(): text must be a string, got " .. type(w.text), 2)
      end
      w.text = w.text or ""
      if kind == "button" and type(w.func) ~= "function" then
        error("add_button(): callback must be a function, got " .. type(w.func), 2)
      end
      w.col, w.row = args[#names + 1], args[#names + 2]
      self.widgets[#self.widgets + 1] = w
      return w
    end
  end
  function api.show(self) self.visible = true end
  function api.hide(self) self.visible = false end
  function api.delete(self) self.deleted = true; self.visible = false end
  function api.set_title(self, t) self.title = t end
  function api.update(self) self.updates = self.updates + 1 end
  function api.del_widget(self, w)
    for i, x in ipairs(self.widgets) do
      if x == w then table.remove(self.widgets, i) return end
    end
  end

  -- Test-only helpers
  function d:_all(kind)
    local out = {}
    for _, w in ipairs(self.widgets) do
      if w.kind == kind then out[#out + 1] = w end
    end
    return out
  end
  function d:_at(col, row, kind)
    for _, w in ipairs(self.widgets) do
      if w.col == col and w.row == row and (not kind or w.kind == kind) then return w end
    end
  end
  function d:_button(pattern)
    for _, w in ipairs(self.widgets) do
      if w.kind == "button" and w.text:find(pattern) then return w end
    end
    error("no button matching '" .. pattern .. "' in dialog '" .. self.title .. "'", 2)
  end
  -- The input widget that sits to the right of a label, in the same row.
  function d:_field(label_pattern)
    for _, l in ipairs(self.widgets) do
      if l.kind == "label" and l.text:find(label_pattern) then
        local best
        for _, w in ipairs(self.widgets) do
          if w.row == l.row and w.col > l.col and w.kind ~= "label" and w.kind ~= "button"
             and (not best or w.col < best.col) then
            best = w
          end
        end
        if best then return best end
      end
    end
    error("no field next to a label matching '" .. label_pattern .. "'", 2)
  end

  return setmetatable(d, { __index = api })
end

-- Exposed for tests/vlc/vlsub_realvlc.lua, which runs the extension inside a
-- real VLC *interface* script: interfaces have real networking but no
-- vlc.dialog, so only the dialog comes from this mock there.
M.new_dialog = new_dialog

-- ------------------------------------------------------------------- net --

local POLL = { POLLIN = 1, POLLPRI = 2, POLLOUT = 4, POLLERR = 8,
               POLLHUP = 16, POLLNVAL = 32, POLLRDHUP = 8192 }

local function split_request(buf)
  local head_end = buf:find("\r\n\r\n", 1, true)
  if not head_end then return nil end
  local head, rest = buf:sub(1, head_end - 1), buf:sub(head_end + 4)
  local length = tonumber(head:lower():match("\r\ncontent%-length:%s*(%d+)")) or 0
  if #rest < length then return nil end
  return head, rest:sub(1, length), rest:sub(length + 1)
end

-- Parse the bytes an extension wrote to a socket into a request table and
-- note anything a real HTTP/1.1 server would choke on.
function M.parse_request(raw, host, port)
  local head, body, extra = split_request(raw)
  assert(head, "incomplete HTTP request")
  local req = { raw = raw, body = body, headers = {}, header_list = {}, problems = {},
                host = host, port = port, via = "tcp",
                scheme = port == 443 and "https" or "http" }
  local lines = {}
  for line in (head .. "\r\n"):gmatch("(.-)\r\n") do lines[#lines + 1] = line end
  local target
  req.method, target, req.version = lines[1]:match("^(%u+) (%S+) (HTTP/%d%.%d)$")
  if not req.method then
    req.problems[#req.problems + 1] = "malformed request line: " .. lines[1]
    req.method, target, req.version = "?", "/", "?"
  end
  if head:gsub("\r\n", ""):find("[\r\n]") then
    req.problems[#req.problems + 1] = "bare CR or LF in header block"
  end
  req.target = target
  req.path, req.raw_query = target:match("^([^?]*)%??(.*)$")
  req.query, req.query_order = {}, {}
  for pair in req.raw_query:gmatch("[^&]+") do
    local k, v = pair:match("^([^=]*)=?(.*)$")
    k, v = decode_uri((k:gsub("+", " "))), decode_uri((v:gsub("+", " ")))
    req.query[k] = v
    req.query_order[#req.query_order + 1] = k
  end
  for i = 2, #lines do
    local k, v = lines[i]:match("^([^:%s]+):%s*(.-)%s*$")
    if not k then
      req.problems[#req.problems + 1] = "malformed header line: " .. lines[i]
    else
      if req.headers[k:lower()] then
        req.problems[#req.problems + 1] = "duplicate header: " .. k
      end
      req.headers[k:lower()] = v
      req.header_list[#req.header_list + 1] = { k, v }
    end
  end
  if req.version == "HTTP/1.1" and not req.headers["host"] then
    req.problems[#req.problems + 1] = "HTTP/1.1 request without Host header"
  end
  if #body > 0 and not req.headers["content-length"] then
    req.problems[#req.problems + 1] = "body sent without Content-Length"
  end
  if extra ~= "" then
    req.problems[#req.problems + 1] = "bytes after the declared body: " .. #extra
  end
  return req
end

-- Decode a raw HTTP response (as stored in fixtures) the way VLC's HTTP
-- access does before handing the body to vlc.stream.
function M.decode_response(raw)
  local head, body = raw:match("^(.-)\r\n\r\n(.*)$")
  local status = tonumber(head:match("^HTTP/%d%.%d (%d+)"))
  local headers = {}
  for k, v in head:gmatch("\r\n([^:\r\n]+):%s*([^\r\n]*)") do headers[k:lower()] = v end
  if (headers["transfer-encoding"] or ""):lower() == "chunked" then
    local out, pos = {}, 1
    while true do
      local line_end = body:find("\r\n", pos, true)
      if not line_end then break end
      local size = tonumber(body:sub(pos, line_end - 1):match("^%x+"), 16)
      if not size or size == 0 then break end
      out[#out + 1] = body:sub(line_end + 2, line_end + 1 + size)
      pos = line_end + 2 + size + 2
    end
    body = table.concat(out)
  end
  return status, headers, body
end

-- ------------------------------------------------------------------- new --

-- opts.dir      directory used for VLC's user/config/data dirs
-- opts.server   network backend (fake_api server); nil = no network at all
-- opts.config   values for vlc.config.get
function M.new(opts)
  opts = opts or {}
  local dir = opts.dir or "/tmp"
  local server = opts.server
  local vlc = { _unknown = {}, _log = {}, _dialogs = {}, _item = nil,
                _vars = {}, _subtitles = {}, _sent = {}, _streams = {},
                _poll_timeouts = 0, _deactivated = false, _failed_connects = 0 }
  setmetatable(vlc, {
    __index = function(_, k)
      vlc._unknown[#vlc._unknown + 1] = "vlc." .. tostring(k)
      return nil
    end,
  })
  local function ns(name, t) rawset(vlc, name, namespace(vlc, "vlc." .. name, t)) end

  -- msg ------------------------------------------------------------------
  local function logger(level)
    return function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      vlc._log[#vlc._log + 1] = { level = level, msg = table.concat(parts, " ") }
    end
  end
  ns("msg", { dbg = logger("dbg"), info = logger("info"),
              warn = logger("warn"), err = logger("err") })
  function vlc._messages(level)
    local out = {}
    for _, l in ipairs(vlc._log) do
      if not level or l.level == level then out[#out + 1] = l.msg end
    end
    return out
  end

  -- config ---------------------------------------------------------------
  local cfg = { ["sub-autodetect-path"] = "./Subtitles, ./subtitles, ./Subs, ./subs",
                intf = "" }
  for k, v in pairs(opts.config or {}) do cfg[k] = v end
  vlc._config = cfg
  ns("config", {
    get = function(name) return cfg[name] end,
    set = function(name, value) cfg[name] = value end,
    datadir = function() return opts.datadir or dir end,
    userdatadir = function() return opts.userdatadir or dir end,
    homedir = function() return opts.homedir or dir end,
    configdir = function() return opts.configdir or dir end,
    cachedir = function() return opts.cachedir or dir end,
    datadir_list = function(name) return { dir .. "/" .. name } end,
  })

  -- strings --------------------------------------------------------------
  local function each(fn) return function(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = fn((select(i, ...))) end
    return (table.unpack or unpack)(out)
  end end
  ns("strings", {
    decode_uri = each(decode_uri),
    encode_uri_component = each(encode_uri_component),
    make_uri = function(path, scheme)
      return (scheme or "file") .. "://" .. path:gsub("[^%w%-%._~/]", function(c)
        return string.format("%%%02X", string.byte(c)) end)
    end,
    make_path = function(uri) return decode_uri((uri:gsub("^file://", ""))) end,
    url_parse = url_parse,
    resolve_xml_special_chars = each(function(s)
      return (s:gsub("&%a+;", function(e) return xml_entities[e] or e end))
    end),
    convert_xml_special_chars = each(function(s)
      return (s:gsub("[<>\"'&]", { ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;",
                                   ["'"] = "&#39;", ["&"] = "&amp;" }))
    end),
    from_charset = function(_, s) return s end,
  })

  -- dialog ---------------------------------------------------------------
  rawset(vlc, "dialog", function(title)
    local d = new_dialog(vlc, title)
    vlc._dialogs[#vlc._dialogs + 1] = d
    return d
  end)
  -- Newest dialog that is still on screen (the extension hides old windows
  -- instead of deleting them, as the original VLSub does)
  function vlc._dialog()
    for i = #vlc._dialogs, 1, -1 do
      if vlc._dialogs[i].visible then return vlc._dialogs[i] end
    end
  end
  function vlc._visible_dialogs()
    local n = 0
    for _, d in ipairs(vlc._dialogs) do if d.visible then n = n + 1 end end
    return n
  end

  -- input / object / var -------------------------------------------------
  ns("input", {
    item = function() return rawget(vlc, "_item") end,
    is_playing = function() return rawget(vlc, "_item") ~= nil end,
    add_subtitle = function(path, autoselect)
      if not rawget(vlc, "_item") then error("can't add subtitle: no current input") end
      if type(path) ~= "string" then error("vlc.input.add_subtitle() usage: (path)") end
      vlc._subtitles[#vlc._subtitles + 1] = { path = path, autoselect = autoselect and true or false }
      return path
    end,
    add_subtitle_mrl = function(mrl, autoselect)
      if not rawget(vlc, "_item") then error("can't add subtitle: no current input") end
      vlc._subtitles[#vlc._subtitles + 1] = { mrl = mrl, autoselect = autoselect and true or false }
      return mrl
    end,
  })
  local input_object = {}
  ns("object", {
    input = function() return rawget(vlc, "_item") and input_object or nil end,
    playlist = function() return {} end,
    libvlc = function() return {} end,
    vout = function() return nil end,
    aout = function() return nil end,
  })
  ns("var", {
    get = function(obj, name)
      if obj == nil then error("bad argument #1 to 'get' (vlc object expected)") end
      return vlc._vars[name]
    end,
    set = function(obj, name, value)
      if obj == nil then error("bad argument #1 to 'set' (vlc object expected)") end
      vlc._vars[name] = value
    end,
    inherit = function(_, name) return vlc._vars[name] end,
  })

  -- net ------------------------------------------------------------------
  local conns, next_fd = {}, 3
  local net = {
    url_parse = url_parse, -- deprecated alias of strings.url_parse
    connect_tcp = function(host, port)
      assert(type(host) == "string", "connect_tcp: host must be a string")
      assert(type(port) == "number", "connect_tcp: port must be a number")
      -- Verified against VLC 3.0.16: a failed connect still returns a normal
      -- looking positive descriptor. Only send() == -1 / recv() == nil reveal
      -- that it is dead, and poll() on it never returns.
      local fd = next_fd
      next_fd = next_fd + 1
      if not server or not server:resolve(host, port) then
        conns[fd] = { host = host, port = port, dead = true, open = false }
        vlc._failed_connects = vlc._failed_connects + 1
        return fd
      end
      conns[fd] = { host = host, port = port, inbuf = "", out = "", eof = false, open = true }
      return fd
    end,
    send = function(fd, data, len)
      local c = conns[fd]
      if not c or not c.open then return -1 end
      data = len and data:sub(1, len) or data
      vlc._sent[#vlc._sent + 1] = { fd = fd, host = c.host, port = c.port, data = data }
      c.inbuf = c.inbuf .. data
      if c.port == 443 then
        -- A TLS server answers plaintext HTTP with an alert and closes.
        c.eof = true
        return #data
      end
      if split_request(c.inbuf) then
        local raw, keep_open = server:handle(M.parse_request(c.inbuf, c.host, c.port))
        c.inbuf = ""
        c.out = c.out .. (raw or "")
        c.eof = not keep_open
      end
      return #data
    end,
    recv = function(fd, len)
      local c = conns[fd]
      if not c or not c.open then return nil end
      len = len or 1
      if #c.out == 0 then
        if c.eof then return nil end
        error("vlc.net.recv() would block forever: nothing to read and the peer keeps the connection open", 2)
      end
      local n = math.min(len, server.segment or 1460, #c.out)
      local chunk = c.out:sub(1, n)
      c.out = c.out:sub(n + 1)
      return chunk
    end,
    poll = function(fds, timeout)
      assert(type(fds) == "table", "bad argument #1 to 'poll' (table expected)")
      if timeout ~= nil then vlc._poll_timeouts = vlc._poll_timeouts + 1 end
      local ready = 0
      for fd, events in pairs(fds) do
        local c = conns[fd]
        local revents = 0
        if c and c.open then
          if (#c.out > 0 or c.eof) and events % 2 == 1 then revents = POLL.POLLIN end
          if #c.out == 0 and c.eof then revents = revents + POLL.POLLHUP end
          if math.floor(events / 4) % 2 == 1 then revents = revents + POLL.POLLOUT end
        end
        fds[fd] = revents
        if revents ~= 0 then ready = ready + 1 end
      end
      if ready == 0 then
        error("vlc.net.poll() would block forever: no descriptor can become ready " ..
              "(VLC ignores the timeout argument)", 2)
      end
      return ready
    end,
    close = function(fd)
      if conns[fd] then conns[fd].open = false end
    end,
    stat = function(path)
      local f = io.open(path, "rb")
      if not f then return nil end
      local is_dir = f:read(0) == nil and select(3, f:read(1)) == 21
      local size = (not is_dir) and f:seek("end") or 0
      f:close()
      return { type = is_dir and "dir" or "file", mode = 420, uid = 0, gid = 0,
               size = size, access_time = os.time(),
               modification_time = (opts.mtime and opts.mtime(path)) or os.time(),
               creation_time = os.time() }
    end,
    -- Real opendir returns the list of entry names directly (no handle)
    opendir = function(path)
      local p = real_popen('ls -a "' .. path .. '" 2>/dev/null')
      local out = {}
      for line in p:lines() do out[#out + 1] = line end
      p:close()
      if #out == 0 then error("cannot open directory `" .. path .. "'") end
      return out
    end,
    listen_tcp = function() error("vlc.net.listen_tcp is not mocked") end,
  }
  for k, v in pairs(POLL) do net[k] = v end
  ns("net", net)
  function vlc._open_sockets()
    local n = 0
    for _, c in pairs(conns) do if c.open then n = n + 1 end end
    return n
  end

  -- stream ---------------------------------------------------------------
  rawset(vlc, "stream", function(url)
    assert(type(url) == "string", "bad argument #1 to 'stream' (string expected)")
    vlc._streams[#vlc._streams + 1] = url
    local data
    local scheme = url:match("^(%a[%w+.-]*)://")
    if scheme == "file" then
      local f = io.open(decode_uri((url:gsub("^file://", ""))), "rb")
      if not f then return nil, "Error when opening stream" end
      data = f:read("*a")
      f:close()
      if not data then return nil, "Error when opening stream" end
    elseif scheme == "http" or scheme == "https" then
      if not server then return nil, "Error when opening stream" end
      local hops = 0
      while true do
        local u = url_parse(url)
        local port = (u.port ~= 0 and u.port) or (u.protocol == "https" and 443 or 80)
        if not server:resolve(u.host, port) then return nil, "Error when opening stream" end
        local target = (u.path or "/") .. (u.option and ("?" .. u.option) or "")
        -- This is ALL vlc.stream can send: a GET with VLC's own headers.
        local raw = "GET " .. target .. " HTTP/1.1\r\nHost: " .. u.host ..
                    "\r\nAccept: */*\r\nUser-Agent: VLC/3.0.21 LibVLC/3.0.21\r\n\r\n"
        local req = M.parse_request(raw, u.host, port)
        req.via, req.scheme = "stream", u.protocol
        local status, headers, body = M.decode_response((server:handle(req)))
        if status >= 300 and status < 400 and headers["location"] and hops < 5 then
          hops = hops + 1
          local loc = headers["location"]
          if loc:sub(1, 1) == "/" then
            loc = u.protocol .. "://" .. u.host .. loc
          end
          url = loc
        elseif status >= 200 and status < 300 then
          data = body
          break
        else
          return nil, "Error when opening stream"
        end
      end
    else
      return nil, "Error when opening stream"
    end
    local pos = 1
    local s = {}
    function s:read(n)
      assert(type(n) == "number", "bad argument #1 to 'read' (number expected)")
      if pos > #data then return nil end
      local chunk = data:sub(pos, pos + n - 1)
      pos = pos + #chunk
      return chunk
    end
    function s:readline()
      if pos > #data then return nil end
      local e = data:find("\n", pos, true) or (#data + 1)
      local line = data:sub(pos, e - 1):gsub("\r$", "")
      pos = e + 1
      return line
    end
    function s:getsize() return #data end
    function s:seek(offset) pos = offset + 1 return true end
    function s:addfilter() end
    return s
  end)

  -- io / errno / extension-only functions ---------------------------------
  ns("io", {
    mkdir = function(path)
      local ok = os.execute('mkdir "' .. path .. '" 2>/dev/null')
      if ok == true or ok == 0 then return 0 end
      return -1, 17
    end,
    open = io.open,
    unlink = function(path) if os.remove(path) then return 0 end return -1, 2 end,
    readdir = function(path) return net.opendir(path) end,
  })
  ns("errno", { ENOENT = 2, EEXIST = 17, EACCES = 13, EINVAL = 22 })
  rawset(vlc, "deactivate", function() vlc._deactivated = true end)
  rawset(vlc, "keep_alive", function() end)

  -- vlc.misc is deliberately absent, see the top of this file.
  return vlc
end

-- Fake media item, as returned by vlc.input.item()
function M.item(uri, metas)
  local it = {}
  function it:uri() return uri end
  function it:name() return (uri:match("([^/]+)$")) end
  function it:metas() return metas or {} end
  function it:duration() return 600 end
  function it:is_preparsed() return true end
  function it:info() return {} end
  function it:stats() return {} end
  return it
end

return M
