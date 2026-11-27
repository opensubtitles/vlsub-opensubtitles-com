# Changelog

All notable changes to VLSub OpenSubtitles.com extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **AI translation on demand.** When no subtitle exists in a language, the API offers an AI translation of an existing subtitle, made when it is downloaded and paid with the AI credits of the OpenSubtitles account. VLSub lists such an entry as "🤖 AI translation from <language> (uses AI credits)", shows the balance before and after, counts the seconds while the server translates (about 20 s for a whole film), and delivers a translation that exists already at once and for free. Without enough credits the server sends a preview; the message says so and links to the credit packages.
- **AI credits in the configuration window**: the balance after Save, and a button that shows it together with the credit packages.
- **Rate subtitles** (needs a login; API since 2026-11-23): after a film watched (70 %) with a subtitle VLSub loaded, the main window asks once how it was - rating 1-5 and timing (right / too early / too late / drifting / wrong), Send, More..., Not now (three times in a row and it stops asking). The "Rate" window does the same for the selected search result, the subtitle loaded last, or any subtitle file (by its MD5): rating, removing it, thanks to the uploader, reporting a problem with the site's reasons in the interface language. Search results show the user's own rating (★4) and thanks (♥).
- **Upload subtitles** (main window > Upload, needs a login): a subtitle file next to the video or any file by its path. The film is found by itself where possible (the search just made, the API's guess from the file name and movie hash, `/features` full-text search) and shown with a link to IMDb; an IMDb id, link or title can be entered. Language from the file name, flags (hearing impaired, foreign parts, translated by person / machine / AI), release name (suggested only when the video's name tells more than title and year) and comment. A film the site does not have yet is registered from its IMDb id. After the upload, a link to the subtitle's page.
- **Search filters** (Config > Set filters): AI translations (Yes / No - No leaves out the on-demand translations and AI translations uploaded by others), machine translations, subtitles for the hearing impaired (include / exclude / only), foreign parts only (include / exclude / only), trusted uploaders only. Defaults are the API's, so nothing changes until one is set. A search that finds nothing while a filter is set says so.
- The site's name in the username label of the configuration window is a link to opensubtitles.com.
- Help window: a section about AI translation; the whole window is shorter and in plainer words.

### Changed
- "Check Updates" moved from the configuration window to the help window. Updates are still checked automatically once a day.
- Version 2.0.0: the API offers AI on-demand entries to this version only.
- **Credits are spent by the Download button only.** A download the extension starts by itself (two media-change events in a row on a selected entry) skips AI on-demand entries.
- While any request waits, VLC is told the extension is alive, so it no longer offers to kill it after 10 seconds.

### Fixed
- **First run on an English system offered no interface languages** (the list was only fetched together with a translation). Also in 1.4.0.
- **New texts stayed English after an update** until the weekly refresh: a translation stored by another version is fetched again at the next start.
- **macOS: the first row of the configuration window was pushed out** by a three-line message.
- **Subtitle file name when no video is open**: the name from the API lost its last four characters (assumed to be an extension, which most names do not have). Only a real subtitle extension and a trailing language tag are removed now.


## [1.4.0] - 2026-11-19

### Added
- **The interface in 61 languages.** The configuration window has an "Interface language" setting: English, Automatic (system language), or one of 61 translations - every language the opensubtitles.org website is translated into, using the site's own wording for the common terms. Translations live in the repository (`locale/`) and are downloaded when chosen and refreshed weekly, so corrections reach everyone without a new release. New installations follow the system language; existing installations stay English until changed. The translations are machine-made: if something reads wrong, please open an issue or a pull request (see `locale/README.md`).

### Fixed
- **A raw subtitle answer made the download fail** with a Lua error and left the window on its progress bar: a body that is valid JSON but not an object (a subtitle starts with its cue number) was treated as an API object. Search had the same weakness.
- **A damaged `vlsub_conf.json` stopped the extension from starting.** It now starts with the default settings.
- **VLC "not responding" when the internet is down**: a connection that cannot be opened blocks VLC until the system gives up, and the extension tried again and again (up to three times per request, then the next request). A dead connection is no longer retried and further requests are refused for 10 seconds, so the window is blocked once.
- **macOS: labels in a language beyond Western European letters were shown empty** (VLC for macOS drops label text outside Latin-1), and the help window cut long lines off.
- Text that no translation could reach ("Ready for search", the sorting drop-downs, "None").

### Changed
- **Configuration window: all fields are aligned** in one column (the drop-downs used to start further right than the username and password fields).
- **Internal clean-up of the script** (9,173 → about 7,500 lines including the translation code): dead code removed (old XML-RPC API, a second HTTP client), the three search paths share one request function, long functions split into steps, debug output cut to the useful lines. Verified with a behaviour-diff test that runs 96 scripted sessions against both v1.3.2 and the current script and compares every request, window, message and file; the intended differences are declared one by one.
- `vlsub_conf.json` now contains only settings (it used to include about 9 kB of interface text). Existing files keep working.
- Debug output is controlled by VLC's own message verbosity; the hidden `debugLogging` setting is gone.

### Not verified
- Windows: no one has run this version there yet. The Windows-only code (paths, locale detection) was changed as little as possible.


## [1.3.2] - 2026-11-19

### Fixed
- **Every subtitle download failing in 1.3.1** with `attempt to call global 'sanitize_filename' (a nil value)`: the filename sanitizer was declared ~2000 lines below the code that calls it and was out of scope there.
- **VLC freezing when the network is down or a server does not answer**: a failed connection still yields a valid-looking socket in VLC, and the HTTP client then waited on it forever. Failed connections are now detected, and every request has a real deadline.
- **First run freezing VLC for 25–40 seconds**: the IP-geolocation lookup used a service published on IPv6 only, and VLC cannot time such a request out. It is now only used when the system gives no locale at all (measured in VLC: first run 42 s → 3.5 s).
- **First run aborting when google.com is unreachable** (offline, or networks where it is blocked).
- **Main window not opening without the API language list**: the built-in list had a broken entry (Hebrew). It also lacked Bulgarian, Irish, Persian, Polish, Serbian and Swahili.
- **A rejected session token was never replaced**: after a `401` the same token was reloaded from the cache and the search repeated until the API rate-limited it. The extension now logs in again once and retries; downloads do the same.
- **`Invalid file_id` saved as a subtitle**: an API answer without a download link was written to the `.srt` file and loaded into the player.
- **Wrong language on first run** for `pt_BR`, `pt_PT`, `zh_CN`, `zh_TW` (invalid codes `pt` / `zh` were saved) and for `LANG=C`.
- **Language could not be set back to "All" / "None"** once one had been saved.
- **Password and session token in VLC's log** when debug logging was enabled. Request and response bodies are no longer logged.
- **Config and session cache readable by other local users**: both files are now created with owner-only permissions on Linux and macOS.
- **Search results silently empty** for JSON containing `}` inside a string, and responses truncated after 100 transfer chunks.
- **Rate limiting, server errors and bad credentials** on name and IMDb searches were all shown as "no result"; they now say what happened.
- **`1080p` taken as the release year** when GuessIt was unavailable; GuessIt is also no longer queried again on every action after a failed lookup, and its cache file is written inside the VLSub folder.
- **Main window not following the playing media**: VLC's `input_changed` callback called a missing `set_interface_main()` and `dlg:get_title()` (which VLC dialogs do not have) and raised a Lua error on every media change.
- Missing functions that raised Lua errors when reached: `ui_yield_if_needed()`, `safe_mwait()`, `interface_no_support()`, `handle_temp_config_click()`; `list_dir()` used directory functions VLC does not provide.
- Legacy socket client: chunked responses split across reads, and a malformed `Host` line after a redirect.
- Compiles under Lua 5.5 (loop variables were being reassigned).

### Added
- **Test suite** (`tests/run.sh`, 203 tests on Lua 5.1/5.2/5.4/5.5): the unmodified extension is driven through its dialog against a mock that behaves like VLC 3.0's Lua API and a fake API server replaying recorded responses of the real one. Covers search (name, hash, IMDb, languages, sorting), login and session cache, settings, download, first-run language detection, the HTTP client's wire format and error handling.
- **Real-VLC test** (`tests/vlc/run.sh`): runs the extension headless inside VLC against the live API.
- **Static analysis** with `luacheck` (`.luacheckrc`): fails on any call to an undefined or out-of-scope function and on Lua features newer than 5.1.
- `tools/dev.sh` to load a working copy into VLC and read its Lua errors; `docs/vlc-lua-environment.md` documenting what VLC's Lua can and cannot do.
- CI runs the suite on every push and pull request, and the release workflow refuses to publish if it fails.

## [1.3.0] - 2026-09-19

### Fixed
- **Login failing with "status: 302" behind proxies and filtered networks** ([#45](https://github.com/opensubtitles/vlsub-opensubtitles-com/issues/45)): HTTP response header names are now looked up case-insensitively, as required by RFC 7230 §3.2. Redirects were only followed when the header arrived as `Location`, so an intercepting proxy or captive portal sending lowercase `location:` left the redirect unfollowed and surfaced the raw `302` as a login error. The same case sensitivity affected `Content-Length` and `Transfer-Encoding`.
- **Redirect targets containing percent-encoded characters**: a redirect to a path with `%20` or `%2F` corrupted the rewritten request, because percent signs in the replacement text were interpreted as capture references. Query strings are also preserved across redirects now.
- **Subtitles starting with ASS override tags** ([#40](https://github.com/opensubtitles/vlsub-opensubtitles-com/issues/40)): subtitle files whose content begins with a curly-brace tag such as `{\an8}` or `{\pos(...)}` no longer download corrupted/truncated. The raw subtitle body from the CDN link was being passed through the JSON response cleaner, which extracted only the first balanced `{...}` block and discarded the rest. The HTTP client now supports a "raw" mode enabled only for the subtitle-file download, preserving the body byte-for-byte; JSON API calls remain unchanged.

### Changed
- **Clearer diagnosis when the network intercepts API requests**: any redirect reaching the UI now reports that the network is redirecting HTTP requests and that a proxy, VPN, captive portal or content filter is intercepting port 80, instead of showing a bare status code. Searches that come back empty for the same reason say so rather than reporting a plain "No result".

## [1.2.9] - 2026-06-09

### Fixed
- **Network share / UNC path handling** ([#32](https://github.com/opensubtitles/vlsub-opensubtitles-com/issues/32)): subtitles for media on Windows network shares (`\\server\share\...`) and SMB/CIFS/NFS protocols now save next to the video file instead of falling back to the Downloads folder. The hostname is preserved from `file://server/share/path` URIs and reconstructed as `//server/share/path` before path resolution.

## [1.2.8] - 2026-06-09

### Fixed
- **Incompatible dkjson dialog**: error dialog now includes Ubuntu/Debian-specific workaround. Distro-bundled VLC ships an old `dkjson.luac` that VLC upgrades do not fix; dialog now explains how to replace it with the latest version from dkolf.de ([#23](https://github.com/opensubtitles/vlsub-opensubtitles-com/issues/23)).

### Documentation
- README troubleshooting now covers the Ubuntu/Debian dkjson fix with full step-by-step instructions.

### Planned
- Package manager support (Homebrew, apt, etc.)
- Subtitle preview before download
- Batch download for TV series
- Custom subtitle styling
- Integration with popular media centers

## [1.0.0] - 2025-01-XX

### Added
- **Initial release** of VLSub for OpenSubtitles.com
- **Modern REST API v2** integration replacing legacy XML-RPC
- **Multi-language support** - select up to 3 preferred languages
- **Smart search methods**:
  - Hash-based search for exact subtitle synchronization
  - Name-based search with GuessIt metadata extraction
  - Automatic fallback from hash to name search
- **Intelligent locale detection**:
  - System locale detection (Windows/macOS/Linux)
  - IP-based geolocation for country detection
  - Timezone-based language suggestions
  - Automatic multi-language recommendations
- **Enhanced user interface**:
  - Debug window for initialization troubleshooting
  - Real-time progress indicators
  - Quality indicators (trusted uploaders, HD, sync status)
  - Language flags and download statistics
  - User quota and download limit display
- **Auto-update system**:
  - Background update checking
  - One-click update installation
  - Version skipping option
  - Automatic backup of current version
- **Advanced features**:
  - Subtitle filename customization with language codes
  - Tag removal option for clean subtitles
  - Configurable working directory
  - Session caching for better performance
  - Comprehensive error handling and user feedback
- **Cross-platform support**:
  - Windows (7, 8, 10, 11)
  - macOS (10.12+)
  - Linux (Ubuntu, Fedora, Arch, etc.)
- **Installation methods**:
  - One-line installation script
  - Manual installation guide
  - Automated GitHub releases

### Technical Improvements
- **Modern architecture** with modular design
- **JSON-based configuration** replacing XML
- **Robust error handling** with user-friendly messages
- **Network timeout management** for unreliable connections
- **Memory optimization** with garbage collection
- **Comprehensive logging** for debugging
- **Security improvements** with proper input validation

### API Features
- **Authentication required** for API access (free OpenSubtitles.com account)
- **Enhanced search parameters** (year, season, episode, language priority)
- **Rich metadata support** (movie details, uploader info, quality indicators)
- **Download quota management** with real-time tracking
- **Rate limiting compliance** with automatic retry logic

### User Experience
- **First-run setup wizard** with automatic configuration
- **Context-aware help system** with detailed documentation
- **Accessibility improvements** with proper contrast and navigation
- **Responsive interface** that adapts to different screen sizes
- **Keyboard shortcuts** for power users
- **Double-click download** for quick subtitle access

### Documentation
- **Comprehensive README** with installation and usage guides
- **Troubleshooting guide** for common issues
- **API documentation** for developers
- **Contributing guidelines** for community participation
- **Language support documentation** with full language list

### Known Issues
- Hash search requires local files (streaming content uses name search)
- Windows paths with special characters may cause issues
- Very large subtitle files (>5MB) may timeout on slow connections
- Some antivirus software may flag the auto-update feature

### Migration from Legacy vlsub
- **Automatic detection** of legacy vlsub installations
- **Configuration migration** from old XML format
- **Side-by-side compatibility** (can coexist with legacy version)
- **Clear differentiation** in VLC menu (shows as "VLSub OpenSubtitles.com")

---

## Version History Notes

### Versioning Scheme
- **Major.Minor.Patch** (e.g., 1.0.0)
- **Major**: Breaking changes or major new features
- **Minor**: New features, significant improvements
- **Patch**: Bug fixes, minor improvements

### Release Schedule
- **Major releases**: Every 6-12 months
- **Minor releases**: Every 2-3 months
- **Patch releases**: As needed for critical fixes

### Support Policy
- **Current version**: Full support with new features
- **Previous major version**: Security and critical bug fixes for 12 months
- **Legacy versions**: Community support only

---

*For older versions and detailed commit history, see the [GitHub releases page](https://github.com/opensubtitles/vlsub-opensubtitles-com/releases).*