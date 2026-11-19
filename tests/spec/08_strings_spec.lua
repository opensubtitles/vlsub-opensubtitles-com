-- The interface strings table. Everything the user reads comes from it, so a
-- translation only has to replace this one table (docs/refactor-brief.md,
-- phase 2).
local H = ...
local describe, it, eq, ok = H.describe, H.it, H.eq, H.ok

local function source()
  return H.read_file(H.SCRIPT)
end

-- key -> text, read from the `local strings = { ... }` block of the source
local function defined_strings(src)
  local block = src:match("\nlocal strings = (%b{})")
  local defined = {}
  for key in block:gmatch("\n%s+([%a_][%w_]*)%s*=") do defined[key] = true end
  return defined, block
end

describe("interface strings", function()
  it("every strings.<key> used in the code is defined", function()
    local src = source()
    local defined = defined_strings(src)
    local missing = {}
    for key in src:gmatch("[^%w_.]strings%.([%a_][%w_]*)") do
      if not defined[key] then missing[key] = true end
    end
    for key in src:gmatch('[^%w_.]lang%["([%a_][%w_]*)"%]') do
      if not defined[key] then missing[key] = true end
    end
    local names = {}
    for k in pairs(missing) do names[#names + 1] = k end
    table.sort(names)
    eq(names, {}, "keys used but not defined (would be nil at run time)")
  end)

  it("no key is defined twice", function()
    local _, block = defined_strings(source())
    local seen, twice = {}, {}
    for key in block:gmatch("\n%s+([%a_][%w_]*)%s*=") do
      if seen[key] then twice[#twice + 1] = key end
      seen[key] = true
    end
    eq(twice, {}, "duplicate keys")
  end)

  it("every string is a non-empty string at run time", function()
    H.launch({ activate = false })
    local strings = H.find_local("strings")
    local count = 0
    for key, value in pairs(strings) do
      ok(type(value) == "string" and value ~= "", "strings." .. tostring(key))
      count = count + 1
    end
    ok(count > 250, "table looks complete (" .. count .. " entries)")
  end)

  it("messages and labels are not written inline any more", function()
    local src = source()
    local body = src:sub((src:find("\nlocal strings = %b{}")))
    body = body:gsub("\nlocal strings = %b{}", "", 1)
    local offenders = {}
    local line_number = select(2, src:sub(1, #src - #body):gsub("\n", "\n"))
    for line in (body .. "\n"):gmatch("(.-)\n") do
      line_number = line_number + 1
      local code = line:gsub("%-%-.*$", "")
      if code:find("setMessage%(") or code:find("setError%(") or code:find("download_failed%(")
         or code:find(":add_label%(") or code:find(":add_button%(") or code:find(":add_html%(") then
        for literal in code:gmatch('"([^"]*)"') do
          local text = literal:gsub("<[^>]*>", "")
          if select(2, text:gsub("%a", "")) >= 3 and text:find("%a%a")
             and not code:find('%[%s*"' .. literal:gsub("%p", "%%%0") .. '"%s*%]') then
            offenders[#offenders + 1] = line_number .. ": " .. literal
          end
        end
      end
    end
    eq(offenders, {}, "inline text in a message or label")
  end)
end)
