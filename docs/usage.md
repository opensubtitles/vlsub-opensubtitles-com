# Usage Guide

This guide explains how to use VLSub OpenSubtitles.com extension effectively.

## First Time Setup

### Account Setup

1. **Create OpenSubtitles.com Account**
   - Visit [OpenSubtitles.com](https://www.opensubtitles.com/newuser)
   - Register for a free account
   - Verify your email address

2. **Configure Extension**
   - Open VLC → View → VLSub OpenSubtitles.com
   - Click "⚙️ Config" button
   - Enter your username and password
   - Click "💾 Save"

## Basic Usage

### Opening the Extension

1. Start VLC Media Player
2. Go to `View → VLSub OpenSubtitles.com`
3. The extension window will open

### Playing a Video

1. **Load your video file** in VLC first
2. **Open the extension** after the video starts
3. The extension will automatically detect video information

## Search Methods

### 🎯 Hash Search (Recommended)

**Best for:** Local video files

**How it works:**
- Calculates a unique fingerprint of your video file
- Finds subtitles that are perfectly synchronized
- Most accurate method for exact matches

**Steps:**
1. Ensure you have a local video file playing
2. Select your preferred language(s)
3. Click "🎯 Search by Hash"
4. Results will show perfectly matched subtitles

### 🔍 Name Search

**Best for:** Streaming content, renamed files, or when hash search fails

**How it works:**
- Uses the filename or manual title entry
- Integrates with GuessIt API for metadata extraction
- Searches by title, year, season, episode

**Steps:**
1. Enter or verify the title in the "Title" field
2. Add year, season, episode if applicable
3. Select your preferred language(s)
4. Click "🔍 Search by Name"

### Auto-Fallback

The extension automatically falls back from hash to name search when:
- Hash search returns no results
- Video is from a streaming source
- File cannot be accessed for hash calculation

## Language Selection

### Multiple Language Support

You can select up to 3 preferred languages:

1. **Primary Language**: Your main preference
2. **Secondary Language**: Fallback option
3. **Third Language**: Additional fallback

### Auto-Detection

The extension automatically detects your preferred languages based on:
- System locale settings
- Geographic location (IP-based)
- Timezone information
- Country-specific language preferences

### Language Priority

Search results are organized by your language preferences:
- Primary language subtitles appear first
- Secondary and third language subtitles follow
- Other languages appear at the bottom

## Downloading Subtitles

### Quick Download

**Double-click any subtitle** in the results list to:
- Download the subtitle file
- Save it with the same name as your video
- Automatically load it in VLC

### Manual Download

1. **Single-click** to select a subtitle
2. Click "📥 Download" button
3. Subtitle will be processed and loaded

### Link Access

1. Select a subtitle from the results
2. Click "🔗 Link" button
3. Opens the subtitle page in your browser

## Quality Indicators

Results show various quality indicators:

- 🎯 **Perfect match** - Moviehash synchronized
- ✓ **Trusted uploader** - Verified contributor
- 🎬 **HD quality** - High definition source
- ♿ **Hearing impaired** - Includes sound descriptions
- 🤖 **AI translated** - Machine translated
- ⚙️ **Machine translated** - Automatically translated

## Configuration Options

### Download Behavior

- **Load and save**: Downloads and saves subtitle file
- **Load only**: Loads subtitle without saving
- **Manual download**: Provides download link only

### File Naming

- **Language codes**: Add language code to filename (e.g., `movie.en.srt`)
- **Remove tags**: Clean subtitle formatting tags
- **Working directory**: Custom location for subtitle storage

### Update Settings

- **Auto-updates**: Enable/disable automatic update checks
- **Check interval**: How often to check for updates (default: 7 days)

## Troubleshooting

### No Results Found

**For Hash Search:**
- Ensure video file is local (not streaming)
- Check file integrity (not corrupted)
- Try name search as fallback

**For Name Search:**
- Verify title spelling
- Add year for better matching
- Try different language selections
- Check if subtitle exists on OpenSubtitles.com

### Download Failures

**Authentication Issues:**
- Verify OpenSubtitles.com credentials
- Check account status (not banned/suspended)
- Try logging out and back in

**Quota Exceeded:**
- Free accounts have daily download limits
- Wait until quota resets (usually 24 hours)
- Consider upgrading account for higher limits

**Network Issues:**
- Check internet connection
- Verify curl is installed and working
- Try again later if server is busy

### Extension Not Working

**Basic Troubleshooting:**
1. Restart VLC completely
2. Check for extension updates
3. Verify VLC version (3.0+ required)
4. Check VLC error messages (Tools → Messages)

**Advanced Troubleshooting:**
1. Enable debug logging:
   - Tools → Preferences → Show settings: All
   - Advanced → Logger verbosity: 2 (Debug)
2. Restart VLC and reproduce issue
3. Check Tools → Messages for detailed errors

## Advanced Features

### Batch Operations

For TV series episodes:
1. Use consistent naming (e.g., `Show.S01E01.mkv`)
2. Search by name with season/episode
3. Results will include series-specific matches

### Custom Metadata

You can manually override detected information:
- Edit title, year, season, episode fields
- Useful for incorrectly detected content
- Changes apply only to current search

### Keyboard Shortcuts

- **Double-click**: Quick download
- **Enter**: Download selected subtitle
- **F5**: Refresh/retry search
- **Escape**: Close extension window

## Best Practices

### File Organization

```
Movies/
├── Movie.Name.2023.1080p.mkv
└── Movie.Name.2023.1080p.en.srt

TV.Shows/
├── Show.Name/
│   ├── Season.01/
│   │   ├── Show.Name.S01E01.mkv
│   │   └── Show.Name.S01E01.en.srt
```

### Naming Conventions

- Use clear, descriptive filenames
- Include year for movies
- Use S##E## format for TV shows
- Avoid special characters in paths (Windows)

### Language Strategy

1. Set your native language as primary
2. Choose English as secondary (most content available)
3. Select regional language as third option

## Support and Help

- **Documentation**: [GitHub Repository](https://github.com/opensubtitles/vlsub-opensubtitles-com)
- **Issues**: [Report bugs](https://github.com/opensubtitles/vlsub-opensubtitles-com/issues)
- **Discussions**: [Community forum](https://github.com/opensubtitles/vlsub-opensubtitles-com/discussions)
