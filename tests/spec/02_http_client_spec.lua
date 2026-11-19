-- The hand-written HTTP/1.1 client (VLCHttpClient, reachable as Curl.new()).
-- It is the only way an extension can send headers or a body, so the exact
-- bytes on the wire matter.
local H = ...
local describe, it, known_bug, eq, ok, has = H.describe, H.it, H.known_bug, H.eq, H.ok, H.has
local api = H.fake_api
local json = H.json
local Curl

local function client_env(o)
  o = o or {}
  o.activate = true
  local env = H.launch(o)
  env.server:reset()
  Curl = H.find_local("Curl") -- file-local in the extension
  return env
end

describe("HTTP client: request bytes", function()
  it("GET: request line, mandatory headers, custom headers, nothing else", function()
    local env = client_env()
    env.server:on("GET example.test/a/b", function() return api.response(200, { ok = true }) end)
    local c = Curl.new()
    c:add_header("Api-Key", "KEY123")
    c:add_header("Authorization", "Bearer TOKEN")
    local res = c:get("http://example.test/a/b?x=1&y=two")

    local req = env.server:last()
    eq(req.problems, {}, "protocol problems")
    eq(req.method, "GET")
    eq(req.target, "/a/b?x=1&y=two")
    eq(req.version, "HTTP/1.1")
    eq(req.headers["host"], "example.test")
    eq(req.headers["connection"], "close")
    eq(req.headers["accept"], "*/*")
    eq(req.headers["api-key"], "KEY123")
    eq(req.headers["authorization"], "Bearer TOKEN")
    eq(req.headers["content-length"], nil, "no Content-Length on GET")
    eq(req.body, "")
    eq(#req.header_list, 6, "header count")
    ok(req.raw:sub(-4) == "\r\n\r\n", "request ends with an empty line")
    eq(res.status, 200)
    eq(json.decode(res.body), { ok = true })
  end)

  it("User-Agent is 'VLSub OpenSubtitles.com v<version>' (the API only serves plain HTTP to it)", function()
    local env = client_env()
    env.server:on("GET example.test/", function() return api.response(200, {}) end)
    Curl.new():get("http://example.test/")
    local version = H.read_file(H.SCRIPT):match('local app_version = "([^"]+)"')
    eq(env.server:last().headers["user-agent"], "VLSub OpenSubtitles.com v" .. version)
  end)

  it("a caller cannot override User-Agent, Host or Connection", function()
    local env = client_env()
    env.server:on("GET example.test/", function() return api.response(200, {}) end)
    local c = Curl.new()
    c:add_header("User-Agent", "Evil/1.0")
    c:add_header("Host", "other.test")
    c:add_header("Connection", "keep-alive")
    c:get("http://example.test/")
    local req = env.server:last()
    eq(req.problems, {}, "no duplicate headers")
    has(req.headers["user-agent"], "VLSub OpenSubtitles.com")
    eq(req.headers["host"], "example.test")
    eq(req.headers["connection"], "close")
  end)

  it("POST: body bytes are exact and Content-Length matches (UTF-8, quotes, braces)", function()
    local env = client_env()
    env.server:on("POST example.test/login", function() return api.response(200, {}) end)
    local body = json.encode({ username = "j\195\182rg", password = 'p"a{s}s\\w\195\182rd' })
    local c = Curl.new()
    c:add_header("Content-Type", "application/json")
    c:post("http://example.test/login", body)
    local req = env.server:last()
    eq(req.problems, {}, "protocol problems")
    eq(req.method, "POST")
    eq(req.body, body)
    eq(req.headers["content-length"], tostring(#body))
    eq(req.headers["content-type"], "application/json")
  end)

  it("DELETE and PUT are sent with the right method", function()
    local env = client_env()
    env.server:on("DELETE example.test/x", function() return api.response(200, {}) end)
    env.server:on("PUT example.test/x", function() return api.response(200, {}) end)
    Curl.new():delete("http://example.test/x")
    eq(env.server:last().method, "DELETE")
    Curl.new():put("http://example.test/x", "abc")
    eq(env.server:last().method, "PUT")
    eq(env.server:last().body, "abc")
  end)

  it("one connection per request and the socket is closed afterwards", function()
    local env = client_env()
    env.server:on("GET example.test/", function() return api.response(200, {}) end)
    Curl.new():get("http://example.test/")
    eq(#env.server.requests, 1)
    eq(env.vlc._open_sockets(), 0, "sockets left open")
  end)
end)

describe("HTTP client: responses", function()
  local function serve(env, raw)
    env.server:on("GET example.test/r", function() return raw end)
  end

  it("Content-Length body", function()
    local env = client_env()
    serve(env, api.response(200, { a = 1, list = { 1, 2, 3 } }))
    local res = Curl.new():get("http://example.test/r")
    eq(res.status, 200)
    eq(json.decode(res.body), { a = 1, list = { 1, 2, 3 } })
    eq(res.headers["content-type"], "application/json; charset=utf-8", "header names are lower-cased")
  end)

  it("real recorded chunked response (60 KB search) decodes to the same JSON", function()
    local env = client_env()
    serve(env, api.fixture("search_name_en"))
    local res = Curl.new():get("http://example.test/r")
    eq(res.status, 200)
    local got = json.decode(res.body)
    eq(#got.data, 50)
    eq(got, api.fixture_json("search_name_en"))
  end)

  for _, segment in ipairs({ 8192, 1460, 536, 97 }) do
    it("same response arriving " .. segment .. " bytes per recv()", function()
      local env = client_env()
      env.server.segment = segment
      serve(env, api.fixture("search_hash"))
      local res = Curl.new():get("http://example.test/r")
      eq(json.decode(res.body), api.fixture_json("search_hash"))
    end)
  end

  it("status codes are passed through with their body", function()
    local env = client_env()
    for _, status in ipairs({ 401, 403, 404, 406, 429, 500, 503 }) do
      serve(env, api.response(status, { message = "nope " .. status }))
      local res = Curl.new():get("http://example.test/r")
      eq(res.status, status)
      eq(json.decode(res.body).message, "nope " .. status)
    end
  end)

  it("real recorded error responses: 401 login (chunked), 429 (Content-Length), 301", function()
    local env = client_env()
    serve(env, api.fixture("login_bad"))
    local res = Curl.new():get("http://example.test/r")
    eq(res.status, 401)
    has(json.decode(res.body).message, "invalid username/password")

    serve(env, api.fixture("rate_limited"))
    res = Curl.new():get("http://example.test/r")
    eq(res.status, 429)
    eq(json.decode(res.body).message, "API rate limit exceeded")

    serve(env, api.fixture("search_unsorted"))
    res = Curl.new():get("http://example.test/r")
    eq(res.status, 301)
    eq(res.headers["location"], "/api/v1/subtitles?languages=en&query=big+buck+bunny")
  end)

  it("raw mode returns the body byte-for-byte (subtitle text with braces and CRLF)", function()
    local env = client_env()
    local text = "1\r\n00:00:01,000 --> 00:00:02,000\r\n{\\an8}Top {x} line\r\n\r\n"
    serve(env, api.response(200, text, { ["Content-Type"] = "text/plain" }))
    local c = Curl.new()
    c:set_raw(true)
    eq(c:get("http://example.test/r").body, text)
    serve(env, api.response(200, text, { ["Content-Type"] = "text/plain" }, { chunked = 7 }))
    c = Curl.new()
    c:set_raw(true)
    eq(c:get("http://example.test/r").body, text, "chunked")
  end)

  it("JSON with a '}' inside a string survives (Content-Length response)", function()
      local env = client_env()
      local payload = { data = { { release = "Smile :-} 2008", n = 1 }, { release = "second", n = 2 } } }
      serve(env, api.response(200, payload))
      local res = Curl.new():get("http://example.test/r")
      eq(json.decode(res.body), payload)
    end)

  it("a JSON array body is returned intact (Content-Length response)", function()
      local env = client_env()
      serve(env, api.response(200, '[{"a":1},{"a":2}]'))
      eq(json.decode(Curl.new():get("http://example.test/r").body), { { a = 1 }, { a = 2 } })
    end)

  it("chunked body with more than 100 chunks is decoded completely", function()
      local env = client_env()
      local text = string.rep("0123456789abcdef", 200) -- 3200 bytes
      serve(env, api.response(200, text, { ["Content-Type"] = "text/plain" }, { chunked = 16 }))
      local c = Curl.new()
      c:set_raw(true)
      eq(#c:get("http://example.test/r").body, #text)
    end)
end)

describe("HTTP client: failures must never hang VLC", function()
  it("connection failure returns promptly without polling a dead socket", function()
      local env = client_env({ offline = true })
      local res = Curl.new():get("http://example.test/")
      eq(res, nil)
    end)

  it("a server that never answers does not block forever", function()
      local env = client_env()
      env.server:on("GET example.test/slow", function() return "", true end) -- no bytes, stays open
      local res = Curl.new():get("http://example.test/slow")
      eq(res, nil)
    end)


  it("empty reply (peer closes immediately) is retried, then reported as nil", function()
    local env = client_env()
    env.server:on("GET example.test/empty", function() return "" end)
    local c = Curl.new()
    c:set_retries(2)
    eq(c:get("http://example.test/empty"), nil)
    eq(#env.server.requests, 3, "attempts = 1 + retries")
  end)

  it("garbage instead of HTTP is reported as nil, not a crash", function()
    local env = client_env()
    env.server:on("GET example.test/junk", function() return "\0\1\2 not http at all" end)
    local c = Curl.new()
    c:set_retries(0)
    eq(c:get("http://example.test/junk"), nil)
  end)
end)

describe("HTTP client: https goes through vlc.stream", function()
  it("GET over https returns the body with status 200", function()
    local env = client_env()
    local c = Curl.new()
    c:set_raw(true)
    local res = c:get("https://www.opensubtitles.com/download/ABC/subfile/x.srt")
    eq(res.status, 200)
    eq(res.body, api.SUBTITLE_TEXT)
    eq(env.server:last().via, "stream")
  end)

  it("headers cannot be sent: they are appended to the URL as x-* parameters", function()
    local env = client_env()
    env.server:on("GET secure.test/q", function() return api.response(200, { ok = true }) end)
    local c = Curl.new()
    c:add_header("Api-Key", "KEY123")
    c:get("https://secure.test/q?b=2&a=1")
    local req = env.server:last()
    eq(req.headers["api-key"], nil, "no real header")
    eq(req.query["x-api-key"], "KEY123")
    eq(req.query_order, { "a", "b", "x-api-key" }, "parameters sorted")
  end)

  it("HTTP error over https yields nil (VLC gives no status code)", function()
    local env = client_env()
    env.server:on("GET secure.test/missing", function() return api.response(404, {}) end)
    eq(Curl.new():get("https://secure.test/missing"), nil)
  end)

  it("unreachable https host yields nil", function()
    local env = client_env()
    env.server.down["secure.test"] = true
    eq(Curl.new():get("https://secure.test/"), nil)
  end)
end)


-- "My internet is down, I save the settings and VLC is not responding."
-- Nothing in VLC's Lua can cut a connection attempt short: on a dead network
-- each one blocks the window until the system gives up. So the extension
-- must make as few as possible. server.blocks_for = what one attempt costs.
H.describe("network down: the window is blocked once, not again and again", function()
  local it, eq, ok, has = H.it, H.eq, H.ok, H.has
  local function attempts(env) return env.vlc._failed_connects + (env.vlc._failed_streams or 0) end

  local function offline(o)
    local env = H.launch(o)
    env.server.offline = true
    env.server.blocks_for = 30
    env.vlc._failed_connects = 0
    return env, H.waited()
  end

  it("Save: one connection attempt, then a clear message; the settings are saved", function()
    local env, before = offline()
    trigger_menu(2)
    env.ui():_at(1, 13, "button"):_click()
    eq(attempts(env), 1, "connection attempts")
    eq(H.waited() - before, 30, "seconds the window was blocked")
    has(env.message(), "no internet connection")
    has(env.message(), "settings were saved")
    ok(env.saved_config(), "config written")
  end)

  it("Save with a new interface language: the translation and the login are not both waited for", function()
    local env, before = offline()
    trigger_menu(2)
    -- the list of languages was fetched while online
    local d = env.ui()
    openSub.option.interfaceLanguage = "en"
    d:_at(2, 9, "dropdown"):_choose_text("^Automatic")
    d:_at(1, 13, "button"):_click()
    eq(attempts(env), 1, "connection attempts")
    eq(H.waited() - before, 30)
  end)

  it("Search: hash, name fallback and GuessIt do not each wait for the dead network", function()
    local dir = H.tmpdir()
    local env, before = offline({ media = "file://" .. dir .. "/Big.Buck.Bunny.2008.mkv" })
    local d = env.ui()
    d:_at(2, 1, "text_input"):set_text("big buck bunny")
    d:_button("Search$"):_click()
    eq(attempts(env), 1, "connection attempts")
    eq(H.waited() - before, 30)
    ok(env.message() ~= "", "a message is shown")
  end)

  it("ten seconds later the next click tries again, and works when the network is back", function()
    local env = offline()
    local d = env.ui()
    d:_at(2, 1, "text_input"):set_text("big buck bunny")
    d:_button("Search$"):_click()
    eq(attempts(env), 1)
    env.server.offline = false
    H.wait(11)
    env.ui():_button("Search$"):_click()
    ok(#env.results().values > 1, "results listed")
  end)

  it("one unreachable request is not retried", function()
    local env = offline()
    local client = H.find_local("Curl").new()
    client:set_retries(3)
    eq(client:get("http://api.opensubtitles.com/api/v1/infos/formats"), nil)
    eq(attempts(env), 1)
  end)
end)
