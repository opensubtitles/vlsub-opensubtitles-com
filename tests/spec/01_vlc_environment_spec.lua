-- What the extension may and may not rely on inside VLC.
--
-- VLC runs extensions in a restricted Lua (5.1 or 5.2 depending on the build)
-- with a small `vlc` API. Everything here is derived from the VLC 3.0.x
-- sources: modules/lua/extension.c (which libraries an extension gets) and
-- modules/lua/libs/*.c (what each function really does).
local H = ...
local describe, it, known_bug, eq, ok = H.describe, H.it, H.known_bug, H.eq, H.ok

-- Every name an extension can use in VLC 3.0.x.
local VLC_API = {
  vlc = { "config", "dialog", "input", "msg", "net", "object", "osd", "playlist",
          "sd", "stream", "memory_stream", "directory_stream", "strings", "var",
          "video", "vlm", "volume", "xml", "io", "errno", "deactivate", "keep_alive",
          "win" },
  config = { "get", "set", "datadir", "userdatadir", "homedir", "configdir",
             "cachedir", "datadir_list" },
  input = { "is_playing", "item", "add_subtitle", "add_subtitle_mrl" },
  msg = { "dbg", "warn", "err", "info" },
  net = { "listen_tcp", "connect_tcp", "close", "send", "recv", "poll", "read",
          "write", "url_parse", "stat", "opendir", "POLLIN", "POLLPRI", "POLLOUT",
          "POLLRDHUP", "POLLERR", "POLLHUP", "POLLNVAL" },
  object = { "input", "playlist", "libvlc", "vout", "aout", "find" },
  strings = { "decode_uri", "encode_uri_component", "make_uri", "make_path",
              "url_parse", "resolve_xml_special_chars", "convert_xml_special_chars",
              "from_charset" },
  var = { "inherit", "get", "get_list", "set", "create", "trigger_callback",
          "libvlc_command", "inc_integer", "dec_integer", "count_choices",
          "toggle_bool", "add_callback", "del_callback" },
  io = { "mkdir", "open", "readdir", "unlink" },
}

-- Names the source mentions that do NOT exist in VLC 3.0 extensions. Each one
-- must be reached only behind a nil check; the tests below prove the guarded
-- path works. Adding a name here needs such a test.
local KNOWN_ABSENT = {
  ["vlc.net.mkdir"] = "does not exist (vlc.io.mkdir does, since 3.0.2)",
  ["vlc.item"] = "only set for playlist parser scripts",
}

local function set(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

describe("VLC environment", function()
  it("source only references vlc.* names that exist in VLC 3.0 (or are known-absent and guarded)", function()
    local src = H.read_file(H.SCRIPT)
    local unexpected = {}
    for a, b in src:gmatch("vlc%.([%a_]+)%.?([%a_]*)") do
      local full = "vlc." .. a .. (b ~= "" and ("." .. b) or "")
      local exists = set(VLC_API.vlc)[a] and (b == "" or not VLC_API[a] or set(VLC_API[a])[b])
      if not exists and not KNOWN_ABSENT[full] and not KNOWN_ABSENT["vlc." .. a] then
        unexpected[full] = true
      elseif not exists and b ~= "" and not KNOWN_ABSENT[full] then
        unexpected[full] = true
      end
    end
    local names = {}
    for k in pairs(unexpected) do names[#names + 1] = k end
    table.sort(names)
    eq(names, {}, "vlc.* names that do not exist in VLC 3.0 extensions")
  end)

  it("dialogs and widgets are only used through methods VLC provides", function()
    -- modules/lua/libs/dialog.c; note there is set_title() but no get_title()
    local allowed = set({ "show", "hide", "delete", "set_title", "update", "del_widget",
      "add_button", "add_label", "add_html", "add_text_input", "add_password",
      "add_check_box", "add_dropdown", "add_list", "add_image", "add_spin_icon",
      "set_text", "get_text", "set_checked", "get_checked", "add_value", "get_value",
      "clear", "get_selection", "animate", "stop" })
    local src = H.read_file(H.SCRIPT):gsub("%-%-[^\n]*", "")
    local bad = {}
    for object, method in src:gmatch("([%a_][%w_]*dlg):([%a_]+)%(") do
      if not allowed[method] then bad[object .. ":" .. method] = true end
    end
    for method in src:gmatch("input_table%[[^%]]+%]:([%a_]+)%(") do
      if not allowed[method] then bad["widget:" .. method] = true end
    end
    local names = {}
    for k in pairs(bad) do names[#names + 1] = k end
    table.sort(names)
    eq(names, {}, "methods that do not exist on VLC dialogs/widgets")
  end)

  it("a full session never calls anything missing (search + download, no Lua errors)", function()
    local dir = H.tmpdir()
    local env = H.launch({ media = "file://" .. H.video(dir, "Big.Buck.Bunny.2008.mkv", 200000) })
    env.ui():_button("Search$"):_click()
    env.results():_select(env.results().values[1].id)
    env.ui():_button("Download"):_click()
    local touched = {}
    for _, name in ipairs(env.vlc._unknown) do touched[name] = true end
    for name in pairs(touched) do
      ok(KNOWN_ABSENT[name], "extension read " .. name .. " which VLC does not provide")
    end
    eq(env.errors(), {}, "errors logged")
  end)

  it("works without vlc.misc (no mdate/mwait in extensions)", function()
    local env = H.launch()
    eq(env.vlc.misc, nil, "mock mirrors VLC: vlc.misc is nil")
    ok(not H.read_file(H.SCRIPT):find("vlc%.misc"), "the extension does not reference vlc.misc")
  end)

  it("does not use Lua features newer than 5.1/5.2", function()
    local src = H.read_file(H.SCRIPT)
    local code = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
    for _, pattern in ipairs({ "[^%w_.]utf8%.", "string%.pack", "string%.unpack",
                               "table%.move", "math%.tointeger", "[^%w_]goto%s+[%a_]",
                               "::[%a_][%w_]*::", "<const>", "<close>" }) do
      ok(not code:find(pattern), "uses a Lua >= 5.2/5.3 feature: " .. pattern)
    end
  end)

  it("requests that need headers or a body never use https (vlc.stream cannot send them)", function()
    local src = H.read_file(H.SCRIPT)
    for url in src:gmatch('"(https://api%.opensubtitles%.com[^"]*)"') do
      error("API URL uses https, which goes through vlc.stream (GET only, no Api-Key): " .. url)
    end
    for _, name in ipairs({ "api_languages_url", "login_api_url", "guessit_api_url" }) do
      ok(src:find(name .. ' = "http://api%.opensubtitles%.com/'), name .. " is plain http")
    end
  end)
end)

describe("VLC mock fidelity (documents real VLC behaviour)", function()
  it("a failed connect_tcp still returns a positive descriptor; send says -1, recv nil", function()
    local env = H.launch({ activate = false, offline = true })
    local fd = env.vlc.net.connect_tcp("api.opensubtitles.com", 80)
    ok(type(fd) == "number" and fd > 0, "descriptor looks valid: " .. tostring(fd))
    eq(env.vlc.net.send(fd, "GET / HTTP/1.1\r\n\r\n"), -1)
    eq(env.vlc.net.recv(fd, 100), nil)
    H.raises(function() env.vlc.net.poll({ [fd] = env.vlc.net.POLLIN }, 500) end, "block forever")
  end)

  it("recv returns nil at end of stream and at most the requested length", function()
    local env = H.launch({ activate = false })
    local fd = env.vlc.net.connect_tcp("www.google.com", 80)
    env.vlc.net.send(fd, "GET / HTTP/1.1\r\nHost: www.google.com\r\n\r\n")
    eq(#env.vlc.net.recv(fd, 5), 5)
    eq(#env.vlc.net.recv(fd), 1, "default length is 1 byte")
    while env.vlc.net.recv(fd, 4096) do end
    eq(env.vlc.net.recv(fd, 4096), nil)
  end)

  it("poll blocks forever when nothing can arrive, whatever timeout is passed", function()
    local env = H.launch({ activate = false })
    local fd = env.vlc.net.connect_tcp("www.google.com", 80)
    H.raises(function() env.vlc.net.poll({ [fd] = env.vlc.net.POLLIN }, 500) end, "block forever")
    H.raises(function() env.vlc.net.poll({ [-1] = env.vlc.net.POLLIN }, 500) end, "block forever")
  end)

  it("plain TCP to port 443 gets no HTTP answer", function()
    local env = H.launch({ activate = false })
    local fd = env.vlc.net.connect_tcp("api.opensubtitles.com", 443)
    env.vlc.net.send(fd, "GET / HTTP/1.1\r\nHost: api.opensubtitles.com\r\n\r\n")
    eq(env.vlc.net.recv(fd, 4096), nil)
  end)

  it("vlc.stream can only GET, sends no custom headers, and returns nil on HTTP errors", function()
    local env = H.launch({ activate = false })
    local s = env.vlc.stream("https://www.google.com/")
    eq(s:read(4096), "<html>ok</html>")
    eq(s:read(4096), nil)
    local req = env.server:last("GET www.google.com/")
    eq(req.headers["api-key"], nil)
    eq(req.via, "stream")
    -- the API needs an Api-Key header, so it is unusable through vlc.stream
    eq(env.vlc.stream("https://api.opensubtitles.com/api/v1/infos/languages"), nil)
  end)
end)
