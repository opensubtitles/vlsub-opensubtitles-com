local H = ...
local describe, it, eq, ok = H.describe, H.it, H.eq, H.ok

describe("startup", function()
  it("exposes the entry points VLC calls", function()
    H.launch({ activate = false })
    for _, name in ipairs({ "descriptor", "activate", "deactivate", "close", "menu",
                            "trigger_menu", "input_changed", "meta_changed" }) do
      eq(type(_G[name]), "function", name)
    end
    local d = descriptor()
    ok(d.title and d.version and d.capabilities, "descriptor fields")
  end)

  it("activate() without media shows the main window and makes no login request", function()
    local env = H.launch()
    eq(#env.server:seen("POST api.opensubtitles.com/api/v1/login"), 0, "login requests")
    ok(env.ui():_button("Search$"), "main window has a search button")
    eq(env.message(), "Ready for search")
    eq(env.errors(), {}, "errors logged")
  end)

  it("activate() with a local video auto-searches by hash, then by name", function()
    local dir = H.tmpdir()
    local env = H.launch({ media = "file://" .. H.video(dir, "Big.Buck.Bunny.2008.1080p.mkv", 200000) })
    local searches = env.server:seen("GET api.opensubtitles.com/api/v1/subtitles")
    eq(#searches, 2, "search requests")
    eq(searches[1].query.moviehash, "e6ed0e283146465f")
    eq(searches[2].query.query, "big buck bunny")
    eq(#env.results().values, 50, "results listed")
  end)

  it("first run (no config) ends on the configuration window", function()
    local env = H.launch({ first_run = true })
    H.has(env.ui().title, "Configuration")
    ok(H.exists(env.dir .. "/vlsub_conf.json"), "config file created")
  end)
end)
