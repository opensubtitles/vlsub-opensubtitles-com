-- Writes locale/en.json: the English interface strings exactly as they are in
-- vlsubcom.lua, sorted by key. It is the reference translators work from.
--
--     lua tests/export_strings.lua
--
-- tests/spec/09_locale_spec.lua fails when the file is out of date.

local here = (arg and arg[0] or "tests/export_strings.lua"):match("^(.*)[/\\][^/\\]*$") or "."
package.path = here .. "/lib/?.lua;" .. package.path
local H = require("harness")

H.launch({ activate = false })
local strings = H.find_local("strings")
local keys = {}
for key in pairs(strings) do keys[#keys + 1] = key end
table.sort(keys)

local text = H.json.encode(strings, { indent = true, keyorder = keys })
if arg and arg[1] == "--print" then
  io.write(text, "\n")
else
  H.write_file(here .. "/../locale/en.json", text .. "\n")
  print("locale/en.json: " .. #keys .. " strings")
end
H.cleanup()
