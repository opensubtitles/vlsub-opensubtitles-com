# Changelog

All notable changes to VLSub OpenSubtitles.com extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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