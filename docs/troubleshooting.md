# Troubleshooting Guide

Common issues and their solutions for VLSub OpenSubtitles.com extension.

## Installation Issues

### Extension Not Appearing in VLC Menu

**Symptoms:** VLSub OpenSubtitles.com doesn't appear in View menu

**Solutions:**

1. **Check file location**
   ```bash
   # Verify file exists in correct location
   # Windows: %APPDATA%\vlc\lua\extensions\vlsubcom.lua
   # macOS: ~/Library/Application Support/org.videolan.vlc/lua/extensions/vlsubcom.lua
   # Linux: ~/.local/share/vlc/lua/extensions/vlsubcom.lua
   ```

2. **Verify file integrity**
   - File should be around 100-200KB
   - Re-download if file seems corrupted

3. **Check VLC version**
   - Requires VLC 3.0 or newer
   - Update VLC if necessary

4. **Restart VLC completely**
   - Close all VLC windows
   - Wait a few seconds
   - Restart VLC

5. **Check file permissions (Linux/macOS)**
   ```bash
   chmod 644 ~/.local/share/vlc/lua/extensions/vlsubcom.lua
   ```

### Syntax Errors on Load

**Symptoms:** Extension appears but shows Lua syntax errors

**Solutions:**

1. **Re-download the file**
   - Download from official releases page
   - Ensure complete download (no partial files)

2. **Check file encoding**
   - File should be UTF-8 encoded
   - Avoid copying from web browsers (may corrupt encoding)

3. **Antivirus interference**
   - Some antivirus software may modify Lua files
   - Add extension to antivirus whitelist

## Authentication Issues

### Login Failed

**Symptoms:** "Authentication failed" or "Invalid credentials"

**Solutions:**

1. **Verify credentials**
   - Double-check username and password
   - Try logging in at opensubtitles.com website
   - Ensure account is active (not banned)

2. **Clear saved credentials**
   - Delete configuration file
   - Re-enter credentials fresh

3. **Account issues**
   - Verify email address if newly registered
   - Check for account suspension emails
   - Reset password if necessary

4. **Network/proxy issues**
   - Check internet connection
   - Disable VPN temporarily
   - Configure proxy settings if needed

### Session Expired

**Symptoms:** "Session expired, retrying" messages

**Solutions:**

1. **Normal behavior** - Extension automatically retries
2. **Persistent issues** - Clear session cache and re-login
3. **Network stability** - Check for intermittent connection issues

## Search Issues

### No Results Found

**Symptoms:** Search completes but shows "No result"

**Hash Search Troubleshooting:**

1. **File accessibility**
   - Ensure file is local (not streaming)
   - Check file isn't corrupted
   - Verify file size > 64KB

2. **File format support**
   - Works with most video formats (MP4, MKV, AVI, etc.)
   - Some exotic formats may not be supported

3. **Fallback to name search**
   - Extension automatically tries name search
   - Manually trigger name search if needed

**Name Search Troubleshooting:**

1. **Title accuracy**
   - Check spelling of movie/show title
   - Try alternative titles (original vs. translated)
   - Remove special characters

2. **Metadata issues**
   - Add year for movies
   - Specify season/episode for TV shows
   - Try simpler search terms

3. **Language availability**
   - Check if subtitles exist for selected languages
   - Try searching with "All" languages
   - Popular content has more subtitle options

### Search Hangs or Times Out

**Symptoms:** Search never completes or shows timeout errors

**Solutions:**

1. **Network connectivity**
   ```bash
   # Test connection to OpenSubtitles API
   curl -I https://api.opensubtitles.com/api/v1/
   ```

2. **Firewall/antivirus blocking**
   - Allow VLC through firewall
   - Whitelist OpenSubtitles.com domains
   - Temporarily disable antivirus

3. **Server overload**
   - Try again during off-peak hours
   - Check OpenSubtitles.com status page

## Download Issues

### Download Failed

**Symptoms:** "Download failed" or "Unable to download subtitle"

**Solutions:**

1. **Quota exceeded**
   - Free accounts have daily limits
   - Wait for quota reset (24 hours)
   - Check account status on website

2. **File permissions**
   ```bash
   # Ensure write permissions to video directory
   # Or set custom working directory in config
   ```

3. **Curl dependency**
   ```bash
   # Verify curl is installed
   curl --version
   
   # Install if missing:
   # Windows: Install Git for Windows or use Windows Subsystem for Linux
   # macOS: Usually pre-installed, or install via Homebrew
   # Linux: sudo apt install curl (Ubuntu/Debian)
   ```

4. **Network issues**
   - Check internet connection
   - Try downloading manually via link
   - Verify OpenSubtitles.com accessibility

### Subtitle Not Loading in VLC

**Symptoms:** Download succeeds but subtitle doesn't appear

**Solutions:**

1. **Automatic loading issues**
   - Ensure subtitle file is in same directory as video
   - Check filename matches video (except extension)
   - Verify subtitle format (should be .srt)

2. **Manual loading**
   - VLC: Subtitle → Add Subtitle File
   - Select the downloaded subtitle manually

3. **Subtitle encoding**
   - Try different subtitle from search results
   - Some subtitles may have encoding issues

4. **VLC subtitle settings**
   - VLC: Tools → Preferences → Subtitles/OSD
   - Ensure subtitles are enabled
   - Check font and size settings

## Performance Issues

### Extension Slow to Load

**Symptoms:** Long delays when opening extension

**Solutions:**

1. **Clear cache files**
   ```bash
   # Delete cache files in VLSub working directory
   rm session_cache.json
   rm cache_subtitle_languages.json
   ```

2. **Network optimization**
   - Use wired connection instead of WiFi
   - Close bandwidth-heavy applications
   - Try different DNS servers (8.8.8.8, 1.1.1.1)

3. **VLC optimization**
   - Close other VLC instances
   - Disable unnecessary VLC extensions
   - Restart VLC periodically

### High CPU Usage

**Symptoms:** VLC consumes excessive CPU when using extension

**Solutions:**

1. **Update VLC** to latest version
2. **Reduce simultaneous operations**
   - Don't search while video is loading
   - Wait for one operation to complete

3. **System resources**
   - Close other applications
   - Check for malware/background processes

## Debug Information

### Enabling Debug Mode

1. **VLC Debug Logging**
   ```
   Tools → Preferences → Show settings: All
   Advanced → Logger verbosity: 2 (Debug)
   ```

2. **Restart VLC** and reproduce issue

3. **View debug output**
   ```
   Tools → Messages
   Look for [VLSub] prefixed messages
   ```

### Common Debug Messages

**Normal Messages:**
```
[VLSub] Starting activation
[VLSub] Configuration check passed
[VLSub] JSON module loaded successfully
[VLSub] Using cached session
[VLSub] Hash search completed
```

**Error Messages:**
```
[VLSub] CRITICAL: JSON module load failed
[VLSub] Network test failed
[VLSub] Authentication failed
[VLSub] Download failed with status: 429
```

### Collecting Debug Information

When reporting issues, include:

1. **System information**
   - Operating System and version
   - VLC version
   - Extension version

2. **Error messages**
   - Complete error text
   - VLC debug log excerpt

3. **Steps to reproduce**
   - Exact sequence of actions
   - Video file information (format, size, source)

4. **Network information**
   - Internet connection type
   - Proxy/VPN usage
   - Firewall software

## Advanced Troubleshooting

### Manual API Testing

Test OpenSubtitles.com API directly:

```bash
# Test API connectivity
curl -H "Api-Key: YOUR_API_KEY" \
     -H "User-Agent: VLSub-Test" \
     "https://api.opensubtitles.com/api/v1/infos/languages"

# Test authentication
curl -X POST \
     -H "Api-Key: YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"username":"your_username","password":"your_password"}' \
     "https://api.opensubtitles.com/api/v1/login"
```

### Configuration Reset

Complete configuration reset:

1. **Close VLC completely**
2. **Delete configuration files**
   ```bash
   # Navigate to VLSub working directory and delete:
   rm vlsub_conf.json
   rm session_cache.json
   rm cache_subtitle_languages.json
   rm last_update_check.txt
   rm skip_version.txt
   ```
3. **Restart VLC** and reconfigure

### Reinstallation

Clean reinstallation process:

1. **Uninstall current version**
   ```bash
   # Delete extension file
   rm vlsubcom.lua
   
   # Delete configuration (optional)
   rm -rf vlsub.com/
   ```

2. **Download latest version** from releases page

3. **Follow installation guide** from beginning

## Getting Help

### Before Seeking Help

1. **Search existing issues** on GitHub
2. **Check documentation** thoroughly
3. **Try basic troubleshooting** steps
4. **Collect debug information**

### Where to Get Help

1. **GitHub Issues** - For bugs and technical problems
   - Provide system information
   - Include debug logs
   - Describe steps to reproduce

2. **GitHub Discussions** - For usage questions
   - General usage questions
   - Feature discussions
   - Community support

3. **OpenSubtitles.com Support** - For account issues
   - Account problems
   - API access issues
   - Billing questions (premium accounts)

### Information to Include

When seeking help, always provide:

```
**System Information:**
- OS: [Windows 11 / macOS 14.1 / Ubuntu 22.04]
- VLC Version: [3.0.18]
- Extension Version: [1.0.0]

**Problem Description:**
[Clear description of the issue]

**Steps to Reproduce:**
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected vs Actual Behavior:**
Expected: [What should happen]
Actual: [What actually happens]

**Debug Log:**
```
[Paste relevant VLC debug messages here]
```

**Additional Context:**
[Any other relevant information]
```

This format helps maintainers and community members provide faster, more accurate help.