-- In-process stand-in for everything the extension talks to over the network.
--
-- Requests arrive already parsed by mock_vlc (which received the exact bytes
-- the extension wrote to its socket), responses go back as raw HTTP bytes.
-- Where possible the bytes are recordings of the real api.opensubtitles.com
-- (tests/fixtures/raw/*.http, captured with `curl -i --raw`), so chunked
-- transfer encoding, header casing and payload shapes are the real thing.
--
-- The OpenSubtitles REST API rules the real server enforces are enforced
-- here too:
--   * Api-Key header required                        -> 403
--   * plain HTTP is only served to User-Agent
--     "VLSub OpenSubtitles.com..."                   -> 301 to https otherwise
--   * query parameters sorted, lower-case, no leading
--     zeros in ids                                   -> 301 to canonical URL
--   * POST /download needs a valid Bearer token      -> 401
--   * 5 requests / second                            -> 429 (opt-in)

local mock = require("mock_vlc")
local json = require("dkjson")

local M = {}

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local FIXTURES = here .. "/../fixtures/raw/"

function M.fixture(name)
  local f = assert(io.open(FIXTURES .. name .. ".http", "rb"), "missing fixture " .. name)
  local raw = f:read("*a")
  f:close()
  return raw
end

-- Body of a recorded response, decoded (for building expectations in tests)
function M.fixture_json(name)
  local _, _, body = mock.decode_response(M.fixture(name))
  return (json.decode(body))
end

local REASON = { [200] = "OK", [301] = "Moved Permanently", [302] = "Found",
                 [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden",
                 [404] = "Not Found", [406] = "Not Acceptable",
                 [429] = "Too Many Requests", [500] = "Internal Server Error",
                 [502] = "Bad Gateway", [503] = "Service Unavailable" }

-- Build raw response bytes. opts.chunked = size splits the body into chunks.
function M.response(status, body, headers, opts)
  opts = opts or {}
  body = body or ""
  if type(body) == "table" then body = json.encode(body) end
  local lines = { "HTTP/1.1 " .. status .. " " .. (REASON[status] or "Status") }
  local has_type = false
  for k, v in pairs(headers or {}) do
    lines[#lines + 1] = k .. ": " .. v
    if k:lower() == "content-type" then has_type = true end
  end
  if not has_type then lines[#lines + 1] = "Content-Type: application/json; charset=utf-8" end
  lines[#lines + 1] = "Connection: close"
  if opts.chunked then
    lines[#lines + 1] = "Transfer-Encoding: chunked"
    local parts = {}
    for i = 1, #body, opts.chunked do
      local piece = body:sub(i, i + opts.chunked - 1)
      parts[#parts + 1] = string.format("%x\r\n%s\r\n", #piece, piece)
    end
    parts[#parts + 1] = "0\r\n\r\n"
    return table.concat(lines, "\r\n") .. "\r\n\r\n" .. table.concat(parts)
  end
  lines[#lines + 1] = "Content-Length: " .. #body
  return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
end

local SUBTITLE_TEXT = "1\r\n00:00:01,000 --> 00:00:04,000\r\nHello from the fake server\r\n\r\n" ..
                      "2\r\n00:00:05,000 --> 00:00:08,000\r\n{\\an8}Second line with {braces}\r\n"
M.SUBTITLE_TEXT = SUBTITLE_TEXT

-- Canonical form the real API redirects to. Rules confirmed against the live
-- API on 2026-11-19 (each of these got a 301 to the canonical URL):
--   * parameters not in alphabetical order
--   * upper-case letters in a value            (languages=EN, query=Big)
--   * a space sent as %20 instead of +
--   * leading zeros or "tt" in *_id, leading zeros in *_number
-- Accepted as-is (200): %2C or a literal comma, any order of the languages
-- inside the list, percent-encoded UTF-8.
local function canonical_query(req)
  local keys = {}
  for k in pairs(req.query) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = req.query[k]:lower()
    if k:match("id$") or k:match("_number$") then
      v = v:gsub("^tt", ""):gsub("^0+(%d)", "%1")
    end
    parts[#parts + 1] = k:lower() .. "=" .. v:gsub(" ", "+")
  end
  return table.concat(parts, "&")
end

-- The query as sent, decoded the same way, in the order it was sent.
local function sent_query(req)
  local parts = {}
  for _, k in ipairs(req.query_order) do
    parts[#parts + 1] = k .. "=" .. req.query[k]:gsub(" ", "+")
  end
  return table.concat(parts, "&")
end

function M.is_canonical(req)
  return not req.raw_query:find("%%20") and sent_query(req) == canonical_query(req)
end
M.canonical_query = canonical_query

-- opts.api_key     key the server accepts (default: any non-empty key)
-- opts.username / opts.password   the one valid account
function M.new(opts)
  opts = opts or {}
  local s = {
    requests = {},            -- every request received, in order
    routes = {},              -- "METHOD host/path" -> handler(req, server)
    offline = false,          -- true: every connection attempt fails
    down = {},                -- [host] = true: that host is unreachable
    segment = 1460,           -- bytes per recv()
    username = opts.username or "tester",
    password = opts.password or "test-password",
    token = "eyJhbGciOiJIUzI1NiJ9.fake-token-for-tests.sig",
    user = { allowed_downloads = 100, allowed_translations = 5, level = "Sub leecher",
             user_id = 66, ext_installed = false, vip = false },
    downloads_used = 0,
    rate_limit = nil,         -- number: 429 after that many requests
  }

  function s:resolve(host)
    return not (self.offline or self.down[host])
  end

  function s:on(key, handler) self.routes[key] = handler end

  -- Requests matching a "METHOD host/path" pattern (plain prefix match)
  function s:seen(prefix)
    local out = {}
    for _, r in ipairs(self.requests) do
      if (r.method .. " " .. r.host .. r.path):sub(1, #prefix) == prefix then
        out[#out + 1] = r
      end
    end
    return out
  end
  function s:last(prefix)
    local all = self:seen(prefix or "")
    return all[#all]
  end
  function s:reset() self.requests = {} end

  function s:handle(req)
    self.requests[#self.requests + 1] = req
    if self.rate_limit and #self.requests > self.rate_limit then
      return M.fixture("rate_limited")
    end
    local key = req.method .. " " .. req.host .. req.path
    local handler = self.routes[key]
    if not handler then
      -- longest registered prefix ending in "*"
      local best = -1
      for pattern, h in pairs(self.routes) do
        if pattern:sub(-1) == "*" and key:sub(1, #pattern - 1) == pattern:sub(1, -2)
           and #pattern > best then
          handler, best = h, #pattern
        end
      end
    end
    if not handler then
      return M.response(404, { message = "no route for " .. key })
    end
    return handler(req, self)
  end

  -- ---------------------------------------------- api.opensubtitles.com --
  local API = "api.opensubtitles.com/api/v1"

  local function guard(handler)
    return function(req, srv)
      if req.via == "stream" then
        -- vlc.stream cannot send Api-Key: the real API rejects it.
        return M.response(403, { message = "You cannot consume this service" })
      end
      if not req.headers["api-key"] or req.headers["api-key"] == ""
         or (opts.api_key and req.headers["api-key"] ~= opts.api_key) then
        return M.response(403, { message = "You cannot consume this service" })
      end
      -- Recorded behaviour (2026-11-19): the API answers plain HTTP only for
      -- a User-Agent starting with "VLSub OpenSubtitles.com". Any other agent
      -- is redirected to https, which an extension cannot use (no headers).
      if (req.headers["user-agent"] or ""):sub(1, 23) ~= "VLSub OpenSubtitles.com" then
        return M.response(301, "", { Location = "https://" .. req.host .. req.target })
      end
      -- Recorded behaviour: only /subtitles is canonicalised (guessit accepts
      -- mixed-case filenames as-is).
      if req.path:match("/subtitles$") and not M.is_canonical(req) then
        return M.response(301, "<html>301 Moved Permanently</html>",
          { ["Content-Type"] = "text/html",
            Location = req.path .. "?" .. canonical_query(req) }, { chunked = 64 })
      end
      return handler(req, srv)
    end
  end

  local function authorized(req, srv)
    return req.headers["authorization"] == "Bearer " .. srv.token
  end

  s:on("GET " .. API .. "/infos/languages", guard(function()
    return M.fixture("languages")
  end))

  s:on("GET " .. API .. "/subtitles", guard(function(req)
    local q = req.query
    if q.moviehash then
      if q.moviehash == "8e245d9679d31e12" then return M.fixture("search_hash") end
      return M.fixture("search_none")
    elseif q.imdb_id then
      return M.fixture("search_imdb")
    elseif q.query and q.query:find("zzz") then
      return M.fixture("search_none")
    elseif q.season_number or q.episode_number then
      return M.fixture("search_episode")
    elseif q.languages and q.languages:find(",") then
      return M.fixture("search_name_multi")
    end
    return M.fixture("search_name_en")
  end))

  s:on("GET " .. API .. "/utilities/guessit", guard(function(req)
    local name = req.query.filename or ""
    if name:lower():find("breaking") then return M.fixture("guessit") end
    local title = name:gsub("%.[%w]+$", ""):gsub("[%._]", " ")
    local year = title:match("%f[%d](%d%d%d%d)%f[%D]")
    if year then title = title:gsub("%s*" .. year .. ".*$", "") end
    return M.response(200, { title = title, year = tonumber(year), type = "movie" },
                      nil, { chunked = 200 })
  end))

  s:on("POST " .. API .. "/login", guard(function(req, srv)
    local body = json.decode(req.body)
    if req.headers["content-type"] ~= "application/json" or not body then
      return M.response(400, { message = "Bad Request", status = 400 })
    end
    if body.username == srv.username and body.password == srv.password then
      return M.response(200, { user = srv.user, base_url = "api.opensubtitles.com",
                               token = srv.token, status = 200 }, nil, { chunked = 300 })
    end
    return M.fixture("login_bad")
  end))

  s:on("DELETE " .. API .. "/logout", guard(function(req, srv)
    if not authorized(req, srv) then return M.response(401, { message = "Unauthorized", status = 401 }) end
    return M.response(200, { message = "token successfully destroyed", status = 200 })
  end))

  s:on("GET " .. API .. "/infos/user", guard(function(req, srv)
    if not authorized(req, srv) then return M.response(401, { message = "Unauthorized", status = 401 }) end
    return M.response(200, { data = {
      allowed_downloads = srv.user.allowed_downloads, level = srv.user.level,
      user_id = srv.user.user_id, ext_installed = false, vip = srv.user.vip,
      downloads_count = srv.downloads_used,
      remaining_downloads = srv.user.allowed_downloads - srv.downloads_used } })
  end))

  s:on("POST " .. API .. "/download", guard(function(req, srv)
    local body = json.decode(req.body)
    if not authorized(req, srv) then
      return M.response(401, { message = "You must be logged in to download", status = 401 })
    end
    if not body or not tonumber(body.file_id) or tonumber(body.file_id) <= 1 then
      return M.fixture("download_noauth") -- real API: 200 {"message":"Invalid file_id"}
    end
    if srv.downloads_used >= srv.user.allowed_downloads then
      return M.response(406, { requests = srv.downloads_used, remaining = 0,
        message = "You have downloaded your allowed 100 subtitles for 24h.",
        reset_time = "10 hours and 3 minutes", reset_time_utc = "2026-11-20T00:00:00.000Z" })
    end
    srv.downloads_used = srv.downloads_used + 1
    return M.response(200, {
      link = "https://www.opensubtitles.com/download/ABC123/subfile/file_" ..
             tostring(body.file_id) .. ".srt",
      file_name = "file_" .. tostring(body.file_id) .. ".srt",
      requests = srv.downloads_used,
      remaining = srv.user.allowed_downloads - srv.downloads_used,
      message = "Your quota will be renewed in 23 hours and 59 minutes",
      reset_time = "23 hours and 59 minutes",
      reset_time_utc = "2026-11-20T05:00:00.000Z" }, nil, { chunked = 120 })
  end))

  -- --------------------------------------------------------- other hosts --
  s:on("GET www.opensubtitles.com/download/*", function(req)
    if req.scheme ~= "https" then
      return M.response(301, "", { Location = "https://www.opensubtitles.com" .. req.target })
    end
    return M.response(200, SUBTITLE_TEXT, { ["Content-Type"] = "application/octet-stream" })
  end)

  s:on("GET api.github.com/repos/opensubtitles/vlsub-opensubtitles-com/releases/latest", function()
    return M.response(200, { tag_name = "v" .. (opts.latest_version or "0.0.1"),
      name = "VLSub " .. (opts.latest_version or "0.0.1"), body = "Release notes",
      html_url = "https://github.com/opensubtitles/vlsub-opensubtitles-com/releases",
      assets = {} })
  end)

  s:on("GET api.myip.com/", function()
    return M.response(200, { ip = "203.0.113.7", country = "Slovakia", cc = "SK" })
  end)
  s:on("GET www.google.com/", function()
    return M.response(200, "<html>ok</html>", { ["Content-Type"] = "text/html" })
  end)
  s:on("GET httpbin.org/get", function(req)
    return M.response(200, { headers = req.headers, url = "https://httpbin.org/get" })
  end)
  s:on("GET api.opensubtitles.com/", function()
    return M.response(200, "<html>OpenSubtitles API</html>", { ["Content-Type"] = "text/html" })
  end)

  return s
end

return M
