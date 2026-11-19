-- Runs every tests/spec/*_spec.lua.
--
--   lua tests/run_tests.lua            all specs
--   lua tests/run_tests.lua search     only tests whose name contains "search"

local here = (arg and arg[0] or "tests/run_tests.lua"):match("^(.*)[/\\][^/\\]*$") or "."
package.path = here .. "/lib/?.lua;" .. package.path
local H = require("harness")

local specs = {}
local p = io.popen('ls -1 "' .. here .. '/spec"')
for name in p:lines() do
  if name:match("_spec%.lua$") then specs[#specs + 1] = name end
end
p:close()
table.sort(specs)

for _, name in ipairs(specs) do
  assert(loadfile(here .. "/spec/" .. name))(H)
end

os.exit(H.run(arg and arg[1]) and 0 or 1)
