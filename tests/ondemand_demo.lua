-- Shows what the extension does with an AI on-demand entry, against the
-- SIMULATED server in tests/lib/fake_api.lua (see docs/ai-translation-brief.md).
--   lua tests/ondemand_demo.lua [waits] [credits]      e.g.  ... 2 120   or   ... 0 0
package.path = ((arg and arg[0] or "tests/x"):match("^(.*)[/\\][^/\\]*$") or ".") .. "/lib/?.lua;" .. package.path
local H = require("harness")
local dir = H.tmpdir()
local env = H.launch({ config = { language = "cs" }, media = "file://" .. dir .. "/Big.Buck.Bunny.2008.mkv" })
env.server.ai.on_demand = { language = "cs", from = "pl" }
env.server.ai.waits = tonumber(arg[1] or 0)
env.server.ai.credits = tonumber(arg[2] or 120)
local d = env.ui()
d:_at(2, 1, "text_input"):set_text("big buck bunny")
d:_button("Search$"):_click()
local list = env.results()
print("rows in the result list: " .. #list.values)
for i, v in ipairs(list.values) do if i <= 2 then print(string.format("  %2d  %s", i, v.text:sub(1, 150))) end end
print("message: " .. env.message():gsub("<[^>]+>", ""))
for _, v in ipairs(list.values) do if v.text:find("Big.Buck.Bunny.2008.cs", 1, true) then list:_select(v.id) end end
local quota_before = env.server.downloads_used
env.ui():_button("Download"):_click()
print("\nclick Download on row 1 (the on-demand row):")
print("  id the server received : " .. tostring(env.server.ai.last_id_sent))
print("  id it had sent         : " .. env.server.ai.ON_DEMAND_ID)
print("  translations paid      : " .. env.server.ai.spent .. "   credits left: " .. env.server.ai.credits .. "   quota used: " .. env.server.downloads_used - quota_before)
print("  message: " .. env.message():gsub("<[^>]+>", ""))
print("  files next to the video: " .. table.concat(H.ls(dir), ", "))
for _, e in ipairs(env.errors()) do print("  ERR " .. e) end
