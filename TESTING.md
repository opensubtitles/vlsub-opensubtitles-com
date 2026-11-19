# Testing VLSub OpenSubtitles.com

Quick guide to testing changes before submitting a pull request.

## 🚀 Quick Start (macOS)

```bash
# 1. Install test dependencies (one-time setup)
brew install lua luacheck

# 2. Run the test suite (< 5 seconds)
./tests/run.sh

# 3. Test in real VLC
./tools/dev.sh link                    # VLC loads your working copy
./tools/dev.sh run ~/Movies/test.mkv   # Start VLC with debug logging

# 4. Use the extension in VLC
# View → Extensions → VLSub OpenSubtitles.com
# Try searching/downloading

# 5. Check for errors
./tools/dev.sh errors                  # Shows any Lua crashes/warnings

# 6. When done
./tools/dev.sh restore                 # Back to original extension
```

## 🐧 Quick Start (Linux)

```bash
# 1. Install test dependencies
sudo apt install lua5.2 lua-check      # Debian/Ubuntu
# OR
sudo dnf install lua luacheck          # Fedora
# OR
sudo pacman -S lua luacheck            # Arch

# 2-6: Same as macOS above
./tests/run.sh
./tools/dev.sh link
# etc.
```

## 🪟 Quick Start (Windows)

```powershell
# 1. Install Lua (one-time setup)
# Download from https://github.com/rjpcomputing/luaforwindows/releases
# Or use chocolatey: choco install lua luarocks

# 2. Install luacheck
luarocks install luacheck

# 3. Run tests (Git Bash or WSL recommended)
bash tests/run.sh

# 4. Manual testing in VLC
# Copy vlsubcom.lua to %APPDATA%\vlc\lua\extensions\
# Start VLC, check Tools → Messages (verbosity 2) for errors
```

---

## 📋 Three Testing Layers

### Layer 1: Offline Test Suite ⚡️ **Start here**

**Fast** (< 5 seconds), **offline**, catches most bugs.

```bash
./tests/run.sh                     # Full suite: syntax + luacheck + 201 tests
lua tests/run_tests.lua download   # Only tests matching "download"
LUA=lua5.2 ./tests/run.sh          # Test with VLC's Lua version
```

**What it tests:**
- ✅ Lua syntax errors
- ✅ Undefined function calls (the v1.3.1 bug)
- ✅ Search (hash, name, IMDb)
- ✅ Login & authentication
- ✅ Download & file handling
- ✅ Language selection
- ✅ Configuration saving
- ✅ Error handling

**How it works:** Loads `vlsubcom.lua` with a VLC API simulator and fake OpenSubtitles API using recorded responses.

👉 **See [tests/README.md](tests/README.md) for detailed test writing guide**

### Layer 2: Real VLC Integration 🧪

**Runs the extension in headless VLC** against the **live API**.

```bash
./tests/vlc/run.sh                                    # Anonymous search only
VLSUB_USER=you VLSUB_PASS=secret ./tests/vlc/run.sh  # With login + download
```

**What it tests:**
- Real VLC Lua environment
- Real network requests
- Real SSL/TLS
- Actual API behavior

**Warning:** Depends on network and API availability. CI runs this but doesn't block merges if it fails.

### Layer 3: Manual GUI Testing 🎮

**Interactive testing** with VLC's full UI.

```bash
# Make VLC load your working copy
./tools/dev.sh link              # Symlink (edits apply immediately)
# OR
./tools/dev.sh install           # Copy (need to reinstall after edits)

# Start VLC with debug logging
./tools/dev.sh run ~/Movies/test-video.mkv

# In VLC:
#   - macOS: VLC → Extensions → VLSub OpenSubtitles.com
#   - Linux/Windows: View → VLSub OpenSubtitles.com

# Check for errors
./tools/dev.sh errors            # Shows Lua errors from the log
./tools/dev.sh log               # Live tail of VLSub output

# Put back your original extension
./tools/dev.sh restore
```

**Available tools:**
```bash
./tools/dev.sh status            # What is VLC loading?
./tools/dev.sh test              # Alias for ./tests/run.sh
./tools/dev.sh realvlc           # Alias for ./tests/vlc/run.sh
```

---

## ✅ Pre-Commit Checklist

Before submitting a PR, make sure:

1. **Tests pass**
   ```bash
   ./tests/run.sh
   ```

2. **No luacheck warnings**
   ```bash
   luacheck vlsubcom.lua
   ```

3. **Extension loads in VLC**
   ```bash
   ./tools/dev.sh link
   ./tools/dev.sh run
   ./tools/dev.sh errors  # Should show "no Lua errors"
   ```

4. **Manual smoke test**
   - [ ] Configuration window opens
   - [ ] Search by name finds results
   - [ ] Search by hash works (with local video)
   - [ ] Download works
   - [ ] No VLC freezes or crashes

5. **Update CHANGELOG.md** with your changes

6. **Add a test** for your bug fix or feature
   - See [tests/README.md#writing-a-test](tests/README.md#writing-a-test)

---

## 🐛 When Tests Fail

### "luacheck not found"

```bash
# macOS
brew install luacheck

# Linux
sudo apt install lua-check         # Debian/Ubuntu
sudo dnf install luacheck          # Fedora
luarocks install luacheck          # Any distro with luarocks

# Windows
luarocks install luacheck
```

### "Syntax error" or "attempt to call nil"

You have a Lua syntax error or undefined function. The error message shows the line number:

```
luac: vlsubcom.lua:5692: attempt to call global 'sanitize_filename' (a nil value)
                       ^^^^
                       Line 5692
```

### "luac: attempt to assign to const variable"

The code assigns to a `for` loop variable. Lua 5.1–5.4 (and so VLC, which embeds 5.1 or 5.2) accept that; Lua 5.5 rejects it at compile time, and CI runs the suite on 5.5 too:

```lua
-- ❌ Bad (compile error on Lua 5.5)
for line in str:gmatch("[^\n]+") do
  line = line:gsub(...)  -- loop variables are read-only in 5.5
end

-- ✅ Good (works in 5.1, 5.2, 5.4, 5.5)
for line_value in str:gmatch("[^\n]+") do
  local line = line_value:gsub(...)
end
```

Test with the right Lua version:
```bash
LUA=lua5.2 ./tests/run.sh
```

### "Extension loads but doesn't work in VLC"

Check the debug log:

```bash
./tools/dev.sh run ~/Movies/test.mkv

# In another terminal:
./tools/dev.sh errors              # Show errors
./tools/dev.sh log                 # Live output
```

Or check manually:
```
macOS:    ~/Library/Logs/VLC/
Linux:    VLC → Tools → Messages (Ctrl+M)
Windows:  VLC → Tools → Messages (Ctrl+M)
```

---

## 📚 More Documentation

- **[tests/README.md](tests/README.md)** — Deep dive: how tests work, how to write tests
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Full contribution guide
- **[docs/vlc-lua-environment.md](docs/vlc-lua-environment.md)** — VLC's Lua quirks and limits

---

## 🆘 Getting Help

- **Ask in your PR** if tests fail and you're not sure why
- **GitHub Issues** for reproducible test bugs
- **Check existing issues** — someone may have hit the same error

---

## ⚙️ Optional: Git Hooks

Run tests automatically on every commit:

```bash
git config core.hooksPath .githooks
```

This runs `./tests/run.sh` before each commit. If tests fail, the commit is blocked.

To bypass the hook once (e.g., WIP commit):
```bash
git commit --no-verify -m "WIP: debugging"
```
