--[[
--I have this vlc extension. if user run it, set up his credentials, but there is no film loaded, he write something for search, then some results come, and then click download it is buggy. Actually nothing is downloade

================================================================================
VLSub OpenSubtitles.com Extension for VLC Media Player 3.0+
================================================================================

DESCRIPTION:
A modern VLC extension for downloading subtitles from OpenSubtitles.com using 
their latest REST API v2. This extension provides smart search capabilities,
multi-language support, automatic metadata detection, and enhanced performance
compared to legacy XML-RPC based extensions.

FEATURES:
- 🔍 Smart Search: Hash-based + name-based search with GuessIt integration
- 🌐 Multi-language Support: Up to 3 preferred languages with prioritization
- 🎯 Auto-detection: System locale, timezone, and IP geolocation detection
- 📱 Modern API: OpenSubtitles.com REST API v2 for better performance
- 🔄 Auto-updates: Built-in update mechanism
- 🎬 Smart Metadata: GuessIt API integration for movie/TV show detection
- 🏆 Quality Indicators: Trusted uploaders, download counts, sync quality
- 💾 Flexible Download: Auto-load or manual save with language codes
- 🌍 Country-specific: Intelligent language suggestions

REQUIREMENTS:
- VLC Media Player 3.0 or newer
- OpenSubtitles.com account (free registration required)
- Internet connection for searching and downloading
- curl command-line tool (for downloads - usually pre-installed)

INSTALLATION:
Quick Install (Recommended):
  macOS/Linux: curl -sSL https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/scripts/install.sh | bash
  Windows: iwr -useb https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/scripts/install.ps1 | iex

Manual Install:
1. Download vlsubcom.lua from: https://github.com/opensubtitles/vlsub-opensubtitles-com/releases
2. Copy to VLC extensions directory:
   - Windows: %APPDATA%\vlc\lua\extensions\
   - macOS: ~/Library/Application Support/org.videolan.vlc/lua/extensions/
   - Linux: ~/.local/share/vlc/lua/extensions/
3. Restart VLC Media Player
4. Access via View → VLSub OpenSubtitles.com

USAGE:
1. Setup: Open VLC → View → VLSub OpenSubtitles.com → Config
2. Login: Enter your OpenSubtitles.com username and password
3. Play: Start your video file
4. Search: Click "🎯 Search by Hash" or "🔍 Search by Name"
5. Download: Double-click any subtitle to download and load automatically

SUPPORTED LANGUAGES:
100+ languages including major languages (English, Spanish, French, German, 
Italian, Portuguese, Russian, Chinese, Japanese, Korean), regional variants,
and all EU languages.

TROUBLESHOOTING:
- "No results found": Ensure video is local for hash search, try name search
- "Authentication failed": Verify credentials and internet connection
- "Download failed": Check quota limits, verify curl installation
- Extension not visible: Restart VLC, check installation directory

DEBUG LOGGING:
Enable in VLC: Tools → Preferences → Show settings: All → Advanced → 
Logger verbosity: 2 (Debug)

API COMPARISON:
                    Legacy vlsub (.org)    VLSub OpenSubtitles.com
API                 XML-RPC (legacy)       REST API v2 (modern)
Authentication      Optional               Required (free account)
Language Selection  Single language        Up to 3 with priority
Search Methods      Basic hash/name        Hash + Name + GuessIt
Auto-updates        None                   Built-in system
Performance         Slower XML parsing     Fast JSON API

TODO:

- Integrate AI translation/transcription (ai.opensubtitles.com)
- Code cleanup and optimization

PROJECT LINKS:
Repository: https://github.com/opensubtitles/vlsub-opensubtitles-com/
Issues: https://github.com/opensubtitles/vlsub-opensubtitles-com/issues
Documentation: https://github.com/opensubtitles/vlsub-opensubtitles-com/blob/main/docs/
OpenSubtitles.com: https://www.opensubtitles.com/
Contact: https://www.opensubtitles.com/en/contact/

================================================================================
COPYRIGHT & LICENSE:
================================================================================

Copyright 2025 OpenSubtitles.com
Based on original work Copyright 2013 Guillaume Le Maout

Authors: 
- OpenSubtitles.com Team
- Guillaume Le Maout (original vlsub author)
- Additional Development: Enhanced with assistance from Claude (Anthropic AI)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

================================================================================
VERSION HISTORY & CHANGELOG:
================================================================================

For detailed version history and changelog, see:
https://github.com/opensubtitles/vlsub-opensubtitles-com/releases

Latest changes can be found in the repository commit history:
https://github.com/opensubtitles/vlsub-opensubtitles-com/commits/main

================================================================================

--]]

            --[[ Global var ]]-- 

local app_name = "VLSub OpenSubtitles.com";
local app_version = "1.1.6";
local app_useragent = app_name.." "..app_version;

local config = {
  api_key = "d3Sba6j6VYnty3ir5T8GXYoAuiLSBf0S",
  cache_languages_duration_seconds = 30 * 24 * 60 * 60, -- 30 days in seconds
  api_languages_url = "https://api.opensubtitles.com/api/v1/infos/languages",
  token_cache_duration_seconds = 24 * 60 * 60, -- 24 hours in seconds
  login_api_url = "https://api.opensubtitles.com/api/v1/login",
  guessit_api_url = "https://api.opensubtitles.com/api/v1/utilities/guessit"  -- Add GuessIt URL
}

-- Auto-update configuration
local update_config = {
  check_url = "https://api.github.com/repos/opensubtitles/vlsub-opensubtitles-com/releases/latest",
  current_version = app_version, -- Uses existing app_version variable
  check_interval_seconds = 24 * 60 * 60, -- 24 hours
  last_check_file = "last_update_check.json"
}

-- First, update the options structure to support 3 languages
local options = {
  language = nil,
  language2 = nil,  -- Second language
  language3 = nil,  -- Third language
  downloadBehaviour = 'save',
  langExt = true,
  removeTag = false,
  showMediaInformation = true,
  progressBarSize = 80,
  intLang = 'eng',
  translations_avail = {
    eng = 'English',
    cze = 'Czech', 
    dan = 'Danish', 
    dut = 'Nederlands',
    fin = 'Finnish',
    fre = 'Français',
    ell = 'Greek',
    baq = 'Basque',
    pob = 'Brazilian Portuguese',
    por = 'Portuguese (Portugal)',
    rum = 'Romanian',
    slo = 'Slovak',
    spa = 'Spanish',
    swe = 'Swedish',
    ukr = 'Ukrainian',
    hun = 'Hungarian',
    scc = 'Serbian'
  },
  translation = {
    int_all = 'All',
    int_descr = 'Download subtitles from OpenSubtitles.com',
    int_research = 'Search',
    int_config = 'Config',
    int_configuration = 'Configuration',
    int_help = 'Help',
    int_search_hash = 'Search by hash',
    int_search_name = 'Search by name',
    int_title = 'Title',
    int_season = 'TV Season',
    int_episode = 'TV Episode',
    int_show_help = 'Help',
    int_show_conf = 'Config',
    int_dowload_sel = 'Download selected',
    int_close = 'Close',
    int_ok = 'Ok',
    int_save = 'Save',
    int_cancel = 'Cancel',
    int_bool_true = 'Yes',
    int_bool_false = 'No',
    int_search_transl = 'Search translations',
    int_searching_transl = 'Searching translations ...',
    int_int_lang = 'Interface language',
    int_default_lang = '1. Subtitles Language',           -- Updated
    int_second_lang = '2. Subtitles Language',            -- Updated
    int_third_lang = '3. Subtitles Language',             -- Updated
    int_dowload_behav = 'What to do with subtitles',
    int_dowload_save = 'Load and save',
    int_dowload_load = 'Load only',
    int_dowload_manual =  'Manual download',
    int_display_code = 'Save language code in file name',
    int_remove_tag = 'Remove tags',
    int_vlsub_work_dir = 'VLSub working directory',
    int_os_username = 'OpenSubtitles.com Username',
    int_os_password = 'OpenSubtitles.com Password',
  
    action_login = 'Logging in',
    action_logout = 'Logging out',
    action_noop = 'Checking session',
    action_search = 'Searching subtitles',
    action_hash = 'Calculating movie hash',
    
    mess_success = 'Success',
    mess_error = 'Error',
    mess_no_response = 'Server not responding',
    mess_unauthorized = 'Request unauthorized',
    mess_expired = 'Session expired, retrying',
    mess_overloaded = 'Server overloaded, please retry later',
    mess_no_input = 'Please use this method during playing',
    mess_not_local = 'This method works with local file only (for now)',
    mess_not_found = 'File not found',
    mess_not_found2 = 'File not found (illegal character?)',
    mess_no_selection = 'No subtitles selected',
    mess_save_fail = 'Unable to save subtitles',
    mess_click_link = 'Click here to open the file',
    mess_complete = 'Search complete',
    mess_no_res = 'No result',
    mess_res = 'result(s)',
    mess_loaded = 'Subtitles loaded',
    mess_not_load = 'Unable to load subtitles',
    mess_downloading = 'Downloading subtitle',
    mess_dowload_link = 'Download link',
    mess_err_conf_access ='Can\'t find a suitable path to save'..
      'config, please set it manually',
    mess_err_wrong_path ='the path contains illegal character, '..
      'please correct it',
    mess_err_cant_download_interface_translation='could not download interface translation'
  }
}

-- must be here for backward compatibility
local languages = {
  {'eng', 'English'},
}

-- default subtitle languages
local sub_languages = {
    { language_code = "ab", language_name = "Abkhazian" },
    { language_code = "af", language_name = "Afrikaans" },
    { language_code = "sq", language_name = "Albanian" },
    { language_code = "am", language_name = "Amharic" },
    { language_code = "ar", language_name = "Arabic" },
    { language_code = "an", language_name = "Aragonese" },
    { language_code = "hy", language_name = "Armenian" },
    { language_code = "as", language_name = "Assamese" },
    { language_code = "at", language_name = "Asturian" },
    { language_code = "az-az", language_name = "Azerbaijani" },
    { language_code = "az-zb", language_name = "South Azerbaijani" },
    { language_code = "eu", language_name = "Basque" },
    { language_code = "be", language_name = "Belarusian" },
    { language_code = "bn", language_name = "Bengali" },
    { language_code = "bs", language_name = "Bosnian" },
    { language_code = "br", language_name = "Breton" },
    { language_code = "my", language_name = "Burmese" },
    { language_code = "ca", language_name = "Catalan" },
    { language_code = "zh-ca", language_name = "Chinese (Cantonese)" },
    { language_code = "ze", language_name = "Chinese bilingual" },
    { language_code = "zh-cn", language_name = "Chinese (simplified)" },
    { language_code = "zh-tw", language_name = "Chinese (traditional)" },
    { language_code = "hr", language_name = "Croatian" },
    { language_code = "cs", language_name = "Czech" },
    { language_code = "da", language_name = "Danish" },
    { language_code = "pr", language_name = "Dari" },
    { language_code = "nl", language_name = "Dutch" },
    { language_code = "en", language_name = "English" },
    { language_code = "eo", language_name = "Esperanto" },
    { language_code = "et", language_name = "Estonian" },
    { language_code = "ex", language_name = "Extremaduran" },
    { language_code = "tl", language_name = "Tagalog" },
    { language_code = "fi", language_name = "Finnish" },
    { language_code = "fr", language_name = "French" },
    { language_code = "gd", language_name = "Gaelic" },
    { language_code = "gl", language_name = "Galician" },
    { language_code = "ka", language_name = "Georgian" },
    { language_code = "de", language_name = "German" },
    { language_code = "el", language_name = "Greek" },
    { language_code = "he", language = "Hebrew" },
    { language_code = "hi", language_name = "Hindi" },
    { language_code = "hu", language_name = "Hungarian" },
    { language_code = "is", language_name = "Icelandic" },
    { language_code = "ig", language_name = "Igbo" },
    { language_code = "id", language_name = "Indonesian" },
    { language_code = "ia", language_name = "Interlingua" },
    { language_code = "it", language_name = "Italian" },
    { language_code = "ja", language_name = "Japanese" },
    { language_code = "kn", language_name = "Kannada" },
    { language_code = "kk", language_name = "Kazakh" },
    { language_code = "km", language_name = "Khmer" },
    { language_code = "ko", language_name = "Korean" },
    { language_code = "ku", language_name = "Kurdish" },
    { language_code = "lv", language_name = "Latvian" },
    { language_code = "lt", language_name = "Lithuanian" },
    { language_code = "lb", language_name = "Luxembourgish" },
    { language_code = "ma", language_name = "Manipuri" },
    { language_code = "mk", language_name = "Macedonian" },
    { language_code = "ml", language_name = "Malayalam" },
    { language_code = "ms", language_name = "Malay" },
    { language_code = "mr", language_name = "Marathi" },
    { language_code = "me", language_name = "Montenegrin" },
    { language_code = "mn", language_name = "Mongolian" },
    { language_code = "nv", language_name = "Navajo" },
    { language_code = "ne", language_name = "Nepali" },
    { language_code = "no", language_name = "Norwegian" },
    { language_code = "oc", language_name = "Occitan" },
    { language_code = "or", language_name = "Odia" },
    { language_code = "pm", language_name = "Portuguese (MZ)" },
    { language_code = "pt-pt", language_name = "Portuguese" },
    { language_code = "pt-br", language_name = "Portuguese (BR)" },
    { language_code = "ps", language_name = "Pushto" },
    { language_code = "ro", language_name = "Romanian" },
    { language_code = "ru", language_name = "Russian" },
    { language_code = "se", language_name = "Northern Sami" },
    { language_code = "sx", language_name = "Santali" },
    { language_code = "sd", language_name = "Sindhi" },
    { language_code = "si", language_name = "Sinhalese" },
    { language_code = "sk", language_name = "Slovak" },
    { language_code = "sl", language_name = "Slovenian" },
    { language_code = "so", language_name = "Somali" },
    { language_code = "es", language_name = "Spanish" },
    { language_code = "ea", language_name = "Spanish (LA)" },
    { language_code = "sp", language_name = "Spanish (EU)" },
    { language_code = "sv", language_name = "Swedish" },
    { language_code = "sy", language_name = "Syriac" },
    { language_code = "ta", language_name = "Tamil" },
    { language_code = "tt", language_name = "Tatar" },
    { language_code = "te", language_name = "Telugu" },
    { language_code = "tm-td", language_name = "Tetum" },
    { language_code = "th", language_name = "Thai" },
    { language_code = "tp", language_name = "Toki Pona" },
    { language_code = "tr", language_name = "Turkish" },
    { language_code = "tk", language_name = "Turkmen" },
    { language_code = "uk", language_name = "Ukrainian" },
    { language_code = "ur", language_name = "Urdu" },
    { language_code = "uz", language_name = "Uzbek" },
    { language_code = "vi", language_name = "Vietnamese" },
    { language_code = "cy", language_name = "Welsh" }
}




-- initial declarations

local json = nil
local curl = nil 
local dlg = nil
local input_table = {} -- General widget id reference
local select_conf = {} -- Drop down widget / option table association 

-- Add a global variable to track the previous window
local previous_window = "main" -- Default to main window

-- Add global variable to track authentication status
local is_authenticated = false

local debug_dlg = nil
local initialization_complete = false
local debug_messages = {}
local debug_log_rows = {} -- Array for individual debug log rows

local configurationPassed = false
local jsonModuleLoaded = false
local networkTestsFailed = false
local curlAvailable = false
local criticalFailure = false


-- Store initialization results for later use
local init_results = {
  is_first_run = false,
  has_auth = false
}


local Curl = {}
Curl.__index = Curl



local last_click_time = 0
local last_click_item = 0
local double_click_threshold = 500 -- milliseconds


            --[[ VLC extension stuff ]]--

function descriptor()
  return { 
    title = app_useragent,
    version = app_version,
    author = "OpenSubtitles",
    url = 'http://www.opensubtitles.com/',
    shortdesc = app_name;
    description = options.translation.int_descr,
    capabilities = {"menu", "input-listener" }
  }
end

function check_cli_curl()
    local handle
    if openSub.conf.os == "win" then
        handle = io.popen("where curl >nul 2>&1 && echo found")
    else
        handle = io.popen("command -v curl 2>/dev/null")
    end
    
    if handle then
        local result = handle:read("*a")
        handle:close()
        
        if openSub.conf.os == "win" then
            -- On Windows, check for "found" string
            if not result or result == "" or not result:match("found") then
                vlc.msg.err("[VLSub] 'curl' command-line tool is not available. Some features may not work.")
                return false
            end
        else
            -- On macOS/Linux, check if we got a path back (non-empty result)
            if not result or result:gsub("%s+", "") == "" then
                vlc.msg.err("[VLSub] 'curl' command-line tool is not available. Some features may not work.")
                return false
            else
                vlc.msg.dbg("[VLSub] curl found at: " .. result:gsub("%s+", ""))
            end
        end
    else
        vlc.msg.err("[VLSub] Unable to check for curl command availability.")
        return false
    end
    return true
end

-- Modified activate function - only detect locale/IP if user has no preferences
function activate()
  vlc.msg.dbg("[VLSub] Starting activation with debug window")
  
  -- Reset status tracking variables
  configurationPassed = false
  jsonModuleLoaded = false
  networkTestsFailed = false
  curlAvailable = false
  criticalFailure = false
  
  -- Show debug window immediately
  show_debug_window()
  update_debug_progress("Initializing VLSub...")
  append_debug_log("VLSub activation started")
  
  -- Test network first
  local has_network = test_network_connectivity()
  if not has_network then
    networkTestsFailed = true
  end
  
  -- JSON module check
  update_debug_progress("Loading JSON module...")
  local json_ok, json_module = pcall(require, "dkjson")
  if not json_ok then
    update_debug_status("ERROR: Failed to load JSON module")
    append_debug_log("CRITICAL: JSON module load failed: " .. tostring(json_module))
    criticalFailure = true
    return false
  end
  json = json_module
  jsonModuleLoaded = true
  append_debug_log("JSON module loaded successfully")
  
  -- Config check
  update_debug_progress("Checking configuration...")
  if not check_config() then 
    update_debug_status("ERROR: Unsupported VLC version")
    append_debug_log("CRITICAL: VLC version not supported")
    criticalFailure = true
    return false
  end
  configurationPassed = true
  append_debug_log("Configuration check passed")
  
  -- Curl availability check
  update_debug_progress("Checking curl availability...")
  pcall(function()
    if not check_cli_curl() then
      curlAvailable = false
      update_debug_status("WARNING: curl not available")
      append_debug_log("WARNING: curl command not found - some features may not work")
    else
      curlAvailable = true
      append_debug_log("curl command available")
    end
  end)
  
  -- Language initialization
  update_debug_progress("Loading subtitle languages...")
  convert_sub_languages()
  languages = sub_languages
  openSub.conf.languages = languages
  
  if has_network then
    update_debug_status("Initializing languages from API...")
    pcall(function()
      initialize_languages()
      append_debug_log("Language list loaded from API")
    end)
  else
    update_debug_status("Using offline language list...")
    append_debug_log("Using built-in language list (offline mode)")
  end
  
  -- MODIFIED: Only detect locale if user has no language preferences set
  update_debug_progress("Checking user preferences...")
  local has_user_preferences = check_user_has_language_preferences()
  
  if has_user_preferences then
    append_debug_log("User has language preferences - skipping locale detection")
    vlc.msg.dbg("[VLSub] User has preferences set, skipping IP/locale detection")
  else
    append_debug_log("No user preferences found - detecting locale...")
    
    local is_first_run_detected = is_first_run()
    
    if is_first_run_detected then
      append_debug_log("First run detected")
    end
    
    -- Enhanced locale detection with debug output
    vlc.msg.dbg("[VLSub] Starting locale detection...")
    append_debug_log("Starting locale detection...")
    
    local saved_user_pref = nil
    if is_first_run_detected then
      saved_user_pref = openSub.option.language
      openSub.option.language = nil
      append_debug_log("Temporarily cleared user preference for clean detection")
    end
    
    local detected_locale = detect_user_locale()
    
    if saved_user_pref then
      openSub.option.language = saved_user_pref
    end
    
    if detected_locale then
      append_debug_log("Locale detected: " .. detected_locale.locale .. " from " .. detected_locale.source)
      
      if detected_locale.suggested_languages and #detected_locale.suggested_languages > 0 then
        local lang_codes = {}
        for i, suggestion in ipairs(detected_locale.suggested_languages) do
          table.insert(lang_codes, suggestion.language)
        end
        append_debug_log("Found " .. #detected_locale.suggested_languages .. " suggested languages: " .. table.concat(lang_codes, ", "))

        
        for i, suggestion in ipairs(detected_locale.suggested_languages) do
          local os_lang = map_to_opensubtitles_language(suggestion.language)
          
          local found_language = false
          for j, lang_pair in ipairs(openSub.conf.languages) do
            if lang_pair[1] == os_lang or lang_pair[1] == suggestion.language then
              found_language = true
              
              if i == 1 and (not openSub.option.language or openSub.option.language == "") then
                openSub.option.language = lang_pair[1]
                append_debug_log("Set primary language: " .. lang_pair[1])
              elseif i == 2 and (not openSub.option.language2 or openSub.option.language2 == "") then
                openSub.option.language2 = lang_pair[1]
                append_debug_log("Set secondary language: " .. lang_pair[1])
              elseif i == 3 and (not openSub.option.language3 or openSub.option.language3 == "") then
                openSub.option.language3 = lang_pair[1]
                append_debug_log("Set third language: " .. lang_pair[1])
              end
              break
            end
          end
          
          if not found_language then
            append_debug_log("Language not available: " .. os_lang)
          end
        end
        
        if is_first_run_detected then
          update_debug_progress("Saving auto-detected settings...")
          local auto_save_success = save_config()
          if auto_save_success then
            append_debug_log("Auto-detected settings saved")
          else
            append_debug_log("Failed to save auto-detected settings")
          end
        end
      end
    else
      append_debug_log("Could not detect user locale")
    end
  end
  
  -- File info initialization
  update_debug_progress("Getting file information...")
  if vlc.input.item() then
    openSub.getFileInfo()
    openSub.getMovieInfo()
    append_debug_log("File info loaded for current media")
  else
    append_debug_log("No media loaded")
  end
  
  -- Authentication check
  update_debug_progress("Checking authentication...")
  local username = trim(openSub.option.os_username or "")
  local password = trim(openSub.option.os_password or "")
  local has_credentials = (username ~= "" and password ~= "")
  local has_valid_session = has_valid_authentication()
  
  vlc.msg.dbg("[VLSub] Authentication status:")
  vlc.msg.dbg("[VLSub]   - username: '" .. username .. "'")
  vlc.msg.dbg("[VLSub]   - password: " .. (password ~= "" and "[set]" or "[empty]"))
  vlc.msg.dbg("[VLSub]   - has_credentials: " .. tostring(has_credentials))
  vlc.msg.dbg("[VLSub]   - has_valid_session: " .. tostring(has_valid_session))
  
  is_authenticated = has_credentials or has_valid_session
  
  if is_authenticated then
    append_debug_log("Valid authentication found - credentials available")
  else
    append_debug_log("No valid authentication - missing credentials")
  end
  
  -- Store results for when debug window closes
  init_results.is_first_run = not has_user_preferences
  init_results.has_auth = is_authenticated
  
  vlc.msg.dbg("[VLSub] Storing initialization results:")
  vlc.msg.dbg("[VLSub]   - is_first_run: " .. tostring(init_results.is_first_run))
  vlc.msg.dbg("[VLSub]   - has_auth: " .. tostring(init_results.has_auth))
  
  -- Mark initialization as complete
  initialization_complete = true
  
  -- Determine final status and auto-close if appropriate
  update_debug_progress("Initialization complete!")
  append_debug_log("Initialization complete - checking for auto-close...")
  
  if not has_user_preferences then
    append_debug_log("Ready to show configuration window (no preferences)")
  else
    if init_results.has_auth then
      is_authenticated = true
      append_debug_log("Ready to show main window (authenticated)")
    else
      is_authenticated = false
      append_debug_log("Ready to show configuration window (no auth)")
    end
  end
  
  -- Check if we should auto-close
  checkInitializationStatus()

  -- Initialize auto-update checking
  update_debug_progress("Initializing auto-update system...")
  append_debug_log("Setting up automatic update checking...")
  initialize_auto_update()
  
  vlc.msg.dbg("[VLSub] Activation complete")
end


-- NEW FUNCTION: Check if user has language preferences set
function check_user_has_language_preferences()
  -- Check if user has any language preferences configured
  local has_primary = openSub.option.language and openSub.option.language ~= ""
  local has_secondary = openSub.option.language2 and openSub.option.language2 ~= ""
  local has_tertiary = openSub.option.language3 and openSub.option.language3 ~= ""
  
  vlc.msg.dbg("[VLSub] Checking user language preferences:")
  vlc.msg.dbg("[VLSub]   - Primary language: " .. (openSub.option.language or "none"))
  vlc.msg.dbg("[VLSub]   - Secondary language: " .. (openSub.option.language2 or "none"))
  vlc.msg.dbg("[VLSub]   - Tertiary language: " .. (openSub.option.language3 or "none"))
  
  local has_preferences = has_primary or has_secondary or has_tertiary
  vlc.msg.dbg("[VLSub]   - Has language preferences: " .. tostring(has_preferences))
  
  return has_preferences
end


-- Also update the build command to be more Windows-friendly
function Curl:_build_command(method, url, data)
    local cmd = {}
    
    -- Start with basic curl command
    table.insert(cmd, 'curl')
    table.insert(cmd, '-s')  -- Silent mode
    table.insert(cmd, '-i')  -- Include headers
    
    -- Always set a reasonable timeout
    local timeout = self.timeout or 30
    table.insert(cmd, '--max-time')
    table.insert(cmd, tostring(timeout))
    table.insert(cmd, '--connect-timeout')
    table.insert(cmd, '10')  -- Separate connection timeout
    
    -- Add method
    table.insert(cmd, '-X')
    table.insert(cmd, method)

    if self.follow_redirects then
        table.insert(cmd, '-L')
        if self.max_redirects then
            table.insert(cmd, '--max-redirs')
            table.insert(cmd, tostring(self.max_redirects))
        end
    end

    -- Add headers
    for _, h in ipairs(self.headers) do
        table.insert(cmd, h)
    end

    -- Add data for POST/PUT
    if data then
        table.insert(cmd, '-d')
        table.insert(cmd, '"' .. escape(data) .. '"')
    end

    -- Add proxy if set
    if self.proxy then
        table.insert(cmd, '--proxy')
        table.insert(cmd, '"' .. escape(self.proxy) .. '"')
    end
    
    -- Additional reliability options
    table.insert(cmd, '--retry')
    table.insert(cmd, tostring(self.retries or 2))
    table.insert(cmd, '--retry-delay')
    table.insert(cmd, '1')
    table.insert(cmd, '--retry-max-time')
    table.insert(cmd, tostring(timeout * 2))
    
    -- Handle SSL issues gracefully
    table.insert(cmd, '--insecure')  -- Allow self-signed certs if needed
    
    -- Disable progress meter and other potential output
    table.insert(cmd, '--no-progress-meter')  -- Available in newer curl versions
    
    -- Add URL last
    table.insert(cmd, '"' .. escape(url) .. '"')

    return table.concat(cmd, " ")
end


-- Function to get the last update check timestamp (FIXED)
function get_last_update_check()
  -- Use a fallback directory if main config path isn't available
  local check_dir = openSub.conf.dirPath
  
  if not check_dir then
    -- Try alternative directories for storing update check data
    local userdatadir = vlc.config.userdatadir()
    local datadir = vlc.config.datadir()
    
    if userdatadir then
      check_dir = userdatadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    elseif datadir then
      check_dir = datadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    else
      vlc.msg.dbg("[VLSub] No directory available for update check storage")
      return 0
    end
    
    -- Try to create the directory if it doesn't exist
    if not is_dir(check_dir) then
      mkdir_p(check_dir)
    end
  end
  
  local check_file_path = check_dir .. slash .. update_config.last_check_file
  
  if not file_exist(check_file_path) then
    vlc.msg.dbg("[VLSub] No previous update check file found")
    return 0
  end
  
  local file = io.open(check_file_path, "rb")
  if not file then
    vlc.msg.dbg("[VLSub] Cannot read update check file")
    return 0
  end
  
  local content = file:read("*all")
  file:close()
  
  local ok, data = pcall(json.decode, content, 1, true)
  if ok and data and data.last_check then
    vlc.msg.dbg("[VLSub] Last update check: " .. data.last_check)
    return tonumber(data.last_check) or 0
  end
  
  vlc.msg.dbg("[VLSub] Invalid update check file format")
  return 0
end


-- Function to save the last update check timestamp (FIXED)
function save_last_update_check()
  -- Use the same fallback logic as get_last_update_check
  local check_dir = openSub.conf.dirPath
  
  if not check_dir then
    local userdatadir = vlc.config.userdatadir()
    local datadir = vlc.config.datadir()
    
    if userdatadir then
      check_dir = userdatadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    elseif datadir then
      check_dir = datadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    else
      vlc.msg.err("[VLSub] No directory available for saving update check")
      return false
    end
    
    -- Ensure directory exists
    if not is_dir(check_dir) then
      mkdir_p(check_dir)
    end
  end
  
  local check_file_path = check_dir .. slash .. update_config.last_check_file
  
  local data = {
    last_check = os.time(),
    version_checked = update_config.current_version
  }
  
  if file_touch(check_file_path) then
    local file = io.open(check_file_path, "wb")
    if file then
      local content = json.encode(data, { indent = true })
      file:write(content)
      file:flush()
      file:close()
      vlc.msg.dbg("[VLSub] Update check timestamp saved")
      return true
    end
  end
  
  vlc.msg.err("[VLSub] Failed to save update check timestamp")
  return false
end

-- Function to check if we should perform an update check
function should_check_for_updates()
  local last_check = get_last_update_check()
  local now = os.time()
  local time_since_last_check = now - last_check
  
  vlc.msg.dbg("[VLSub] Last update check: " .. last_check .. ", time since: " .. time_since_last_check .. "s")
  
  return time_since_last_check >= update_config.check_interval_seconds
end

-- Function to compare version strings (semantic versioning)
function compare_versions(version1, version2)
  -- Returns: 1 if version1 > version2, -1 if version1 < version2, 0 if equal
  
  local function parse_version(version)
    local parts = {}
    for part in string.gmatch(version, "(%d+)") do
      table.insert(parts, tonumber(part))
    end
    -- Pad with zeros if needed
    while #parts < 3 do
      table.insert(parts, 0)
    end
    return parts
  end
  
  local v1_parts = parse_version(version1)
  local v2_parts = parse_version(version2)
  
  for i = 1, 3 do
    if v1_parts[i] > v2_parts[i] then
      return 1
    elseif v1_parts[i] < v2_parts[i] then
      return -1
    end
  end
  
  return 0
end

-- Function to get installation instructions for the user's OS
function get_install_instructions(download_url)
  local instructions = {}
  
  if openSub.conf.os == "win" then
    -- Windows instructions
    table.insert(instructions, "<b>Windows Installation:</b>")
    table.insert(instructions, "")
    table.insert(instructions, "<b>Option 1 - PowerShell (Recommended):</b>")
    table.insert(instructions, "1. Press Win+R, type 'powershell' and press Enter")
    table.insert(instructions, "2. Copy and paste this command:")
    table.insert(instructions, "<code>iwr -useb https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/scripts/install.ps1 | iex</code>")
    table.insert(instructions, "")
    table.insert(instructions, "<b>Option 2 - Manual Download:</b>")
    table.insert(instructions, "1. Download: <a href='" .. download_url .. "'>vlsubcom.lua</a>")
    table.insert(instructions, "2. Copy to: <code>%APPDATA%\\vlc\\lua\\extensions\\</code>")
    table.insert(instructions, "3. Restart VLC")
    
  else
    -- macOS/Linux instructions
    local os_name = "Linux"
    if string.find(string.lower(os.getenv("HOME") or ""), "users") then
      os_name = "macOS"
    end
    
    table.insert(instructions, "<b>" .. os_name .. " Installation:</b>")
    table.insert(instructions, "")
    table.insert(instructions, "<b>Option 1 - Automatic (Recommended):</b>")
    table.insert(instructions, "1. Open Terminal")
    table.insert(instructions, "2. Copy and paste this command:")
    table.insert(instructions, "<code>curl -sSL https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/scripts/install.sh | bash</code>")
    table.insert(instructions, "")
    table.insert(instructions, "<b>Option 2 - Manual Download:</b>")
    table.insert(instructions, "1. Download: <a href='" .. download_url .. "'>vlsubcom.lua</a>")
    if os_name == "macOS" then
      table.insert(instructions, "2. Copy to: <code>~/Library/Application Support/org.videolan.vlc/lua/extensions/</code>")
    else
      table.insert(instructions, "2. Copy to: <code>~/.local/share/vlc/lua/extensions/</code>")
    end
    table.insert(instructions, "3. Restart VLC")
  end
  
  table.insert(instructions, "")
  table.insert(instructions, "<b>After installation:</b>")
  table.insert(instructions, "• Restart VLC Media Player")
  table.insert(instructions, "• Access via View → VLSub OpenSubtitles.com")
  
  return table.concat(instructions, "<br>")
end

-- Compact function to show update available dialog (single dialog, VLC-compatible, compact)
function show_update_dialog(latest_version, release_notes, download_url)
  if not dlg then
    return -- No dialog available
  end
  
  vlc.msg.dbg("[VLSub] Showing update dialog for version: " .. latest_version)
  
  -- Close current dialog and show update dialog
  close_dlg()
  
  dlg = vlc.dialog("VLSub Update Available - " .. latest_version)
  
  -- Row 1: Update notification header with link and version info in compact format
  dlg:add_label("<a href='https://github.com/opensubtitles/vlsub-opensubtitles-com'><b>VLSub Update Available</b></a> (" .. update_config.current_version .. " => " .. latest_version .. ")", 1, 1, 6, 1)
  
  -- Row 2: Installation instructions
  dlg:add_label("<b>Installation Instructions:</b>", 1, 2, 6, 1)
  
  -- Detect OS and show appropriate instructions
  if openSub.conf.os == "win" then
    -- Windows instructions - compact with 2-line fallback
    dlg:add_label("Open PowerShell as Administrator and run:", 1, 3, 6, 1)
    dlg:add_label("iwr -useb https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/scripts/install.ps1 | iex", 1, 4, 6, 1)
    dlg:add_label("If this doesn't work, download <a href='" .. download_url .. "'>vlsubcom.lua</a> and save to:", 1, 5, 6, 1)
    dlg:add_label("%APPDATA%\\vlc\\lua\\extensions\\vlsubcom.lua", 1, 6, 6, 1)
    
  else
    -- macOS/Linux instructions - compact with 2-line fallback
    local install_path = "~/.local/share/vlc/lua/extensions/vlsubcom.lua"
    
    -- Detect macOS
    if string.find(string.lower(os.getenv("HOME") or ""), "users") or 
       string.find(string.lower(os.getenv("USER") or ""), "user") then
      install_path = "~/Library/Application Support/org.videolan.vlc/lua/extensions/vlsubcom.lua"
    end
    
    dlg:add_label("Open Terminal and run:", 1, 3, 6, 1)
    dlg:add_label("curl -sSL https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/scripts/install.sh | bash", 1, 4, 6, 1)
    dlg:add_label("If this doesn't work, download <a href='" .. download_url .. "'>vlsubcom.lua</a> and save to:", 1, 5, 6, 1)
    dlg:add_label(install_path, 1, 6, 6, 1)
  end
  
  dlg:add_label("Then restart VLC and access via View → VLSub OpenSubtitles.com", 1, 7, 6, 1)
  
  -- Row 8: What's new section (compact - exactly 6 lines)
  dlg:add_label("<b>What's New in v" .. latest_version .. ":</b>", 1, 8, 6, 1)
  
  -- Process and display release notes - exactly 6 lines
  local processed_notes = process_release_notes(release_notes)
  local notes_lines = split_text_into_lines(processed_notes, 80)
  
  -- Display exactly 6 lines of release notes
  for i = 1, 6 do
    local line_content = ""
    if i <= #notes_lines then
      line_content = notes_lines[i]
    end
    dlg:add_label(line_content, 1, 8 + i, 6, 1)
  end
  
  -- Row 15: Action buttons (compact layout)
  dlg:add_button("⏭️ Skip Version", function()
    save_skipped_version(latest_version)
    close_dlg()
    show_appropriate_window()
  end, 2, 15, 1, 1)
  
  dlg:add_button("⏰ Later", function()
    close_dlg()
    show_appropriate_window()
  end, 4, 15, 1, 1)
  
  dlg:add_button("❌ Close", function()
    close_dlg()
    show_appropriate_window()
  end, 5, 15, 1, 1)
  
  if dlg then
    dlg:show()
  end
end

-- Helper function to process release notes (ASCII-only, simple text output) - NO DEBUG
function process_release_notes(notes)
  if not notes or notes == "" or string.gsub(notes, "%s", "") == "" then
    return "General improvements and bug fixes."
  end
  
  -- Start processing
  local processed = notes
  
  -- Remove all non-ASCII characters (including emojis and unicode bullets)
  processed = string.gsub(processed, "[^\32-\126\n\r\t]", "")
  
  -- Remove all markdown headers completely (##, ###, etc.)
  processed = string.gsub(processed, "#+%s*[^\n]*\n?", "")
  
  -- Remove markdown bold/italic (**text** *text*)
  processed = string.gsub(processed, "%*%*([^*]+)%*%*", "%1")
  processed = string.gsub(processed, "%*([^*]+)%*", "%1")
  
  -- Remove markdown links [text](url) -> text
  processed = string.gsub(processed, "%[([^%]]+)%]%([^%)]+%)", "%1")
  
  -- Remove code blocks completely
  processed = string.gsub(processed, "```[^`]*```", "")
  processed = string.gsub(processed, "`([^`]+)`", "%1")
  
  -- Convert markdown lists to simple ASCII bullet points using "-"
  processed = string.gsub(processed, "^%s*[-*+]%s+", "- ")
  processed = string.gsub(processed, "\n%s*[-*+]%s+", "\n- ")
  
  -- Remove installation and documentation sections (not needed in dialog)
  local sections_to_remove = {
    "Installation[^\n]*\n[^#]*",
    "Requirements[^\n]*\n[^#]*", 
    "Documentation[^\n]*\n[^#]*",
    "Quick Install[^\n]*\n[^#]*",
    "Manual Install[^\n]*\n[^#]*"
  }
  
  for _, pattern in ipairs(sections_to_remove) do
    processed = string.gsub(processed, pattern, "")
  end
  
  -- Clean up excessive whitespace
  processed = string.gsub(processed, "\n\n+", "\n")
  processed = string.gsub(processed, "^%s+", "")
  processed = string.gsub(processed, "%s+$", "")
  
  -- If after all processing we have very little content, provide a default
  if processed == "" or string.len(processed) < 10 then
    return "General improvements and bug fixes."
  end
  
  -- Split into individual features and clean up
  local features = {}
  for line in processed:gmatch("[^\n]+") do
    line = string.gsub(line, "^%s*", "") -- Remove leading spaces
    line = string.gsub(line, "%s*$", "") -- Remove trailing spaces
    
    -- Skip empty lines and section headers
    if line ~= "" and not string.match(line, "^[A-Z][a-z]+%s*$") then
      table.insert(features, line)
    end
  end
  
  -- Return first few meaningful features
  local result_lines = {}
  local count = 0
  for _, feature in ipairs(features) do
    if count >= 6 then break end -- Limit to 6 features
    if string.len(feature) > 5 then -- Skip very short lines
      table.insert(result_lines, feature)
      count = count + 1
    end
  end
  
  if #result_lines == 0 then
    return "General improvements and bug fixes."
  end
  
  local final_result = table.concat(result_lines, "\n")
  
  -- Final safety check - ensure only ASCII characters in result
  final_result = string.gsub(final_result, "[^\32-\126\n\r\t]", "")
  
  return final_result
end

-- Helper function to split text into lines with word wrapping
function split_text_into_lines(text, max_length)
  local lines = {}
  
  -- Split by existing newlines first
  for paragraph in text:gmatch("[^\n]+") do
    local words = {}
    
    -- Split paragraph into words
    for word in string.gmatch(paragraph, "%S+") do
      table.insert(words, word)
    end
    
    local current_line = ""
    
    for _, word in ipairs(words) do
      -- Check if adding this word would exceed the line length
      local test_line = current_line == "" and word or (current_line .. " " .. word)
      
      if #test_line <= max_length then
        current_line = test_line
      else
        -- Line would be too long, start a new line
        if current_line ~= "" then
          table.insert(lines, current_line)
        end
        current_line = word
      end
    end
    
    -- Add the last line if it's not empty
    if current_line ~= "" then
      table.insert(lines, current_line)
    end
  end
  
  return lines
end

-- Helper function to save skipped version
function save_skipped_version(version)
  -- Use the same directory logic as update checks
  local check_dir = openSub.conf.dirPath
  
  if not check_dir then
    local userdatadir = vlc.config.userdatadir()
    local datadir = vlc.config.datadir()
    
    if userdatadir then
      check_dir = userdatadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    elseif datadir then
      check_dir = datadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    else
      return false
    end
    
    -- Ensure directory exists
    if not is_dir(check_dir) then
      mkdir_p(check_dir)
    end
  end
  
  local skip_file_path = check_dir .. slash .. "skipped_version.txt"
  
  if file_touch(skip_file_path) then
    local file = io.open(skip_file_path, "w")
    if file then
      file:write(version)
      file:close()
      return true
    end
  end
  
  return false
end

-- Function to check if a version was previously skipped
function is_version_skipped(version)
  local check_dir = openSub.conf.dirPath
  
  if not check_dir then
    local userdatadir = vlc.config.userdatadir()
    local datadir = vlc.config.datadir()
    
    if userdatadir then
      check_dir = userdatadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    elseif datadir then
      check_dir = datadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    else
      return false
    end
  end
  
  local skip_file_path = check_dir .. slash .. "skipped_version.txt"
  
  if not file_exist(skip_file_path) then
    return false
  end
  
  local file = io.open(skip_file_path, "r")
  if not file then
    return false
  end
  
  local skipped_version = file:read("*all")
  file:close()
  
  if skipped_version then
    skipped_version = string.gsub(skipped_version, "%s+", "") -- Trim whitespace
    return skipped_version == version
  end
  
  return false
end



-- Function to get the last update check timestamp (FIXED)
function get_last_update_check()
  -- Use a fallback directory if main config path isn't available
  local check_dir = openSub.conf.dirPath
  
  if not check_dir then
    -- Try alternative directories for storing update check data
    local userdatadir = vlc.config.userdatadir()
    local datadir = vlc.config.datadir()
    
    if userdatadir then
      check_dir = userdatadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    elseif datadir then
      check_dir = datadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    else
      vlc.msg.dbg("[VLSub] No directory available for update check storage")
      return 0
    end
    
    -- Try to create the directory if it doesn't exist
    if not is_dir(check_dir) then
      mkdir_p(check_dir)
    end
  end
  
  local check_file_path = check_dir .. slash .. update_config.last_check_file
  
  if not file_exist(check_file_path) then
    vlc.msg.dbg("[VLSub] No previous update check file found")
    return 0
  end
  
  local file = io.open(check_file_path, "rb")
  if not file then
    vlc.msg.dbg("[VLSub] Cannot read update check file")
    return 0
  end
  
  local content = file:read("*all")
  file:close()
  
  local ok, data = pcall(json.decode, content, 1, true)
  if ok and data and data.last_check then
    vlc.msg.dbg("[VLSub] Last update check: " .. data.last_check)
    return tonumber(data.last_check) or 0
  end
  
  vlc.msg.dbg("[VLSub] Invalid update check file format")
  return 0
end

-- Function to save the last update check timestamp (FIXED)
function save_last_update_check()
  -- Use the same fallback logic as get_last_update_check
  local check_dir = openSub.conf.dirPath
  
  if not check_dir then
    local userdatadir = vlc.config.userdatadir()
    local datadir = vlc.config.datadir()
    
    if userdatadir then
      check_dir = userdatadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    elseif datadir then
      check_dir = datadir .. slash .. "lua" .. slash .. "extensions" .. slash .. "userdata" .. slash .. "vlsub.com"
    else
      vlc.msg.err("[VLSub] No directory available for saving update check")
      return false
    end
    
    -- Ensure directory exists
    if not is_dir(check_dir) then
      mkdir_p(check_dir)
    end
  end
  
  local check_file_path = check_dir .. slash .. update_config.last_check_file
  
  local data = {
    last_check = os.time(),
    version_checked = update_config.current_version
  }
  
  if file_touch(check_file_path) then
    local file = io.open(check_file_path, "wb")
    if file then
      local content = json.encode(data, { indent = true })
      file:write(content)
      file:flush()
      file:close()
      vlc.msg.dbg("[VLSub] Update check timestamp saved")
      return true
    end
  end
  
  vlc.msg.err("[VLSub] Failed to save update check timestamp")
  return false
end

-- Function to initialize auto-update checking (FIXED)
function initialize_auto_update()
  vlc.msg.dbg("[VLSub] Initializing auto-update system...")
  
  -- Always attempt update check, regardless of config state
  -- The only requirements are: json module loaded and some network connectivity
  
  if not jsonModuleLoaded then
    vlc.msg.dbg("[VLSub] Skipping auto-update: JSON module not loaded")
    return
  end
  
  -- Don't require full config - we can check for updates even without OpenSubtitles credentials
  vlc.msg.dbg("[VLSub] Auto-update check starting...")
  
  -- Perform update check in background (non-blocking)
  pcall(function()
    check_for_updates(false) -- Don't force, respect timing
  end)
end

-- Main function to check for updates (ENHANCED)
function check_for_updates(force_check)
  vlc.msg.dbg("[VLSub] check_for_updates called, force=" .. tostring(force_check))
  
  -- Don't check if no internet connection (unless forced)
  if networkTestsFailed and not force_check then
    vlc.msg.dbg("[VLSub] Skipping update check - no internet connection")
    return
  end
  
  -- Check if we should perform the check (unless forced)
  if not force_check and not should_check_for_updates() then
    vlc.msg.dbg("[VLSub] Skipping update check - too soon since last check")
    return
  end
  
  vlc.msg.dbg("[VLSub] Proceeding with update check...")
  
  -- Make API request to GitHub
  local client = Curl.new()
  client:add_header("User-Agent", app_useragent)
  client:add_header("Accept", "application/vnd.github.v3+json")
  client:set_timeout(15)  -- Slightly longer timeout for update checks
  client:set_retries(1)
  
  local res = client:get(update_config.check_url)
  
  if not res or res.status ~= 200 then
    vlc.msg.err("[VLSub] Failed to check for updates: " .. (res and res.status or "no response"))
    
    -- Still save the check attempt to avoid repeated failures
    if force_check then
      save_last_update_check()
    end
    return
  end
  
  if not res.body then
    vlc.msg.err("[VLSub] Empty response from update check")
    return
  end
  
  -- Parse the GitHub API response
  local ok, release_data = pcall(json.decode, res.body, 1, true)
  if not ok or not release_data then
    vlc.msg.err("[VLSub] Failed to parse update response")
    return
  end
  
  local latest_version = release_data.tag_name or release_data.name
  if not latest_version then
    vlc.msg.err("[VLSub] No version found in release data")
    return
  end
  
  -- Remove 'v' prefix if present
  latest_version = string.gsub(latest_version, "^v", "")
  
  vlc.msg.dbg("[VLSub] Current version: " .. update_config.current_version)
  vlc.msg.dbg("[VLSub] Latest version: " .. latest_version)
  
  -- Save that we performed the check (IMPORTANT: do this regardless of result)
  save_last_update_check()
  
  -- Compare versions
  local version_comparison = compare_versions(latest_version, update_config.current_version)
  
  if version_comparison > 0 then
    -- New version available
    vlc.msg.dbg("[VLSub] Update available: " .. latest_version)
    
    -- Check if this version was skipped (only if not forced)
    if is_version_skipped(latest_version) and not force_check then
      vlc.msg.dbg("[VLSub] Version " .. latest_version .. " was previously skipped")
      return
    end
    
    -- Find download URL (look for .lua file in assets)
    local download_url = "https://github.com/opensubtitles/vlsub-opensubtitles-com/releases/latest"
    if release_data.assets then
      for _, asset in ipairs(release_data.assets) do
        if asset.name and string.match(asset.name, "%.lua$") then
          download_url = asset.browser_download_url
          break
        end
      end
    end
    
    local release_notes = release_data.body or ""
    
    -- Show update dialog (this will work even without full config)
    show_update_dialog(latest_version, release_notes, download_url)
    
  else
    vlc.msg.dbg("[VLSub] No update available")
    if force_check then
      -- If manually triggered, show a message only if we have an interface
      if input_table and input_table["message"] then
        setMessage(success_tag("You're running the latest version (" .. update_config.current_version .. ")"))
      end
    end
  end
end

-- Function to add "Check for Updates" button to config window
function add_update_button_to_config()
  -- Add this to your interface_config() function, in the button row
  dlg:add_button("🔄 Check Updates", function()
    check_for_updates(true) -- Force check
  end, 1, 11, 1, 1)
end

-- Function to initialize auto-update checking (FIXED)
function initialize_auto_update()
  vlc.msg.dbg("[VLSub] Initializing auto-update system...")
  
  -- Always attempt update check, regardless of config state
  -- The only requirements are: json module loaded and some network connectivity
  
  if not jsonModuleLoaded then
    vlc.msg.dbg("[VLSub] Skipping auto-update: JSON module not loaded")
    return
  end
  
  -- Don't require full config - we can check for updates even without OpenSubtitles credentials
  vlc.msg.dbg("[VLSub] Auto-update check starting...")
  
  -- Perform update check in background (non-blocking)
  pcall(function()
    check_for_updates(false) -- Don't force, respect timing
  end)
end




-- MODIFIED: IP-based geolocation detection - only called when no preferences exist
function detect_ip_based_locale(detected_locales)
  -- This function should only be called from detect_user_locale() 
  -- when user has no preferences set
  vlc.msg.dbg("[VLSub] Attempting IP-based geolocation detection...")
  append_debug_log("Performing IP geolocation lookup...")
  
  local ip_api_url = "https://api.myip.com"
  
  -- Use the same curl wrapper as other API calls
  local client = Curl.new()
  client:add_header("User-Agent", app_useragent)
  client:set_timeout(10) -- Short timeout for IP detection
  client:set_retries(1)  -- Single retry
  
  local res = client:get(ip_api_url)
  
  if not res then
    vlc.msg.dbg("[VLSub] IP geolocation: No response from API")
    append_debug_log("IP detection failed - no response")
    return
  end

  if not res or res.status ~= 200 then
    local status = (res and res.status) or "N/A"
    vlc.msg.dbg("[VLSub] IP geolocation: API request failed with status: " .. status)
    append_debug_log("IP detection failed - status " .. status)
    return
  end

  if not res.body or res.body == "" then
    vlc.msg.dbg("[VLSub] IP geolocation: Empty response body")
    append_debug_log("IP detection failed - empty response")
    return
  end
  
  -- Parse the JSON response
  local ok, ip_data = pcall(json.decode, res.body, 1, true)
  if not ok or not ip_data then
    vlc.msg.dbg("[VLSub] IP geolocation: Failed to parse response: " .. (res.body or "no body"))
    append_debug_log("IP detection failed - parse error")
    return
  end
  
  vlc.msg.dbg("[VLSub] IP geolocation result: " .. json.encode(ip_data, { indent = true }))
  
  -- Extract country code and map to language
  local country_code = ip_data.cc
  local country_name = ip_data.country
  local ip_address = ip_data.ip
  
  if country_code and country_code ~= "" then
    vlc.msg.dbg("[VLSub] Detected country from IP: " .. country_name .. " (" .. country_code .. ")")
    append_debug_log("IP location: " .. country_name .. " (" .. country_code .. ")")
    
    -- Map country codes to primary languages
    local country_language_map = {
      -- Major countries with their primary languages
      US = "en", GB = "en", AU = "en", CA = "en", NZ = "en", IE = "en", ZA = "en",
      DE = "de", AT = "de", CH = "de", 
      FR = "fr", BE = "fr", CH = "fr", CA = "fr",
      ES = "es", MX = "es", AR = "es", CO = "es", PE = "es", VE = "es", CL = "es",
      IT = "it", CH = "it",
      PT = "pt", BR = "pt",
      RU = "ru", BY = "ru", KZ = "ru",
      CN = "zh-cn", TW = "zh-tw", HK = "zh-ca", SG = "zh-cn",
      JP = "ja",
      KR = "ko",
      NL = "nl", BE = "nl",
      SE = "sv",
      NO = "no",
      DK = "da",
      FI = "fi",
      PL = "pl",
      CZ = "cs",
      SK = "sk", -- Slovakia -> Slovak
      HU = "hu",
      RO = "ro",
      BG = "bg",
      HR = "hr",
      RS = "sr",
      SI = "sl",
      GR = "el",
      TR = "tr",
      UA = "uk",
      IN = "hi", -- India (though many languages, Hindi is most common)
      TH = "th",
      VN = "vi",
      ID = "id",
      MY = "ms",
      PH = "tl",
      SA = "ar", AE = "ar", EG = "ar", MA = "ar",
      IL = "he",
      IR = "fa"
    }
    
    local primary_language = country_language_map[country_code]
    if primary_language then
      vlc.msg.dbg("[VLSub] Mapped country " .. country_code .. " to primary language: " .. primary_language)
      append_debug_log("Language suggestion from IP: " .. primary_language)
      table.insert(detected_locales, {source = "ip_geolocation", locale = primary_language})
      
      -- For some countries, add country-specific locale
      local country_specific = primary_language .. "_" .. country_code
      table.insert(detected_locales, {source = "ip_country_specific", locale = country_specific})
      vlc.msg.dbg("[VLSub] Also added country-specific locale: " .. country_specific)
    else
      vlc.msg.dbg("[VLSub] No language mapping found for country: " .. country_code)
      append_debug_log("No language mapping for country: " .. country_code)
    end
  else
    vlc.msg.dbg("[VLSub] No country code in IP geolocation response")
    append_debug_log("IP detection failed - no country code")
  end
end



-- Helper function to force user to stay in config until authenticated
function force_config_until_authenticated()
  if not has_valid_authentication() then
    vlc.msg.dbg("[VLSub] Authentication required - staying in config window")
    setMessage(error_tag("Please enter valid OpenSubtitles.com credentials and click Save before proceeding."))
    return true -- Stay in config
  end
  return false -- Can proceed
end



-- Improved initialize_languages with better error handling
function initialize_languages()
  local cache_file_path = openSub.conf.dirPath .. slash .. "cache_subtitle_languages.json"
  
  -- Check cache first
  if file_exist(cache_file_path) then
    local file_stat = vlc.net.stat(cache_file_path)
    if file_stat and (os.time() - file_stat.modification_time < config.cache_languages_duration_seconds) then
      vlc.msg.dbg("[VLSub] Loading languages from cache")
      
      local cache_file = io.open(cache_file_path, "rb")
      if cache_file then
        local cache_content = cache_file:read("*all")
        cache_file:close()
        
        local ok, parsed_data = pcall(json.decode, cache_content, 1, true)
        if ok and parsed_data and type(parsed_data.data) == "table" then
          local formatted_langs = {}
          for _, lang_obj in ipairs(parsed_data.data) do
            if type(lang_obj.language_code) == "string" and type(lang_obj.language_name) == "string" then
              table.insert(formatted_langs, {lang_obj.language_code, lang_obj.language_name})
            end
          end
          
          if #formatted_langs > 0 then
            vlc.msg.dbg("[VLSub] Successfully loaded " .. #formatted_langs .. " languages from cache")
            openSub.conf.languages = formatted_langs
            return
          end
        end
      end
    end
  end
  
  -- Use built-in languages as fallback
  openSub.conf.languages = sub_languages
  vlc.msg.dbg("[VLSub] Using built-in language list (" .. #sub_languages .. " languages)")
  
  -- Try to fetch from API with aggressive timeouts
  vlc.msg.dbg("[VLSub] Attempting to fetch fresh language list from API")
  
  local client = Curl.new()
  client:set_aggressive_timeouts()
  client:add_header("Api-Key", config.api_key)
  client:add_header("User-Agent", app_useragent)
  
  local res = client:get(config.api_languages_url)
  
  if res and res.status == 200 and res.body then
    local ok, parsed_data = pcall(json.decode, res.body, 1, true)
    if ok and parsed_data and type(parsed_data.data) == "table" then
      -- Save to cache
      if file_touch(cache_file_path) then
        local cache_file = io.open(cache_file_path, "wb")
        if cache_file then
          cache_file:write(res.body)
          cache_file:flush()
          cache_file:close()
          vlc.msg.dbg("[VLSub] Cached " .. #parsed_data.data .. " languages")
        end
      end
      
      -- Update current session
      local formatted_langs = {}
      for _, lang_obj in ipairs(parsed_data.data) do
        if type(lang_obj.language_code) == "string" and type(lang_obj.language_name) == "string" then
          table.insert(formatted_langs, {lang_obj.language_code, lang_obj.language_name})
        end
      end
      if #formatted_langs > 0 then
        openSub.conf.languages = formatted_langs
        vlc.msg.dbg("[VLSub] Updated with " .. #formatted_langs .. " languages from API")
      end
    else
      vlc.msg.err("[VLSub] Failed to parse API language response")
    end
  else
    vlc.msg.err("[VLSub] Failed to fetch languages from API, using built-in list")
  end
  
  vlc.msg.dbg("[VLSub] Final language count: " .. #openSub.conf.languages)
end




function close()
  vlc.deactivate()
end

function deactivate()
  vlc.msg.dbg("[VLsub] Bye bye!")
  if dlg then
    dlg:hide() 
  end
  
  -- DISABLED: Don't logout or clear token on deactivation
  -- if openSub.session.token and openSub.session.token ~= "" then
  --   openSub.logoutRestAPI()
  -- end
  
  vlc.msg.dbg("[VLsub] Keeping session token for next use")
end

function menu()
  return { 	  
    lang.int_research, 
    lang.int_config, 
    lang.int_help
  }
end

function meta_changed()
  return false
end


            --[[ Interface data ]]--



-- Modified interface_main function - update the help button to pass window context
function interface_main()
  -- Row 1: Title field and Search by Hash button
  dlg:add_label(lang["int_title"]..":", 1, 1, 1, 1)
  input_table['title'] = dlg:add_text_input(
    openSub.movie.title or "", 2, 1, 4, 1)
  dlg:add_button("🎯 "..lang["int_search_hash"], 
    searchHash, 6, 1, 1, 1)
  
  -- Row 2: TV Season and TV Episode (EPISODE MADE SMALLER)
  dlg:add_label(lang["int_season"]..":", 1, 2, 1, 1)
  input_table['seasonNumber'] = dlg:add_text_input(
    openSub.movie.seasonNumber or "", 2, 2, 1, 1)
  dlg:add_label(lang["int_episode"]..":", 3, 2, 1, 1)
  input_table['episodeNumber'] = dlg:add_text_input(
    openSub.movie.episodeNumber or "", 4, 2, 1, 1)
  
  -- Row 3: Year and Search by Name button
  dlg:add_label("Year:", 1, 3, 1, 1)
  input_table['year'] = dlg:add_text_input(
    openSub.movie.year or "", 2, 3, 1, 1)
  dlg:add_button("🔍 "..lang["int_search_name"], 
    searchIMBD_v2, 6, 3, 1, 1)
  
  -- Row 4: Language selection
  dlg:add_label(lang["int_default_lang"]..":", 1, 4, 1, 1)
  input_table['language'] =  dlg:add_dropdown(2, 4, 4, 1)
  
  -- Row 5: Secondary language
  dlg:add_label(lang["int_second_lang"]..":", 1, 5, 1, 1)
  input_table['language2'] =  dlg:add_dropdown(2, 5, 4, 1)
  
  -- Row 6: Third language
  dlg:add_label(lang["int_third_lang"]..":", 1, 6, 1, 1)
  input_table['language3'] =  dlg:add_dropdown(2, 6, 4, 1)
  
  -- Row 7: Results list label
  dlg:add_label("Search Results:", 1, 7, 6, 1)
  
  -- Row 8: Results list
  input_table['mainlist'] = dlg:add_list(1, 8, 6, 1)
  
  -- Row 9: Status message
  input_table['message'] = nil
  input_table['message'] = dlg:add_label('Ready for search', 1, 9, 6, 1)
  
  -- Row 10: Action buttons - MODIFIED HELP BUTTON
  dlg:add_button(
    "📥 Download", download_subtitles_v2, 1, 10, 1, 1)
  
  dlg:add_button(
    "🔗 Link", open_subtitle_link, 2, 10, 1, 1)
  
  dlg:add_button(
    "⚙️ Config", show_conf, 5, 10, 1, 1)
  dlg:add_button(
    "❓ Help", 
    function() show_help("main") end, -- Pass "main" to indicate source window
    6, 10, 1, 1)
  
  -- Set up language dropdowns
  assoc_select_conf('language', 'language', openSub.conf.languages, 2, lang["int_all"])
  assoc_select_conf('language2', 'language2', openSub.conf.languages, 2, 'None')
  assoc_select_conf('language3', 'language3', openSub.conf.languages, 2, 'None')
    
  -- Only call display_subtitles if we actually have search results to display
  if openSub.itemStore and type(openSub.itemStore) == "table" and #openSub.itemStore > 0 then
    display_subtitles()
  end
end

-- Updated interface_config with repositioned buttons: Save, Help, Check Updates, Close
function interface_config()
  -- Row 1: OpenSubtitles username
  dlg:add_label(lang["int_os_username"]..":", 1, 1, 1, 1)
  input_table['os_username'] = dlg:add_text_input(
    type(openSub.option.os_username) == "string"
    and openSub.option.os_username or "", 2, 1, 2, 1)

  -- Row 2: OpenSubtitles password
  dlg:add_label(lang["int_os_password"]..":", 1, 2, 1, 1)
  input_table['os_password'] = dlg:add_password(
    type(openSub.option.os_password) == "string"
    and openSub.option.os_password or "", 2, 2, 2, 1)

  -- Row 3: Default primary language
  dlg:add_label(lang["int_default_lang"]..":", 1, 3, 2, 1)
  input_table['default_language'] = dlg:add_dropdown(3, 3, 1, 1)

  -- Row 4: Default secondary language
  dlg:add_label(lang["int_second_lang"]..":", 1, 4, 2, 1)
  input_table['default_language2'] = dlg:add_dropdown(3, 4, 1, 1)

  -- Row 5: Default third language
  dlg:add_label(lang["int_third_lang"]..":", 1, 5, 2, 1)
  input_table['default_language3'] = dlg:add_dropdown(3, 5, 1, 1)

  -- Row 6: Download behavior
  dlg:add_label(lang["int_dowload_behav"]..":", 1, 6, 2, 1)
  input_table['downloadBehaviour'] = dlg:add_dropdown(3, 6, 1, 1)

  -- Row 7: Display language code
  dlg:add_label(lang["int_display_code"]..":", 1, 7, 2, 1)
  input_table['langExt'] = dlg:add_dropdown(3, 7, 1, 1)

  -- Row 8: Remove tags
  dlg:add_label(lang["int_remove_tag"]..":", 1, 8, 2, 1)
  input_table['removeTag'] = dlg:add_dropdown(3, 8, 1, 1)

  -- Row 9: Working directory
  if openSub.conf.dirPath then
    -- Check if macOS and remove link functionality
    if openSub.conf.os == "lin" then
      dlg:add_label(lang["int_vlsub_work_dir"], 1, 9, 2, 1)
    elseif openSub.conf.os == "win" then
      dlg:add_label(
        "<a href='file:///"..openSub.conf.dirPath.."'>"..
        lang["int_vlsub_work_dir"].."</a>", 1, 9, 2, 1)
    else
      dlg:add_label(
        "<a href='"..openSub.conf.dirPath.."'>"..
        lang["int_vlsub_work_dir"].."</a>", 1, 9, 2, 1)
    end
  else
    dlg:add_label(lang["int_vlsub_work_dir"], 1, 9, 2, 1)
  end

  input_table['dir_path'] = dlg:add_text_input(
    openSub.conf.dirPath, 2, 9, 2, 1)

  -- Row 10: Status message
  input_table['message'] = nil
  input_table['message'] = dlg:add_label('', 1, 10, 4, 1)

  -- Row 11: Action buttons - NEW ORDER: Save, Help, Check Updates, Close
  dlg:add_button(
    "💾 " .. lang["int_save"],
    apply_config, 1, 11, 1, 1)
  
  dlg:add_button(
    "❓ " .. lang["int_help"],
    function() show_help("config") end,
    2, 11, 1, 1)
  
  dlg:add_button(
    "🔄 Check Updates",
    function() check_for_updates(true) end, 3, 11, 1, 1)
  
  -- Conditional close button - only enabled after successful authentication
  if has_valid_authentication() then
    dlg:add_button(
      "❌ " .. lang["int_close"],
      show_main, 4, 11, 1, 1)
  else
    -- Disabled close button or placeholder
    dlg:add_label(
      "<span style='color:#999;'>❌ " .. lang["int_close"] .. " (Login Required)</span>", 
      4, 11, 1, 1)
  end

  -- Setup dropdown values and language dropdowns
  input_table['langExt']:add_value(
    lang["int_bool_"..tostring(openSub.option.langExt)], 1)
  input_table['langExt']:add_value(
    lang["int_bool_"..tostring(not openSub.option.langExt)], 2)
  input_table['removeTag']:add_value(
    lang["int_bool_"..tostring(openSub.option.removeTag)], 1)
  input_table['removeTag']:add_value(
    lang["int_bool_"..tostring(not openSub.option.removeTag)], 2)

  assoc_select_conf('default_language', 'language', openSub.conf.languages, 2, lang["int_all"])
  assoc_select_conf('default_language2', 'language2', openSub.conf.languages, 2, 'None')
  assoc_select_conf('default_language3', 'language3', openSub.conf.languages, 2, 'None')
  assoc_select_conf('downloadBehaviour', 'downloadBehaviour', openSub.conf.downloadBehaviours, 1)
end




-- Modified interface_help function with improved content
function interface_help()
  -- Row 1: Search Methods
  dlg:add_label("SEARCH METHODS:", 1, 1, 6, 1)
  dlg:add_label("Hash Search: Uses video file fingerprint for exact matches", 1, 2, 6, 1)
  dlg:add_label("Name Search: Uses GuessIt API to extract title/year/episode from filename", 1, 3, 6, 1)
  dlg:add_label("Auto-fallback from hash to name search if no results found", 1, 4, 6, 1)
  
  -- Row 5: Language Features
  dlg:add_label("", 1, 5, 6, 1) -- Spacer
  dlg:add_label("LANGUAGE & DETECTION:", 1, 6, 6, 1)
  dlg:add_label("Auto-detects locale from system settings, IP geolocation, timezone", 1, 7, 6, 1)
  dlg:add_label("Results grouped by selected languages in priority order", 1, 8, 6, 1)
  dlg:add_label("Choose up to 3 preferred subtitle languages", 1, 9, 6, 1)
  
  -- Row 10: Technical Details
  dlg:add_label("", 1, 10, 6, 1) -- Spacer
  dlg:add_label("TECHNICAL INFO:", 1, 11, 6, 1)
  dlg:add_label("GuessIt API extracts movie/TV metadata from filenames", 1, 12, 6, 1)
  dlg:add_label("Shows quality indicators: trusted uploaders, download counts, sync", 1, 13, 6, 1)
  dlg:add_label("Windows: Use English characters in file paths for best results", 1, 14, 6, 1)
  
  -- Row 15: Account & Download
  dlg:add_label("", 1, 15, 6, 1) -- Spacer
  dlg:add_label("ACCOUNT & QUOTAS:", 1, 16, 6, 1)
  dlg:add_label("<a href='https://www.opensubtitles.com'>Free OpenSubtitles.com account required for downloads</a>", 1, 17, 6, 1)
  dlg:add_label("Extension displays your rank, daily quota and current usage", 1, 18, 6, 1)
  dlg:add_label("Select subtitle and click Download or Link button", 1, 19, 6, 1)
  
  -- Row 20: Links
  dlg:add_label("", 1, 20, 6, 1) -- Spacer
  dlg:add_label("<a href='https://www.opensubtitles.com/en/support_us/'>Support OpenSubtitles</a> - thank you very much", 1, 21, 6, 1)
  
  -- Row 22: Close button with icon
  dlg:add_label("", 1, 22, 6, 1) -- Spacer
  dlg:add_button("❌ Close", 
    function()
      if previous_window == "config" then
        show_conf()
      else
        show_main()
      end
    end, 
    3, 23, 2, 1)
end


function trigger_menu(dlg_id)
  if dlg_id == 1 then
    close_dlg()
    dlg = vlc.dialog(
      openSub.conf.useragent)
    interface_main()
  elseif dlg_id == 2 then
    close_dlg()
    dlg = vlc.dialog(
      openSub.conf.useragent..': '..lang["int_configuration"])
    interface_config()
  elseif dlg_id == 3 then
    close_dlg()
    dlg = vlc.dialog(
      openSub.conf.useragent..': '..lang["int_help"])
    interface_help()
  end
  collectgarbage() --~ !important	
end 

function show_main()
  trigger_menu(1)
end

-- Modified show_conf function to pass the window identifier when calling help
function show_conf()
  trigger_menu(2)
end

function show_help(from_window)
  if from_window then
    previous_window = from_window
  end
  trigger_menu(3)
end

-- New function to update button labels dynamically
function update_debug_buttons()
  if not debug_messages or not debug_dlg then
    return
  end
  
  local allTestsPassed = configurationPassed and jsonModuleLoaded and not criticalFailure
  
  -- Update OK button based on status
  if debug_messages.ok_button then
    if not initialization_complete then
      -- Still initializing
      debug_messages.ok_button:set_text("⏳ Continue")
    elseif allTestsPassed and not networkTestsFailed then
      -- All good - will auto-close
      debug_messages.ok_button:set_text("✅ Auto-close (2s)")
    elseif allTestsPassed and networkTestsFailed then
      -- Core works but offline
      debug_messages.ok_button:set_text("🌐 Continue Offline")
    else
      -- Has errors
      debug_messages.ok_button:set_text("⚠️ Continue Anyway")
    end
  end
  
  -- Update Cancel/Close button
  if debug_messages.cancel_button then
    debug_messages.cancel_button:set_text("❌ Close VLSub")
  end
  
  if debug_dlg then
    debug_dlg:update()
  end
end

function show_debug_window()
  if debug_dlg then
    debug_dlg:hide()
    debug_dlg = nil
  end
  
  -- Initialize debug_messages table and log rows
  debug_messages = {}
  debug_log_rows = {} -- Array for individual log rows
  
  debug_dlg = vlc.dialog("VLSub - Initializing...")
  
  -- Create debug interface (6 columns, 16 rows)
  debug_dlg:add_label("VLSub is starting up...", 1, 1, 6, 1)
  debug_dlg:add_label("", 1, 2, 6, 1) -- Spacer
  
  -- Progress area
  debug_dlg:add_label("Progress:", 1, 3, 1, 1)
  debug_messages.progress = debug_dlg:add_label("Starting...", 2, 3, 5, 1)
  
  -- Status area  
  debug_dlg:add_label("Status:", 1, 4, 1, 1)
  debug_messages.status = debug_dlg:add_label("Initializing components", 2, 4, 5, 1)
  
  -- Network status
  debug_dlg:add_label("Network:", 1, 5, 1, 1)
  debug_messages.network = debug_dlg:add_label("Checking connectivity...", 2, 5, 5, 1)
  
  -- Empty row for spacing
  debug_dlg:add_label("", 1, 6, 6, 1)
  
  -- Debug log area - 8 individual rows for messages
  debug_dlg:add_label("Debug Log:", 1, 7, 6, 1)
  
  -- Create 8 individual log message rows (rows 8-15)
  for i = 1, 8 do
    local row_number = 7 + i -- Start at row 8
    debug_log_rows[i] = debug_dlg:add_label("", 1, row_number, 6, 1)
  end
  
  -- Initialize first message
  debug_log_rows[1]:set_text("VLSub initialization starting...")
  
  -- Buttons (visible at row 16) - Store references for dynamic updates
  debug_messages.ok_button = debug_dlg:add_button("⏳ Continue", function() 
    close_debug_window()
    show_appropriate_window()
  end, 2, 16, 2, 1)
  
  debug_messages.cancel_button = debug_dlg:add_button("❌ Close", function() 
    close_debug_window()
    vlc.deactivate() 
  end, 4, 16, 2, 1)
  
  debug_dlg:show()
  collectgarbage()
end


function close_dlg()
  vlc.msg.dbg("[VLSub] Closing dialog")

  if dlg ~= nil then 
    --~ dlg:delete() -- Throw an error
    dlg:hide() 
  end
  
  dlg = nil
  input_table = nil
  input_table = {}
  collectgarbage() --~ !important	
end

            --[[ Drop down / config association]]--
function assoc_select_conf(select_id, option, conf, ind, default)
-- Helper for i/o interaction between drop down and option list
  select_conf[select_id] = {
    cf = conf,
    opt  = option,
    dflt = default,
    ind = ind
  }
  -- DON'T reorder - just display in original order
  display_select(select_id)
end

function set_default_option(select_id)
-- DON'T reorder languages - this was causing index issues
-- Just keep the original order from conf
  -- This function now does nothing to avoid reordering
end

-- Missing display_select function that's called by assoc_select_conf
function display_select(select_id)
-- Display the drop down values with flags and consistent ordering
-- Put selected item first so VLC shows it as selected, but keep track of real indices
  local conf = select_conf[select_id].cf
  local opt = select_conf[select_id].opt
  local option = openSub.option[opt]
  local default = select_conf[select_id].dflt
  
  -- If we have a default option and no selection, show default first
  if not option and default then
    input_table[select_id]:add_value(default, 0)
    -- Then add all languages in original order with flags
    for k, l in ipairs(conf) do
      local displayText = l[2] or "" -- language name
      local flag = getLanguageFlag(l[1]) or ""
      if flag ~= "" then
        displayText = displayText .. " " .. flag
      end
      input_table[select_id]:add_value(displayText, k)
    end
    return
  end
  
  -- If we have a selected option, put it first, then others
  local selected_found = false
  for k, l in ipairs(conf) do
    if option and option == l[1] then
      -- Put selected language first with flag
      local flag = getLanguageFlag(l[1])
      local displayText = l[2] -- language name
      if flag ~= "" then
        displayText = displayText .. " " .. flag
      end
      input_table[select_id]:add_value(displayText, k)
      selected_found = true
      break
    end
  end
  
  -- Add default if exists and no language was selected
  if default and not selected_found then
    input_table[select_id]:add_value(default, 0)
  end
  
  -- Add all other languages in original order with flags
  for k, l in ipairs(conf) do
    if not option or option ~= l[1] then
      local flag = getLanguageFlag(l[1])
      local displayText = l[2] -- language name
      if flag ~= "" then
        displayText = displayText .. " " .. flag
      end
      input_table[select_id]:add_value(displayText, k)
    end
  end
end





-- Updated display_subtitles function - button is always present, logic handles empty results
function display_subtitles()
  local mainlist = input_table["mainlist"]
  mainlist:clear()
  
  -- Safe check for no results - FIXED to avoid string/number comparison error
  local hasNoResults = false
  local hasResults = false
  
  if not openSub.itemStore then
    vlc.msg.dbg("[VLSub] itemStore is nil")
    hasNoResults = true
  elseif type(openSub.itemStore) == "string" then
    if openSub.itemStore == "0" then
      vlc.msg.dbg("[VLSub] itemStore is string '0'")
      hasNoResults = true
    end
  elseif type(openSub.itemStore) == "number" then
    if openSub.itemStore == 0 then
      vlc.msg.dbg("[VLSub] itemStore is number 0")
      hasNoResults = true
    end
  elseif type(openSub.itemStore) == "table" then
    if #openSub.itemStore == 0 then
      vlc.msg.dbg("[VLSub] itemStore is empty table")
      hasNoResults = true
    else
      vlc.msg.dbg("[VLSub] itemStore has " .. #openSub.itemStore .. " items")
      hasResults = true
    end
  end
  
  if hasNoResults then 
    mainlist:add_value(lang["mess_no_res"], 1)
    
    -- Enhanced message for different search scenarios
    local message = "<b>"..lang["mess_complete"]..":</b> "..lang["mess_no_res"]
    
    if openSub.lastSearchMethod == "hash" and openSub.file.hash and openSub.file.hash ~= "" then
      message = message .. " for moviehash " .. openSub.file.hash
    elseif openSub.lastSearchMethod == "hash_fallback" then
      message = message .. " (searched by hash + name)"
      if openSub.file.hash and openSub.file.hash ~= "" then
        message = message .. " for moviehash " .. openSub.file.hash
      end
      if openSub.movie.title and openSub.movie.title ~= "" then
        message = message .. " and title '" .. openSub.movie.title .. "'"
      end
    end
    
    setMessage(message)
    
  elseif hasResults then 
    -- Get user selected languages in order
    local selectedLanguages = getUserSelectedLanguages()
    
    -- Group subtitles by language
    local groupedSubtitles = {}
    local otherSubtitles = {}
    
    -- Initialize groups for selected languages
    for _, langCode in ipairs(selectedLanguages) do
      groupedSubtitles[langCode] = {}
    end
    
    -- Group all subtitles by language
    for i, item in ipairs(openSub.itemStore) do
      local langCode = item.SubLanguageID or "?"
      local found = false
      
      -- Check if this language is in user's selection
      for _, selectedLang in ipairs(selectedLanguages) do
        if langCode == selectedLang then
          table.insert(groupedSubtitles[selectedLang], {item = item, originalIndex = i})
          found = true
          break
        end
      end
      
      -- If not in user's selection, put in "other" group
      if not found then
        table.insert(otherSubtitles, {item = item, originalIndex = i})
      end
    end
    
    local displayIndex = 1
    
    -- Display subtitles in language priority order
    for _, langCode in ipairs(selectedLanguages) do
      if groupedSubtitles[langCode] and #groupedSubtitles[langCode] > 0 then
        for _, subtitle in ipairs(groupedSubtitles[langCode]) do
          local item = subtitle.item
          local originalIndex = subtitle.originalIndex
          local displayText = buildSubtitleDisplayText(item, langCode)
          
          mainlist:add_value(displayText, originalIndex)
          displayIndex = displayIndex + 1
        end
      end
    end
    
    -- Display other languages at the end
    for _, subtitle in ipairs(otherSubtitles) do
      local item = subtitle.item
      local originalIndex = subtitle.originalIndex
      local langCode = item.SubLanguageID or "?"
      local displayText = buildSubtitleDisplayText(item, langCode)
      
      mainlist:add_value(displayText, originalIndex)
    end
    
    -- Enhanced completion message showing search method used
    local message = "<b>"..lang["mess_complete"]..":</b> "..
      #(openSub.itemStore).."  "..lang["mess_res"]
    
    if openSub.lastSearchMethod == "hash" and openSub.file.hash and openSub.file.hash ~= "" then
      message = message .. " for moviehash " .. openSub.file.hash
    elseif openSub.lastSearchMethod == "hash_fallback" then
      message = message .. " (found via name search after hash failed)"
      if openSub.movie.title and openSub.movie.title ~= "" then
        message = message .. " for title '" .. openSub.movie.title .. "'"
      end
    elseif openSub.lastSearchMethod == "name" then
      if openSub.movie.title and openSub.movie.title ~= "" then
        message = message .. " for title '" .. openSub.movie.title .. "'"
      end
    end
    
    setMessage(message)
  end
end

-- New function to open subtitle link in browser
function open_subtitle_link()
  -- Check if we have any results first
  local hasResults = false
  
  if openSub.itemStore and type(openSub.itemStore) == "table" and #openSub.itemStore > 0 then
    hasResults = true
  end
  
  if not hasResults then
    setMessage(error_tag("No subtitles available. Please search first."))
    return false
  end
  
  local index = get_first_sel(input_table["mainlist"])
  
  if index == 0 then
    setMessage(error_tag("Please select a subtitle from the list first."))
    return false
  end
  
  local item = openSub.itemStore[index]
  
  -- Use the direct URL from API results
  local subtitle_url = item.url
  
  if not subtitle_url or subtitle_url == "" then
    setMessage(error_tag("No URL available for this subtitle."))
    return false
  end
  
  vlc.msg.dbg("[VLSub] Opening subtitle URL from API: " .. subtitle_url)
  
  -- Create clickable link message
  local link_message = "<span style='color:#181'>"
  link_message = link_message .. "<b>Subtitle Link:</b>"
  link_message = link_message .. "</span> &nbsp;"
  link_message = link_message .. "<a href='" .. subtitle_url .. "'>"
  link_message = link_message .. (item.SubFileName or "View Subtitle") .. "</a>"
  
  setMessage(link_message)
  
  return true
end


-- Updated buildSubtitleDisplayText function without language brackets
function buildSubtitleDisplayText(item, langCode)
  local flag = getLanguageFlag(langCode)
  
  -- Build display text starting with flag (if available)
  local displayText = ""
  if flag ~= "" then
    displayText = flag .. " "
  end
  
  -- Add filename/release name
  displayText = displayText .. (item.SubFileName or "???")
  
  -- REMOVED: Add language code in brackets
  -- displayText = displayText .. " [" .. langCode .. "]"
  
  -- Quality indicators with Unicode icons
  local qualityIndicators = {}
  
  -- Moviehash match (highest priority - exact match)
  if item.MoviehashMatch then
    table.insert(qualityIndicators, "🎯") -- Target icon for perfect match
  end
  
  -- Trusted uploader
  if item.FromTrusted then
    table.insert(qualityIndicators, "✓") -- Checkmark for trusted
  end
  
  -- HD quality
  if item.HD then
    table.insert(qualityIndicators, "🎬") -- Film camera for HD
  end
  
  -- Hearing impaired
  if item.HearingImpaired then
    table.insert(qualityIndicators, "♿") -- Wheelchair for hearing impaired
  end
  
  -- Translation indicators (lower priority)
  if item.AITranslated then
    table.insert(qualityIndicators, "🤖") -- Robot for AI translated
  elseif item.MachineTranslated then
    table.insert(qualityIndicators, "⚙️") -- Gear for machine translated
  end
  
  -- Add quality indicators if any
  if #qualityIndicators > 0 then
    displayText = displayText .. " " .. table.concat(qualityIndicators, "")
  end
  
  -- Only show CD count if it's not 1 CD
  local cdCount = tonumber(item.SubSumCD) or 1
  if cdCount > 1 then
    displayText = displayText .. " (" .. cdCount .. " CD)"
  end
  
  -- Add uploader info with icon
  if item.UploaderName and item.UploaderName ~= "" then
    local uploaderLower = string.lower(item.UploaderName)
    if uploaderLower ~= "anonymous" then
      displayText = displayText .. " 👤" .. item.UploaderName
    end
  end
  
  -- Add download count with downwards arrow
  local downloadCount = item.SubDownloadsCnt or "0"
  displayText = displayText .. " [" .. downloadCount .. "↓]"
  
  -- Add upload date at the end
  if item.UploadDate and item.UploadDate ~= "" then
    -- Parse ISO date format: "2024-08-01T14:54:58Z" -> "2024-08-01"
    local dateOnly = item.UploadDate:match("(%d%d%d%d%-%d%d%-%d%d)")
    if dateOnly then
      displayText = displayText .. " 📅" .. dateOnly
    end
  end
  
  return displayText
end


            --[[ Config & interface localization]]--

function check_config()
  -- Make a copy of english translation to use it as default 
  -- in case some element aren't translated in other translations
  eng_translation = {}
  for k, v in pairs(openSub.option.translation) do
    eng_translation[k] = v
  end
  
  -- Get available translation full name from code
  trsl_names = {}
  for i, lg in ipairs(languages) do
    trsl_names[lg[1]] = lg[2]
  end
  
  if is_window_path(vlc.config.datadir()) then
    openSub.conf.os = "win"
    slash = "\\"
  else
    openSub.conf.os = "lin"
    slash = "/"
  end
  
  local path_generic = {"lua", "extensions", "userdata", "vlsub.com"}
  local dirPath = slash..table.concat(path_generic, slash)
  local filePath	= slash.."vlsub_conf.json"
  local config_saved = false
  sub_dir = slash.."vlsub_subtitles"
  
  -- Check if config file path is stored in vlc config
  local other_dirs = {}
  
  for path in 
  vlc.config.get("sub-autodetect-path"):gmatch("[^,]+") do
    if path:match(".*"..sub_dir.."$") then
      openSub.conf.dirPath = path:gsub(
        "%s*(.*)"..sub_dir.."%s*$", "%1")
      config_saved = true
    end
    table.insert(other_dirs, path)
  end
  
  -- if not stored in vlc config
  -- try to find a suitable config file path 
  
  if openSub.conf.dirPath then
    if not is_dir(openSub.conf.dirPath) and
    (openSub.conf.os == "lin"  or
    is_win_safe(openSub.conf.dirPath)) then
      mkdir_p(openSub.conf.dirPath)
    end
  else
    local userdatadir = vlc.config.userdatadir()
    local datadir = vlc.config.datadir()
    
    -- check if the config already exist
    if file_exist(userdatadir..dirPath..filePath) then
      -- in vlc.config.userdatadir()
      openSub.conf.dirPath = userdatadir..dirPath
      config_saved = true
    elseif file_exist(datadir..dirPath..filePath) then
      -- in vlc.config.datadir()
      openSub.conf.dirPath = datadir..dirPath
      config_saved = true
    else
      -- if not found determine an accessible path
      local extension_path = slash..path_generic[1]
        ..slash..path_generic[2]
      
      -- use the same folder as the extension if accessible
      if is_dir(userdatadir..extension_path) 
      and file_touch(userdatadir..dirPath..filePath) then
          openSub.conf.dirPath = userdatadir..dirPath
      elseif file_touch(datadir..dirPath..filePath) then
        openSub.conf.dirPath = datadir..dirPath
      end
      
      -- try to create working dir in user folder
      if not openSub.conf.dirPath
      and is_dir(userdatadir) then
        if not is_dir(userdatadir..dirPath) then
          mkdir_p(userdatadir..dirPath)
        end
        if is_dir(userdatadir..dirPath) and
        file_touch(userdatadir..dirPath..filePath) then
          openSub.conf.dirPath = userdatadir..dirPath
        end
      end
      
      -- try to create working dir in vlc folder	
      if not openSub.conf.dirPath and
      is_dir(datadir) then
        if not is_dir(datadir..dirPath) then
          mkdir_p(datadir..dirPath)
        end
        if file_touch(datadir..dirPath..filePath) then
          openSub.conf.dirPath = datadir..dirPath
        end
      end
    end
  end
  
  if openSub.conf.dirPath then
    vlc.msg.dbg("[VLSub] Working directory: " ..
      (openSub.conf.dirPath or "not found"))
    
    openSub.conf.filePath = openSub.conf.dirPath..filePath 
    openSub.conf.localePath = openSub.conf.dirPath..slash.."locale"
    
    if config_saved 
    and file_exist(openSub.conf.filePath) then
      vlc.msg.dbg(
        "[VLSub] Loading config file: "..openSub.conf.filePath)
      load_config()
    else
      vlc.msg.dbg("[VLSub] No config file")
      getenv_lang()
      config_saved = save_config()
      if not config_saved then
        vlc.msg.dbg("[VLSub] Unable to save config")
      end
    end
    
    -- Check presence of a translation file 
    -- in "%vlsub_directory%/locale"
    -- Add translation files to available translation list
    local file_list = list_dir(openSub.conf.localePath)
    local translations_avail = openSub.conf.translations_avail
    
    if file_list then
      for i, file_name in ipairs(file_list) do
        local lg =  string.gsub(
          file_name,
          "^(%w%w%w).xml$",
          "%1")
        if lg 
        and not openSub.option.translations_avail[lg] then
          table.insert(translations_avail, {
            lg,
            trsl_names[lg]
          })
        end
      end
    end
    
    -- Load selected translation from file
    if openSub.option.intLang ~= "eng" 
    and not openSub.conf.translated
    then
      local transl_file_path = openSub.conf.localePath..
        slash..openSub.option.intLang..".xml"
      if file_exist(transl_file_path) then
        vlc.msg.dbg(
          "[VLSub] Loading translation from file: "..
          transl_file_path)
        load_transl(transl_file_path)
      end
    end
  else
    vlc.msg.dbg("[VLSub] Unable to find a suitable path"..
      "to save config, please set it manually")
  end
  
  lang = nil
  lang = options.translation -- just a short cut
  
  if not vlc.net or not vlc.net.poll then
    dlg = vlc.dialog(
      openSub.conf.useragent..': '..lang["mess_error"])
    interface_no_support()
    dlg:show()
    return false
  end
  
  SetDownloadBehaviours()
  if not openSub.conf.dirPath then
    setError(lang["mess_err_conf_access"])
  end
    
  -- Set table list of available translations from assoc. array 
  -- so it is sortable
  
  for k, l in pairs(openSub.option.translations_avail) do		
    if k == openSub.option.int_research then
      table.insert(openSub.conf.translations_avail, 1, {k, l})
    else
      table.insert(openSub.conf.translations_avail, {k, l})
    end
  end
  collectgarbage()
  return true
end

function load_config()
-- Overwrite default conf with loaded conf
  local tmpFile = io.open(openSub.conf.filePath, "rb")
  if not tmpFile then return false end
  local resp = tmpFile:read("*all")
  tmpFile:flush()
  tmpFile:close()
  -- local option = parse_xml(resp)
   local option, pos, err = json.decode (resp)  
  
  for key, value in pairs(option) do
    if type(value) == "table" then
      if key == "translation" then
        openSub.conf.translated = true
        for k, v in pairs(value) do
          openSub.option.translation[k] = v
        end
      else
        openSub.option[key] = value
      end
    else
      if value == "true" then
        openSub.option[key] = true
      elseif value == "false" then
        openSub.option[key] = false
      else
        openSub.option[key] = value
      end
    end
  end
  collectgarbage()
end

function load_transl(path)
-- Overwrite default conf with loaded conf
  local tmpFile = assert(io.open(path, "rb"))
  local resp = tmpFile:read("*all")
  tmpFile:flush()
  tmpFile:close()
  openSub.option.translation = nil
  
  openSub.option.translation = parse_xml(resp)	
  collectgarbage()
end

function apply_translation()
-- Overwrite default conf with loaded conf
  for k, v in pairs(eng_translation) do
    if not openSub.option.translation[k] then
      openSub.option.translation[k] = eng_translation[k]
    end
  end
end

function getenv_lang()
-- Retrieve the user OS language 
  local os_lang = os.getenv("LANG")
  
  if os_lang then -- unix, mac
    openSub.option.language = string.sub(os_lang, 0, 2)
  else -- Windows
    local lang_w = string.match(
      os.setlocale("", "collate"),
      "^[^_]+")
    for i, v in ipairs(openSub.conf.languages) do
     if v[2] == lang_w then
      openSub.option.language = v[1]
     end
    end 
  end
end

-- Modified apply_config function to preserve success messages
function apply_config()
  -- Handle dropdown selections - get the actual language code from the stored mapping
  for select_id, v in pairs(select_conf) do
    if input_table[select_id]
    and select_conf[select_id] then
      local sel_val = input_table[select_id]:get_value()
      local sel_cf = select_conf[select_id]
      local opt = sel_cf.opt

      if sel_val == 0 and sel_cf.dflt then
        openSub.option[opt] = nil  -- Default/None selected
      elseif sel_val > 0 and sel_cf.cf[sel_val] then
        -- Get the language code from the original config array
        openSub.option[opt] = sel_cf.cf[sel_val][1]
      end
    end
  end

  -- Get username and password, trim whitespace
  local username = trim(input_table['os_username']:get_text() or "")
  local password = trim(input_table['os_password']:get_text() or "")

  -- Set the trimmed values
  openSub.option.os_username = username
  openSub.option.os_password = password

  if input_table["langExt"]:get_value() == 2 then
    openSub.option.langExt = not openSub.option.langExt
  end

  if input_table["removeTag"]:get_value() == 2 then
    openSub.option.removeTag = not openSub.option.removeTag
  end

  -- Set a custom working directory
  local dir_path = input_table['dir_path']:get_text()
  local dir_path_err = false
  if trim(dir_path) == "" then dir_path = nil end

  if dir_path ~= openSub.conf.dirPath then
    if openSub.conf.os == "lin"
    or is_win_safe(dir_path)
    or not dir_path then
      local other_dirs = {}

      for path in
      vlc.config.get(
        "sub-autodetect-path"):gmatch("[^,]+"
      ) do
        path = trim(path)
        if path ~= (openSub.conf.dirPath or "")..sub_dir then
          table.insert(other_dirs, path)
        end
      end
      openSub.conf.dirPath = dir_path
      if dir_path then
        table.insert(other_dirs,
        string.gsub(dir_path, "^(.-)[\\/]?$", "%1")..sub_dir)

        if not is_dir(dir_path) then
          mkdir_p(dir_path)
        end

        openSub.conf.filePath = openSub.conf.dirPath..
          slash.."vlsub_conf.json"
        openSub.conf.localePath = openSub.conf.dirPath..
          slash.."locale"
      else
        openSub.conf.filePath = nil
        openSub.conf.localePath = nil
      end
      vlc.config.set(
        "sub-autodetect-path",
        table.concat(other_dirs, ", "))
    else
      dir_path_err = true
      setError(lang["mess_err_wrong_path"]..
        "<br><b>"..
        string.gsub(
          dir_path,
          "[^%:%w%p%s§¤]+",
          "<span style='color:#B23'>%1</span>"
        )..
        "</b>")
    end
  end

  if openSub.conf.dirPath and not dir_path_err then
    -- Check if we have credentials before attempting login
    if username == "" or password == "" then
      setError("Username and password are required for authentication")
      is_authenticated = false
      return
    end

    -- Clear any existing session to force fresh login for verification
    openSub.session.token = ""
    openSub.session.token_expires = 0
    openSub.session.user_info = nil

    local login_success = openSub.checkLoginAndUserInfo()

    if login_success then
      is_authenticated = true
      local config_saved = save_config()
      if not config_saved then
        setError(lang["mess_err_conf_access"])
        is_authenticated = false
      else
        -- Keep the successful message that was set by checkLoginAndUserInfo
        local current_message = input_table["message"]:get_text()
        if current_message and string.find(current_message, "Success") then
          setMessage(current_message .. "<br>Configuration saved. You can now close this window.")
        else
          setMessage(success_tag("Config saved and login successful! You can now close this window."))
        end
        
        -- FIXED: Don't refresh the interface - just update the close button state
        vlc.msg.dbg("[VLSub] Authentication successful, updating interface without refresh")
        
        -- Update the close button to be enabled (if it exists)
        -- Remove the old disabled close button label and add enabled button
        if dlg then
          -- Try to update just the close button area without full refresh
          local close_button_exists = false
          
          -- Check if we can add the close button (this might fail if button already exists)
          local success, err = pcall(function()
            dlg:add_button(
              "❌ " .. lang["int_close"],
              show_main, 4, 11, 1, 1)
          end)
          
          if success then
            vlc.msg.dbg("[VLSub] Successfully added close button")
          else
            vlc.msg.dbg("[VLSub] Close button may already exist: " .. tostring(err))
          end
          
          dlg:update()
        end
      end
    else
      is_authenticated = false
      vlc.msg.dbg("[VLSub] Login failed during apply_config, staying in config window.")
    end
  else
    setError(lang["mess_err_conf_access"])
    is_authenticated = false
  end
end




function save_config()
-- Dump local config into config file 
  if openSub.conf.dirPath
  and openSub.conf.filePath then
    vlc.msg.dbg(
      "[VLSub] Saving config file:  "..
      openSub.conf.filePath)
    
    if file_touch(openSub.conf.filePath) then
      local tmpFile = assert(
        io.open(openSub.conf.filePath, "wb"))
        local resp = json.encode (openSub.option, { indent = true })        
      --local resp = dump_xml(openSub.option)
      tmpFile:write(resp)
      tmpFile:flush()
      tmpFile:close()
      tmpFile = nil
    else
      return false
    end
    collectgarbage()
    return true
  else
    vlc.msg.dbg("[VLSub] Unable fount a suitable path "..
      "to save config, please set it manually")
    setError(lang["mess_err_conf_access"])
    return false
  end
end

function SetDownloadBehaviours()
  openSub.conf.downloadBehaviours = nil 
  openSub.conf.downloadBehaviours = { 
    {'save', lang["int_dowload_save"]},
    {'manual', lang["int_dowload_manual"]}
  }
end

function get_available_translations()
-- Get all available translation files from the internet
-- (drop previous direct download from github repo 
-- causing error  with github https CA certficate on OS X an XP)
-- https://github.com/exebetche/vlsub/tree/master/locale

  local translations_url = "http://addons.videolan.org/CONTENT/"..
    "content-files/148752-vlsub_translations.xml"
  
  if input_table['intLangBut']:get_text() == lang["int_search_transl"] 
  then
    openSub.actionLabel = lang["int_searching_transl"]
    
    local translations_content = get(translations_url)
    if not translations_content then
      collectgarbage()
      return false
    end
    local translations_avail = openSub.option.translations_avail
    all_trsl = parse_xml(translations_content)
    local lg, trsl
    
    for lg, trsl in pairs(all_trsl) do
      if lg ~= options.intLang[1] 
      and not translations_avail[lg] then
        translations_avail[lg] = trsl_names[lg] or ""
        table.insert(openSub.conf.translations_avail, {
          lg,
          trsl_names[lg]
        })
        input_table['intLang']:add_value(
          trsl_names[lg],
          #openSub.conf.translations_avail)
      end
    end
    
    setMessage(success_tag(lang["mess_complete"]))
    collectgarbage()
  end
  return true
end

function set_translation(lg)
  openSub.option.translation = nil
  openSub.option.translation = {}
  
  if lg == 'eng' then
    for k, v in pairs(eng_translation) do
      openSub.option.translation[k] = v
    end
  else
    -- If translation file exists in /locale directory load it
    if openSub.conf.localePath 
    and file_exist(openSub.conf.localePath..
      slash..lg..".xml") then
      local transl_file_path = openSub.conf.localePath..
      slash..lg..".xml"
      vlc.msg.dbg("[VLSub] Loading translation from file: "..
        transl_file_path)
      load_transl(transl_file_path)
      apply_translation()
    else
      -- Load translation file from internet
      if not all_trsl and not get_available_translations() then
        setMessage(error_tag(lang["mess_err_cant_download_interface_translation"]))
        return false
      end

      if not all_trsl or not all_trsl[lg] then
        vlc.msg.dbg("[VLSub] Error, translation not found")
        return false
      end
      openSub.option.translation = all_trsl[lg]
      apply_translation()
      all_trsl = nil
    end
  end
  
  lang = nil
  lang = openSub.option.translation
  collectgarbage()
  return true
end 

            --[[ Core ]]--

openSub = {
  itemStore = nil,
  actionLabel = "",
  lastSearchMethod = "",
  conf = {
    url = "http://api.opensubtitles.org/xml-rpc",
    path = nil,
    HTTPVersion = "1.1",
    userAgentHTTP = app_useragent,
    useragent = app_useragent,
    translations_avail = {},
    downloadBehaviours = nil,
    languages = sub_languages
  },
  option = options,
  session = {
    loginTime = 0,
    token = "",
    -- New fields for REST API
    user_info = nil,
    token_expires = 0, -- Timestamp when token expires
    base_url = "api.opensubtitles.com"    
  },
  file = {
    hasInput = false,
    uri = nil,
    ext = nil,
    name = nil,
    path = nil,
    protocol = nil,
    cleanName = nil,
    dir = nil,
    hash = nil,
    bytesize = nil,
    fps = nil,
    timems = nil,
    frames = nil,
    guessit_data = nil
  },
  movie = {
    title = "",
    seasonNumber = "",
    episodeNumber = "",
    year = "",
    sublanguageid = ""
  },
  request = function(methodName)
    local params = openSub.methods[methodName].params()
    local reqTable = openSub.getMethodBase(methodName, params)
    local request = "<?xml version='1.0'?>"..dump_xml(reqTable)
    local host, path = parse_url(openSub.conf.url)		
    local header = {
      "POST "..path.." HTTP/"..openSub.conf.HTTPVersion, 
      "Host: "..host, 
      "User-Agent: "..openSub.conf.userAgentHTTP, 
      "Content-Type: text/xml", 
      "Content-Length: "..string.len(request),
      "",
      ""
    }
    request = table.concat(header, "\r\n")..request
    
    local response
    local status, responseStr = http_req(host, 80, request)
    
    if status == 200 then 
      response = parse_xmlrpc(responseStr)
      
      if response then
        if response.status == "200 OK" then
          return openSub.methods[methodName]
            .callback(response)
        elseif response.status == "406 No session" then
          openSub.request("LogIn")
        elseif response then
          setError("code '"..
            response.status..
            "' ("..status..")")
          return false
        end
      else
        setError("Server not responding")
        return false
      end
    elseif status == 401 then
      setError("Request unauthorized")
      response = parse_xmlrpc(responseStr)
      if openSub.session.token ~= response.token then
        setMessage("Session expired, retrying")
        openSub.session.token = response.token
        openSub.request(methodName)
      end
      return false
    elseif status == 503 then 
      setError("Server overloaded, please retry later")
      return false
    end
    
  end,
  getMethodBase = function(methodName, param)
    if openSub.methods[methodName].methodName then
      methodName = openSub.methods[methodName].methodName
    end
    
    local request = {
     methodCall={
      methodName=methodName,
      params={ param=param }}}
    
    return request
  end,
  methods = {
    LogIn = {
      params = function()
        openSub.actionLabel = lang["action_login"]
        return {
          { value={ string=openSub.option.os_username } },
          { value={ string=openSub.option.os_password } },
          { value={ string=openSub.movie.sublanguageid } },
          { value={ string=openSub.conf.useragent } } 
        }
      end,
      callback = function(resp)
        openSub.session.token = resp.token
        openSub.session.loginTime = os.time()
        return true
      end
    },
    LogOut = {
      params = function()
        openSub.actionLabel = lang["action_logout"]
        return {
          { value={ string=openSub.session.token } } 
        }
      end,
      callback = function()
        return true
      end
    },
    NoOperation = {
      params = function()
        openSub.actionLabel = lang["action_noop"]
        return {
          { value={ string=openSub.session.token } } 
        }
      end,
      callback = function(resp)
        return true
      end
    },
    SearchSubtitlesByHash = {
      methodName = "SearchSubtitles",
      params = function()
        openSub.actionLabel = lang["action_search"]
        setMessage(openSub.actionLabel..": "..
          progressBarContent(0))
        
        return {
          { value={ string=openSub.session.token } },
          { value={
            array={
             data={
              value={
               struct={
                member={
                 { name="sublanguageid", value={ 
                  string=openSub.movie.sublanguageid } 
                  },
                 { name="moviehash", value={ 
                  string=openSub.file.hash } },
                 { name="moviebytesize", value={ 
                  double=openSub.file.bytesize } } 
                  }}}}}}}
        }
      end,
      callback = function(resp)
        openSub.itemStore = resp.data
      end
    },
    SearchSubtitles = {
      methodName = "SearchSubtitles",
      params = function()
        openSub.actionLabel = lang["action_search"]
        setMessage(openSub.actionLabel..": "..
          progressBarContent(0))
                
        local member = {
             { name="sublanguageid", value={ 
              string=openSub.movie.sublanguageid } },
             { name="query", value={ 
              string=openSub.movie.title } } }
             
        
if isValidPositiveNumber(openSub.movie.seasonNumber) then
  table.insert(params, "season_number=" .. openSub.movie.seasonNumber)
end


if isValidPositiveNumber(openSub.movie.episodeNumber) then
  table.insert(params, "season_number=" .. openSub.movie.episodeNumber)
end

        
        return {
          { value={ string=openSub.session.token } },
          { value={
            array={
             data={
              value={
               struct={
                member=member
                  }}}}}}
        }
      end,
      callback = function(resp)
        openSub.itemStore = resp.data
      end
    },
    SearchSubtitles2 = {
      methodName = "SearchSubtitles",
      params = function()
        openSub.actionLabel = lang["action_search"]
        setMessage(openSub.actionLabel..": "..
          progressBarContent(0))
                
        local member = {
             { name="sublanguageid", value={ 
              string=openSub.movie.sublanguageid } },
             { name="tag", value={ 
              string=openSub.file.completeName } } }
        
        return {
          { value={ string=openSub.session.token } },
          { value={
            array={
             data={
              value={
               struct={
                member=member
                  }}}}}}
        }
      end,
      callback = function(resp)
        openSub.itemStore = resp.data
      end
    }
  },
  getInputItem = function()
    return vlc.item or vlc.input.item()
  end,
getFileInfo = function()
  -- Get video file path, name, extension from input uri
  local item = openSub.getInputItem()
  local file = openSub.file
  if not item then
    file.hasInput = false;
    file.cleanName = nil;
    file.protocol = nil;
    file.path = nil;
    file.ext = nil;
    file.uri = nil;
    file.guessit_data = nil; -- Clear GuessIt data when no input
  else
    vlc.msg.dbg("[VLSub] Video URI: "..item:uri())
    local parsed_uri = vlc.net.url_parse(item:uri())
    file.uri = item:uri()
    file.protocol = parsed_uri["protocol"]
    file.path = parsed_uri["path"]
    
    -- Corrections
    
    -- For windows
    file.path = string.match(file.path, "^/(%a:/.+)$") or file.path
    
    -- For file in archive
    local archive_path, name_in_archive = string.match(
      file.path, '^([^!]+)!/([^!/]*)$')
    if archive_path and archive_path ~= "" then
      file.path = string.gsub(
        archive_path,
        '\063',
        '%%')
      file.path = vlc.strings.decode_uri(file.path)
      file.completeName = string.gsub(
        name_in_archive,
        '\063',
        '%%')
      file.completeName = vlc.strings.decode_uri(
        file.completeName)
      file.is_archive = true
    else -- "classic" input
      file.path = vlc.strings.decode_uri(file.path)
      file.dir, file.completeName = string.match(
        file.path,
        '^(.+/)([^/]*)$')
      if file.dir == nil then
        -- happens on http://example.org/?x=y
        file.dir = openSub.conf.dirPath..slash
      end
      
      local file_stat = vlc.net.stat(file.path)
      if file_stat 
      then
        file.stat = file_stat
      end
      
      file.is_archive = false
    end
    
    if file.completeName == nil then
      file.completeName = ''
    end
    file.name, file.ext = string.match(
      file.completeName,
      '^([^/]-)%.?([^%.]*)$')
    
    if file.ext == "part" then
      file.name, file.ext = string.match(
        file.name,
        '^([^/]+)%.([^%.]+)$')
    end
    
    file.hasInput = true;
    file.cleanName = string.gsub(
      file.name,
      "[%._]", " ")
    
    vlc.msg.dbg("[VLSub] file info " .. json.encode(file, { indent = true }))
    

    -- Call GuessIt API when we have a valid filename
    if file.completeName and file.completeName ~= "" then
      vlc.msg.dbg("[VLSub] Calling GuessIt for filename: " .. file.completeName)
      openSub.callGuessIt(file.completeName)
    end
  end
  collectgarbage()
end,
 

-- Modify the getMovieInfo function to populate the year field
getMovieInfo = function()
  -- Clean video file name and check for season/episode pattern in title
  if not openSub.file.name then
    openSub.movie.title = ""
    openSub.movie.seasonNumber = ""
    openSub.movie.episodeNumber = ""
    openSub.movie.year = ""  -- ADD THIS LINE
    return false 
  end
  
  local infoString = openSub.file.cleanName
  if infoString == nil then
    infoString = ''
  end
  
  if infoString == '' then
    -- read from meta-title
    local meta = vlc.var.get(vlc.object.input(), 'meta-title')
    if meta ~= nil then
      infoString = meta
    end
  end
  
  if infoString == '' then
    -- read from metadata
    local metas = vlc.input.item():metas()
    if metas['title'] ~= nil then
      infoString = metas['title']
    end
  end
  
  -- Try to use GuessIt data first if available
  if openSub.file.guessit_data then
    local guessit = openSub.file.guessit_data
    
    if guessit.title then
      openSub.movie.title = guessit.title
    else
      -- Fallback to parsed title from filename
      openSub.movie.title = infoString
    end
    
    -- Set year from GuessIt
    if guessit.year then
      openSub.movie.year = tostring(guessit.year)
    else
      openSub.movie.year = ""
    end
    
    -- Use GuessIt season/episode if available
    if guessit.season then
      openSub.movie.seasonNumber = tostring(guessit.season)
    else
      openSub.movie.seasonNumber = ""
    end
    
    if guessit.episode then
      openSub.movie.episodeNumber = tostring(guessit.episode)
    else
      openSub.movie.episodeNumber = ""
    end
    
    vlc.msg.dbg("[VLSub] Using GuessIt data - Title: " .. (openSub.movie.title or "none") .. 
                ", Year: " .. (openSub.movie.year or "none") ..
                ", Season: " .. (openSub.movie.seasonNumber or "none") .. 
                ", Episode: " .. (openSub.movie.episodeNumber or "none"))
  else
    -- Fallback to original parsing logic if GuessIt data not available
    local showName, seasonNumber, episodeNumber = string.match(
      infoString,
      "(.+)[sS](%d?%d)[eE](%d%d).*")

    if not showName then
      showName, seasonNumber, episodeNumber = string.match(
      infoString,
      "(.-)(%d?%d)[xX](%d%d).*")
    end
    
    if showName then
      openSub.movie.title = showName
      openSub.movie.seasonNumber = seasonNumber
      openSub.movie.episodeNumber = episodeNumber
    else
      openSub.movie.title = infoString
      openSub.movie.seasonNumber = ""
      openSub.movie.episodeNumber = ""
    end
    
    -- Try to extract year from title using regex (fallback)
    local yearMatch = string.match(infoString, ".*(%d%d%d%d).*")
    if yearMatch then
      openSub.movie.year = yearMatch
    else
      openSub.movie.year = ""
    end
    
    vlc.msg.dbg("[VLSub] Using fallback parsing - Title: " .. (openSub.movie.title or "none") .. 
                ", Year: " .. (openSub.movie.year or "none") ..
                ", Season: " .. (openSub.movie.seasonNumber or "none") .. 
                ", Episode: " .. (openSub.movie.episodeNumber or "none"))
  end
  
  collectgarbage()
end,  
  -- Modified getMovieHash function with safety checks
 getMovieHash = function()
  -- Calculate movie hash
  openSub.actionLabel = lang["action_hash"]
  setMessage(openSub.actionLabel..": "..progressBarContent(0))
  
  local item = openSub.getInputItem()
  
  if not item then
    setError(lang["mess_no_input"])
    return false
  end
  
  openSub.getFileInfo()
  
  -- SAFETY CHECK: Only proceed with local files
  if not openSub.isLocalFileForHashing() then
    setError("Hash search only works with local video files")
    return false
  end
    
  if not openSub.file.path then
    setError(lang["mess_not_found"])
    return false
  end
  
  local data_start = ""
  local data_end = ""
  local size
  local chunk_size = 65536
      
  -- Get data for hash calculation
  if openSub.file.is_archive then
    vlc.msg.dbg("[VLSub] Read hash data from stream")
  
    local file = vlc.stream(openSub.file.uri)
    if not file then
      vlc.msg.dbg("[VLSub] Cannot open stream for archive")
      setError("Cannot open archive stream for hashing")
      return false
    end
    
    local dataTmp1 = ""
    local dataTmp2 = ""
    size = chunk_size
    
    data_start = file:read(chunk_size)
    if not data_start then
      vlc.msg.dbg("[VLSub] Cannot read start data from archive stream")
      setError("Cannot read archive data for hashing")
      return false
    end
    
    while data_end do
      size = size + string.len(data_end)
      dataTmp1 = dataTmp2
      dataTmp2 = data_end
      data_end = file:read(chunk_size)
      collectgarbage()
    end
    data_end = string.sub((dataTmp1..dataTmp2), -chunk_size)
  elseif not file_exist(openSub.file.path) 
  and openSub.file.stat then
    -- This case should not happen with our safety check, but keeping for completeness
    vlc.msg.dbg("[VLSub] File doesn't exist but has stat - this shouldn't happen with safety checks")
    setError("File not accessible for hashing")
    return false
  else
    vlc.msg.dbg("[VLSub] Read hash data from local file")
    local file = io.open(openSub.file.path, "rb")
    if not file then
      vlc.msg.dbg("[VLSub] Cannot open local file")
      setError("Cannot open local file for hashing")
      return false
    end
    
    data_start = file:read(chunk_size)
    if not data_start then
      file:close()
      setError("Cannot read file data for hashing")
      return false
    end
    
    size = file:seek("end", -chunk_size)
    if not size then
      file:close()
      setError("Cannot seek in file for hashing")
      return false
    end
    size = size + chunk_size
    
    data_end = file:read(chunk_size)
    if not data_end then
      file:close()
      setError("Cannot read end data for hashing")
      return false
    end
    
    file:close()
  end
  
  -- Validate we have the data we need
  if not data_start or not data_end or #data_start == 0 or #data_end == 0 then
    setError("Insufficient data for hash calculation")
    return false
  end
  
  -- Hash calculation
  local lo = size
  local hi = 0
  local o,a,b,c,d,e,f,g,h
  local hash_data = data_start..data_end
  local max_size = 4294967296
  local overflow
  
  for i = 1,  #hash_data, 8 do
    a,b,c,d,e,f,g,h = hash_data:byte(i,i+7)
    if not a then break end -- Safety check for incomplete byte reads
    
    -- Provide default values for missing bytes
    b = b or 0
    c = c or 0
    d = d or 0
    e = e or 0
    f = f or 0
    g = g or 0
    h = h or 0
    
    lo = lo + a + b*256 + c*65536 + d*16777216
    hi = hi + e + f*256 + g*65536 + h*16777216
    
    if lo > max_size then
      overflow = math.floor(lo/max_size)
      lo = lo-(overflow*max_size)
      hi = hi+overflow
    end
    
    if hi > max_size then
      overflow = math.floor(hi/max_size)
      hi = hi-(overflow*max_size)
    end
  end
  
  openSub.file.bytesize = size
  openSub.file.hash = string.format("%08x%08x", hi,lo)
  vlc.msg.dbg("[VLSub] Video hash: "..openSub.file.hash)
  vlc.msg.dbg("[VLSub] Video bytesize: "..size)
  collectgarbage()
  return true
end,
  checkSession = function()
  -- First try to load cached session
  if openSub.loadSessionCache() then
    return true
  end
  
  -- If no valid cache, perform new login
  return openSub.loginWithRestAPI()
end, 
getAuthHeader = function()
  if openSub.session.token ~= "" then
    return "Bearer " .. openSub.session.token
  end
  return nil
end,
  checkSessionOLD = function()
    
    if openSub.session.token == "" then
      openSub.request("LogIn")
    else
      openSub.request("NoOperation")
    end
  end
}

function searchHash()
  openSub.lastSearchMethod = "hash" -- Track that this started as a hash search
  
  -- Get file info first
  openSub.getFileInfo()
  
  -- Check if this is a suitable file for hashing BEFORE attempting hash calculation
  if not openSub.isLocalFileForHashing() then
    vlc.msg.dbg("[VLSub] File not suitable for hash search, falling back to name search")
    
    -- Set up for name search fallback immediately
    openSub.lastSearchMethod = "hash_fallback" -- Track that this is a fallback
    
    -- Get movie title and info for name search
    openSub.getMovieInfo()
    
    -- Use the detected title or get from input field
    if not openSub.movie.title or openSub.movie.title == "" then
      if input_table["title"] and input_table["title"]:get_text() then
        openSub.movie.title = trim(input_table["title"]:get_text())
      end
    end
    
    -- Only proceed with name search if we have a title
    if openSub.movie.title and openSub.movie.title ~= "" then
      vlc.msg.dbg("[VLSub] Performing name search for streaming content with title: " .. openSub.movie.title)
      
      openSub.movie.sublanguageid = getSelectedLanguages()
      
      -- Update the title field in the interface
      if input_table["title"] then
        input_table["title"]:set_text(openSub.movie.title)
      end
      
      -- Ensure session is valid and perform name search
      openSub.checkSession()
      openSub.searchSubtitlesNewAPI()
    else
      vlc.msg.dbg("[VLSub] Cannot perform search: no local file for hashing and no title for name search")
      openSub.itemStore = {}
      setError("Hash search requires local files. Please enter a title for name search.")
    end
    
    display_subtitles()
    return
  end
  
  -- Proceed with hash calculation for local files
  openSub.movie.sublanguageid = getSelectedLanguages()
  
  if not openSub.getMovieHash() then
    -- Hash calculation failed, try name search fallback if we have a title
    vlc.msg.dbg("[VLSub] Hash calculation failed, attempting name search fallback")
    
    openSub.lastSearchMethod = "hash_fallback"
    openSub.getMovieInfo()
    
    if not openSub.movie.title or openSub.movie.title == "" then
      if input_table["title"] and input_table["title"]:get_text() then
        openSub.movie.title = trim(input_table["title"]:get_text())
      end
    end
    
    if openSub.movie.title and openSub.movie.title ~= "" then
      vlc.msg.dbg("[VLSub] Performing name search fallback after hash failure")
      openSub.checkSession()
      openSub.searchSubtitlesNewAPI()
    else
      openSub.itemStore = {}
      setError("Hash calculation failed and no title available for name search")
    end
    
    display_subtitles()
    return
  end
  
  -- Hash calculation successful, proceed with hash search
  openSub.checkSession()
  openSub.searchSubtitlesByHashNewAPI()
  
  -- Check if hash search returned results
  vlc.msg.dbg("[VLSub] Hash search completed. itemStore type: " .. type(openSub.itemStore) .. ", value: " .. tostring(openSub.itemStore))
  
  local hasNoResults = false
  
  if not openSub.itemStore then
    hasNoResults = true
    vlc.msg.dbg("[VLSub] itemStore is nil")
  elseif type(openSub.itemStore) == "string" then
    if openSub.itemStore == "0" then
      hasNoResults = true
      vlc.msg.dbg("[VLSub] itemStore is string '0'")
    end
  elseif type(openSub.itemStore) == "number" then
    if openSub.itemStore == 0 then
      hasNoResults = true
      vlc.msg.dbg("[VLSub] itemStore is number 0")
    end
  elseif type(openSub.itemStore) == "table" then
    if #openSub.itemStore == 0 then
      hasNoResults = true
      vlc.msg.dbg("[VLSub] itemStore is empty table")
    end
  end
  
  if hasNoResults then
    vlc.msg.dbg("[VLSub] Hash search returned 0 results, falling back to name search")
    
    -- Set up for name search fallback
    openSub.lastSearchMethod = "hash_fallback"
    openSub.getMovieInfo()
    
    if not openSub.movie.title or openSub.movie.title == "" then
      if input_table["title"] and input_table["title"]:get_text() then
        openSub.movie.title = trim(input_table["title"]:get_text())
      end
    end
    
    if openSub.movie.title and openSub.movie.title ~= "" then
      vlc.msg.dbg("[VLSub] Performing fallback name search with title: " .. openSub.movie.title)
      
      openSub.itemStore = nil
      openSub.movie.sublanguageid = getSelectedLanguages()
      
      if input_table["title"] then
        input_table["title"]:set_text(openSub.movie.title)
      end
      
      openSub.checkSession()
      openSub.searchSubtitlesNewAPI()
    else
      vlc.msg.dbg("[VLSub] Cannot perform name search fallback: no title available")
    end
  end
  
  display_subtitles()
end

-- Updated searchIMBD_v2 function to capture year from input field
function searchIMBD_v2()
  openSub.lastSearchMethod = "name" -- Track that this is a name search
  
  openSub.movie.title = trim(input_table["title"]:get_text())
  openSub.movie.year = trim(input_table["year"]:get_text())  -- Capture year from input
  openSub.movie.seasonNumber = tonumber(
    input_table["seasonNumber"]:get_text())
  openSub.movie.episodeNumber = tonumber(
    input_table["episodeNumber"]:get_text())

  -- Debug: check available languages
  debugLanguages()
  
  openSub.movie.sublanguageid = getSelectedLanguages()
  
  if openSub.movie.title ~= "" then
    -- Use new API search instead of old XML-RPC
    openSub.searchSubtitlesNewAPI()
    display_subtitles()
  end
end

function searchIMBD()
  openSub.movie.title = trim(input_table["title"]:get_text())
  openSub.movie.seasonNumber = tonumber(
    input_table["seasonNumber"]:get_text())
  openSub.movie.episodeNumber = tonumber(
    input_table["episodeNumber"]:get_text())

  local sel = input_table["language"]:get_value()
  if sel == 0 then
    openSub.movie.sublanguageid = 'all'
  else
    openSub.movie.sublanguageid = openSub.conf.languages[sel][1]
  end
  
  if openSub.movie.title ~= "" then
    openSub.checkSession()
    openSub.request("SearchSubtitles")
    display_subtitles()
  end
end

-- Simplified GuessIt function with minimal debug output
openSub.callGuessIt = function(filename)
  if not filename or filename == "" then
    vlc.msg.dbg("[VLSub] GuessIt: No filename provided")
    return false
  end
  
  vlc.msg.dbg("[VLSub] GuessIt: Analyzing filename: " .. filename)
  
  -- Prepare the GuessIt request
  local guessit_url = config.guessit_api_url .. "?filename=" .. vlc.strings.encode_uri_component(filename)
  
  -- Make the API request
  local client = Curl.new()
  client:add_header("Api-Key", config.api_key)
  client:add_header("User-Agent", app_useragent)
  client:set_timeout(15)
  client:set_retries(1)
  
  local res = client:get(guessit_url)

  if not res then
  vlc.msg.dbg("[VLSub] IP geolocation: No response from API")
  return
end

if res.status ~= 200 then
  local status = res.status or "N/A"
  vlc.msg.dbg("[VLSub] IP geolocation: API request failed with status: " .. tostring(status))
  return
end

  
  if not res.body then
    vlc.msg.err("[VLSub] GuessIt: Empty response body")
    return false
  end
  
  -- Parse the GuessIt response
  local ok, guessit_response = pcall(json.decode, res.body, 1, true)
  if not ok or not guessit_response then
    vlc.msg.err("[VLSub] GuessIt: Failed to parse response: " .. (res.body or "no body"))
    return false
  end
  
  -- Store the GuessIt data
  openSub.file.guessit_data = guessit_response
  
  -- Simple debug output - just the raw JSON response
  vlc.msg.dbg("[VLSub] GuessIt: " .. json.encode(guessit_response, { indent = true }))
  
  return true
end





function add_sub(subPath)
  if vlc.item or vlc.input.item() then
    subPath = decode_uri(subPath)
    vlc.msg.dbg("[VLsub] Adding subtitle :" .. subPath)
    vlc.var.set(vlc.object.input(), 'sub-file', subPath)
    
    -- This is the key fix - use the same method as your working script
    local success = vlc.input.add_subtitle(subPath, true)
    
    if success then
      -- Force enable subtitles like your working script does
      -- vlc.var.set(vlc.object.input(), "spu", 1) --this was working
      vlc.var.set(vlc.object.input(), "spu", true)
      vlc.msg.dbg("[VLsub] Subtitle loaded and enabled successfully")
      return true
    else
      vlc.msg.err("[VLsub] Failed to load subtitle")
      return false
    end
  end
  return false
end


            --[[ Interface helpers]]--

function progressBarContent(pct)
  local accomplished = math.ceil(
    openSub.option.progressBarSize*pct/100)
  local left = openSub.option.progressBarSize - accomplished
  local content = "<span style='background-color:#181;color:#181;'>"..
    string.rep ("-", accomplished).."</span>"..
    "<span style='background-color:#fff;color:#fff;'>"..
    string.rep ("-", left)..
    "</span>"
  return content
end

function setMessage(str)
  if input_table["message"] then
    input_table["message"]:set_text(str)
    dlg:update()
  end
end


function setError(mess)
  setMessage(error_tag(mess))
end

function success_tag(str)
  return "<span style='color:#28a745;font-weight:bold;'> "..
    lang["mess_success"]..":</span> "..str..""
end

function error_tag(str)
  return "<span style='color:#dc3545;font-weight:bold;'> "..
    lang["mess_error"]..":</span> "..str..""
end

function warning_tag(str)
  return "<span style='color:#ffc107;font-weight:bold;'>"..
    "Warning"..":</span> "..str..""
end

function info_tag(str)
  return "<span style='color:#17a2b8;font-weight:bold;'>"..
    "Info"..":</span> "..str..""
end

function loading_tag(str)
  return "<span style='color:#6c757d;font-weight:bold;'>"..
    "Loading"..":</span> "..str..""
end

function download_tag(str)
  return "<span style='color:#007bff;font-weight:bold;'>"..
    "Download"..":</span> "..str..""
end


            --[[ Network utils]]--

function get(url)
  local host, path = parse_url(url)
  local header = {
    "GET "..path.." HTTP/"..openSub.conf.HTTPVersion, 
    "Host: "..host, 
    "User-Agent: "..openSub.conf.userAgentHTTP,
    "",
    ""
  }
  local request = table.concat(header, "\r\n")

  local status, response = http_req(host, 80, request)
  
  if status == 200 then 
    return response
  else
    vlc.msg.err("[VLSub] HTTP "..tostring(status).." : "..response)
    return false
  end
end

function http_req(host, port, request)
	local fd = vlc.net.connect_tcp(host, port)
	if not fd then 
		setError("Unable to connect to server")
		return nil, "" 
	end
	local pollfds = {}
	
	pollfds[fd] = vlc.net.POLLIN
	vlc.net.send(fd, request)
	vlc.net.poll(pollfds)

	local response = vlc.net.recv(fd, 2048)
	local buf = ""
	local headerStr, header, body
	local contentLength, status, TransferEncoding, chunked
	local pct = 0
	
	while response and #response>0 do
		buf = buf..response
		
		if not header then
			headerStr, body = buf:match("(.-\r?\n)\r?\n(.*)")

			if headerStr then
				header = parse_header(headerStr);
				status = tonumber(header["statuscode"]);
				contentLength = tonumber(header["Content-Length"]);
				if not contentLength then
					contentLength = tonumber(header["X-Uncompressed-Content-Length"])
				end
				
				TransferEncoding = trim(header["Transfer-Encoding"]);
				chunked = (TransferEncoding=="chunked");
				
				buf = body;
				body = "";
			end
		end
		
		if chunked then
			chunk_size_hex, chunk_content = buf:match("(%x+)\r?\n(.*)")
			chunk_size = tonumber(chunk_size_hex,16)
			chunk_content_len = chunk_content:len()
			chunk_remaining = chunk_size-chunk_content_len

			while chunk_content_len > chunk_size do
				body = body..chunk_content:sub(0, chunk_size)
				buf = chunk_content:sub(chunk_size+2)
				
				chunk_size_hex, chunk_content = buf:match("(%x+)\r?\n(.*)")
				
				if not chunk_size_hex 
				or chunk_size_hex == "0" then
					chunk_size = 0
					break
				end
				
				chunk_size = tonumber(chunk_size_hex,16)
				chunk_content_len = chunk_content:len()
				chunk_remaining = chunk_size-chunk_content_len
			end
			
			if chunk_size == 0 then
				break
			end
		end

		if contentLength then
      if #body == 0 then
        bodyLength = #buf
      else
        bodyLength = #body
      end
      
			pct = bodyLength / contentLength * 100
			setMessage(openSub.actionLabel..": "..progressBarContent(pct))
			if bodyLength >= contentLength then
				break
			end
		end

		vlc.net.poll(pollfds)
		response = vlc.net.recv(fd, 1024)
	end
	
	if not chunked then
		body = buf
	end
	
	if status == 301 
	and header["Location"] then
		local host, path = parse_url(trim(header["Location"]))
		request = request
		:gsub("^([^%s]+ )([^%s]+)", "%1"..path)
		:gsub("(Host: )([^\n]*)", "%1"..host)

		return http_req(host, port, request)
	end

	return status, body
end

function parse_header(data)
  local header = {}
  
  for name, s, val in string.gmatch(
    data,
    "([^%s:]+)(:?)%s([^\n]+)\r?\n")
  do
    if s == "" then 
    header['statuscode'] = tonumber(string.sub(val, 1 , 3))
    else 
      header[name] = val
    end
  end
  return header
end 

function parse_url(url)
  local url_parsed = vlc.net.url_parse(url)
  return  url_parsed["host"], 
    url_parsed["path"],
    url_parsed["option"]
end

            --[[ XML utils]]--

function parse_xml(data)
  local tree = {}
  local stack = {}
  local tmp = {}
  local level = 0
  local op, tag, p, empty, val
  table.insert(stack, tree)
  local resolve_xml =  vlc.strings.resolve_xml_special_chars

  for op, tag, p, empty, val in string.gmatch(
    data, 
    "[%s\r\n\t]*<(%/?)([%w:_]+)(.-)(%/?)>"..
    "[%s\r\n\t]*([^<]*)[%s\r\n\t]*"
  ) do
    if op=="/" then
      if level>0 then
        level = level - 1
        table.remove(stack)
      end
    else
      level = level + 1
      if val == "" then
        if type(stack[level][tag]) == "nil" then
          stack[level][tag] = {}
          table.insert(stack, stack[level][tag])
        else
          if type(stack[level][tag][1]) == "nil" then
            tmp = nil
            tmp = stack[level][tag]
            stack[level][tag] = nil
            stack[level][tag] = {}
            table.insert(stack[level][tag], tmp)
          end
          tmp = nil
          tmp = {}
          table.insert(stack[level][tag], tmp)
          table.insert(stack, tmp)
        end
      else
        if type(stack[level][tag]) == "nil" then
          stack[level][tag] = {}
        end
        stack[level][tag] = resolve_xml(val)
        table.insert(stack,  {})
      end
      if empty ~= "" then
        stack[level][tag] = ""
        level = level - 1
        table.remove(stack)
      end
    end
  end
  
  collectgarbage()
  return tree
end

function parse_xmlrpc(xmlText)
	local stack = {}
	local tree = {}
	local tmp, name = nil, nil
	table.insert(stack, tree)
	local FromXmlString =  vlc.strings.resolve_xml_special_chars
	
	local data_handle = {
		int = function(v) return tonumber(v) end,
		i4 = function(v) return tonumber(v) end,
		double = function(v) return tonumber(v) end,
		boolean = function(v) return tostring(v) end,
		base64 = function(v) return tostring(v) end, -- FIXME
		["string"] = function(v) return FromXmlString(v) end
	}
	
   for c, label, empty, value 
   in xmlText:gmatch("<(%/?)([%w_:]+)(%/?)>([^<]*)") do
   
		if c == "" 
		then -- start tag
			if label == "struct"
			or label == "array" then
				tmp = nil
				tmp = {}
				if name then
					stack[#stack][name] = tmp
				else
					table.insert(stack[#stack], tmp)
				end
				table.insert(stack, tmp)
				name = nil
			elseif label == "name" then
				name = value
			elseif data_handle[label] then
				if name then
					stack[#stack][name] = data_handle[label](value)
				else
					table.insert(stack[#stack], 
					data_handle[label](value))
				end
				name = nil
			end
			if empty == "/"  -- empty tag
			and #stack>0 
			and (label == "struct"
			or label == "array")
			then
				table.remove(stack)
			end
		else -- end tag
			if #stack>0 
			and (label == "struct"
			or label == "array")then
				table.remove(stack)
			end
		end
	end
	
	return tree[1]
end

function dump_xml(data)
  local level = 0
  local stack = {}
  local dump = ""
  local convert_xml = vlc.strings.convert_xml_special_chars
  
  local function parse(data, stack)
    local data_index = {}
    local k
    local v
    local i
    local tb
    
    for k,v in pairs(data) do
      table.insert(data_index, {k, v})
      table.sort(data_index, function(a, b)
        return a[1] < b[1] 
      end)
    end
    
    for i,tb in pairs(data_index) do
      k = tb[1]
      v = tb[2]
      if type(k)=="string" then
        dump = dump.."\r\n"..string.rep(
          " ",
          level)..
          "<"..k..">"	
        table.insert(stack, k)
        level = level + 1
      elseif type(k)=="number" and k ~= 1 then
        dump = dump.."\r\n"..string.rep(
          " ",
          level-1)..
          "<"..stack[level]..">"
      end
      
      if type(v)=="table" then
        parse(v, stack)
      elseif type(v)=="string" then
        dump = dump..(convert_xml(v) or v)
      elseif type(v)=="number" then
        dump = dump..v
      else
        dump = dump..tostring(v)
      end
      
      if type(k)=="string" then
        if type(v)=="table" then
          dump = dump.."\r\n"..string.rep(
            " ",
            level-1)..
            "</"..k..">"
        else
          dump = dump.."</"..k..">"
        end
        table.remove(stack)
        level = level - 1
        
      elseif type(k)=="number" and k ~= #data then
        if type(v)=="table" then
          dump = dump.."\r\n"..string.rep(
            " ",
            level-1)..
            "</"..stack[level]..">"
        else
          dump = dump.."</"..stack[level]..">"
        end
      end
    end
  end
  parse(data, stack)
  collectgarbage()
  return dump
end

            --[[ Misc utils]]--

function make_uri(str)
  str = str:gsub("\\", "/")
  local windowdrive = string.match(str, "^(%a:).+$")
  local encode_uri = vlc.strings.encode_uri_component
  local encodedPath = ""
  for w in string.gmatch(str, "/([^/]+)") do
    encodedPath = encodedPath.."/"..encode_uri(w) 
  end
    
  if windowdrive then
    return "file:///"..windowdrive..encodedPath
  else
    return "file://"..encodedPath
  end
end

function file_touch(name) -- test write ability
  if not name or trim(name) == "" 
  then return false end
  
  local f=io.open(name ,"w")
  if f~=nil then 
    io.close(f) 
    return true 
  else 
    return false 
  end
end

function file_exist(name) -- test readability
  if not name or trim(name) == "" 
  then return false end
  local f=io.open(name ,"r")
  if f~=nil then 
    io.close(f) 
    return true 
  else 
    return false 
  end
end

function is_dir(path)
  if not path or trim(path) == "" 
  then return false end
  -- Remove slash at the end or it won't work on Windows
  path = string.gsub(path, "^(.-)[\\/]?$", "%1")
  local f, _, code = io.open(path, "rb")
  
  if f then 
    _, _, code = f:read("*a")
    f:close()
    if code == 21 then
      return true
    end
  elseif code == 13 then
    return true
  end
  
  return false
end

function list_dir(path)
  if not path or trim(path) == "" 
  then return false end
  local dir_list_cmd 
  local list = {}
  if not is_dir(path) then return false end
  
  if openSub.conf.os == "win" then
    dir_list_cmd = io.popen('dir /b "'..path..'"')
  elseif openSub.conf.os == "lin" then
    dir_list_cmd = io.popen('ls -1 "'..path..'"')
  end
  
  if dir_list_cmd then
    for filename in dir_list_cmd:lines() do
      if string.match(filename, "^[^%s]+.+$") then
        table.insert(list, filename)
      end
    end
    return list
  else
    return false
  end
end

function mkdir_p(path)
  if not path or trim(path) == "" 
  then return false end
  if openSub.conf.os == "win" then
    os.execute('mkdir "' .. path..'"')
  elseif openSub.conf.os == "lin" then
    os.execute("mkdir -p '" .. path.."'")
  end
end

function decode_uri(str)
  return str:gsub("/", slash)
end

function is_window_path(path)
  return string.match(path, "^(%a:.+)$")
end

function is_win_safe(path)
  if not path or trim(path) == "" 
  or not is_window_path(path)
  then return false end
  return string.match(path, "^%a?%:?[\\%w%p%s§¤]+$")
end
    
function trim(str)
  if not str then return "" end
  return string.gsub(str, "^[\r\n%s]*(.-)[\r\n%s]*$", "%1")
end

function remove_tag(str)
  return string.gsub(str, "{[^}]+}", "")
end

function convert_sub_languages()
  local converted = {}
  for _, lang_obj in ipairs(sub_languages) do
    table.insert(converted, {lang_obj.language_code, lang_obj.language_name})
  end
  sub_languages = converted
end


-- Update the new API search to handle multiple languages
openSub.searchSubtitlesNewAPI = function()
  openSub.actionLabel = lang["action_search"]
  setMessage(openSub.actionLabel..": "..progressBarContent(0))
  
  -- Ensure we have valid session
  if not openSub.checkSession() then
    vlc.msg.err("[VLSub] Failed to establish session")
    openSub.itemStore = "0"
    return
  end
  
  -- Build the API URL
  local base_url = "https://api.opensubtitles.com/api/v1/subtitles"
  local params = {}
  
  -- Add query parameter (movie title)
  if openSub.movie.title and openSub.movie.title ~= "" then
    table.insert(params, "query=" .. vlc.strings.encode_uri_component(openSub.movie.title))
  end
  
  -- Add year parameter if available
  if openSub.movie.year and openSub.movie.year ~= "" then
    table.insert(params, "year=" .. vlc.strings.encode_uri_component(openSub.movie.year))
    vlc.msg.dbg("[VLSub] Including year in search: " .. openSub.movie.year)
  end
  
  -- Add language parameter (multiple languages, comma separated)
  if openSub.movie.sublanguageid and openSub.movie.sublanguageid ~= "all" then
    table.insert(params, "languages=" .. openSub.movie.sublanguageid)
    vlc.msg.dbg("[VLSub] Searching in languages: " .. openSub.movie.sublanguageid)
  end
  
  -- Add season and episode if available
  if openSub.movie.seasonNumber and openSub.movie.seasonNumber ~= "" and tonumber(openSub.movie.seasonNumber) and tonumber(openSub.movie.seasonNumber) > 0 then
    table.insert(params, "season_number=" .. openSub.movie.seasonNumber)
    vlc.msg.dbg("[VLSub] Including season: " .. openSub.movie.seasonNumber)
  end

  if openSub.movie.episodeNumber and openSub.movie.episodeNumber ~= "" and tonumber(openSub.movie.episodeNumber) and tonumber(openSub.movie.episodeNumber) > 0 then
    table.insert(params, "episode_number=" .. openSub.movie.episodeNumber)
    vlc.msg.dbg("[VLSub] Including episode: " .. openSub.movie.episodeNumber)
  end
  
  -- REMOVED: order_by and order_direction parameters
  -- table.insert(params, "order_by=download_count")
  -- table.insert(params, "order_direction=desc")
  
  local url = base_url
  if #params > 0 then
    url = url .. "?" .. table.concat(params, "&")
  end
  
  vlc.msg.dbg("[VLSub] API URL: " .. url)
  
  -- Make the API request with authentication
  local client = Curl.new()
  client:add_header("Api-Key", config.api_key)
  client:add_header("User-Agent", openSub.conf.userAgentHTTP)
  
  -- Add authorization header if we have a token
  local auth_header = openSub.getAuthHeader()
  if auth_header then
    client:add_header("Authorization", auth_header)
  end
  
  client:set_timeout(30)
  client:set_retries(2)
  
  local res = client:get(url)
  
  if res and res.status == 200 and res.body then
    vlc.msg.dbg("[VLSub] API request successful, status: " .. res.status)
    local ok, parsed_data = pcall(json.decode, res.body, 1, true)
    if ok and parsed_data and parsed_data.data then
      openSub.itemStore = openSub.convertNewAPIResponse(parsed_data.data)
      vlc.msg.dbg("[VLSub] Found " .. #openSub.itemStore .. " subtitles")
    else
      vlc.msg.err("[VLSub] Failed to parse API response: " .. (res.body or "no body"))
      openSub.itemStore = "0"
    end
  elseif res and res.status == 401 then
    -- Token expired or invalid, try to re-login
    vlc.msg.dbg("[VLSub] Authentication failed, attempting re-login")
    openSub.session.token = ""
    openSub.session.token_expires = 0
    if openSub.checkSession() then
      -- Retry the search with new token
      openSub.searchSubtitlesNewAPI()
    else
      openSub.itemStore = "0"
    end
  elseif res and res.status then
    vlc.msg.err("[VLSub] API request failed with status: " .. res.status)
    if res.body then
      vlc.msg.err("[VLSub] Error response: " .. res.body)
    end
    openSub.itemStore = "0"
  else
    vlc.msg.err("[VLSub] API request failed - no response")
    openSub.itemStore = "0"
  end
end

-- Convert the new API response format to the old XML-RPC format for compatibility
-- Enhanced buildSubtitleDisplayText function with upload date


openSub.convertNewAPIResponse = function(newData)
  local convertedData = {}
  
  for i, item in ipairs(newData) do
    if item.type == "subtitle" and item.attributes then
      local attr = item.attributes
      local files = attr.files or {}
      local firstFile = files[1] or {}
      
      -- Create an object that matches the old API structure
      local convertedItem = {
        -- Basic subtitle info
        SubFileName = firstFile.file_name or (attr.release or "Unknown") .. ".srt",
        SubLanguageID = attr.language or "eng",
        SubFormat = "srt", -- Modern API typically provides SRT files
        SubSize = tostring(attr.new_download_count or 0), -- Use download count as a proxy
        SubHash = attr.subtitle_id or tostring(i),
        SubLastTS = "",
        SubTSGroup = "1",
        SubDownloadsCnt = tostring(attr.download_count or 0),
        SubBad = "0",
        SubRating = tostring(attr.ratings or 0),
        SubSumCD = tostring(attr.nb_cd or 1),
        SubAuthorComment = attr.comments or "",
        SubAddDate = attr.upload_date or "", -- Keep this for compatibility
        UploadDate = attr.upload_date or "", -- CORRECT FIELD NAME
        SubFeatured = attr.from_trusted and "1" or "0",
        SubHD = attr.hd and "1" or "0",
        url = attr.url, -- Extract URL from API response for Link button
        
        -- Movie/Episode info
        MovieName = "",
        MovieNameEng = "",
        MovieYear = "",
        MovieImdbRating = "",
        SubMovieID = "",
        MovieImdbID = "",
        MovieKind = "",
        
        -- Series specific info
        SeriesSeason = "",
        SeriesEpisode = "",
        SeriesIMDBParent = "",
        
        -- Download info - This is the key part for downloading
        SubDownloadLink = "", -- Old API provided direct download links
        ZipDownloadLink = "", -- This needs to be constructed for the new API
        
        -- Additional fields that might be used
        ISO639 = attr.language or "eng",
        LanguageName = attr.language or "English",
        SubActualCD = tostring(attr.nb_cd or 1),
        SubSumVotes = tostring(attr.votes or 0),
        
        -- New API specific fields that we'll preserve
        SubtitleID = attr.subtitle_id,
        FileID = firstFile.file_id,
        MovieReleaseName = attr.release or firstFile.file_name or "Unknown",
        
        -- Enhanced fields for display
        FromTrusted = attr.from_trusted or false,
        AITranslated = attr.ai_translated or false,
        MachineTranslated = attr.machine_translated or false,
        MoviehashMatch = attr.moviehash_match or false,
        UploaderName = (attr.uploader and attr.uploader.name) or "Unknown",
        UploaderRank = (attr.uploader and attr.uploader.rank) or "",
        HearingImpaired = attr.hearing_impaired or false,
        FPS = attr.fps or 0,
        HD = attr.hd or false
      }
      
      -- Fill in movie/episode details if available
      if attr.feature_details then
        local details = attr.feature_details
        convertedItem.MovieName = details.movie_name or details.title or ""
        convertedItem.MovieYear = tostring(details.year or "")
        convertedItem.MovieImdbID = tostring(details.imdb_id or "")
        convertedItem.SeriesSeason = tostring(details.season_number or "")
        convertedItem.SeriesEpisode = tostring(details.episode_number or "")
        convertedItem.SeriesIMDBParent = tostring(details.parent_imdb_id or "")
      end
      
      -- For the new API, we need to construct download URLs
      -- The download will be handled differently in the download function
      convertedItem.ZipDownloadLink = "https://api.opensubtitles.com/api/v1/download"
      convertedItem.SubDownloadLink = convertedItem.ZipDownloadLink
      
      table.insert(convertedData, convertedItem)
    end
  end
  
  return convertedData
end




-- Improved login function with timeouts
openSub.loginWithRestAPI = function()
  openSub.actionLabel = lang["action_login"]
  
  -- Check cached token first
  if openSub.session.token ~= "" and openSub.session.token_expires > os.time() then
    vlc.msg.dbg("[VLSub] Using cached token")
    return true
  end
  
  -- Check credentials
  if not openSub.option.os_username or not openSub.option.os_password or 
     openSub.option.os_username == "" or openSub.option.os_password == "" then
    vlc.msg.dbg("[VLSub] No credentials - using anonymous access")
    openSub.session.token = ""
    openSub.session.user_info = nil
    openSub.session.token_expires = 0
    return true
  end
  
  log_api_endpoint("LOGIN", config.login_api_url, "POST", "Authenticate with OpenSubtitles.com")  
  vlc.msg.dbg("[VLSub] Attempting login for: " .. openSub.option.os_username)
  
  local login_data = {
    username = openSub.option.os_username,
    password = openSub.option.os_password
  }
  
  local request_body = json.encode(login_data)
  
  -- Use aggressive timeouts for login
  local client = Curl.new()
  client:set_aggressive_timeouts()
  client:add_header("Api-Key", config.api_key)
  client:add_header("Content-Type", "application/json")
  client:add_header("User-Agent", openSub.conf.userAgentHTTP)
  
  local res = client:post(config.login_api_url, request_body)
  
  if not res then
    vlc.msg.err("[VLSub] Login request failed - network timeout")
    setError("Login failed - network timeout or no internet connection")
    return false
  end
  
  if res.status ~= 200 then
    vlc.msg.err("[VLSub] Login failed with status: " .. res.status)
    if res.body then
      local ok, error_data = pcall(json.decode, res.body, 1, true)
      if ok and error_data and error_data.message then
        setError("Login failed: " .. error_data.message)
      else
        setError("Login failed with status: " .. res.status)
      end
    else
      setError("Login failed - network error")
    end
    return false
  end
  
  if not res.body then
    vlc.msg.err("[VLSub] Login response has no body")
    setError("Login failed - empty response")
    return false
  end
  
  local ok, login_response = pcall(json.decode, res.body, 1, true)
  if not ok or not login_response then
    vlc.msg.err("[VLSub] Failed to parse login response")
    setError("Login failed - invalid response format")
    return false
  end
  
  if login_response.status ~= 200 then
    vlc.msg.err("[VLSub] Login failed, API status: " .. (login_response.status or "unknown"))
    setError("Login failed: " .. (login_response.message or ("Status " .. (login_response.status or "unknown"))))
    return false
  end
  
  if not login_response.token then
    vlc.msg.err("[VLSub] No token in login response")
    setError("Login failed - no authentication token received")
    return false
  end
  
  -- Store session info
  openSub.session.token = login_response.token
  openSub.session.user_info = login_response.user
  openSub.session.loginTime = os.time()
  openSub.session.token_expires = os.time() + config.token_cache_duration_seconds
  
  if login_response.base_url then
    openSub.session.base_url = login_response.base_url
  end
  
  vlc.msg.dbg("[VLSub] Login successful")
  openSub.saveSessionCache()
  
  return true
end

-- New function to save session cache
openSub.saveSessionCache = function()
  if not openSub.conf.dirPath then
    return false
  end
  
  local cache_file_path = openSub.conf.dirPath .. slash .. "session_cache.json"
  
  local session_data = {
    token = openSub.session.token,
    user_info = openSub.session.user_info,
    token_expires = openSub.session.token_expires,
    base_url = openSub.session.base_url,
    loginTime = openSub.session.loginTime,
    username = openSub.option.os_username -- Store username to validate cache
  }
  
  if file_touch(cache_file_path) then
    local cache_file = io.open(cache_file_path, "wb")
    if cache_file then
      local cache_content = json.encode(session_data, { indent = true })
      cache_file:write(cache_content)
      cache_file:flush()
      cache_file:close()
      vlc.msg.dbg("[VLSub] Session cached to: " .. cache_file_path)
      return true
    end
  end
  
  vlc.msg.err("[VLSub] Failed to save session cache")
  return false
end

-- New function to load session cache
openSub.loadSessionCache = function()
  if not openSub.conf.dirPath then
    return false
  end
  
  local cache_file_path = openSub.conf.dirPath .. slash .. "session_cache.json"
  
  if not file_exist(cache_file_path) then
    return false
  end
  
  local cache_file = io.open(cache_file_path, "rb")
  if not cache_file then
    return false
  end
  
  local cache_content = cache_file:read("*all")
  cache_file:close()
  
  local ok, session_data = pcall(json.decode, cache_content, 1, true)
  if not ok or not session_data then
    vlc.msg.dbg("[VLSub] Failed to parse session cache")
    return false
  end
  
  -- Validate cache data
  if not session_data.token or not session_data.token_expires then
    vlc.msg.dbg("[VLSub] Invalid session cache data")
    return false
  end
  
  -- Check if token is still valid
  if session_data.token_expires <= os.time() then
    vlc.msg.dbg("[VLSub] Cached token expired")
    return false
  end
  
  -- Check if username matches (to handle account switching)
  if session_data.username ~= openSub.option.os_username then
    vlc.msg.dbg("[VLSub] Cached session for different user")
    return false
  end
  
  -- Load cached session
  openSub.session.token = session_data.token
  openSub.session.user_info = session_data.user_info
  openSub.session.token_expires = session_data.token_expires
  openSub.session.base_url = session_data.base_url or "api.opensubtitles.com"
  openSub.session.loginTime = session_data.loginTime or os.time()
  
  vlc.msg.dbg("[VLSub] Loaded cached session, expires in " .. (openSub.session.token_expires - os.time()) .. " seconds")
  return true
end

-- New logout function for REST API
openSub.logoutRestAPI = function()
  if openSub.session.token == "" then
    return true -- Already logged out
  end
  
  openSub.actionLabel = lang["action_logout"]
  
  local logout_url = "https://api.opensubtitles.com/api/v1/logout"
  
  local client = Curl.new()
  client:add_header("Api-Key", config.api_key)
  client:add_header("Authorization", "Bearer " .. openSub.session.token)
  client:add_header("User-Agent", openSub.conf.userAgentHTTP)
  client:set_timeout(15)
  
  local res = client:delete(logout_url)
  
  -- Clear session regardless of logout success
  openSub.session.token = ""
  openSub.session.user_info = nil
  openSub.session.token_expires = 0
  openSub.session.loginTime = 0
  
  -- Remove session cache file
  if openSub.conf.dirPath then
    local cache_file_path = openSub.conf.dirPath .. slash .. "session_cache.json"
    if file_exist(cache_file_path) then
      os.remove(cache_file_path)
    end
  end
  
  if res and res.status == 200 then
    vlc.msg.dbg("[VLSub] Successfully logged out from REST API")
  else
    vlc.msg.dbg("[VLSub] Logout request failed, but session cleared locally")
  end
  
  return true
end



-- Enhanced saveAndLoadSubtitle function with Downloads folder support
openSub.saveAndLoadSubtitle = function(subtitle_content, item)
  if not subtitle_content or subtitle_content == "" then
    local errorMsg = "Empty subtitle content received"
    vlc.msg.err("[VLSub] " .. errorMsg)
    setMessage(error_tag(errorMsg))
    return false
  end
  
  vlc.msg.dbg("[VLSub] Processing subtitle content, size: " .. #subtitle_content .. " bytes")
  
  -- Process subtitle content (remove tags if option is set)
  if openSub.option.removeTag then
    subtitle_content = remove_tag(subtitle_content)
  end
  
  -- Determine subtitle filename
  local subfileName = "subtitle"
  if openSub.file.name and openSub.file.name ~= '' then
    subfileName = openSub.file.name 
  elseif item.SubFileName then
    subfileName = string.sub(item.SubFileName, 1, #item.SubFileName - 4)
  else
    -- Use search query as filename if no video loaded
    if openSub.movie.title and openSub.movie.title ~= "" then
      subfileName = openSub.movie.title
      -- Clean filename for filesystem
      subfileName = string.gsub(subfileName, "[<>:\"/\\|?*]", "_") -- Remove invalid characters
      subfileName = string.gsub(subfileName, "%s+", "_") -- Replace spaces with underscores
    else
      local inputItem = openSub.getInputItem()
      if inputItem then
        local uriName = vlc.strings.encode_uri_component(inputItem:uri())
        if uriName then
          subfileName = string.sub(uriName, -64, -1)
        end
      end
    end
  end
  
  if openSub.option.langExt then
    subfileName = subfileName.."."..item.SubLanguageID
  end
  
  subfileName = subfileName.."."..item.SubFormat
  
  -- Determine target directory with Downloads folder fallback
  local target
  local saveLocation = ""
  local saved_to_downloads = false
  
  -- First priority: save with video file if available
  if openSub.file.hasInput and openSub.file.dir and is_dir(openSub.file.dir) then
    target = openSub.file.dir..subfileName
    saveLocation = " (saved with video file)"
    vlc.msg.dbg("[VLSub] Attempting to save with video file: " .. target)
    
  -- Second priority: Downloads folder when no video or video dir not accessible
  else
    local downloads_folder = get_downloads_folder()
    if downloads_folder then
      target = downloads_folder .. slash .. subfileName
      saveLocation = " (saved to Downloads folder)"
      saved_to_downloads = true
      vlc.msg.dbg("[VLSub] Attempting to save to Downloads: " .. target)
      
    -- Third priority: VLSub directory
    elseif openSub.conf.dirPath then
      target = openSub.conf.dirPath..slash..subfileName
      saveLocation = " (saved to VLSub directory)"
      vlc.msg.dbg("[VLSub] Attempting to save to VLSub directory: " .. target)
    else
      local errorMsg = "Cannot determine save location for subtitle file"
      vlc.msg.err("[VLSub] " .. errorMsg)
      setMessage(error_tag(errorMsg))
      return false
    end
  end
  
  -- Test if we can write to the target location
  if not file_touch(target) then
    vlc.msg.dbg("[VLSub] Cannot write to primary target, trying fallbacks...")
    
    -- Fallback 1: Downloads folder if not already tried
    if not saved_to_downloads then
      local downloads_folder = get_downloads_folder()
      if downloads_folder then
        target = downloads_folder .. slash .. subfileName
        saveLocation = " (saved to Downloads folder)"
        saved_to_downloads = true
        vlc.msg.dbg("[VLSub] Fallback: trying Downloads folder: " .. target)
        
        if not file_touch(target) then
          vlc.msg.dbg("[VLSub] Downloads folder also not writable")
        end
      end
    end
    
    -- Fallback 2: VLSub directory if not already tried
    if not file_touch(target) and openSub.conf.dirPath then
      target = openSub.conf.dirPath..slash..subfileName
      saveLocation = " (saved to VLSub directory)"
      saved_to_downloads = false
      vlc.msg.dbg("[VLSub] Final fallback: VLSub directory: " .. target)
      
      if not file_touch(target) then
        local errorMsg = "Cannot write to any available location: " .. target
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
      end
    end
    
    if not file_touch(target) then
      local errorMsg = "Cannot write subtitle file to any location"
      vlc.msg.err("[VLSub] " .. errorMsg)
      setMessage(error_tag(errorMsg))
      return false
    end
  end
  
  vlc.msg.dbg("[VLSub] Final save target: " .. target)
  
  -- Write subtitle content to file
  local subfile = io.open(target, "wb")
  if not subfile then
    local errorMsg = "Cannot open file for writing: " .. target
    vlc.msg.err("[VLSub] " .. errorMsg)
    setMessage(error_tag(errorMsg))
    return false
  end
  
  subfile:write(subtitle_content)
  subfile:flush()
  subfile:close()
  
  vlc.msg.dbg("[VLSub] Subtitle file saved successfully")
  
  -- Try to load subtitles into VLC if video is playing
  local subtitle_loaded = false
  if openSub.file.hasInput and add_sub(target) then
    subtitle_loaded = true
    vlc.msg.dbg("[VLSub] Subtitle loaded successfully into VLC")
  end
  
  -- Build success message based on context
  local successMsg
  if subtitle_loaded then
    successMsg = lang["mess_loaded"] .. saveLocation
  else
    if saved_to_downloads then
      successMsg = "Subtitles saved to Downloads"  -- Removed duplicate saveLocation
    else
      successMsg = "Subtitles saved" .. saveLocation
    end
  end
  
  setMessage(success_tag(successMsg))

  return true
end



-- Enhanced download_subtitles_v2 function with better no-video handling
function download_subtitles_v2()
  -- Check if we have any results first
  local hasResults = false
  
  if openSub.itemStore and type(openSub.itemStore) == "table" and #openSub.itemStore > 0 then
    hasResults = true
  end
  
  if not hasResults then
    setMessage(error_tag("No subtitles available for download. Please search first."))
    return false
  end
  
  local index = get_first_sel(input_table["mainlist"])
  
  if index == 0 then
    setMessage(error_tag(lang["mess_no_selection"]))
    return false
  end
  
  openSub.actionLabel = lang["mess_downloading"] 
  setMessage(openSub.actionLabel..": "..progressBarContent(10))
  
  local item = openSub.itemStore[index]
  
  -- Check if manual download is explicitly requested
  if openSub.option.downloadBehaviour == 'manual' then
    -- For manual download, provide the web URL
    local link = "<span style='color:#181'>"
    link = link.."<b>"..lang["mess_dowload_link"]..":</b>"
    link = link.."</span> &nbsp;"
    link = link.."<a href='https://www.opensubtitles.com/subtitles/"..
      (item.SubtitleID or item.SubHash).."'>"
    link = link..(item.MovieReleaseName or item.SubFileName).."</a>"
    
    setMessage(link)
    return false
  end

  -- Show download progress
  setMessage(openSub.actionLabel..": "..progressBarContent(25))
  
  -- Always attempt automatic download (even without video loaded)
  vlc.msg.dbg("[VLSub] Attempting automatic download. Video loaded: " .. tostring(openSub.file.hasInput))
  
  local success = openSub.downloadFromNewAPI(item)
  
  return success
end



-- Fixed getSelectedLanguages function
function getSelectedLanguages()
  local languages = {}
  
  -- Debug: log dropdown values
  local sel1 = input_table["language"]:get_value()
  vlc.msg.dbg("[VLSub] Primary language dropdown value: " .. tostring(sel1))
  
  -- Get primary language
  if sel1 > 0 and openSub.conf.languages[sel1] then
    local lang1 = openSub.conf.languages[sel1][1]
    vlc.msg.dbg("[VLSub] Primary language selected: " .. lang1)
    table.insert(languages, lang1)
  end
  
  -- Get secondary language
  if input_table["language2"] then
    local sel2 = input_table["language2"]:get_value()
    vlc.msg.dbg("[VLSub] Secondary language dropdown value: " .. tostring(sel2))
    if sel2 > 0 and openSub.conf.languages[sel2] then
      local lang2 = openSub.conf.languages[sel2][1]
      vlc.msg.dbg("[VLSub] Secondary language selected: " .. lang2)
      -- Avoid duplicates
      local found = false
      for _, lang in ipairs(languages) do
        if lang == lang2 then
          found = true
          break
        end
      end
      if not found then
        table.insert(languages, lang2)
      end
    end
  end
  
  -- Get third language
  if input_table["language3"] then
    local sel3 = input_table["language3"]:get_value()
    vlc.msg.dbg("[VLSub] Third language dropdown value: " .. tostring(sel3))
    if sel3 > 0 and openSub.conf.languages[sel3] then
      local lang3 = openSub.conf.languages[sel3][1]
      vlc.msg.dbg("[VLSub] Third language selected: " .. lang3)
      -- Avoid duplicates
      local found = false
      for _, lang in ipairs(languages) do
        if lang == lang3 then
          found = true
          break
        end
      end
      if not found then
        table.insert(languages, lang3)
      end
    end
  end
  
  -- Sort languages alphabetically as required by API
  table.sort(languages)
  
  local result
  if #languages == 0 then
    result = 'all'
  else
    result = table.concat(languages, ',')
  end
  
  vlc.msg.dbg("[VLSub] Final language string: " .. result)
  return result
end

-- Also add this debug function to check what languages are available
function debugLanguages()
  vlc.msg.dbg("[VLSub] Available languages:")
  for i, lang in ipairs(openSub.conf.languages) do
    vlc.msg.dbg("[VLSub] " .. i .. ": " .. lang[1] .. " = " .. lang[2])
  end
end


-- Language code to Unicode flag mapping
local language_flags = {
  -- Major languages
  ["en"] = "🇺🇸", -- English (US flag)
  ["eng"] = "🇺🇸", -- English
  ["fr"] = "🇫🇷", -- French
  ["fre"] = "🇫🇷", -- French
  ["de"] = "🇩🇪", -- German
  ["ger"] = "🇩🇪", -- German
  ["es"] = "🇪🇸", -- Spanish
  ["spa"] = "🇪🇸", -- Spanish
  ["it"] = "🇮🇹", -- Italian
  ["ita"] = "🇮🇹", -- Italian
  ["pt"] = "🇵🇹", -- Portuguese
  ["por"] = "🇵🇹", -- Portuguese
  ["pt-br"] = "🇧🇷", -- Portuguese (Brazil)
  ["pob"] = "🇧🇷", -- Portuguese (Brazil)
  ["pt-pt"] = "🇵🇹", -- Portuguese (Portugal)
  ["ru"] = "🇷🇺", -- Russian
  ["rus"] = "🇷🇺", -- Russian
  ["zh"] = "🇨🇳", -- Chinese
  ["chi"] = "🇨🇳", -- Chinese
  ["zh-cn"] = "🇨🇳", -- Chinese (Simplified)
  ["zh-tw"] = "🇹🇼", -- Chinese (Traditional)
  ["zh-ca"] = "🇭🇰", -- Chinese (Cantonese)
  ["ja"] = "🇯🇵", -- Japanese
  ["jpn"] = "🇯🇵", -- Japanese
  ["ko"] = "🇰🇷", -- Korean
  ["kor"] = "🇰🇷", -- Korean
  ["ar"] = "🇸🇦", -- Arabic
  ["ara"] = "🇸🇦", -- Arabic
  ["hi"] = "🇮🇳", -- Hindi
  ["hin"] = "🇮🇳", -- Hindi
  
  -- European languages
  ["nl"] = "🇳🇱", -- Dutch
  ["dut"] = "🇳🇱", -- Dutch
  ["sv"] = "🇸🇪", -- Swedish
  ["swe"] = "🇸🇪", -- Swedish
  ["no"] = "🇳🇴", -- Norwegian
  ["nor"] = "🇳🇴", -- Norwegian
  ["da"] = "🇩🇰", -- Danish
  ["dan"] = "🇩🇰", -- Danish
  ["fi"] = "🇫🇮", -- Finnish
  ["fin"] = "🇫🇮", -- Finnish
  ["pl"] = "🇵🇱", -- Polish
  ["pol"] = "🇵🇱", -- Polish
  ["cs"] = "🇨🇿", -- Czech
  ["cze"] = "🇨🇿", -- Czech
  ["sk"] = "🇸🇰", -- Slovak
  ["slo"] = "🇸🇰", -- Slovak
  ["hu"] = "🇭🇺", -- Hungarian
  ["hun"] = "🇭🇺", -- Hungarian
  ["ro"] = "🇷🇴", -- Romanian
  ["rum"] = "🇷🇴", -- Romanian
  ["bg"] = "🇧🇬", -- Bulgarian
  ["bul"] = "🇧🇬", -- Bulgarian
  ["hr"] = "🇭🇷", -- Croatian
  ["hrv"] = "🇭🇷", -- Croatian
  ["sr"] = "🇷🇸", -- Serbian
  ["scc"] = "🇷🇸", -- Serbian
  ["bs"] = "🇧🇦", -- Bosnian
  ["bos"] = "🇧🇦", -- Bosnian
  ["sl"] = "🇸🇮", -- Slovenian
  ["slv"] = "🇸🇮", -- Slovenian
  ["mk"] = "🇲🇰", -- Macedonian
  ["mac"] = "🇲🇰", -- Macedonian
  ["me"] = "🇲🇪", -- Montenegrin
  ["el"] = "🇬🇷", -- Greek
  ["ell"] = "🇬�", -- Greek
  ["tr"] = "🇹🇷", -- Turkish
  ["tur"] = "🇹🇷", -- Turkish
  
  -- Other European
  ["is"] = "🇮🇸", -- Icelandic
  ["ice"] = "🇮🇸", -- Icelandic
  ["ga"] = "🇮🇪", -- Irish
  ["gle"] = "🇮🇪", -- Irish
  ["cy"] = "🏴󠁧󠁢󠁷󠁬󠁳󠁿", -- Welsh
  ["wel"] = "🏴󠁧󠁢󠁷󠁬󠁳󠁿", -- Welsh
  ["eu"] = "🏴󠁥󠁳󠁰󠁶󠁿", -- Basque
  ["baq"] = "🏴󠁥󠁳󠁰󠁶󠁿", -- Basque (using Basque Country flag)
  ["ca"] = "🏴󠁥󠁳󠁣󠁴󠁿", -- Catalan
  ["cat"] = "🏴󠁥󠁳󠁣󠁴󠁿", -- Catalan
  ["gl"] = "🏴󠁥󠁳󠁧󠁡󠁿", -- Galician
  ["glg"] = "🏴󠁥󠁳󠁧󠁡󠁿", -- Galician
  
  -- Asian languages
  ["th"] = "🇹🇭", -- Thai
  ["tha"] = "🇹🇭", -- Thai
  ["vi"] = "🇻🇳", -- Vietnamese
  ["vie"] = "🇻🇳", -- Vietnamese
  ["id"] = "🇮🇩", -- Indonesian
  ["ind"] = "🇮🇩", -- Indonesian
  ["ms"] = "🇲🇾", -- Malay
  ["may"] = "🇲🇾", -- Malay
  ["tl"] = "🇵🇭", -- Tagalog
  ["tgl"] = "🇵🇭", -- Tagalog
  ["he"] = "🇮🇱", -- Hebrew
  ["heb"] = "🇮🇱", -- Hebrew
  ["fa"] = "🇮🇷", -- Persian
  ["per"] = "🇮🇷", -- Persian
  ["ur"] = "🇵🇰", -- Urdu
  ["urd"] = "🇵🇰", -- Urdu
  ["bn"] = "🇧🇩", -- Bengali
  ["ben"] = "🇧🇩", -- Bengali
  ["ta"] = "🇱🇰", -- Tamil
  ["tam"] = "🇱🇰", -- Tamil
  ["te"] = "🇮🇳", -- Telugu
  ["tel"] = "🇮🇳", -- Telugu
  ["kn"] = "🇮🇳", -- Kannada
  ["kan"] = "🇮🇳", -- Kannada
  ["ml"] = "🇮🇳", -- Malayalam
  ["mal"] = "🇮🇳", -- Malayalam
  ["mr"] = "🇮🇳", -- Marathi
  ["mar"] = "🇮🇳", -- Marathi
  
  -- African languages
  ["af"] = "🇿🇦", -- Afrikaans
  ["afr"] = "🇿🇦", -- Afrikaans
  ["sw"] = "🇰🇪", -- Swahili
  ["swa"] = "🇰🇪", -- Swahili
  ["am"] = "🇪🇹", -- Amharic
  ["amh"] = "🇪🇹", -- Amharic
  ["so"] = "🇸🇴", -- Somali
  ["som"] = "🇸🇴", -- Somali
  
  -- Americas
  ["ea"] = "🇲🇽", -- Spanish (Latin America)
  ["sp"] = "🇪🇸", -- Spanish (Spain)
  ["pm"] = "🇲🇿", -- Portuguese (Mozambique)
  
  -- Other languages
  ["eo"] = "🏳️", -- Esperanto (neutral flag)
  ["epo"] = "🏳️", -- Esperanto
  ["la"] = "🇻🇦", -- Latin (Vatican)
  ["lat"] = "🇻🇦", -- Latin
  
  -- Nordic/Baltic
  ["et"] = "🇪🇪", -- Estonian
  ["est"] = "🇪🇪", -- Estonian
  ["lv"] = "🇱🇻", -- Latvian
  ["lav"] = "🇱🇻", -- Latvian
  ["lt"] = "🇱🇹", -- Lithuanian
  ["lit"] = "🇱🇹", -- Lithuanian
  
  -- Eastern European
  ["uk"] = "🇺🇦", -- Ukrainian
  ["ukr"] = "🇺🇦", -- Ukrainian
  ["be"] = "🇧🇾", -- Belarusian
  ["bel"] = "🇧🇾", -- Belarusian
  ["kk"] = "🇰🇿", -- Kazakh
  ["kaz"] = "🇰🇿", -- Kazakh
  ["uz"] = "🇺🇿", -- Uzbek
  ["uzb"] = "🇺🇿", -- Uzbek
  ["ky"] = "🇰🇬", -- Kyrgyz
  ["kir"] = "🇰🇬", -- Kyrgyz
  ["tg"] = "🇹🇯", -- Tajik
  ["tgk"] = "🇹🇯", -- Tajik
  ["tm"] = "🇹🇲", -- Turkmen
  ["tuk"] = "🇹🇲", -- Turkmen
  ["az"] = "🇦🇿", -- Azerbaijani
  ["aze"] = "🇦🇿", -- Azerbaijani
  ["az-az"] = "🇦🇿", -- Azerbaijani
  ["az-zb"] = "🇦🇿", -- South Azerbaijani
  ["hy"] = "🇦🇲", -- Armenian
  ["arm"] = "🇦🇲", -- Armenian
  ["ka"] = "🇬🇪", -- Georgian
  ["geo"] = "🇬🇪", -- Georgian
  
  -- Additional variants
  ["sq"] = "🇦🇱", -- Albanian
  ["alb"] = "🇦🇱", -- Albanian
  ["mt"] = "🇲🇹", -- Maltese
  ["mlt"] = "🇲🇹", -- Maltese
  ["mk"] = "🇲🇰", -- Macedonian
  ["ze"] = "🇨🇳" -- Chinese bilingual
}

-- Function to get flag for language code
function getLanguageFlag(langCode)
  if not langCode or langCode == "" then
    return ""
  end
  
  -- Convert to lowercase for matching
  local code = string.lower(langCode)
  
  -- Return flag if found, empty string if not
  return language_flags[code] or ""
end


-- Get user selected languages in order
function getUserSelectedLanguages()
  local languages = {}
  
  -- Get primary language
  local sel1 = input_table["language"]:get_value()
  if sel1 > 0 and openSub.conf.languages[sel1] then
    local lang1 = openSub.conf.languages[sel1][1]
    table.insert(languages, lang1)
  end
  
  -- Get secondary language
  if input_table["language2"] then
    local sel2 = input_table["language2"]:get_value()
    if sel2 > 0 and openSub.conf.languages[sel2] then
      local lang2 = openSub.conf.languages[sel2][1]
      -- Avoid duplicates
      local found = false
      for _, lang in ipairs(languages) do
        if lang == lang2 then
          found = true
          break
        end
      end
      if not found then
        table.insert(languages, lang2)
      end
    end
  end
  
  -- Get third language
  if input_table["language3"] then
    local sel3 = input_table["language3"]:get_value()
    if sel3 > 0 and openSub.conf.languages[sel3] then
      local lang3 = openSub.conf.languages[sel3][1]
      -- Avoid duplicates
      local found = false
      for _, lang in ipairs(languages) do
        if lang == lang3 then
          found = true
          break
        end
      end
      if not found then
        table.insert(languages, lang3)
      end
    end
  end
  
  return languages
end

-- New function to search by hash using REST API
openSub.searchSubtitlesByHashNewAPI = function()
    openSub.actionLabel = lang["action_search"]
    setMessage(openSub.actionLabel..": "..progressBarContent(0))
    
    -- Ensure we have valid session
    if not openSub.checkSession() then
        vlc.msg.err("[VLSub] Failed to establish session")
        openSub.itemStore = {} -- Set to empty table
        setMessage(error_tag(lang["mess_no_res"]))
        display_subtitles()
        return
    end
    
    -- Build the API URL
    local base_url = "https://api.opensubtitles.com/api/v1/subtitles"
    local params = {}
    
    -- Add moviehash parameter (required for hash search)
    if openSub.file.hash and openSub.file.hash ~= "" then
        table.insert(params, "moviehash=" .. vlc.strings.encode_uri_component(openSub.file.hash))
        vlc.msg.dbg("[VLSub] Searching with hash: " .. openSub.file.hash)
    else
        vlc.msg.err("[VLSub] No movie hash available")
        openSub.itemStore = {} -- Set to empty table
        setMessage(error_tag(lang["mess_no_input"]))
        display_subtitles()
        return
    end
    
    -- Add moviebytesize parameter (recommended for better matching)
    if openSub.file.bytesize and openSub.file.bytesize > 0 then
        table.insert(params, "moviebytesize=" .. openSub.file.bytesize)
        vlc.msg.dbg("[VLSub] Using file size: " .. openSub.file.bytesize)
    end
    
    -- Add language parameter (multiple languages, comma separated)
    if openSub.movie.sublanguageid and openSub.movie.sublanguageid ~= "all" then
        table.insert(params, "languages=" .. openSub.movie.sublanguageid)
        vlc.msg.dbg("[VLSub] Searching in languages: " .. openSub.movie.sublanguageid)
    end
    
    local url = base_url
    if #params > 0 then
        url = url .. "?" .. table.concat(params, "&")
    end
    
    vlc.msg.dbg("[VLSub] Hash search API URL: " .. url)
    
    -- Make the API request with authentication
    local client = Curl.new()
    client:add_header("Api-Key", config.api_key)
    client:add_header("User-Agent", openSub.conf.userAgentHTTP)
    
    -- Add authorization header if we have a token
    local auth_header = openSub.getAuthHeader()
    if auth_header then
        client:add_header("Authorization", auth_header)
    end
    
    client:set_timeout(30)
    client:set_retries(2)
    
    local res = client:get(url)
    
    if res and res.status == 200 and res.body then
        vlc.msg.dbg("[VLSub] Hash search API request successful, status: " .. res.status)
        local ok, parsed_data = pcall(json.decode, res.body, 1, true)
        if ok and parsed_data and parsed_data.data then
            openSub.itemStore = openSub.convertNewAPIResponse(parsed_data.data)
            vlc.msg.dbg("[VLSub] Found " .. #openSub.itemStore .. " subtitles by hash")
            
            if #openSub.itemStore > 0 then
                vlc.msg.dbg("[VLSub] Hash search successful - found synchronized subtitles")
                setMessage(success_tag(lang["mess_complete"] .. ": " .. #openSub.itemStore .. " " .. lang["mess_res"]))
            else
                vlc.msg.dbg("[VLSub] Hash search returned no results")
                setMessage(error_tag(lang["mess_no_res"]))
            end
        else
            vlc.msg.err("[VLSub] Failed to parse hash search API response: " .. (res.body or "no body"))
            openSub.itemStore = {} -- Set to empty table
            setMessage(error_tag(lang["mess_no_res"]))
        end
    elseif res and res.status == 401 then
        -- Token expired or invalid, try to re-login
        vlc.msg.dbg("[VLSub] Authentication failed during hash search, attempting re-login")
        openSub.session.token = ""
        openSub.session.token_expires = 0
        if openSub.checkSession() then
            -- Retry the search with new token
            openSub.searchSubtitlesByHashNewAPI()
            return
        else
            openSub.itemStore = {} -- Set to empty table
            setMessage(error_tag(lang["mess_unauthorized"]))
        end
    elseif res and res.status then
        vlc.msg.err("[VLSub] Hash search API request failed with status: " .. res.status)
        if res.body then
            vlc.msg.err("[VLSub] Hash search error response: " .. res.body)
        end
        openSub.itemStore = {} -- Set to empty table
        setMessage(error_tag(lang["mess_error"] .. ": HTTP " .. res.status))
    else
        vlc.msg.err("[VLSub] Hash search API request failed - no response")
        openSub.itemStore = {} -- Set to empty table
        setMessage(error_tag(lang["mess_no_response"]))
    end
    
    display_subtitles()
end

-- Function to get current time in milliseconds
function getCurrentTimeMs()
  -- Use os.clock for better precision on macOS
  return math.floor(os.clock() * 1000)
end

function subtitle_list_click_handler()
  if not input_table["mainlist"] then
    return
  end
  
  local current_time = getCurrentTimeMs()
  local selected_item = get_first_sel(input_table["mainlist"])
  
  if selected_item == 0 then
    -- No item selected, reset tracking
    last_click_time = 0
    last_click_item = 0
    return
  end
  
  -- Check if this is a double-click
  local time_diff = current_time - last_click_time
  local is_same_item = (selected_item == last_click_item)
  
  if time_diff < double_click_threshold and is_same_item and last_click_time > 0 then
    -- Double-click detected! Trigger download
    vlc.msg.dbg("[VLSub] Double-click detected on item " .. selected_item .. ", triggering download")
    download_subtitles_v2()
    
    -- Reset to prevent triple-click issues
    last_click_time = 0
    last_click_item = 0
  else
    -- Single click - just update tracking
    vlc.msg.dbg("[VLSub] Single click on item " .. selected_item .. " (time: " .. current_time .. ")")
    last_click_time = current_time
    last_click_item = selected_item
  end
end


function input_changed()
  collectgarbage()
  
  -- Only update interface if not in config mode, or preserve messages in config mode
  if dlg and dlg:get_title() and string.find(dlg:get_title(), "Configuration") then
    -- In config mode - don't call set_interface_main which might clear messages
    -- Just handle subtitle list clicks if any
    if input_table["mainlist"] then
      subtitle_list_click_handler()
    end
  else
    -- In main mode - normal behavior
    set_interface_main()
    if input_table["mainlist"] then
      subtitle_list_click_handler()
    end
  end
  
  collectgarbage()
end

-- New trigger_action function (VLC calls this on list interactions)
function trigger_action()
  -- This function gets called when user interacts with dialog elements
  -- including list selections on macOS
  subtitle_list_click_handler()
end

-- Missing helper function: get_first_sel
function get_first_sel(list)
  if not list then
    return 0
  end
  
  local selection = list:get_selection()
  if not selection then
    return 0
  end
  
  for index, name in pairs(selection) do 
    return index
  end
  return 0
end

-- Enhanced downloadFromNewAPI with improved quota display
openSub.downloadFromNewAPI = function(item)
    if not item.FileID then
        local errorMsg = "No file ID available for download"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    end

    -- Check session first
    if not openSub.checkSession() then
        local errorMsg = "Authentication failed - please check your OpenSubtitles.com credentials"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    end

    local download_url = "https://api.opensubtitles.com/api/v1/download"

    -- Prepare the download request body
    local request_body = json.encode({
        file_id = tonumber(item.FileID)
    })

    vlc.msg.dbg("[VLSub] Downloading subtitle file ID: " .. item.FileID)
    setMessage(openSub.actionLabel..": "..progressBarContent(50))

    log_api_endpoint("DOWNLOAD", "api.opensubtitles.com/api/v1/download", "POST", 
                   "Download subtitle file ID: " .. (item.FileID or "unknown"))

    -- Make the download request using curl wrapper
    local client = Curl.new()
    client:add_header("Api-Key", config.api_key)
    client:add_header("User-Agent", openSub.conf.userAgentHTTP)
    client:add_header("Content-Type", "application/json")

    -- Add the Authorization header
    local auth_header = openSub.getAuthHeader()
    if auth_header then
        client:add_header("Authorization", auth_header)
        vlc.msg.dbg("[VLSub] Added Authorization header for download")
    else
        local errorMsg = "Authentication required for download, open config window to set credentials"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    end

    client:set_timeout(30)
    client:set_retries(2)

    setMessage(openSub.actionLabel..": "..progressBarContent(60))

    local res = client:post(download_url, request_body)

    if not res then
        local errorMsg = "No response from download server"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    end

    -- Handle different HTTP status codes
    if res.status == 401 then
        local errorMsg = "Authentication failed (401) - please check your credentials"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    elseif res.status == 403 then
        local errorMsg = "Access forbidden (403) - insufficient permissions"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    elseif res.status == 429 then
        local errorMsg = "Too many requests (429) - please wait and try again"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    elseif res.status == 500 then
        local errorMsg = "Server error (500) - please try again later"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    elseif res.status == 503 then
        local errorMsg = "Service unavailable (503) - server overloaded"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    elseif res.status ~= 200 then
        local errorMsg = "Download failed with HTTP status: " .. res.status
        vlc.msg.err("[VLSub] " .. errorMsg)
        if res.body then
            vlc.msg.err("[VLSub] Error response: " .. res.body)
            local ok, error_data = pcall(json.decode, res.body, 1, true)
            if ok and error_data and error_data.message then
                errorMsg = errorMsg .. " - " .. error_data.message
            end
        end
        setMessage(error_tag(errorMsg))
        return false
    end

    if not res.body or res.body == "" then
        local errorMsg = "Empty response from download server"
        vlc.msg.err("[VLSub] " .. errorMsg)
        setMessage(error_tag(errorMsg))
        return false
    end

    setMessage(openSub.actionLabel..": "..progressBarContent(75))

    -- Parse the download response
    local ok, download_response = pcall(json.decode, res.body, 1, true)
    local subtitle_content
    local downloads_used = "N/A"
    local downloads_remaining = "N/A"
    local reset_time_display = "N/A"

    if ok and download_response then
        -- Extract quota information
        if download_response.requests ~= nil then
            downloads_used = tostring(download_response.requests)
        end
        if download_response.remaining ~= nil then
            downloads_remaining = tostring(download_response.remaining)
        end
        if download_response.reset_time then
            reset_time_display = download_response.reset_time
        end

        if download_response.link then
            vlc.msg.dbg("[VLSub] Got download link: " .. download_response.link)
            setMessage(openSub.actionLabel..": "..progressBarContent(80))

            -- Download from the provided link
            local download_client = Curl.new()
            download_client:set_timeout(60)
            download_client:set_retries(3)

            local subtitle_res = download_client:get(download_response.link)
            if not subtitle_res then
                local errorMsg = "Failed to download from provided link"
                vlc.msg.err("[VLSub] " .. errorMsg)
                setMessage(error_tag(errorMsg))
                return false
            elseif subtitle_res.status ~= 200 then
                local errorMsg = "Failed to download subtitle content (HTTP " .. subtitle_res.status .. ")"
                vlc.msg.err("[VLSub] " .. errorMsg)
                setMessage(error_tag(errorMsg))
                return false
            elseif not subtitle_res.body then
                local errorMsg = "Empty subtitle content downloaded"
                vlc.msg.err("[VLSub] " .. errorMsg)
                setMessage(error_tag(errorMsg))
                return false
            end
            subtitle_content = subtitle_res.body
        elseif download_response.content then
            subtitle_content = download_response.content
            vlc.msg.dbg("[VLSub] Got direct subtitle content from API response")
        elseif download_response.error then
            local errorMsg = "API returned error: " .. (download_response.error or "Unknown error")
            vlc.msg.err("[VLSub] " .. errorMsg)
            setMessage(error_tag(errorMsg))
            return false
        else
            subtitle_content = res.body
            vlc.msg.dbg("[VLSub] Using entire response as subtitle content (fallback)")
        end
    else
        vlc.msg.dbg("[VLSub] Response is not JSON, treating as direct subtitle content")
        subtitle_content = res.body
    end

    setMessage(openSub.actionLabel..": "..progressBarContent(90))

    -- Save and load subtitle, then update message with quota
    local success_load_save = openSub.saveAndLoadSubtitle(subtitle_content, item)
    if success_load_save then
        -- Build enhanced message with quota info
        local base_message = input_table["message"]:get_text()
        
        -- Extract the base success message (before any quota info)
        local clean_message = string.gsub(base_message, "<[^>]*>", "") -- Remove HTML tags
        clean_message = string.gsub(clean_message, "Success:%s*", "") -- Remove "Success:" prefix
        
        -- Calculate quota info
        local num_downloads_used = tonumber(downloads_used)
        local num_downloads_remaining = tonumber(downloads_remaining)
        local total_allowed_downloads = "N/A"

        if num_downloads_used ~= nil and num_downloads_remaining ~= nil then
             total_allowed_downloads = tostring(num_downloads_used + num_downloads_remaining)
        end

        -- Format the quota message
        local quota_display = ""
        if num_downloads_used ~= nil and total_allowed_downloads ~= "N/A" then
            quota_display = "Quota: " .. num_downloads_used .. "/" .. total_allowed_downloads .. " downloads"
        end

        if reset_time_display ~= "N/A" then
            if quota_display ~= "" then
                quota_display = quota_display .. ", reset in: " .. reset_time_display
            else
                quota_display = "Quota reset in: " .. reset_time_display
            end
        end

        local final_message = clean_message
        if quota_display ~= "" then
            final_message = final_message .. ". " .. quota_display .. "."
        end

        setMessage(success_tag(final_message))
    end

    return success_load_save
end


-- Enhanced temporary config button with tooltip explanation
function show_auth_error_with_config_button(errorMessage)
  -- Show error message with helpful tooltip
  local brandedError = "<span style='color:#ff6600;' title='Authentication is required to download subtitles from OpenSubtitles.com'><b>🔐 Authentication Error:</b></span> " .. errorMessage
  setMessage(error_tag(brandedError))
  
  -- Add temporary config button
  if dlg and not input_table['temp_config_button'] then
    input_table['temp_config_button'] = dlg:add_button(
      "🔧 Setup Account", 
      handle_temp_config_click, 
      2, 10, 1, 1  -- Position in button row
    )
    dlg:update()
  end
end

-- Helper function to detect first run
function is_first_run()
  -- Check if both username and password are missing or empty
  local username = openSub.option.os_username or ""
  local password = openSub.option.os_password or ""
  
  -- Trim whitespace
  username = trim(username)
  password = trim(password)
  
  -- Return true if either is empty (first run)
  if username == "" or password == "" then
    vlc.msg.dbg("[VLsub] Missing credentials - username: '" .. username .. "', password: " .. (password ~= "" and "[set]" or "[empty]") .. "'")
    return true
  end
  
  return false
end

openSub.checkLoginAndUserInfo = function()
  openSub.actionLabel = "Checking login status"
  setMessage(loading_tag("Verifying credentials..."))
  
  -- First ensure we have credentials
  local username = trim(openSub.option.os_username or "")
  local password = trim(openSub.option.os_password or "")
  
  if username == "" or password == "" then
    setMessage(error_tag("Username and password are required for authentication"))
    return false
  end
  
  -- Force fresh login (don't use cached token for verification)
  vlc.msg.dbg("[VLSub] Performing fresh login for verification")
  local authenticated = openSub.loginWithRestAPI()
  
  if not authenticated then
    -- Error message should already be set by loginWithRestAPI
    return false
  end
  
  -- Now get user information
  setMessage(loading_tag("Fetching account information..."))
  
  local user_info_url = "https://api.opensubtitles.com/api/v1/infos/user"
  
  local client = Curl.new()
  client:add_header("Api-Key", config.api_key)
  client:add_header("User-Agent", openSub.conf.userAgentHTTP)
  
  -- Add authorization header
  local auth_header = openSub.getAuthHeader()
  if auth_header then
    client:add_header("Authorization", auth_header)
  else
    setMessage(error_tag("No authentication token available"))
    return false
  end
  
  client:set_timeout(30)
  client:set_retries(2)
  
  local res = client:get(user_info_url)
  
  if not res then
    setMessage(error_tag("No response from user info API"))
    return false
  end
  
  if res.status == 401 then
    setMessage(error_tag("Authentication failed (401) - please check your credentials"))
    -- Clear invalid token
    openSub.session.token = ""
    openSub.session.token_expires = 0
    return false
  elseif res.status == 403 then
    setMessage(error_tag("Access forbidden (403) - insufficient permissions"))
    return false
  elseif res.status ~= 200 then
    local errorMsg = "User info request failed with HTTP status: " .. res.status
    if res.body then
      vlc.msg.err("[VLSub] Error response: " .. res.body)
      -- Try to parse error message
      local ok, error_data = pcall(json.decode, res.body, 1, true)
      if ok and error_data and error_data.message then
        errorMsg = errorMsg .. " - " .. error_data.message
      end
    end
    setMessage(error_tag(errorMsg))
    return false
  end
  
  if not res.body then
    setMessage(error_tag("Empty response from user info API"))
    return false
  end
  
  -- Parse the user info response
  local ok, user_response = pcall(json.decode, res.body, 1, true)
  if not ok or not user_response then
    setMessage(error_tag("Failed to parse user info response"))
    return false
  end
  
  if not user_response.data then
    setMessage(error_tag("Invalid user info response format"))
    return false
  end
  
  local user_data = user_response.data
  
  -- Simple one-line format
  local downloads_count = user_data.downloads_count or 0
  local allowed_downloads = user_data.allowed_downloads or 0
  local username = user_data.username or "Unknown"
  local level = user_data.level or "Unknown"
  local reset_time = user_data.reset_time or user_data.reset_time_utc or "Unknown"
  
  local user_info_html = success_tag("" .. username .. " (" .. level .. "), " .. downloads_count .. "/" .. allowed_downloads .. " downloads, reset in: " .. reset_time)
  
  -- Store this message in a way that won't get cleared
  openSub.lastSuccessMessage = user_info_html
  
  -- Force update the message display and ensure it persists
  setMessage(user_info_html)
  if dlg then
    dlg:update()
  end
  
  -- Update session with fresh user info
  openSub.session.user_info = user_data
  
  vlc.msg.dbg("[VLSub] User info check successful for: " .. (user_data.username or "unknown"))
  vlc.msg.dbg("[VLSub] Downloads: " .. downloads_count .. "/" .. allowed_downloads .. ", Remaining: " .. (user_data.remaining or "N/A"))
  
  return true
end

-- Add this function to check if file is local and suitable for hashing
function openSub.isLocalFileForHashing()
  local file = openSub.file
  
  -- Check if we have valid file info
  if not file.hasInput or not file.protocol or not file.path then
    vlc.msg.dbg("[VLSub] No valid file input for hashing")
    return false
  end
  
  -- Only allow local file protocols
  if file.protocol ~= "file" then
    vlc.msg.dbg("[VLSub] File protocol '" .. file.protocol .. "' not supported for hashing")
    return false
  end
  
  -- Check if file actually exists locally (for file:// protocol)
  if file.protocol == "file" then
    if file.is_archive then
      vlc.msg.dbg("[VLSub] Archive files supported for hashing via stream")
      return true
    end
    
    if not file.path or not file_exist(file.path) then
      vlc.msg.dbg("[VLSub] File does not exist locally: " .. (file.path or "nil"))
      return false
    end
  end
  
  -- Additional check for minimum file size (very small files might not be valid)
  if file.stat and file.stat.size and file.stat.size < 65536 then
    vlc.msg.dbg("[VLSub] File too small for reliable hashing: " .. file.stat.size .. " bytes")
    return false
  end
  
  vlc.msg.dbg("[VLSub] File is suitable for hashing: " .. file.path)
  return true
end

-- Function to check if user has valid authentication
function has_valid_authentication()
  -- Check if we have credentials
  local username = trim(openSub.option.os_username or "")
  local password = trim(openSub.option.os_password or "")
  
  if username == "" or password == "" then
    return false
  end
  
  -- Check if we have a valid session
  if openSub.session.token and openSub.session.token ~= "" and 
     openSub.session.token_expires > os.time() then
    return true
  end
  
  return is_authenticated
end

-- Enhanced locale detection function with IP geolocation
function detect_user_locale()
  local detected_locales = {}
  
  vlc.msg.dbg("[VLSub] Starting locale detection...")
  
  -- Method 1: Environment variables (Unix/Linux/macOS)
  local env_vars = {"LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LC_CTYPE"}
  
  for _, var in ipairs(env_vars) do
    local value = os.getenv(var)
    if value and value ~= "" then
      vlc.msg.dbg("[VLSub] Environment " .. var .. ": " .. value)
      table.insert(detected_locales, {source = "env_" .. var, locale = value})
      
      -- Extract language code from locale (e.g., "en_US.UTF-8" -> "en")
      local lang_code = string.match(value, "^([a-z][a-z])")
      if lang_code then
        vlc.msg.dbg("[VLSub] Extracted language code from " .. var .. ": " .. lang_code)
      end
    end
  end
  
  -- Method 2: VLC's own locale settings
  local vlc_lang = vlc.config.get("intf")
  if vlc_lang and vlc_lang ~= "" then
    vlc.msg.dbg("[VLSub] VLC interface language: " .. vlc_lang)
    table.insert(detected_locales, {source = "vlc_intf", locale = vlc_lang})
  end
  
  -- Method 3: System locale via Lua's os.setlocale (works differently on different platforms)
  local sys_locale = os.setlocale(nil, "time")
  if sys_locale and sys_locale ~= "C" and sys_locale ~= "POSIX" then
    vlc.msg.dbg("[VLSub] System locale (time): " .. sys_locale)
    table.insert(detected_locales, {source = "sys_time", locale = sys_locale})
  end
  
  local sys_locale_collate = os.setlocale(nil, "collate")
  if sys_locale_collate and sys_locale_collate ~= "C" and sys_locale_collate ~= "POSIX" then
    vlc.msg.dbg("[VLSub] System locale (collate): " .. sys_locale_collate)
    table.insert(detected_locales, {source = "sys_collate", locale = sys_locale_collate})
  end
  
  local sys_locale_ctype = os.setlocale(nil, "ctype")
  if sys_locale_ctype and sys_locale_ctype ~= "C" and sys_locale_ctype ~= "POSIX" then
    vlc.msg.dbg("[VLSub] System locale (ctype): " .. sys_locale_ctype)
    table.insert(detected_locales, {source = "sys_ctype", locale = sys_locale_ctype})
  end
  
  -- Method 4: Platform-specific detection
  if openSub.conf.os == "win" then
    -- Windows-specific locale detection
    detect_windows_locale(detected_locales)
  elseif openSub.conf.os == "lin" then
    -- Linux/Unix-specific locale detection
    detect_unix_locale(detected_locales)
  end
  
  -- Method 5: Try to detect from user's subtitle language preferences if available
  if openSub.option.language and openSub.option.language ~= "" then
    vlc.msg.dbg("[VLSub] User's preferred subtitle language: " .. openSub.option.language)
    table.insert(detected_locales, {source = "user_pref", locale = openSub.option.language})
  end
  
  -- Method 6: IP-based geolocation (NEW!)
  detect_ip_based_locale(detected_locales)
  
  -- Analyze and prioritize the detected locales
  local best_guess = analyze_detected_locales(detected_locales)
  
  vlc.msg.dbg("[VLSub] Locale detection summary:")
  vlc.msg.dbg("[VLSub] Total detection methods tried: " .. #detected_locales)
  if best_guess then
    vlc.msg.dbg("[VLSub] Best guess locale: " .. best_guess.locale .. " (from " .. best_guess.source .. ")")
    vlc.msg.dbg("[VLSub] Extracted language: " .. (best_guess.language or "unknown"))
    vlc.msg.dbg("[VLSub] Extracted country: " .. (best_guess.country or "unknown"))
  else
    vlc.msg.dbg("[VLSub] Could not determine user locale")
  end
  
  return best_guess
end




-- Windows-specific locale detection (safe methods only)
function detect_windows_locale(detected_locales)
  vlc.msg.dbg("[VLSub] Attempting Windows locale detection (safe methods only)...")
  
  -- Method 1: Safe environment variables (no permissions needed)
  local win_env_vars = {
    "LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES", 
    "USERPROFILE", -- Often contains username with locale hints
    "COMPUTERNAME", -- Sometimes contains region info
    "TZ" -- Timezone
  }
  
  for _, var in ipairs(win_env_vars) do
    local value = os.getenv(var)
    if value and value ~= "" then
      vlc.msg.dbg("[VLSub] Windows env " .. var .. ": " .. value)
      if var == "LANG" or var == "LANGUAGE" or var == "LC_ALL" or var == "LC_MESSAGES" then
        table.insert(detected_locales, {source = "win_env_" .. var, locale = value})
      end
    end
  end
  
  -- Method 2: Safe system commands (usually work without special permissions)
  local safe_commands = {
    -- Get system locale via echo and built-in variables (safer than registry)
    'echo %LANG% 2>nul',
    -- Try to get timezone (can hint at locale)
    'tzutil /g 2>nul',
    -- Get system code page (can indicate language)
    'chcp 2>nul'
  }
  
  for i, cmd in ipairs(safe_commands) do
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*all")
      handle:close()
      
      if result and result ~= "" then
        result = string.gsub(result, "[\r\n]", "")
        result = string.gsub(result, "%s+", " ")
        result = string.gsub(result, "^%s*(.-)%s*$", "%1")
        
        vlc.msg.dbg("[VLSub] Windows safe command " .. i .. " result: " .. result)
        
        if i == 1 and result ~= "%LANG%" and result ~= "" then -- LANG variable
          table.insert(detected_locales, {source = "win_safe_lang", locale = result})
        elseif i == 2 and result ~= "" then -- Timezone
          vlc.msg.dbg("[VLSub] Windows timezone: " .. result)
          -- Map common Windows timezones to locales
          local tz_locale_map = {
            ["Eastern Standard Time"] = "en_US",
            ["Pacific Standard Time"] = "en_US", 
            ["Central Standard Time"] = "en_US",
            ["Mountain Standard Time"] = "en_US",
            ["GMT Standard Time"] = "en_GB",
            ["Central European Time"] = "de_DE",
            ["Romance Standard Time"] = "fr_FR",
            ["Tokyo Standard Time"] = "ja_JP",
            ["China Standard Time"] = "zh_CN",
            ["Korea Standard Time"] = "ko_KR"
          }
          local mapped = tz_locale_map[result]
          if mapped then
            vlc.msg.dbg("[VLSub] Mapped Windows timezone to: " .. mapped)
            table.insert(detected_locales, {source = "win_timezone_hint", locale = mapped})
          end
        elseif i == 3 and result ~= "" then -- Code page
          vlc.msg.dbg("[VLSub] Windows code page: " .. result)
          -- Extract code page number
          local cp = string.match(result, "(%d+)")
          if cp then
            -- Map common Windows code pages to locales  
            local cp_locale_map = {
              ["1252"] = "en_US", -- Western European
              ["1251"] = "ru_RU", -- Cyrillic
              ["1250"] = "pl_PL", -- Central European
              ["932"] = "ja_JP",  -- Japanese
              ["936"] = "zh_CN",  -- Chinese Simplified
              ["950"] = "zh_TW",  -- Chinese Traditional
              ["949"] = "ko_KR",  -- Korean
              ["1254"] = "tr_TR", -- Turkish
              ["1253"] = "el_GR", -- Greek
              ["1255"] = "he_IL", -- Hebrew
              ["1256"] = "ar_SA"  -- Arabic
            }
            local mapped = cp_locale_map[cp]
            if mapped then
              vlc.msg.dbg("[VLSub] Mapped code page " .. cp .. " to: " .. mapped)
              table.insert(detected_locales, {source = "win_codepage_hint", locale = mapped})
            end
          end
        end
      end
    end
  end
  
  -- Method 3: Try to detect via available system commands/tools
  local region_commands = {
    'where powershell >nul 2>&1 && echo powershell_available',
    'where cmd >nul 2>&1 && echo cmd_available',
    'dir /b "%WINDIR%\\System32\\en-US" >nul 2>&1 && echo english_resources'
  }
  
  for i, cmd in ipairs(region_commands) do
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*all")
      handle:close()
      
      if result and string.find(result, "available") then
        vlc.msg.dbg("[VLSub] Windows tool " .. i .. " available")
        if i == 3 then -- English resources found
          table.insert(detected_locales, {source = "win_english_resources", locale = "en_US"})
        end
      end
    end
  end
  
  -- Method 4: Check VLC's own language if we can safely access it
  -- This is safe because we're already running inside VLC
  local vlc_lang = vlc.config.get("intf")
  if vlc_lang and vlc_lang ~= "" then
    vlc.msg.dbg("[VLSub] VLC Windows interface language: " .. vlc_lang)
    table.insert(detected_locales, {source = "win_vlc_intf", locale = vlc_lang})
  end
end

-- macOS-specific locale detection using safe methods (no special permissions)
function detect_macos_locale(detected_locales)
  vlc.msg.dbg("[VLSub] Attempting macOS-specific locale detection (safe methods only)...")
  
  -- Method 1: Basic defaults read for public preferences (usually works without permissions)
  local safe_commands = {
    -- Try to get Apple locale (often works)
    'defaults read -g AppleLocale 2>/dev/null',
    -- Try to get first language from languages array
    'defaults read -g AppleLanguages 2>/dev/null | head -5'
  }
  
  for i, cmd in ipairs(safe_commands) do
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*all")
      handle:close()
      
      if result and result ~= "" then
        vlc.msg.dbg("[VLSub] Safe macOS method " .. i .. " result: " .. result:sub(1, 100))
        
        if i == 1 then -- AppleLocale
          local locale = string.gsub(result, "%s+", "")
          locale = string.gsub(locale, "[\r\n]", "")
          if locale ~= "" and locale ~= "(null)" then
            vlc.msg.dbg("[VLSub] Found safe AppleLocale: " .. locale)
            table.insert(detected_locales, {source = "macos_safe_locale", locale = locale})
          end
        elseif i == 2 then -- AppleLanguages (first few lines)
          -- Extract first language from array output
          local first_lang = string.match(result, '"([^"]+)"')
          if first_lang then
            vlc.msg.dbg("[VLSub] Found safe AppleLanguage: " .. first_lang)
            table.insert(detected_locales, {source = "macos_safe_language", locale = first_lang})
          end
        end
      end
    end
  end
  
  -- Method 2: Check environment variables that might be set by macOS apps
  local macos_env_vars = {"LC_ALL", "LC_MESSAGES", "LANG"}
  for _, var in ipairs(macos_env_vars) do
    local value = os.getenv(var)
    if value and value ~= "" and value ~= "C" then
      vlc.msg.dbg("[VLSub] macOS env " .. var .. ": " .. value)
      table.insert(detected_locales, {source = "macos_env_" .. var, locale = value})
    end
  end
  
  -- Method 3: Try to infer from timezone (sometimes correlates with locale)
  local tz_handle = io.popen('date +%Z 2>/dev/null')
  if tz_handle then
    local tz_result = tz_handle:read("*all")
    tz_handle:close()
    
    if tz_result and tz_result ~= "" then
      tz_result = string.gsub(tz_result, "[\r\n]", "")
      vlc.msg.dbg("[VLSub] macOS timezone: " .. tz_result)
      
      -- Simple timezone to locale mapping (very basic)
      local tz_locale_map = {
        EST = "en_US", PST = "en_US", MST = "en_US", CST = "en_US",
        CET = "en_GB", GMT = "en_GB", BST = "en_GB",
        JST = "ja_JP", KST = "ko_KR", CST = "zh_CN"
      }
      
      local mapped_locale = tz_locale_map[tz_result]
      if mapped_locale then
        vlc.msg.dbg("[VLSub] Mapped timezone " .. tz_result .. " to locale: " .. mapped_locale)
        table.insert(detected_locales, {source = "macos_timezone_hint", locale = mapped_locale})
      end
    end
  end
  
  -- Method 4: Check if we're in a specific region based on available system commands
  local region_commands = {
    'which say 2>/dev/null', -- English voice synthesis (common in English macOS)
    'ls /System/Library/CoreServices/SystemVersion.plist 2>/dev/null' -- Always there, but can check access
  }
  
  for i, cmd in ipairs(region_commands) do
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*all")
      handle:close()
      
      if result and result ~= "" then
        vlc.msg.dbg("[VLSub] macOS region command " .. i .. " available")
        if i == 1 then -- say command available
          table.insert(detected_locales, {source = "macos_say_available", locale = "en_US"})
        end
      end
    end
  end
end

-- Enhanced analyze_detected_locales function with English fallback
function analyze_detected_locales(detected_locales)
  if #detected_locales == 0 then
    return nil
  end
  
  -- Priority order for sources (higher index = higher priority)
  local source_priority = {
    user_pref = 15,
    linux_user_config = 13,
    macos_safe_locale = 12,
    macos_safe_language = 11,
    win_safe_lang = 10,
    win_vlc_intf = 9,
    linux_printenv_1 = 8,
    macos_env_LANG = 8,
    win_env_LANG = 8,
    env_LANG = 7,
    env_LC_ALL = 6,
    ip_geolocation = 6,
    locale_cmd_LANG = 5,
    vlc_intf = 4,
    file_locale_conf = 4,
    file_locale = 4,
    file_i18n = 4,
    ip_country_specific = 3,
    linux_available_locale = 3,
    win_timezone_hint = 3,
    win_codepage_hint = 3,
    linux_timezone_hint = 2,
    macos_timezone_hint = 2,
    win_english_resources = 1,
    sys_time = 1,
    sys_collate = 0,
    sys_ctype = 0
  }
  
  local best_locale = nil
  local best_priority = -1
  
  -- Collect all languages found with their countries
  local languages_found = {}
  local countries_found = {}
  
  for _, detection in ipairs(detected_locales) do
    local priority = source_priority[detection.source] or 0
    
    vlc.msg.dbg("[VLSub] Analyzing: " .. detection.locale .. " (source: " .. detection.source .. ", priority: " .. priority .. ")")
    
    -- Parse each detection to collect languages and countries
    local lang, country = parse_locale_string(detection.locale)
    if lang then
      if not languages_found[lang] then
        languages_found[lang] = {priority = priority, source = detection.source, count = 1}
      else
        -- Update if higher priority, or increment count
        if priority > languages_found[lang].priority then
          languages_found[lang].priority = priority
          languages_found[lang].source = detection.source
        end
        languages_found[lang].count = languages_found[lang].count + 1
      end
    end
    
    if country then
      if not countries_found[country] then
        countries_found[country] = {priority = priority, source = detection.source, count = 1}
      else
        if priority > countries_found[country].priority then
          countries_found[country].priority = priority
          countries_found[country].source = detection.source
        end
        countries_found[country].count = countries_found[country].count + 1
      end
    end
    
    if priority > best_priority then
      best_priority = priority
      best_locale = detection
    end
  end
  
  -- Log language analysis
  vlc.msg.dbg("[VLSub] Language analysis:")
  for lang, info in pairs(languages_found) do
    vlc.msg.dbg("[VLSub]   " .. lang .. ": priority=" .. info.priority .. ", count=" .. info.count .. ", source=" .. info.source)
  end
  
  vlc.msg.dbg("[VLSub] Country analysis:")
  for country, info in pairs(countries_found) do
    vlc.msg.dbg("[VLSub]   " .. country .. ": priority=" .. info.priority .. ", count=" .. info.count .. ", source=" .. info.source)
  end
  
  if best_locale then
    -- Parse the locale string to extract language and country
    local locale_str = best_locale.locale
    local language, country = parse_locale_string(locale_str)
    
    -- Build suggested languages list - ALWAYS BUILD MULTI-LANGUAGE SUGGESTIONS
    local suggested_languages = {}
    
    -- Add primary language (from best detection)
    if language then
      table.insert(suggested_languages, {
        language = language,
        priority = best_priority,
        source = best_locale.source,
        reason = "primary_detection"
      })
    end
    
    -- ALWAYS check for country-based languages, regardless of primary language
    local most_likely_country = nil
    local highest_country_priority = -1
    
    -- Look for country in all detections, including IP-based ones
    for country_code, info in pairs(countries_found) do
      if info.priority > highest_country_priority then
        highest_country_priority = info.priority
        most_likely_country = country_code
      end
    end
    
    -- Also check for direct country detection from IP geolocation
    for _, detection in ipairs(detected_locales) do
      if detection.source == "ip_geolocation" or detection.source == "ip_country_specific" then
        local detected_lang, detected_country = parse_locale_string(detection.locale)
        if detected_country and (not most_likely_country or source_priority[detection.source] >= highest_country_priority) then
          most_likely_country = detected_country
          highest_country_priority = source_priority[detection.source] or 0
          vlc.msg.dbg("[VLSub] Using IP-detected country: " .. detected_country)
        end
      end
    end
    
    if most_likely_country then
      vlc.msg.dbg("[VLSub] Processing country-based languages for: " .. most_likely_country)
      
      -- Enhanced country to languages mapping (native + commonly understood)
      local country_languages_map = {
        -- Central Europe - Slavic languages
        ["sk"] = {"sk", "cs"}, -- Slovakia: Slovak + Czech (very similar languages)
        ["cz"] = {"cs", "sk"}, -- Czech Republic: Czech + Slovak
        
        -- Scandinavia - North Germanic languages
        ["se"] = {"sv", "no", "da"}, -- Sweden: Swedish + Norwegian + Danish
        ["no"] = {"no", "sv", "da"}, -- Norway: Norwegian + Swedish + Danish  
        ["dk"] = {"da", "sv", "no"}, -- Denmark: Danish + Swedish + Norwegian
        
        -- Netherlands/Belgium - Dutch/Flemish
        ["nl"] = {"nl", "de", "en"}, -- Netherlands: Dutch + German + English
        ["be"] = {"nl", "fr", "de"}, -- Belgium: Dutch/Flemish + French + German
        
        -- Switzerland - Multilingual country
        ["ch"] = {"de", "fr", "it", "en"}, -- Switzerland: German + French + Italian + English
        
        -- Austria - German speaking
        ["at"] = {"de", "en"}, -- Austria: German + English
        
        -- Former Yugoslavia - South Slavic languages
        ["hr"] = {"hr", "sr", "bs"}, -- Croatia: Croatian + Serbian + Bosnian
        ["rs"] = {"sr", "hr", "bs"}, -- Serbia: Serbian + Croatian + Bosnian
        ["ba"] = {"bs", "hr", "sr"}, -- Bosnia: Bosnian + Croatian + Serbian
        ["me"] = {"sr", "hr", "bs"}, -- Montenegro: Serbian + Croatian + Bosnian
        ["si"] = {"sl", "hr", "de"}, -- Slovenia: Slovenian + Croatian + German
        ["mk"] = {"mk", "sr", "bg"}, -- North Macedonia: Macedonian + Serbian + Bulgarian
        
        -- Baltic states
        ["lv"] = {"lv", "ru", "en"}, -- Latvia: Latvian + Russian + English
        ["lt"] = {"lt", "ru", "en"}, -- Lithuania: Lithuanian + Russian + English  
        ["ee"] = {"et", "ru", "en"}, -- Estonia: Estonian + Russian + English
        
        -- Eastern Europe
        ["ua"] = {"uk", "ru", "en"}, -- Ukraine: Ukrainian + Russian + English
        ["by"] = {"be", "ru", "en"}, -- Belarus: Belarusian + Russian + English
        ["md"] = {"ro", "ru", "en"}, -- Moldova: Romanian + Russian + English
        
        -- Portuguese/Spanish speaking
        ["pt"] = {"pt", "es", "en"}, -- Portugal: Portuguese + Spanish + English
        ["es"] = {"es", "pt", "ca"}, -- Spain: Spanish + Portuguese + Catalan
        
        -- English + local languages
        ["ie"] = {"en", "ga"}, -- Ireland: English + Irish Gaelic
        ["gb"] = {"en", "cy", "gd"}, -- UK: English + Welsh + Scottish Gaelic
        
        -- German speaking regions
        ["de"] = {"de", "en"}, -- Germany: German + English
        ["lu"] = {"fr", "de", "lb"}, -- Luxembourg: French + German + Luxembourgish
        
        -- Nordic with English
        ["fi"] = {"fi", "sv", "en"}, -- Finland: Finnish + Swedish + English
        ["is"] = {"is", "da", "en"}, -- Iceland: Icelandic + Danish + English
        
        -- Multilingual regions
        ["ca"] = {"en", "fr"}, -- Canada: English + French
        ["sg"] = {"en", "zh-cn", "ms", "ta"}, -- Singapore: English + Chinese + Malay + Tamil
        ["in"] = {"hi", "en", "bn", "te"}, -- India: Hindi + English + regional languages
        
        -- Major single language countries (with English as common second language)
        ["us"] = {"en"}, -- USA: English
        ["au"] = {"en"}, -- Australia: English
        ["nz"] = {"en"}, -- New Zealand: English
        ["fr"] = {"fr", "en"}, -- France: French + English
        ["it"] = {"it", "en"}, -- Italy: Italian + English
        ["pl"] = {"pl", "en"}, -- Poland: Polish + English
        ["ro"] = {"ro", "en"}, -- Romania: Romanian + English
        ["hu"] = {"hu", "en"}, -- Hungary: Hungarian + English
        ["bg"] = {"bg", "en"}, -- Bulgaria: Bulgarian + English
        ["gr"] = {"el", "en"}, -- Greece: Greek + English
        ["tr"] = {"tr", "en"}, -- Turkey: Turkish + English
        ["ru"] = {"ru", "en"}, -- Russia: Russian + English
        ["jp"] = {"ja", "en"}, -- Japan: Japanese + English
        ["kr"] = {"ko", "en"}, -- South Korea: Korean + English
        ["cn"] = {"zh-cn", "en"}, -- China: Chinese + English
        ["tw"] = {"zh-tw", "en"}, -- Taiwan: Traditional Chinese + English
        ["hk"] = {"zh-ca", "en"}, -- Hong Kong: Cantonese + English
        ["th"] = {"th", "en"}, -- Thailand: Thai + English
        ["vn"] = {"vi", "en"}, -- Vietnam: Vietnamese + English
        ["id"] = {"id", "en"}, -- Indonesia: Indonesian + English
        ["my"] = {"ms", "en", "zh-cn"}, -- Malaysia: Malay + English + Chinese
        ["ph"] = {"tl", "en"}, -- Philippines: Tagalog + English
        ["br"] = {"pt-br", "es", "en"}, -- Brazil: Portuguese + Spanish + English
        ["mx"] = {"es", "en"}, -- Mexico: Spanish + English
        ["ar"] = {"es", "en"}, -- Argentina: Spanish + English
        ["cl"] = {"es", "en"}, -- Chile: Spanish + English
        ["co"] = {"es", "en"}, -- Colombia: Spanish + English
        ["pe"] = {"es", "en"}, -- Peru: Spanish + English
        ["ve"] = {"es", "en"}, -- Venezuela: Spanish + English
        ["ec"] = {"es", "en"}, -- Ecuador: Spanish + English
        ["bo"] = {"es", "en"}, -- Bolivia: Spanish + English
        ["py"] = {"es", "en"}, -- Paraguay: Spanish + English
        ["uy"] = {"es", "en"}, -- Uruguay: Spanish + English
        
        -- Arabic speaking countries
        ["sa"] = {"ar", "en"}, -- Saudi Arabia: Arabic + English
        ["ae"] = {"ar", "en"}, -- UAE: Arabic + English
        ["eg"] = {"ar", "en"}, -- Egypt: Arabic + English
        ["ma"] = {"ar", "fr", "en"}, -- Morocco: Arabic + French + English
        ["tn"] = {"ar", "fr", "en"}, -- Tunisia: Arabic + French + English
        ["dz"] = {"ar", "fr", "en"}, -- Algeria: Arabic + French + English
        ["lb"] = {"ar", "fr", "en"}, -- Lebanon: Arabic + French + English
        ["sy"] = {"ar", "en"}, -- Syria: Arabic + English
        ["jo"] = {"ar", "en"}, -- Jordan: Arabic + English
        ["iq"] = {"ar", "en"}, -- Iraq: Arabic + English
        ["kw"] = {"ar", "en"}, -- Kuwait: Arabic + English
        ["qa"] = {"ar", "en"}, -- Qatar: Arabic + English
        ["bh"] = {"ar", "en"}, -- Bahrain: Arabic + English
        ["om"] = {"ar", "en"}, -- Oman: Arabic + English
        ["ye"] = {"ar", "en"}, -- Yemen: Arabic + English
        
        -- Persian/Farsi speaking
        ["ir"] = {"fa", "en"}, -- Iran: Persian + English
        ["af"] = {"fa", "ar", "en"}, -- Afghanistan: Persian + Arabic + English
        
        -- Hebrew speaking
        ["il"] = {"he", "ar", "en"}, -- Israel: Hebrew + Arabic + English
        
        -- African countries (former colonies with multilingual heritage)
        ["za"] = {"en", "af", "zu"}, -- South Africa: English + Afrikaans + Zulu
        ["ng"] = {"en", "ha", "ig"}, -- Nigeria: English + Hausa + Igbo
        ["ke"] = {"en", "sw"}, -- Kenya: English + Swahili
        ["tz"] = {"sw", "en"}, -- Tanzania: Swahili + English
        ["gh"] = {"en", "tw"}, -- Ghana: English + Twi
        ["et"] = {"am", "en"}, -- Ethiopia: Amharic + English
      }
      
      local country_languages = country_languages_map[most_likely_country]
      if country_languages then
        vlc.msg.dbg("[VLSub] Found " .. #country_languages .. " languages for country " .. most_likely_country)
        for i, lang_code in ipairs(country_languages) do
          -- Skip if already added as primary
          local already_added = false
          for _, existing in ipairs(suggested_languages) do
            if existing.language == lang_code then
              already_added = true
              break
            end
          end
          
          if not already_added then
            vlc.msg.dbg("[VLSub] Adding country language " .. i .. ": " .. lang_code)
            table.insert(suggested_languages, {
              language = lang_code,
              priority = highest_country_priority,
              source = "country_multilingual",
              reason = i == 1 and "country_native_language" or "country_understood_language"
            })
          else
            vlc.msg.dbg("[VLSub] Skipping duplicate language: " .. lang_code)
          end
        end
      else
        vlc.msg.dbg("[VLSub] No multilingual mapping found for country: " .. most_likely_country)
      end
    end
    
    -- ENHANCED: Check if English is already included, if not add it as fallback
    local has_english = false
    for _, lang_suggestion in ipairs(suggested_languages) do
      if lang_suggestion.language == "en" then
        has_english = true
        break
      end
    end
    
    -- If English is not present and we have 1-2 languages detected, add English as fallback
    if not has_english and #suggested_languages >= 1 and #suggested_languages <= 2 then
      vlc.msg.dbg("[VLSub] Adding English as fallback language (detected " .. #suggested_languages .. " non-English languages)")
      table.insert(suggested_languages, {
        language = "en",
        priority = 1, -- Lower priority than detected languages
        source = "english_fallback",
        reason = "international_fallback"
      })
    end
    
    -- ADDITIONAL: Always ensure English is available if no languages detected at all
    if #suggested_languages == 0 then
      vlc.msg.dbg("[VLSub] No languages detected, defaulting to English")
      table.insert(suggested_languages, {
        language = "en",
        priority = 1,
        source = "english_default",
        reason = "default_language"
      })
    end
    
    vlc.msg.dbg("[VLSub] Final suggested languages count: " .. #suggested_languages)
    for i, lang_suggestion in ipairs(suggested_languages) do
      vlc.msg.dbg("[VLSub]   " .. i .. ": " .. lang_suggestion.language .. " (" .. lang_suggestion.reason .. ")")
    end
    
    return {
      locale = locale_str,
      source = best_locale.source,
      language = language,
      country = country,
      priority = best_priority,
      suggested_languages = suggested_languages,
      languages_analysis = languages_found,
      countries_analysis = countries_found
    }
  end
  
  return nil
end



-- Unix/Linux-specific locale detection  
function detect_unix_locale(detected_locales)
  vlc.msg.dbg("[VLSub] Attempting Unix/Linux locale detection...")
  
  -- Check if we're on macOS for additional detection methods
  local is_macos = false
  local handle = io.popen("uname -s 2>/dev/null")
  if handle then
    local result = handle:read("*all")
    handle:close()
    if result and string.find(result, "Darwin") then
      is_macos = true
      vlc.msg.dbg("[VLSub] Detected macOS system")
    else
      vlc.msg.dbg("[VLSub] Detected Unix/Linux system")
    end
  end
  
  -- macOS-specific locale detection
  if is_macos then
    detect_macos_locale(detected_locales)
  end
  
  -- Method 1: Standard locale command (safe, no permissions needed)
  local handle = io.popen("locale 2>/dev/null")
  if handle then
    local result = handle:read("*all")
    handle:close()
    
    if result and result ~= "" then
      vlc.msg.dbg("[VLSub] Locale command output:")
      for line in result:gmatch("[^\r\n]+") do
        vlc.msg.dbg("[VLSub]   " .. line)
        
        -- Extract locale values
        local var, value = string.match(line, "([^=]+)=(.+)")
        if var and value then
          value = string.gsub(value, '"', '') -- Remove quotes
          if value ~= "C" and value ~= "POSIX" and value ~= "" then
            table.insert(detected_locales, {source = "locale_cmd_" .. var, locale = value})
          end
        end
      end
    end
  end
  
  -- Method 2: Safe system files (readable by all users, no special permissions)
  local safe_locale_files = {
    "/etc/locale.conf",     -- systemd systems (Arch, Fedora, etc.)
    "/etc/default/locale",  -- Debian/Ubuntu systems  
    "/etc/sysconfig/i18n",  -- Red Hat/CentOS systems
    "/etc/environment"      -- Some distributions
  }
  
  for _, file_path in ipairs(safe_locale_files) do
    -- These files are typically world-readable, no special permissions needed
    local file = io.open(file_path, "r")
    if file then
      vlc.msg.dbg("[VLSub] Reading locale from: " .. file_path)
      local content = file:read("*all")
      file:close()
      
      for line in content:gmatch("[^\r\n]+") do
        -- Skip comments
        if not string.match(line, "^%s*#") and string.find(line, "=") then
          local var, value = string.match(line, "([^=]+)=(.+)")
          if var and value then
            -- Clean up variable name and value
            var = string.gsub(var, "^%s*(.-)%s*$", "%1")
            value = string.gsub(value, '"', '') -- Remove quotes
            value = string.gsub(value, "^%s*(.-)%s*$", "%1") -- Trim whitespace
            
            if (string.match(var, "LANG") or string.match(var, "LC_")) and 
               value ~= "C" and value ~= "POSIX" and value ~= "" then
              vlc.msg.dbg("[VLSub] Found in " .. file_path .. ": " .. var .. "=" .. value)
              table.insert(detected_locales, {source = "file_" .. string.gsub(file_path, ".*/", ""), locale = value})
            end
          end
        end
      end
    end
  end
  
  -- Method 3: Additional safe system commands (no permissions needed)
  local safe_commands = {
    -- Get current user's shell locale settings
    'printenv LANG 2>/dev/null',
    'printenv LC_ALL 2>/dev/null', 
    'printenv LANGUAGE 2>/dev/null',
    -- Check available locales (safe, read-only)
    'locale -a 2>/dev/null | head -5',
    -- Get timezone info (can hint at locale)
    'timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null'
  }
  
  for i, cmd in ipairs(safe_commands) do
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*all")
      handle:close()
      
      if result and result ~= "" then
        result = string.gsub(result, "[\r\n]", " ")
        result = string.gsub(result, "^%s*(.-)%s*$", "%1")
        
        vlc.msg.dbg("[VLSub] Linux safe command " .. i .. " result: " .. result:sub(1, 100))
        
        if i <= 3 and result ~= "" then -- Environment variables
          table.insert(detected_locales, {source = "linux_printenv_" .. i, locale = result})
        elseif i == 4 and result ~= "" then -- Available locales
          -- Parse first few available locales
          for locale in result:gmatch("([%w_%-%.]+)") do
            if string.match(locale, "^[a-z][a-z]_[A-Z][A-Z]") then
              vlc.msg.dbg("[VLSub] Found available locale: " .. locale)
              table.insert(detected_locales, {source = "linux_available_locale", locale = locale})
              break -- Just take the first good one
            end
          end
        elseif i == 5 and result ~= "" then -- Timezone
          vlc.msg.dbg("[VLSub] Linux timezone: " .. result)
          -- Map common timezones to likely locales
          local tz_locale_map = {
            ["America/New_York"] = "en_US",
            ["America/Los_Angeles"] = "en_US",
            ["America/Chicago"] = "en_US", 
            ["America/Denver"] = "en_US",
            ["Europe/London"] = "en_GB",
            ["Europe/Berlin"] = "de_DE",
            ["Europe/Paris"] = "fr_FR",
            ["Europe/Rome"] = "it_IT",
            ["Europe/Madrid"] = "es_ES",
            ["Asia/Tokyo"] = "ja_JP",
            ["Asia/Shanghai"] = "zh_CN",
            ["Asia/Seoul"] = "ko_KR",
            ["Australia/Sydney"] = "en_AU"
          }
          local mapped = tz_locale_map[result]
          if mapped then
            vlc.msg.dbg("[VLSub] Mapped Linux timezone to: " .. mapped)
            table.insert(detected_locales, {source = "linux_timezone_hint", locale = mapped})
          end
        end
      end
    end
  end
  
  -- Method 4: Check for desktop environment language (safe)
  local de_env_vars = {
    "XDG_CURRENT_DESKTOP", -- Desktop environment
    "DESKTOP_SESSION",     -- Desktop session
    "GDMSESSION"          -- GDM session
  }
  
  for _, var in ipairs(de_env_vars) do
    local value = os.getenv(var)
    if value then
      vlc.msg.dbg("[VLSub] Desktop environment " .. var .. ": " .. value)
      -- This doesn't directly give us locale, but shows we're in a graphical environment
    end
  end
  
  -- Method 5: Check user's home directory for .locale or similar files (safe)
  local home = os.getenv("HOME")
  if home then
    local user_locale_files = {
      home .. "/.locale",
      home .. "/.config/locale.conf",
      home .. "/.dmrc" -- Display manager config, sometimes has language
    }
    
    for _, file_path in ipairs(user_locale_files) do
      local file = io.open(file_path, "r")
      if file then
        vlc.msg.dbg("[VLSub] Reading user locale from: " .. file_path)
        local content = file:read("*all")
        file:close()
        
        -- Look for language/locale settings
        for line in content:gmatch("[^\r\n]+") do
          if string.find(line, "=") and not string.match(line, "^%s*#") then
            local var, value = string.match(line, "([^=]+)=(.+)")
            if var and value then
              var = string.gsub(var, "^%s*(.-)%s*$", "%1")
              value = string.gsub(value, '"', '')
              value = string.gsub(value, "^%s*(.-)%s*$", "%1")
              
              if (string.match(var:lower(), "lang") or string.match(var:lower(), "locale")) and 
                 value ~= "" and value ~= "C" then
                vlc.msg.dbg("[VLSub] Found user locale: " .. var .. "=" .. value)
                table.insert(detected_locales, {source = "linux_user_config", locale = value})
              end
            end
          end
        end
      end
    end
  end
end




-- Parse locale string to extract language and country codes
function parse_locale_string(locale_str)
  if not locale_str or locale_str == "" then
    return nil, nil
  end
  
  -- Handle different locale formats:
  -- en_US.UTF-8, en-US, en_US, en, fr_FR.UTF-8, en_SK, etc.
  
  -- First, extract the main part before any encoding (before . or @)
  local main_part = string.match(locale_str, "^([^%.@]+)")
  if not main_part then
    main_part = locale_str
  end
  
  -- Now extract language and country
  local language, country
  
  -- Format: en_US, en-US, en_SK, etc. (both underscore and hyphen)
  language, country = string.match(main_part, "^([a-z][a-z])[_%-]([A-Z][A-Z])$")
  if language and country then
    return language, string.lower(country)
  end
  
  -- Format: just language code (en, fr, de, etc.)
  language = string.match(main_part, "^([a-z][a-z])$")
  if language then
    return language, nil
  end
  
  -- Format: language_Script_Country (zh_Hans_CN, etc.)
  language, country = string.match(main_part, "^([a-z][a-z])_[A-Za-z]+_([A-Z][A-Z])$")
  if language and country then
    return language, string.lower(country)
  end
  
  vlc.msg.dbg("[VLSub] Could not parse locale string: " .. locale_str)
  return nil, nil
end



-- Map language codes to OpenSubtitles language codes (2-character codes from API)
function map_to_opensubtitles_language(language_code)
  -- Mapping table based on the actual OpenSubtitles API language codes
  local language_mapping = {
    -- Direct matches (no mapping needed)
    ab = "ab", -- Abkhazian
    af = "af", -- Afrikaans
    sq = "sq", -- Albanian
    am = "am", -- Amharic
    ar = "ar", -- Arabic
    an = "an", -- Aragonese
    hy = "hy", -- Armenian
    as = "as", -- Assamese
    at = "at", -- Asturian
    eu = "eu", -- Basque
    be = "be", -- Belarusian
    bn = "bn", -- Bengali
    bs = "bs", -- Bosnian
    br = "br", -- Breton
    bg = "bg", -- Bulgarian
    my = "my", -- Burmese
    ca = "ca", -- Catalan
    hr = "hr", -- Croatian
    cs = "cs", -- Czech
    da = "da", -- Danish
    pr = "pr", -- Dari
    nl = "nl", -- Dutch
    en = "en", -- English
    eo = "eo", -- Esperanto
    et = "et", -- Estonian
    ex = "ex", -- Extremaduran
    fi = "fi", -- Finnish
    fr = "fr", -- French
    gd = "gd", -- Gaelic
    gl = "gl", -- Galician
    ka = "ka", -- Georgian
    de = "de", -- German
    el = "el", -- Greek
    he = "he", -- Hebrew
    hi = "hi", -- Hindi
    hu = "hu", -- Hungarian
    is = "is", -- Icelandic
    ig = "ig", -- Igbo
    id = "id", -- Indonesian
    ia = "ia", -- Interlingua
    ga = "ga", -- Irish
    it = "it", -- Italian
    ja = "ja", -- Japanese
    kn = "kn", -- Kannada
    kk = "kk", -- Kazakh
    km = "km", -- Khmer
    ko = "ko", -- Korean
    ku = "ku", -- Kurdish
    lv = "lv", -- Latvian
    lt = "lt", -- Lithuanian
    lb = "lb", -- Luxembourgish
    mk = "mk", -- Macedonian
    ms = "ms", -- Malay
    ml = "ml", -- Malayalam
    ma = "ma", -- Manipuri
    mr = "mr", -- Marathi
    mn = "mn", -- Mongolian
    me = "me", -- Montenegrin
    nv = "nv", -- Navajo
    ne = "ne", -- Nepali
    se = "se", -- Northern Sami
    no = "no", -- Norwegian
    oc = "oc", -- Occitan
    ["or"] = "or", -- Odia (quoted because 'or' is reserved keyword)
    fa = "fa", -- Persian
    pl = "pl", -- Polish
    ro = "ro", -- Romanian
    ru = "ru", -- Russian
    sx = "sx", -- Santali
    sr = "sr", -- Serbian
    sd = "sd", -- Sindhi
    si = "si", -- Sinhalese
    sk = "sk", -- Slovak
    sl = "sl", -- Slovenian
    so = "so", -- Somali
    es = "es", -- Spanish
    sp = "sp", -- Spanish (EU)
    ea = "ea", -- Spanish (LA)
    sw = "sw", -- Swahili
    sv = "sv", -- Swedish
    sy = "sy", -- Syriac
    tl = "tl", -- Tagalog
    ta = "ta", -- Tamil
    tt = "tt", -- Tatar
    te = "te", -- Telugu
    th = "th", -- Thai
    tp = "tp", -- Toki Pona
    tr = "tr", -- Turkish
    tk = "tk", -- Turkmen
    uk = "uk", -- Ukrainian
    ur = "ur", -- Urdu
    uz = "uz", -- Uzbek
    vi = "vi", -- Vietnamese
    cy = "cy", -- Welsh
    
    -- Special mappings for complex codes
    ["az-az"] = "az-az", -- Azerbaijani
    ["az-zb"] = "az-zb", -- South Azerbaijani
    ["zh-ca"] = "zh-ca", -- Chinese (Cantonese)
    ["zh-cn"] = "zh-cn", -- Chinese (simplified)
    ["zh-tw"] = "zh-tw", -- Chinese (traditional)
    ["pt-pt"] = "pt-pt", -- Portuguese
    ["pt-br"] = "pt-br", -- Portuguese (BR)
    ["tm-td"] = "tm-td", -- Tetum
    ze = "ze", -- Chinese bilingual
    pm = "pm", -- Portuguese (MZ)
    ps = "ps", -- Pushto
    
    -- Common locale mappings to OpenSubtitles codes
    zh = "zh-cn", -- Chinese -> Chinese (simplified)
    pt = "pt-pt", -- Portuguese -> Portuguese (Portugal)
    az = "az-az", -- Azerbaijani -> Azerbaijani
    tm = "tm-td" -- Turkmen -> Tetum (this might need verification)
  }
  
  -- First try direct mapping
  local mapped = language_mapping[language_code]
  if mapped then
    return mapped
  end
  
  -- If no mapping found, return original code
  return language_code
end



-- Updated check_login_clicked function to use current form data
function check_login_clicked()
  vlc.msg.dbg("[VLSub] Check login button clicked")
  
  -- Get current form values (don't save config yet, just use temp values)
  local temp_username = trim(input_table['os_username']:get_text() or "")
  local temp_password = trim(input_table['os_password']:get_text() or "")
  
  -- Check if username or password is empty
  if temp_username == "" or temp_password == "" then
    setMessage(error_tag("Please enter both username and password before checking login"))
    return
  end
  
  -- Temporarily store current config values
  local saved_username = openSub.option.os_username
  local saved_password = openSub.option.os_password
  
  -- Set temporary values for login test
  openSub.option.os_username = temp_username
  openSub.option.os_password = temp_password
  
  -- Clear any existing session to force fresh login
  openSub.session.token = ""
  openSub.session.token_expires = 0
  openSub.session.user_info = nil
  
  -- Attempt login and get user info
  local success = openSub.checkLoginAndUserInfo()
  
  -- Restore original config values (don't save the temporary ones)
  openSub.option.os_username = saved_username
  openSub.option.os_password = saved_password
  
  if not success then
    vlc.msg.dbg("[VLSub] Login check failed")
    -- Error message should already be set by checkLoginAndUserInfo
  else
    vlc.msg.dbg("[VLSub] Login check successful")
    -- Success message should already be set by checkLoginAndUserInfo
  end
end

local function isValidPositiveNumber(value)
  if not value or value == "" then
    return false
  end
  local num = tonumber(value)
  return num and num > 0
end


local function escape(str)
    return str:gsub('"', '\\"')
end

-- Function to show appropriate window after debug closes
function show_appropriate_window()
  -- Check if user has valid authentication (already configured)
  local has_valid_auth = has_valid_authentication()
  
  vlc.msg.dbg("[VLSub] Determining appropriate window:")
  vlc.msg.dbg("[VLSub]   - has_valid_authentication(): " .. tostring(has_valid_auth))
  vlc.msg.dbg("[VLSub]   - is_first_run result: " .. tostring(init_results.is_first_run))
  vlc.msg.dbg("[VLSub]   - stored has_auth: " .. tostring(init_results.has_auth))
  
  -- Use the stored authentication check from initialization
  if init_results.has_auth or has_valid_auth then
    vlc.msg.dbg("[VLSub] User has valid authentication - showing main window")
    is_authenticated = true
    show_main()
  else
    vlc.msg.dbg("[VLSub] No valid authentication - showing configuration window")
    is_authenticated = false
    show_conf()
  end
end

function update_debug_progress(message)
  if debug_messages and debug_messages.progress then
    debug_messages.progress:set_text(message)
    update_debug_buttons()  -- Update buttons when progress changes
    if debug_dlg then
      debug_dlg:update()
    end
  end
  vlc.msg.dbg("[VLSub Debug] Progress: " .. message)
end

function update_debug_status(message)
  if debug_messages and debug_messages.status then
    debug_messages.status:set_text(message)
    update_debug_buttons()  -- Update buttons when status changes
    if debug_dlg then
      debug_dlg:update()
    end
  end
  vlc.msg.dbg("[VLSub Debug] Status: " .. message)
end

function update_debug_network(message)
  if debug_messages and debug_messages.network then
    debug_messages.network:set_text(message)
    if debug_dlg then
      debug_dlg:update()
    end
  end
  vlc.msg.dbg("[VLSub Debug] Network: " .. message)
end

function append_debug_log(message)
  if not debug_log_rows or #debug_log_rows == 0 then
    vlc.msg.dbg("[VLSub Debug] " .. message)
    return
  end
  
  local timestamp = os.date("%H:%M:%S")
  local new_line = "[" .. timestamp .. "] " .. message
  
  -- Shift all messages down (move each message to the next row)
  for i = 8, 2, -1 do -- Start from bottom, go up
    if debug_log_rows[i-1] then
      local prev_text = debug_log_rows[i-1]:get_text()
      debug_log_rows[i]:set_text(prev_text)
    end
  end
  
  -- Put new message at the top (row 1)
  debug_log_rows[1]:set_text(new_line)
  
  if debug_dlg then
    debug_dlg:update()
  end
  
  vlc.msg.dbg("[VLSub Debug] " .. message)
end

function close_debug_window()
  if debug_dlg then
    debug_dlg:hide()
    debug_dlg = nil
  end
  debug_messages = {}
  debug_log_rows = {}
  initialization_complete = true
end


-- Enhanced function to get Downloads folder path
function get_downloads_folder()
  local downloads_path = nil
  
  if openSub.conf.os == "win" then
    -- Windows: Try multiple methods to find Downloads folder
    local win_downloads_paths = {
      os.getenv("USERPROFILE") .. "\\Downloads",
      os.getenv("HOMEDRIVE") .. os.getenv("HOMEPATH") .. "\\Downloads"
    }
    
    for _, path in ipairs(win_downloads_paths) do
      if path and is_dir(path) then
        downloads_path = path
        break
      end
    end
    
    -- Fallback: try to get Downloads folder via PowerShell
    if not downloads_path then
      local handle = io.popen('powershell -Command "([Environment]::GetFolderPath([Environment+SpecialFolder]::Downloads))" 2>nul')
      if handle then
        local result = handle:read("*all")
        handle:close()
        if result and result ~= "" then
          result = string.gsub(result, "[\r\n]", "")
          if is_dir(result) then
            downloads_path = result
          end
        end
      end
    end
    
  else
    -- macOS/Linux: Standard Downloads folder
    local home = os.getenv("HOME")
    if home then
      local unix_downloads_path = home .. "/Downloads"
      if is_dir(unix_downloads_path) then
        downloads_path = unix_downloads_path
      end
    end
  end
  
  vlc.msg.dbg("[VLSub] Downloads folder detected: " .. (downloads_path or "not found"))
  return downloads_path
end



-- Enhanced network connectivity test with tracking
function test_network_connectivity()
  update_debug_network("Testing network connectivity...")
  
  -- Test with multiple fast endpoints
  local test_urls = {
    "https://www.google.com",
    "https://api.opensubtitles.com", 
    "https://httpbin.org/get"
  }
  
  vlc.msg.warn("[VLSub Network] Starting connectivity tests...")
  append_debug_log("🔍 Starting network tests...")
  
  for i, url in ipairs(test_urls) do
    update_debug_network("Testing connection " .. i .. "/" .. #test_urls .. "...")
    append_debug_log("Testing: " .. url)
    
    vlc.msg.warn("[VLSub Network] Test " .. i .. "/" .. #test_urls .. " → " .. url)
    
    local test_client = Curl.new()
    test_client:set_aggressive_timeouts()
    test_client:set_timeout(3)  -- Very short timeout
    test_client:set_retries(0)  -- No retries for speed
    
    local start_time = os.clock()
    local res = test_client:get(url)  -- This will now be tracked by the enhanced request method
    local end_time = os.clock()
    local elapsed_ms = math.floor((end_time - start_time) * 1000)
    
    if res and res.status and res.status >= 200 and res.status < 400 then
      update_debug_network("Connection OK (responded in " .. elapsed_ms .. "ms)")
      append_debug_log("✅ Network test PASSED")
      vlc.msg.warn("[VLSub Network] Test PASSED - Network connectivity confirmed")
      return true
    else
      append_debug_log("❌ Network test FAILED")
      vlc.msg.warn("[VLSub Network] Test FAILED for " .. url)
    end
  end
  
  update_debug_network("⚠️  OFFLINE MODE - LIMITED FUNCTIONALITY")
  append_debug_log("⚠️  WARNING: No internet connection detected!")
  vlc.msg.warn("[VLSub Network] ALL TESTS FAILED - No internet connection")
  networkTestsFailed = true
  return false
end


function checkInitializationStatus()
  -- Don't check until initialization is complete
  if not initialization_complete then
    return
  end
  
  local allTestsPassed = true
  local hasCriticalFailure = criticalFailure
  local shouldStayOpen = false
  
  -- Check for critical failures that prevent basic functionality
  if not configurationPassed or not jsonModuleLoaded then
    allTestsPassed = false
    hasCriticalFailure = true
    shouldStayOpen = true
  end
  
  -- Handle network test results
  if networkTestsFailed then
    append_debug_log("⚠️  OFFLINE: Extension will have limited functionality")
    update_debug_status("⚠️  WARNING: No internet - limited functionality")
    shouldStayOpen = true  -- Keep debug window open for offline mode
  else
    update_debug_status("Network connection verified")
    append_debug_log("Network connection successful")
  end
  
  -- Update button labels based on current status
  update_debug_buttons()
  
  -- Only auto-close if we have both: working core functionality AND network
  if allTestsPassed and not hasCriticalFailure and not networkTestsFailed then
    vlc.msg.dbg("[VLSub] Full initialization successful - auto-closing debug window in 3 seconds")
    append_debug_log("All tests passed - auto-closing in 3 seconds...")
    
    -- Update button to show countdown
    if debug_messages and debug_messages.ok_button then
      for countdown = 3, 1, -1 do
        debug_messages.ok_button:set_text("✅ Auto-close (" .. countdown .. "s)")
        if debug_dlg then
          debug_dlg:update()
        end
        
        -- Wait 1 second
        local start_time = os.clock()
        while (os.clock() - start_time) < 1 do
          -- Brief delay loop
        end
      end
    end
    
    if debug_dlg then
      close_debug_window()
      show_appropriate_window()
      vlc.msg.dbg("[VLSub] Debug window auto-closed")
    end
  else
    -- Keep debug window open for user information
    if shouldStayOpen then
      if networkTestsFailed and allTestsPassed then
        vlc.msg.dbg("[VLSub] Core functionality OK but offline - keeping debug window open")
        append_debug_log("Click 'Continue Offline' to proceed with limited functionality")
        update_debug_status("Click 'Continue Offline' to proceed")
      else
        vlc.msg.dbg("[VLSub] Critical initialization failure - keeping debug window open")
        append_debug_log("Critical failures detected - click 'Continue Anyway' or 'Close VLSub'")
        update_debug_status("Critical errors - manual intervention needed")
      end
    end
  end
end



function Curl.new()
    local self = setmetatable({}, Curl)
    self.headers = {}
    self.verbose = false  -- Disable verbose by default for production
    self.timeout = nil
    self.retries = 0
    self.proxy = nil
    self.follow_redirects = true
    self.max_redirects = 10
    return self
end

function Curl:add_header(key, value)
    self.headers[#self.headers + 1] = '-H "' .. escape(key) .. ': ' .. escape(value) .. '"'
    return self
end

function Curl:clear_headers()
    self.headers = {}
    return self
end

function Curl:set_verbose(enabled)
    self.verbose = enabled
    return self
end

function Curl:set_timeout(seconds)
    self.timeout = tonumber(seconds)
    return self
end

function Curl:set_retries(count)
    self.retries = tonumber(count)
    return self
end

function Curl:set_proxy(proxy_url)
    self.proxy = proxy_url
    return self
end

function Curl:set_follow_redirects(enabled, max_redirects)
    self.follow_redirects = enabled
    if max_redirects then
        self.max_redirects = tonumber(max_redirects)
    end
    return self
end

function Curl:_build_command(method, url, data)
    local cmd = {
        'curl -s -i',
        '-X', method
    }

    if self.follow_redirects then
        table.insert(cmd, '-L')
        if self.max_redirects then
            table.insert(cmd, '--max-redirs ' .. self.max_redirects)
        end
    end

    for _, h in ipairs(self.headers) do
        table.insert(cmd, h)
    end

    if data then
        table.insert(cmd, '-d "' .. escape(data) .. '"')
    end

    if self.timeout then
        table.insert(cmd, '--max-time ' .. tonumber(self.timeout))
    end

    if self.proxy then
        table.insert(cmd, '--proxy "' .. escape(self.proxy) .. '"')
    end

    table.insert(cmd, '"' .. escape(url) .. '"')

    return table.concat(cmd, " ")
end


-- Enhanced execute command with better tracking
function Curl:_execute_command(command)
    local attempt = 0
    local result

    -- Fix for Windows: prevent visible command windows
    if openSub.conf.os == "win" then
        -- On Windows, use cmd /c with window hiding flags
        command = 'cmd /c "' .. command .. '" 2>nul'
    else
        -- On Unix/Linux/macOS, redirect stderr to avoid noise
        command = command .. ' 2>/dev/null'
    end

    while attempt <= self.retries do
        -- Log retry attempts if needed
        if attempt > 0 then
            vlc.msg.warn("[VLSub Retry] Attempt " .. (attempt + 1) .. "/" .. (self.retries + 1))
            if debug_log_rows and #debug_log_rows > 0 then
                append_debug_log("🔄 Retry " .. (attempt + 1) .. "/" .. (self.retries + 1))
            end
        end
        
        local handle = io.popen(command)
        local output = handle:read("*a")
        local success, _, exit_code = handle:close()
        result = output
        if success or exit_code == 0 then
            break
        end
        attempt = attempt + 1
    end

    -- Log if all retries failed
    if attempt > self.retries and (not result or result == "") then
        vlc.msg.err("[VLSub Error] All retry attempts failed for curl command")
        if debug_log_rows and #debug_log_rows > 0 then
            append_debug_log("❌ All retries failed")
        end
    end

    return result
end

-- Helper function to track specific API endpoints
function log_api_endpoint(endpoint_name, url, method, description)
    local log_message = "🔗 API Call: " .. endpoint_name .. " (" .. description .. ")"
    vlc.msg.warn("[VLSub API] " .. log_message)
    
    if debug_log_rows and #debug_log_rows > 0 then
        append_debug_log("🔗 " .. endpoint_name .. " API")
    end
end

-- Alternative enhanced version with better Windows handling
function Curl:_execute_command_enhanced(command)
    local attempt = 0
    local result

    while attempt <= self.retries do
        local final_command
        
        if openSub.conf.os == "win" then
            -- Multiple approaches for Windows to hide console windows
            
            -- Method 1: Use cmd /c with null redirection (most compatible)
            final_command = 'cmd /c "' .. command .. '" >nul 2>nul'
            
            -- Method 2: Try PowerShell with hidden window (if you want to use this instead)
            -- final_command = 'powershell -WindowStyle Hidden -ExecutionPolicy Bypass -Command "& {' .. command .. '}" 2>$null'
            
            -- Method 3: Use start with minimized window (another option)
            -- final_command = 'start /min /wait cmd /c "' .. command .. '" >nul 2>nul'
            
        else
            -- Unix/Linux/macOS: just redirect stderr
            final_command = command .. ' 2>/dev/null'
        end
        
        local handle = io.popen(final_command)
        if handle then
            local output = handle:read("*a")
            local success, _, exit_code = handle:close()
            result = output
            if success or exit_code == 0 then
                break
            end
        end
        attempt = attempt + 1
    end

    return result
end


function Curl:_parse_response(raw)
    if self.verbose then
        print("[curl_wrapper] Raw response length:", #raw)
        print("[curl_wrapper] Raw response:\n" .. tostring(raw))
    end
    
    local last_http_pos = 1
    local pos = 1
    while true do
        local found_pos = raw:find("HTTP/%d", pos)
        if not found_pos then
            break
        end
        last_http_pos = found_pos
        pos = found_pos + 1
    end
    
    local final_response = raw:sub(last_http_pos)
    
    if self.verbose then
        print("[curl_wrapper] Final response starting at position:", last_http_pos)
        print("[curl_wrapper] Final response length:", #final_response)
    end
    
    local lines = {}
    for line in (final_response .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        table.insert(lines, line)
    end
    
    if #lines == 0 then
        if self.verbose then
            print("[curl_wrapper] No lines found in final response!")
        end
        return { status = nil, headers = {}, body = raw }
    end
    
    local status_line = lines[1]
    local status_code = tonumber(status_line:match("HTTP/%d+%.?%d* (%d+)"))
    
    if self.verbose then
        print("[curl_wrapper] Final status line:", status_line)
        print("[curl_wrapper] Status code:", status_code)
    end
    
    local body_start_index = nil
    for i = 2, #lines do
        if lines[i] == "" then
            body_start_index = i + 1
            break
        end
    end
    
    local headers = {}
    local header_end = body_start_index and (body_start_index - 2) or #lines
    
    for i = 2, header_end do
        local line = lines[i]
        if line and line ~= "" then
            local k, v = line:match("^([%w%-]+):%s*(.*)$")
            if k and v then
                headers[k:lower()] = v
            end
        end
    end
    
    local body = ""
    if body_start_index and body_start_index <= #lines then
        local body_lines = {}
        for i = body_start_index, #lines do
            if lines[i] then
                table.insert(body_lines, lines[i])
            end
        end
        body = table.concat(body_lines, "\n")
        body = body:gsub("%s*$", "")
    end
    
    if self.verbose then
        print("[curl_wrapper] Parsed headers count:", 0)
        for k, v in pairs(headers) do
            print("[curl_wrapper] Header", k .. ":", v)
        end
        print("[curl_wrapper] Body length:", #body)
        if #body < 1000 then
            print("[curl_wrapper] Body content:\n" .. body)
        else
            print("[curl_wrapper] Body content (first 500 chars):\n" .. body:sub(1, 500) .. "...")
            print("[curl_wrapper] Body content (last 500 chars):\n..." .. body:sub(-500))
        end
    end
    
    return {
        status = status_code,
        headers = headers,
        body = body
    }
end

-- Enhanced Curl wrapper with request tracking for debugging
function Curl:request(method, url, data)
    -- TRACK ALL INTERNET REQUESTS
    local start_time = os.clock()
    local request_id = math.random(1000, 9999)
    
    -- Log request start with warning level for visibility
    local log_message = "🌐 HTTP " .. method .. " → " .. url
    if data and #data > 0 then
        log_message = log_message .. " (data: " .. #data .. " bytes)"
    end
    log_message = log_message .. " [ID:" .. request_id .. "]"
    
    vlc.msg.warn("[VLSub Request] " .. log_message)
    
    -- Also add to debug log if available
    if debug_log_rows and #debug_log_rows > 0 then
        append_debug_log("🌐 " .. method .. " " .. url .. " [" .. request_id .. "]")
    end
    
    -- Build and execute the command
    local cmd = self:_build_command(method, url, data)
    if self.verbose then
        vlc.msg.warn("[VLSub Request] Executing: " .. cmd)
    end
    
    local raw = self:_execute_command(cmd)
    local response = self:_parse_response(raw)
    
    -- Calculate request duration
    local end_time = os.clock()
    local duration_ms = math.floor((end_time - start_time) * 1000)
    
    -- Log response with status and timing
    local response_log = "📡 HTTP " .. method .. " ← " .. url
    if response.status then
        response_log = response_log .. " (status: " .. response.status .. ")"
    else
        response_log = response_log .. " (status: FAILED)"
    end
    response_log = response_log .. " in " .. duration_ms .. "ms [ID:" .. request_id .. "]"
    
    if response.body and #response.body > 0 then
        response_log = response_log .. " (response: " .. #response.body .. " bytes)"
    end
    
    vlc.msg.warn("[VLSub Response] " .. response_log)
    
    -- Add response to debug log with status indicator
    if debug_log_rows and #debug_log_rows > 0 then
        local status_icon = "✅"
        if not response.status or response.status >= 400 then
            status_icon = "❌"
        elseif response.status >= 300 then
            status_icon = "⚠️"
        end
        append_debug_log(status_icon .. " " .. (response.status or "FAIL") .. " " .. duration_ms .. "ms [" .. request_id .. "]")
    end
    
    -- Log any errors or unusual responses
    if not response.status then
        vlc.msg.err("[VLSub Error] No response status for " .. url .. " [ID:" .. request_id .. "]")
    elseif response.status >= 400 then
        vlc.msg.err("[VLSub Error] HTTP " .. response.status .. " for " .. url .. " [ID:" .. request_id .. "]")
        if response.body and #response.body < 500 then
            vlc.msg.err("[VLSub Error] Error body: " .. response.body)
        end
    elseif response.status >= 300 then
        vlc.msg.warn("[VLSub Redirect] HTTP " .. response.status .. " for " .. url .. " [ID:" .. request_id .. "]")
    end
    
    return response
end


function Curl:get(url)
    return self:request("GET", url)
end

function Curl:post(url, data)
    return self:request("POST", url, data)
end

function Curl:put(url, data)
    return self:request("PUT", url, data)
end

function Curl:delete(url)
    return self:request("DELETE", url)
end

-- Improved timeout handling for curl wrapper
function Curl:set_aggressive_timeouts()
  -- Set conservative timeouts for poor connections
  self.timeout = 15  -- 15 seconds total timeout
  self.retries = 2   -- Only 2 retries
  self:add_header("Connection", "close")  -- Don't keep connections alive
  return self
end

-- End of embedded curl wrapper module

