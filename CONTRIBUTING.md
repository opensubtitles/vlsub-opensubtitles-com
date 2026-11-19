# Contributing to VLSub OpenSubtitles.com

Thank you for your interest in contributing to VLSub OpenSubtitles.com! This document provides guidelines and information for contributors.

## 🤝 How to Contribute

### Reporting Bugs 🐛

Before creating a bug report, please:
1. **Search existing issues** to avoid duplicates
2. **Test with the latest version** to ensure the bug still exists
3. **Gather system information** (OS, VLC version, extension version)

When creating a bug report, include:
- **Clear title** describing the issue
- **Steps to reproduce** the problem
- **Expected vs actual behavior**
- **Screenshots/logs** if applicable
- **System information**:
  - Operating System and version
  - VLC Media Player version
  - Extension version
  - Video file format/source

Use our [Bug Report Template](.github/ISSUE_TEMPLATE/bug_report.md).

### Suggesting Features 💡

Feature requests are welcome! Please:
1. **Check existing feature requests** to avoid duplicates
2. **Explain the use case** and why it would be valuable
3. **Describe the proposed solution** in detail
4. **Consider implementation complexity**

Use our [Feature Request Template](.github/ISSUE_TEMPLATE/feature_request.md).

### Code Contributions 💻

#### Getting Started

1. **Fork the repository**
   ```bash
   git clone https://github.com/opensubtitles/vlsub-opensubtitles-com.git
   cd vlsub-opensubtitles-com
   ```

2. **Set up development environment**
   - Install VLC Media Player 3.0+
   - Install Lua 5.3+ for syntax checking
   - Install curl for testing downloads

3. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

#### Development Guidelines

##### Code Style
- **Indentation**: 2 spaces (no tabs)
- **Line length**: Maximum 120 characters
- **Comments**: Use `--` for single-line, `--[[]]--` for multi-line
- **Functions**: Use descriptive names with camelCase
- **Variables**: Use descriptive names with snake_case for locals
- **Constants**: Use UPPER_CASE

##### Example:
```lua
-- Good
local function searchSubtitlesByHash()
  local movie_hash = openSub.file.hash
  local byte_size = openSub.file.bytesize
  
  if not movie_hash or movie_hash == "" then
    vlc.msg.err("[VLSub] No movie hash available")
    return false
  end
  
  -- API call logic here
end

-- Constants
local MAX_RETRY_ATTEMPTS = 3
local DEFAULT_TIMEOUT = 30
```

##### Error Handling
- Always validate inputs
- Provide meaningful error messages
- Use VLC's logging system: `vlc.msg.dbg()`, `vlc.msg.err()`
- Handle network failures gracefully

```lua
-- Good error handling
local function downloadSubtitle(url)
  if not url or url == "" then
    vlc.msg.err("[VLSub] Invalid download URL")
    setMessage(error_tag("Invalid download URL"))
    return false
  end
  
  local client = Curl.new()
  local res = client:get(url)
  
  if not res then
    vlc.msg.err("[VLSub] Network request failed")
    setMessage(error_tag("Network connection failed"))
    return false
  end
  
  if res.status ~= 200 then
    vlc.msg.err("[VLSub] Download failed with status: " .. res.status)
    setMessage(error_tag("Download failed: HTTP " .. res.status))
    return false
  end
  
  return res.body
end
```

#### Testing

> 👉 **Quick start:** See **[TESTING.md](TESTING.md)** for platform-specific setup (Mac/Linux/Windows) and step-by-step testing instructions.

##### Automated Checks (required)

```bash
tests/run.sh            # syntax + luacheck + behaviour tests (offline, < 5 s)
tests/vlc/run.sh        # the extension inside a real headless VLC, live API
tools/dev.sh link       # make VLC load this checkout; then tools/dev.sh run / errors
git config core.hooksPath .githooks   # optional: run tests/run.sh on commit
```

CI runs `tests/run.sh` on Lua 5.1, 5.2 and 5.4 and the release workflow will not publish if it fails.

- Read [docs/vlc-lua-environment.md](docs/vlc-lua-environment.md) first: VLC's Lua is restricted and several `vlc.*` functions do not behave as their names suggest.
- [tests/README.md](tests/README.md) explains the three test layers and how to write a test. Add one for every feature and every bug fix.
- Defects that are known but not fixed yet are written as `known_bug(...)` tests; fixing one means changing it to `it(...)`.
- `luacheck` (`apt install lua-check` / `luarocks install luacheck`) reports any use of an undefined name. If you intentionally introduce a global that is first assigned inside a function, list it in `.luacheckrc`.

##### Manual Testing Checklist
- [ ] Extension loads without errors in VLC
- [ ] Configuration window opens and saves settings
- [ ] Hash search works with local video files
- [ ] Name search works with various filename formats
- [ ] Download and auto-load functionality works
- [ ] Multi-language selection functions correctly
- [ ] Auto-update mechanism works (if applicable)
- [ ] Cross-platform compatibility (test on multiple OS if possible)

##### Test Cases
1. **Fresh installation** - no existing config
2. **Upgrade scenario** - existing config migration
3. **Network failure** - offline/timeout scenarios
4. **Authentication failure** - invalid credentials
5. **No results** - search with no matches
6. **Large files** - movies >4GB for hash calculation
7. **Special characters** - filenames with unicode/symbols

#### Pull Request Process

1. **Update documentation** if needed
2. **Add/update tests** for new functionality
3. **Run syntax check**:
   ```bash
   lua5.3 -l vlsubcom.lua -e "print('Syntax OK')"
   ```
4. **Update CHANGELOG.md** with your changes
5. **Create pull request** with clear description

##### Pull Request Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change)
- [ ] New feature (non-breaking change)
- [ ] Breaking change (fix or feature causing existing functionality to change)
- [ ] Documentation update

## Testing
- [ ] Manual testing completed
- [ ] Cross-platform testing (specify platforms)
- [ ] No syntax errors

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
```

## 🏗️ Project Structure

```
vlsub-opensubtitles-com/
├── vlsubcom.lua              # Main extension file
├── README.md                 # Project documentation
├── CHANGELOG.md              # Version history
├── CONTRIBUTING.md           # This file
├── LICENSE                   # GPL-3.0 license
├── docs/                     # Additional documentation
│   ├── installation.md       # Installation guide
│   ├── usage.md              # Usage examples
│   ├── api.md                # API documentation
│   ├── troubleshooting.md    # Common issues
│   └── screenshots/          # UI screenshots
├── scripts/                  # Installation scripts
│   ├── install.sh            # Unix installation
│   └── install.ps1           # Windows installation
└── .github/                  # GitHub specific files
    ├── workflows/            # CI/CD workflows
    ├── ISSUE_TEMPLATE/       # Issue templates
    └── PULL_REQUEST_TEMPLATE.md
```

## 📚 Key Components

### Core Functions
- `activate()` - Extension initialization
- `searchHash()` - Hash-based subtitle search
- `searchIMBD_v2()` - Name-based search
- `download_subtitles_v2()` - Download and load subtitles
- `openSub.checkLoginAndUserInfo()` - Authentication

### API Integration
- `openSub.loginWithRestAPI()` - REST API authentication
- `openSub.searchSubtitlesNewAPI()` - Modern search API
- `openSub.downloadFromNewAPI()` - Download API

### User Interface
- `interface_main()` - Main search interface
- `interface_config()` - Configuration dialog
- `interface_help()` - Help documentation

## 🔍 Code Review Criteria

### Functionality
- Does the code work as intended?
- Are edge cases handled properly?
- Is error handling comprehensive?

### Code Quality
- Is the code readable and well-documented?
- Does it follow project conventions?
- Are there any code smells or anti-patterns?

### Performance
- Are there any performance bottlenecks?
- Is memory usage optimized?
- Are network requests efficient?

### Security
- Is user input properly validated?
- Are API keys and credentials handled securely?
- Are there any potential vulnerabilities?

## 🌍 Internationalization

Currently, the extension supports interface translation for:
- English (default)
- Czech, Danish, Dutch, Finnish, French
- Greek, Basque, Portuguese, Romanian
- Slovak, Spanish, Swedish, Ukrainian, Hungarian, Serbian

To add a new language:
1. Add language code to `translations_avail` in the script
2. Create translation file in XML format
3. Test the interface with new translations

## 📝 Documentation

### Code Documentation
- Use clear, descriptive comments
- Document complex algorithms
- Explain API integrations
- Include usage examples

### User Documentation
- Keep README.md updated
- Update installation instructions
- Document new features
- Maintain troubleshooting guide

## 🚀 Release Process

1. **Version bump** in `vlsubcom.lua`
2. **Update CHANGELOG.md** with release notes
3. **Create GitHub release** with tag
4. **Test installation scripts**
5. **Update documentation** if needed

## 📞 Getting Help

- **GitHub Discussions**: For general questions and ideas
- **GitHub Issues**: For bugs and feature requests
- **Code Review**: Tag maintainers for complex changes

## 🏆 Recognition

Contributors will be recognized in:
- README.md acknowledgments section
- Release notes for significant contributions
- GitHub contributors list

## 📄 License

By contributing, you agree that your contributions will be licensed under the GNU General Public License v3.0.

---

Thank you for contributing to VLSub OpenSubtitles.com! 🎉