# Frequently Asked Questions

## General Questions

### What is VLSub OpenSubtitles.com?

VLSub OpenSubtitles.com is a modern VLC Media Player extension for downloading subtitles from OpenSubtitles.com using their latest REST API. It provides enhanced features like multi-language support, automatic locale detection, and improved search algorithms.

### How is this different from the original vlsub?

| Feature | Original vlsub | VLSub OpenSubtitles.com |
|---------|----------------|-------------------------|
| API | XML-RPC (legacy) | REST API v2 (modern) |
| Subtitle Source | OpenSubtitles.org | OpenSubtitles.com |
| Authentication | Optional | Required |
| Languages | Single selection | Up to 3 languages |
| Auto-updates | No | Yes |
| Search Methods | Basic | Hash + Name + GuessIt |

### Do I need an OpenSubtitles.com account?

Yes, a free OpenSubtitles.com account is required. The modern API requires authentication for all requests. You can register for free at [opensubtitles.com](https://www.opensubtitles.com/newuser).

### Is this extension free?

Yes, the extension is completely free and open-source (GPL-3.0 license). However, OpenSubtitles.com has download quotas for free accounts. Premium accounts get higher quotas and additional features.

## Installation & Setup

### Which VLC versions are supported?

VLC Media Player 3.0 or newer is required. The extension has been tested with:
- VLC 3.0.x (all versions)
- VLC 4.0.x (when available)

### Why can't I see the extension in VLC's menu?

Common causes:
1. **Wrong location** - File must be in the correct extensions directory
2. **VLC not restarted** - Close VLC completely and restart
3. **Old VLC version** - Update to VLC 3.0+
4. **Syntax errors** - Re-download the file from official releases

### Can I use this alongside the original vlsub?

Yes, both extensions can coexist. They appear as separate menu items:
- "VLSub" (original)
- "VLSub OpenSubtitles.com" (this extension)

## Usage Questions

### Which search method should I use?

**Hash Search** (🎯):
- **Use for**: Local video files
- **Pros**: Exact synchronization matches
- **Cons**: Only works with local files

**Name Search** (🔍):
- **Use for**: Streaming content, renamed files
- **Pros**: Works with any content
- **Cons**: May require manual title adjustment

The extension automatically falls back from hash to name search when appropriate.

### Why do I get "No results found"?

**For Hash Search:**
- File must be local (not streaming)
- File must be accessible and not corrupted
- Subtitle may not exist for that specific file

**For Name Search:**
- Check title spelling and formatting
- Add year for movies, season/episode for TV shows
- Try different language selections
- Verify subtitle exists on OpenSubtitles.com

### How do I select multiple languages?

1. Open the extension interface
2. Use the three language dropdown menus:
   - "1. Subtitles Language" - Primary preference
   - "2. Subtitles Language" - Secondary preference  
   - "3. Subtitles Language" - Third preference
3. Results will be grouped by your language priorities

### Why don't subtitles load automatically?

Common causes:
1. **Wrong directory** - Subtitle must be in same folder as video
2. **Filename mismatch** - Subtitle name must match video name
3. **VLC settings** - Check Tools → Preferences → Subtitles/OSD
4. **Download behavior** - Set to "Load and save" in configuration

## Technical Questions

### What subtitle formats are supported?

The extension primarily downloads SRT format subtitles, which are universally supported by VLC. Some results may include:
- SubRip (.srt)
- WebVTT (.vtt) 
- ASS/SSA (.ass/.ssa)

### How does auto-detection work?

The extension detects your preferred languages using:
1. **System locale** - OS language settings
2. **IP geolocation** - Country-based language suggestions
3. **Timezone** - Regional language patterns
4. **VLC interface language**

### Why does the extension need internet access?

Internet access is required for:
- Searching OpenSubtitles.com database
- Downloading subtitle files
- User authentication
- Auto-update checks
- GuessIt metadata extraction

### How does the auto-update feature work?

The extension checks for updates:
- **Frequency**: Every 7 days by default
- **Method**: GitHub API to check latest release
- **User control**: Can skip versions or disable updates
- **Installation**: Downloads and replaces the extension file

## Account & Quota Questions

### What are the download limits?

**Free Accounts:**
- Limited daily downloads (varies by account age/activity)
- Standard download speed
- Basic features

**Premium Accounts:**
- Higher daily quotas
- Faster download speeds
- Priority support
- Additional features

### How do I check my quota?

After successful login, the extension displays:
- Current downloads used
- Total daily allowance
- Time until quota reset

### What happens when I exceed my quota?

When quota is exceeded:
- Downloads will fail with "quota exceeded" message
- Search still works normally
- Quota resets after 24 hours
- Consider upgrading to premium for higher limits

### Can I use the extension without an account?

No, the modern OpenSubtitles.com API requires authentication for all requests. Free account registration is available at opensubtitles.com.

## Troubleshooting

### The extension window shows errors

**Common solutions:**
1. **Restart VLC** completely
2. **Check internet connection**
3. **Verify OpenSubtitles.com credentials**
4. **Enable debug logging** for detailed error information

### Downloads fail consistently

**Check these factors:**
1. **Account status** - Ensure account isn't suspended
2. **Quota limits** - Check if daily limit exceeded
3. **Network connectivity** - Test internet connection
4. **Curl availability** - Verify curl command is installed

### Extension is slow or unresponsive

**Performance tips:**
1. **Clear cache files** in VLSub working directory
2. **Use wired internet** connection when possible
3. **Close other VLC instances**
4. **Restart VLC** periodically

### Auto-update doesn't work

**Common causes:**
1. **No internet connection** during update check
2. **Firewall blocking** GitHub API access
3. **File permissions** preventing write access
4. **Update interval** hasn't passed yet (7 days default)

## Development & Contributing

### Is the extension open source?

Yes, the extension is licensed under GPL-3.0 and hosted on GitHub at [opensubtitles/vlsub-opensubtitles-com](https://github.com/opensubtitles/vlsub-opensubtitles-com).

### How can I contribute?

You can contribute by:
- **Reporting bugs** with detailed information
- **Suggesting features** with clear use cases
- **Submitting code** improvements via pull requests
- **Improving documentation** and translations
- **Testing** new releases and providing feedback

### How do I report bugs?

1. **Search existing issues** to avoid duplicates
2. **Use the bug report template** on GitHub
3. **Include system information** and debug logs
4. **Provide clear steps** to reproduce the issue

### Can I request new features?

Yes! Feature requests are welcome. Please:
1. **Check existing requests** to avoid duplicates
2. **Use the feature request template**
3. **Explain the use case** and benefits
4. **Be patient** - this is a volunteer project

## Legal & Privacy

### What data does the extension collect?

The extension only sends data necessary for functionality:
- **Authentication** - Username/password to OpenSubtitles.com
- **Search queries** - Movie/TV show metadata for subtitle search
- **File hashes** - Calculated locally, used for exact subtitle matching
- **User agent** - Extension name/version for API identification

### Is my data shared with third parties?

No personal data is shared beyond what's necessary for OpenSubtitles.com API functionality. All data handling follows their privacy policy.

### Can I use this commercially?

Yes, the GPL-3.0 license allows commercial use. However, you must:
- **Provide source code** if distributing
- **Maintain GPL license** for derivative works
- **Credit original authors**

---

Still have questions? Check our [GitHub Discussions](https://github.com/opensubtitles/vlsub-opensubtitles-com/discussions) or [create an issue](https://github.com/opensubtitles/vlsub-opensubtitles-com/issues/new/choose).