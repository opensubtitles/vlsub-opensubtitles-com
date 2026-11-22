-- luacheck configuration for the VLC extension.
--
--     luacheck vlsubcom.lua
--
-- Only the "global variable" checks are enabled. They are the ones that catch
-- calling a function that is not in scope (misspelled name, a `local function`
-- declared below its call site, a helper that was never written) - bugs that
-- are syntactically valid and otherwise only surface when a user clicks the
-- affected button inside VLC.

-- "min" = only what exists in every Lua version (5.1, 5.2, 5.3, LuaJIT). VLC
-- builds embed 5.1 or 5.2 depending on platform, so nothing newer may be used.
std = "min"
max_line_length = false
codes = true

-- Globals created by top-level `function name()` / `name = ...` statements
-- count as defined everywhere in the file.
allow_defined_top = true

-- Injected by VLC
read_globals = { "vlc",
  -- only where they exist, checked when used (the MD5 of an upload)
  "loadstring", "bit32" }

-- Globals that are first assigned inside a function (check_config and the
-- translation loader) instead of at the top level.
globals = {
  "lang",
  "slash",
  "sub_dir",
  "eng_translation",
  "trsl_names",
  "all_trsl",
}

-- 111 setting undefined global, 112 mutating undefined global,
-- 113 accessing undefined global. Syntax errors are always reported.
only = { "11." }

exclude_files = { "tests/vendor/**" }
