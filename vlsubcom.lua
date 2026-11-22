--[[
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
- "Download failed": Check quota limits
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
local app_version = "2.0.0";
local app_useragent = app_name.." v"..app_version;

local config = {
  api_key = "d3Sba6j6VYnty3ir5T8GXYoAuiLSBf0S",
  cache_languages_duration_seconds = 30 * 24 * 60 * 60, -- 30 days in seconds
  token_cache_duration_seconds = 24 * 60 * 60, -- 24 hours in seconds
  cache_guessit_duration_seconds = 7 * 24 * 60 * 60 -- 7 days in seconds (filenames don't change often)
}

-- Where the API is. Developers can point the extension at a test server
-- (tools/dev.sh run --dev-api: a local proxy in front of the https-only
-- development API) with VLSUB_API_URL and VLSUB_API_KEY. Read when used,
-- never at load time; without them nothing changes.
local API_DEFAULT = "http://api.opensubtitles.com/api/v1"

local function api_url(path)
  local base = os.getenv("VLSUB_API_URL")
  if not base or base == "" then
    base = API_DEFAULT
  end
  return (string.gsub(base, "/+$", "")) .. (path or "")
end

-- "http://host[:port]", for the paths the API hands out in redirects
local function api_root()
  return string.match(api_url(""), "^(https?://[^/]+)")
end

local function api_key()
  local key = os.getenv("VLSUB_API_KEY")
  if key and key ~= "" then
    return key
  end
  return config.api_key
end

-- Auto-update configuration
local update_config = {
  check_url = "https://api.github.com/repos/opensubtitles/vlsub-opensubtitles-com/releases/latest",
  current_version = app_version, -- Uses existing app_version variable
  check_interval_seconds = 24 * 60 * 60, -- 24 hours
  last_check_file = "last_update_check.json"
}

-- Supported API sorting fields for /subtitles endpoint
-- { value sent to the API, key of the text shown }
local subtitle_sort_by_options = {
  {"language", "ui_sort_language"},
  {"download_count", "ui_sort_download_count"},
  {"new_download_count", "ui_sort_new_download_count"},
  {"hearing_impaired", "ui_sort_hearing_impaired"},
  {"hd", "ui_sort_hd"},
  {"fps", "ui_sort_fps"},
  {"votes", "ui_sort_votes"},
  {"points", "ui_sort_points"},
  {"ratings", "ui_sort_ratings"},
  {"from_trusted", "ui_sort_from_trusted"},
  {"foreign_parts_only", "ui_sort_foreign_parts_only"},
  {"ai_translated", "ui_sort_ai_translated"},
  {"machine_translated", "ui_sort_machine_translated"},
  {"upload_date", "ui_sort_upload_date"},
  {"release", "ui_sort_release"},
  {"comments", "ui_sort_comments"}
}

local subtitle_sort_direction_options = {
  {"desc", "ui_sort_desc"},
  {"asc", "ui_sort_asc"}
}

-- First, update the options structure to support 3 languages
-- Settings. This table is what gets saved to vlsub_conf.json (plus
-- os_username / os_password once entered), so only settings belong here.
local options = {
  language = nil,
  language2 = nil,  -- Second language
  language3 = nil,  -- Third language
  sortBy = nil,     -- API order_by
  sortDirection = "desc", -- API order_direction
  downloadBehaviour = 'save',
  langExt = true,
  removeTag = false,
  -- false: no AI subtitles at all - neither the paid translations made on
  -- demand nor AI translations somebody uploaded. (A config file without
  -- this key, from an older version, means true.)
  aiTranslations = true,
  -- More search filters (window "Search filters"). The defaults are the
  -- API's own, so nothing changes until the user sets one.
  machineTranslations = false,      -- true: also list machine translations
  hearingImpaired = "include",      -- include / exclude / only (SDH, CC)
  foreignPartsOnly = "include",     -- include / exclude / only (forced)
  trustedOnly = false,              -- true: trusted uploaders only
  progressBarSize = 80
}

-- Interface strings (English)
local strings = {
  int_all = 'All',
  int_descr = 'Download subtitles from OpenSubtitles.com',
  int_research = 'Search',
  int_config = 'Config',
  int_configuration = 'Configuration',
  int_help = 'Help',
  int_search_hash = 'Search by hash',
  int_search_name = 'Search',
  int_title = 'Title',
  int_season = 'TV Season',
  int_episode = 'TV Episode',
  int_imdb = 'IMDB ID',
  int_close = 'Close',
  int_save = 'Save',
  int_bool_true = 'Yes',
  int_bool_false = 'No',
  int_default_lang = '1. Subtitles Language',           -- Updated
  int_second_lang = '2. Subtitles Language',            -- Updated
  int_third_lang = '3. Subtitles Language',             -- Updated
  int_dowload_behav = 'What to do with subtitles',
  int_dowload_save = 'Load and save',
  int_dowload_manual =  'Manual download',
  int_display_code = 'Save language code in file name',
  int_remove_tag = 'Remove tags',
  int_vlsub_work_dir = 'VLSub working directory',
  int_os_username = 'OpenSubtitles.com Username',
  int_os_password = 'OpenSubtitles.com Password',
  int_no_support_mess = [[
    <strong>VLSub is not working with Vlc 2.1.x on
    any platform</strong>
    because the lua "net" module needed to interact
    with opensubtitles has been
    removed in this release for the extensions.
    <br>
    <strong>Works with Vlc 2.2 on mac and linux.</strong>
    <br>
    <strong>On windows you have to install an older version
    of Vlc (2.0.8 for example)</strong>
    to use Vlsub:
    <br>
    <a target="_blank" rel="nofollow"
    href="http://download.videolan.org/pub/videolan/vlc/2.0.8/">
    http://download.videolan.org/pub/videolan/vlc/2.0.8/</a><br>
  ]],

  action_login = 'Logging in',
  action_search = 'Searching subtitles',
  action_hash = 'Calculating movie hash',

  mess_success = 'Success',
  mess_error = 'Error',
  mess_no_response = 'Server not responding',
  mess_unauthorized = 'Request unauthorized',
  mess_no_input = 'Please use this method during playing',
  mess_not_found = 'File not found',
  mess_no_selection = 'No subtitles selected',
  mess_complete = 'Search complete',
  mess_no_res = 'No result',
  mess_downloading = 'Downloading subtitle',
  mess_dowload_link = 'Download link',
  mess_err_conf_access ='Can\'t find a suitable path to save'..
    'config, please set it manually',
  mess_err_wrong_path ='the path contains illegal character, '..
    'please correct it',

  -- Messages that used to be written inline in the code
  ui_could_not_detect_user_locale = "Could not detect user locale",
  ui_saving_auto_detected_settings = "Saving auto-detected settings...",
  ui_auto_detected_settings_saved = "Auto-detected settings saved",
  ui_failed_to_save_auto_detected_settings = "Failed to save auto-detected settings",
  ui_initializing_vlsub_first_run = "Initializing VLSub (First Run)...",
  ui_vlsub_first_time_setup_started = "VLSub first-time setup started",
  ui_loading_json_module = "Loading JSON module...",
  ui_error_failed_to_load_json_module = "ERROR: Failed to load JSON module",
  ui_json_module_loaded_successfully = "JSON module loaded successfully",
  ui_checking_dkjson_compatibility = "Checking dkjson compatibility...",
  ui_error_incompatible_dkjson_version = "ERROR: Incompatible dkjson version",
  ui_critical_dkjson_version_too_old_cannot_parse = "CRITICAL: dkjson version too old - cannot parse floats",
  ui_checking_configuration = "Checking configuration...",
  ui_error_unsupported_vlc_version = "ERROR: Unsupported VLC version",
  ui_critical_vlc_version_not_supported = "CRITICAL: VLC version not supported",
  ui_configuration_check_passed = "Configuration check passed",
  ui_loading_subtitle_languages = "Loading subtitle languages...",
  ui_using_offline_language_list = "Using offline language list...",
  ui_using_built_in_language_list_offline_mode = "Using built-in language list (offline mode)",
  ui_initializing_languages_from_api = "Initializing languages from API...",
  ui_language_list_loaded_from_api = "Language list loaded from API",
  ui_detecting_user_locale = "Detecting user locale...",
  ui_first_run_detected = "First run detected",
  ui_starting_locale_detection = "Starting locale detection...",
  ui_temporarily_cleared_user_preference_for_clean_de = "Temporarily cleared user preference for clean detection",
  ui_getting_file_information = "Getting file information...",
  ui_file_info_loaded_for_current_media = "File info loaded for current media",
  ui_no_media_loaded = "No media loaded",
  ui_checking_authentication = "Checking authentication...",
  ui_valid_authentication_found_credentials_available = "Valid authentication found - credentials available",
  ui_no_valid_authentication_missing_credentials = "No valid authentication - missing credentials",
  ui_initialization_complete = "Initialization complete!",
  ui_initialization_complete_checking_for_auto_close = "Initialization complete - checking for auto-close...",
  ui_ready_to_show_main_window_authenticated = "Ready to show main window (authenticated)",
  ui_ready_to_show_configuration_window_no_auth = "Ready to show configuration window (no auth)",
  ui_initializing_auto_update_system = "Initializing auto-update system...",
  ui_setting_up_automatic_update_checking = "Setting up automatic update checking...",
  ui_installation_instructions = "<b>Installation Instructions:</b>",
  ui_open_powershell_as_administrator_and_run = "Open PowerShell as Administrator and run:",
  ui_open_terminal_and_run = "Open Terminal and run:",
  ui_then_restart_vlc_and_access_via_view = "Then restart VLC and access via View → VLSub OpenSubtitles.com",
  ui_skip_version = "⏭️ Skip Version",
  ui_later = "⏰ Later",
  ui_close = "❌ Close",
  ui_you_re_running_the_latest_version = "You're running the latest version (%s)",
  ui_year = "Year:",
  ui_sort_by = "Sort by:",
  ui_search_results = "Search Results:",
  ui_download = "📥 Download",
  ui_link = "🔗 Link",
  ui_config = "⚙️ Config",
  ui_help = "❓ Help",
  ui_check_updates = "🔄 Check Updates",
  ui_search_methods = "SEARCH METHODS:",
  ui_help_search_hash = "By file: finds the subtitles made for exactly this video file",
  ui_help_search_name = "By name: uses the title, year and episode from the file name",
  ui_help_search_fallback = "If the first finds nothing, the second is tried automatically",
  ui_help_languages_title = "LANGUAGES:",
  ui_results_grouped_by_selected_languages_in_priorit = "Results grouped by selected languages in priority order",
  ui_choose_up_to_3_preferred_subtitle_languages = "Choose up to 3 preferred subtitle languages",
  ui_account_quotas = "ACCOUNT & QUOTAS:",
  ui_free_opensubtitles_com_account_required_for_down = "<a href='https://www.opensubtitles.com'>Free OpenSubtitles.com account required for downloads</a>",
  ui_support_opensubtitles_thank_you_very_much = "<a href='https://www.opensubtitles.com/en/support_us/'>Support OpenSubtitles</a> - thank you very much",
  ui_github_opensubtitles_vlsub_opensubtitles_com_sou = "<a href='https://github.com/opensubtitles/vlsub-opensubtitles-com'>GitHub: opensubtitles/vlsub-opensubtitles-com</a> - source, issues, releases",
  ui_continue = "⏳ Continue",
  ui_auto_close_2s = "✅ Auto-close (2s)",
  ui_continue_offline = "🌐 Continue Offline",
  ui_continue_anyway = "⚠️ Continue Anyway",
  ui_close_vlsub = "❌ Close VLSub",
  ui_vlsub_is_starting_up = "VLSub is starting up...",
  ui_progress = "Progress:",
  ui_starting = "Starting...",
  ui_status = "Status:",
  ui_initializing_components = "Initializing components",
  ui_network = "Network:",
  ui_checking_connectivity = "Checking connectivity...",
  ui_debug_log = "Debug Log:",
  ui_vlsub_initialization_starting = "VLSub initialization starting...",
  ui_no_subtitles_available_please_search_first = "No subtitles available. Please search first.",
  ui_please_select_a_subtitle_from_the_list = "Please select a subtitle from the list first.",
  ui_no_url_available_for_this_subtitle = "No URL available for this subtitle.",
  ui_vlsub_cannot_start_due_to_incompatible_dkjson = "<b>VLSub cannot start due to incompatible dkjson version</b>",
  ui_your_vlc_installation_includes_an_old_version = "Your VLC installation includes an old version of dkjson (JSON parser)",
  ui_that_cannot_parse_floating_point_numbers_properl = "that cannot parse floating point numbers properly.",
  ui_unknown = "unknown",
  ui_required_version_2_4_or_newer = "<b>Required version:</b> 2.4 or newer",
  ui_solution_windows_macos = "<b>Solution (Windows/macOS):</b>",
  ui_upgrade_vlc_to_version_3_0_22 = "Upgrade VLC to version 3.0.22 or newer.",
  ui_solution_ubuntu_debian_linux = "<b>Solution (Ubuntu/Debian Linux):</b>",
  ui_ubuntu_ships_vlc_with_the_broken_dkjson = "Ubuntu ships VLC with the broken dkjson — upgrading VLC does not help.",
  ui_replace_the_bundled_dkjson_luac_with_the = "Replace the bundled <tt>dkjson.luac</tt> with the latest version:",
  ui_1_download_dkjson_lua_from_dkolf_de = "1. Download <a href='https://dkolf.de/dkjson-lua/'>dkjson.lua from dkolf.de</a>",
  ui_2_locate_vlc_s_modules_dir_e = "2. Locate VLC's modules dir (e.g. <tt>/usr/lib/x86_64-linux-gnu/vlc/lua/modules/</tt>)",
  ui_3_back_up_dkjson_luac_and_replace = "3. Back up <tt>dkjson.luac</tt> and replace it with the downloaded file (renamed to <tt>dkjson.luac</tt>)",
  ui_4_restart_vlc_requires_sudo = "4. Restart VLC.  Requires <tt>sudo</tt>.",
  ui_more_info_issue_23_middot_issue_11 = "More info: <a href='https://github.com/opensubtitles/vlsub-opensubtitles-com/issues/23'>Issue #23</a> &middot; <a href='https://github.com/opensubtitles/vlsub-opensubtitles-com/issues/11#issuecomment-3391889129'>Issue #11</a>",
  ui_close_2 = "Close",
  ui_configuration_saved_please_enter_opensubtitles_c = "Configuration saved. Please enter OpenSubtitles.com credentials for full functionality.",
  ui_testing_login_credentials = "Testing login credentials...",
  ui_configuration_saved_you_can_now_close_this = "<br>Configuration saved. You can now close this window.",
  ui_configuration_saved_and_login_successful_you_can = "Configuration saved and login successful! You can now close this window.",
  ui_note_other_configuration_settings_were_saved_suc = "<br><small>Note: Other configuration settings were saved successfully.</small>",
  ui_login_failed_please_check_your_credentials_other = "Login failed - please check your credentials.<br><small>Other configuration settings were saved successfully.</small>",
  ui_hash_search_only_works_with_local_video = "Hash search only works with local video files",
  ui_cannot_open_archive_stream_for_hashing = "Cannot open archive stream for hashing",
  ui_cannot_read_archive_data_for_hashing = "Cannot read archive data for hashing",
  ui_file_not_accessible_for_hashing = "File not accessible for hashing",
  ui_cannot_open_local_file_for_hashing = "Cannot open local file for hashing",
  ui_cannot_read_file_data_for_hashing = "Cannot read file data for hashing",
  ui_cannot_seek_in_file_for_hashing = "Cannot seek in file for hashing",
  ui_cannot_read_end_data_for_hashing = "Cannot read end data for hashing",
  ui_insufficient_data_for_hash_calculation = "Insufficient data for hash calculation",
  ui_hash_search_requires_local_files_please_enter = "Hash search requires local files. Please enter a title for name search.",
  ui_hash_calculation_failed_and_no_title_available = "Hash calculation failed and no title available for name search",
  ui_searching_by_imdb_id = "Searching by IMDB ID...",
  ui_invalid_imdb_id_format = "Invalid IMDB ID format",
  ui_login_failed_network_timeout_or_no_internet = "Login failed - network timeout or no internet connection",
  ui_login_failed_network_error = "Login failed - network error",
  ui_login_failed_empty_response = "Login failed - empty response",
  ui_login_failed_invalid_response_format = "Login failed - invalid response format",
  ui_login_failed_no_authentication_token_received = "Login failed - no authentication token received",
  ui_no_subtitles_available_for_download_please_searc = "No subtitles available for download. Please search first.",
  ui_failed_to_download_from_provided_link = "Failed to download from provided link",
  ui_empty_subtitle_content_downloaded = "Empty subtitle content downloaded",
  ui_no_file_id_available_for_download = "No file ID available for download",
  ui_authentication_failed_please_check_your_opensubt = "Authentication failed - please check your OpenSubtitles.com credentials",
  ui_authentication_required_for_download = "Authentication required for download",
  ui_no_response_from_download_server = "No response from download server",
  ui_authentication_failed_401_please_check_your_cred = "Authentication failed (401) - please check your credentials",
  ui_empty_response_from_download_server = "Empty response from download server",
  ui_verifying_credentials = "Verifying credentials...",
  ui_username_and_password_are_required_for_authentic = "Username and password are required for authentication",
  ui_fetching_account_information = "Fetching account information...",
  ui_no_authentication_token_available = "No authentication token available",
  ui_no_response_from_user_info_api = "No response from user info API",
  ui_access_forbidden_403_insufficient_permissions = "Access forbidden (403) - insufficient permissions",
  ui_empty_response_from_user_info_api = "Empty response from user info API",
  ui_failed_to_parse_user_info_response = "Failed to parse user info response",
  ui_invalid_user_info_response_format = "Invalid user info response format",
  ui_testing_network_connectivity = "Testing network connectivity...",
  ui_offline_mode_limited_functionality = "⚠️  OFFLINE MODE - LIMITED FUNCTIONALITY",
  ui_warning_no_internet_connection_detected = "⚠️  WARNING: No internet connection detected!",
  ui_extension_uses_vlc_s_built_in_networking = "Extension uses VLC's built-in networking (no external tools required)",
  ui_offline_extension_will_have_limited_functionalit = "⚠️  OFFLINE: Extension will have limited functionality",
  ui_warning_no_internet_limited_functionality = "⚠️  WARNING: No internet - limited functionality",
  ui_network_connection_verified = "Network connection verified",
  ui_network_connection_successful = "Network connection successful",
  ui_all_tests_passed_auto_closing_in_3 = "All tests passed - auto-closing in 3 seconds...",
  ui_auto_close = "✅ Auto-close (%ss)",
  ui_click_continue_offline_to_proceed_with_limited = "Click 'Continue Offline' to proceed with limited functionality",
  ui_click_continue_offline_to_proceed = "Click 'Continue Offline' to proceed",
  ui_critical_failures_detected_click_continue_anyway = "Critical failures detected - click 'Continue Anyway' or 'Close VLSub'",
  ui_critical_errors_manual_intervention_needed = "Critical errors - manual intervention needed",
  ui_network_error_connection_failed = "Network error: Connection failed",
  ui_api_error_url_parameters_not_sorted_correctly = "API Error: URL parameters not sorted correctly",
  ui_access_forbidden_403 = "Access forbidden (403).",
  ui_quota_reset_in = "Quota reset in: %s",
  ui_empty_subtitle_content_received = "Empty subtitle content received",
  ui_cannot_determine_save_location_for_subtitle_file = "Cannot determine save location for subtitle file",
  ui_cannot_write_subtitle_file_to_any_location = "Cannot write subtitle file to any location",
  ui_subtitles_saved_to_downloads = "Subtitles saved to Downloads",
  ui_subtitle_link = "<b>Subtitle Link:</b>",
  ui_view_subtitle = "View Subtitle",
  ui_checking_login_status = "Checking login status",
  ui_unknown_2 = "Unknown",
  ui_rate_limit_too_many_requests_please_wait = "Rate limit: Too many requests. Please wait.",
  ui_access_forbidden_check_your_api_permissions = "Access forbidden. Check your API permissions.",
  ui_resource_not_found = "Resource not found.",
  ui_server_error_please_try_again_later = "Server error. Please try again later.",
  ui_service_temporarily_unavailable = "Service temporarily unavailable.",
  ui_subtitle_not_found_404_file_may_have = "Subtitle not found (404) - file may have been removed or ID is invalid",
  ui_too_many_requests_429_please_wait_and = "Too many requests (429) - please wait and try again",
  ui_server_error_500_please_try_again_later = "Server error (500) - please try again later",
  ui_service_unavailable_503_server_overloaded = "Service unavailable (503) - server overloaded",
  ui_locale_detected_from = "Locale detected: %s from %s",
  ui_found_suggested_languages = "Found %s suggested languages: %s",
  ui_set_primary_language = "Set primary language: %s",
  ui_set_secondary_language = "Set secondary language: %s",
  ui_set_third_language = "Set third language: %s",
  ui_if_this_doesn_t_work_download = "If this doesn't work, download <a href='%s'>vlsubcom.lua</a> and save to:",
  ui_quota_downloads = "Quota: %s/%s downloads",
  ui_account_summary = "%s (%s), %s/%s downloads, reset in: %s",
  ui_too_many_requests_429 = "Too many requests (429) - the API allows only a few requests per second. Please wait a moment and try again.",
  ui_authentication_failed_401_check_configuration = "Authentication failed (401) - please check your OpenSubtitles.com username and password in the configuration.",
  ui_server_error_try_again_later = "OpenSubtitles.com server error (%s) - please try again later.",
  ui_network_is_redirecting = "network is redirecting HTTP requests (status %s) - a proxy, VPN, captive portal or content filter is intercepting port 80. Disable it or connect through another network.",
  ui_dkjson_check_passed = "dkjson compatibility check passed (version: %s)",
  ui_update_available = "<a href='https://github.com/opensubtitles/vlsub-opensubtitles-com'><b>VLSub Update Available</b></a> (%s => %s)",
  ui_whats_new_in = "<b>What's New in v%s:</b>",
  ui_failed_to_download_subtitle_http = "Failed to download subtitle content (HTTP %s)",
  ui_testing_connection_n_of = "Testing connection %s/%s...",
  ui_connection_ok_ms = "Connection OK (responded in %sms)",
  ui_network_test_passed_ms = "Network test passed: %s (%sms)",
  ui_network_test_failed_ms = "Network test failed: %s (%sms)",
  ui_loading = "Loading",
  ui_interface_language = "Interface language",
  ui_language_auto = "Automatic (system language)",
  ui_translation_not_available = "The translation for \"%s\" could not be downloaded. The interface stays as it is.",
  ui_translation_unreviewed = "(not reviewed)",

  -- Whole sentences; %s marks where a value goes
  ui_api_returned_error = "API returned error: %s",
  ui_cannot_open_file_for_writing = "Cannot open file for writing: %s",
  ui_cannot_write_to_any_available_location = "Cannot write to any available location: %s",
  ui_critical_json_module_load_failed = "CRITICAL: JSON module load failed: %s",
  ui_current_version = "<b>Current version:</b> %s",
  ui_language_not_available = "Language not available: %s",
  ui_login_failed = "Login failed - %s",
  ui_login_failed_2 = "Login failed: %s",
  ui_login_failed_with_status = "Login failed with status: %s",
  ui_testing = "Testing: %s",
  ui_user_info_request_failed_with_http_status = "User info request failed with HTTP status: %s",
  ui_status_2 = "Status %s",
  ui_error_http = "Error: HTTP %s",
  ui_search_none = "<b>Search complete:</b> No result",
  ui_search_none_hash = "<b>Search complete:</b> No result for moviehash %s",
  ui_search_none_fallback = "<b>Search complete:</b> No result (searched by hash + name)",
  ui_search_none_fallback_hash = "<b>Search complete:</b> No result (searched by hash + name) for moviehash %s",
  ui_search_none_fallback_title = "<b>Search complete:</b> No result (searched by hash + name) and title '%s'",
  ui_search_none_fallback_hash_title = "<b>Search complete:</b> No result (searched by hash + name) for moviehash %s and title '%s'",
  ui_search_found = "<b>Search complete:</b> %s  result(s)",
  ui_search_found_hash = "<b>Search complete:</b> %s  result(s) for moviehash %s",
  ui_search_found_imdb = "<b>Search complete:</b> %s  result(s) for IMDB ID %s",
  ui_search_found_fallback = "<b>Search complete:</b> %s  result(s) (found via name search)",
  ui_search_found_fallback_title = "<b>Search complete:</b> %s  result(s) (found via name search) for title '%s'",
  ui_search_found_title = "<b>Search complete:</b> %s  result(s) for title '%s'",
  ui_search_complete_count = "Search complete: %s result(s)",
  ui_loaded_with_video = "Subtitles loaded (saved with video file)",
  ui_loaded_in_downloads = "Subtitles loaded (saved to Downloads folder)",
  ui_loaded_in_vlsub = "Subtitles loaded (saved to VLSub directory)",
  ui_saved_with_video = "Subtitles saved (saved with video file)",
  ui_saved_in_vlsub = "Subtitles saved (saved to VLSub directory)",
  ui_quota_downloads_reset = "Quota: %s/%s downloads, reset in: %s",
  ui_message_with_quota = "%s. %s.",

  -- Main window: sorting drop-downs and the idle message
  ui_sort_language = "Language",
  ui_sort_download_count = "Downloads",
  ui_sort_new_download_count = "New downloads",
  ui_sort_hearing_impaired = "Hearing impaired",
  ui_sort_hd = "HD",
  ui_sort_fps = "FPS",
  ui_sort_votes = "Votes",
  ui_sort_points = "Points",
  ui_sort_ratings = "Ratings",
  ui_sort_from_trusted = "Trusted",
  ui_sort_foreign_parts_only = "Foreign parts only",
  ui_sort_ai_translated = "AI translated",
  ui_sort_machine_translated = "Machine translated",
  ui_sort_upload_date = "Upload date",
  ui_sort_release = "Release",
  ui_sort_comments = "Comments",
  ui_sort_desc = "Desc",
  ui_sort_asc = "Asc",
  ui_sort_default = "Default",
  ui_ready_for_search = "Ready for search",
  ui_none = "None",

  -- AI on-demand translation
  ui_help_ai_title = "AI TRANSLATION:",
  ui_help_ai_what = "No subtitle in your language? An AI translation can be made on demand (marked with a robot)",
  ui_help_ai_credits = "It is paid with the AI credits of your account; without enough credits you get a short preview",
  ui_ai_on_demand = "AI translation on demand (uses AI credits)",
  ui_ai_on_demand_from = "AI translation from %s (uses AI credits)",
  ui_ai_creating_translation = "Creating the AI translation - this can take a minute, VLC will not respond meanwhile...",
  ui_ai_still_translating = "The AI translation is being made: %s s (a whole film takes about 20 s; this window does not respond meanwhile)",
  ui_ai_translations = "AI translations",
  ui_filters = "Search filters",
  ui_filters_open = "🔧 Set filters",
  ui_filter_machine = "Machine translations",
  ui_filter_hearing_impaired = "For hearing impaired (SDH / CC)",
  ui_filter_foreign_parts = "Foreign parts only (forced)",
  ui_filter_trusted = "Trusted uploaders only",
  ui_filter_include = "Include",
  ui_filter_exclude = "Exclude",
  ui_filter_only = "Only these",
  ui_filters_saved = "Filters saved. They apply from the next search.",
  ui_filters_active = "Search filters are set - some subtitles may be hidden (Config, Search filters)",
  ui_back = "↩ Back",

  -- Upload
  ui_upload = "⬆ Upload",
  ui_upload_title = "Upload subtitles",
  ui_upload_file = "Subtitle file",
  ui_upload_other_path = "Or full path of the file",
  ui_upload_language = "Language",
  ui_upload_film = "Film",
  ui_upload_imdb = "IMDb id, link or title",
  ui_upload_find = "🔍 Find",
  ui_upload_auto = "Automatic",
  ui_upload_translation = "Translated",
  ui_upload_by_person = "By a person",
  ui_upload_by_machine = "By machine translation",
  ui_upload_by_ai = "By AI",
  ui_upload_release = "Release name",
  ui_upload_comment = "Comment",
  ui_upload_check = "✔ Check",
  ui_upload_no_files = "(no subtitle file next to the video)",
  ui_upload_login_first = "Log in to upload: enter username and password in Config, then Save.",
  ui_download_login_first = "Log in to download: enter username and password in Config, then Save.",
  ui_upload_choose_file = "Choose a subtitle file, or enter its full path.",
  ui_upload_cannot_read = "The file cannot be read: %s",
  ui_upload_too_small = "The file is too small to be a subtitle (at least 100 bytes).",
  ui_upload_too_large = "The file is too large to upload from VLC (%s kB; at most %s kB).",
  ui_upload_film_year = "%s (%s)",
  ui_upload_film_unknown = "Not known yet - enter its IMDb id, link or title and press Find.",
  ui_upload_film_not_on_imdb = "No film with that id on IMDb or TMDb.",
  ui_upload_film_needed = "Which film is it? Enter its IMDb id, link or title and press Find.",
  ui_upload_language_needed = "Choose the language of the subtitles.",
  ui_upload_ok_to_upload = "Ready: this subtitle can be uploaded (%s uploads left today).",
  ui_upload_already = "This subtitle is already on OpenSubtitles - nothing to upload.",
  ui_upload_already_at = "This subtitle is already on OpenSubtitles: %s - nothing to upload.",
  ui_upload_would_be_rejected = "The upload would be refused: %s",
  ui_upload_would_be_reviewed = "Ready - a moderator will check it before it appears.",
  ui_upload_done = "Uploaded: %s - thank you!",
  ui_upload_done_review = "Uploaded: %s - it appears once a moderator has checked it. Thank you!",
  ui_upload_failed = "Upload failed: %s",
  ui_upload_working = "Uploading...",
  ui_upload_checking = "Checking...",
  ui_ai_show_credits = "🤖 AI credits: balance / buy",
  ui_ai_credits_balance = "AI credits: %s",
  ui_ai_credits_login_first = "Log in to see your AI credits: enter username and password, then Save.",
  ui_ai_credits_unavailable = "The AI credit balance could not be read. Please try again later.",
  ui_ai_buy_credits = "Buy AI credits:",
  ui_ai_preview_only = "This is only a preview: your account does not have enough AI credits for the full translation (you have %s).",
  ui_ai_creating_translation_credits = "Creating the AI translation (AI credits: %s) - this can take a minute, VLC will not respond meanwhile...",
  ui_ai_credits_left = "AI credits left: %s",
  ui_ai_no_answer = "The AI translation did not arrive in time. It may still be in the making: try again in a minute."
}

-- A message with values filled in: tr(key, a, b) uses the string stored
-- under `key` as a string.format pattern. Whole sentences with %s placeholders, rather than
-- pieces glued together, let a translation choose its own word order.
local function tr(key, ...)
  return string.format(strings[key], ...)
end

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
    { language_code = "eu", language_name = "Basque" },
    { language_code = "be", language_name = "Belarusian" },
    { language_code = "bn", language_name = "Bengali" },
    { language_code = "bs", language_name = "Bosnian" },
    { language_code = "br", language_name = "Breton" },
    { language_code = "bg", language_name = "Bulgarian" },
    { language_code = "my", language_name = "Burmese" },
    { language_code = "ca", language_name = "Catalan" },
    { language_code = "ze", language_name = "Chinese bilingual" },
    { language_code = "zh-ca", language_name = "Chinese (Cantonese)" },
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
    { language_code = "fi", language_name = "Finnish" },
    { language_code = "fr", language_name = "French" },
    { language_code = "gd", language_name = "Gaelic" },
    { language_code = "gl", language_name = "Galician" },
    { language_code = "ka", language_name = "Georgian" },
    { language_code = "de", language_name = "German" },
    { language_code = "el", language_name = "Greek" },
    { language_code = "he", language_name = "Hebrew" },
    { language_code = "hi", language_name = "Hindi" },
    { language_code = "hu", language_name = "Hungarian" },
    { language_code = "is", language_name = "Icelandic" },
    { language_code = "ig", language_name = "Igbo" },
    { language_code = "id", language_name = "Indonesian" },
    { language_code = "ia", language_name = "Interlingua" },
    { language_code = "ga", language_name = "Irish" },
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
    { language_code = "mk", language_name = "Macedonian" },
    { language_code = "ms", language_name = "Malay" },
    { language_code = "ml", language_name = "Malayalam" },
    { language_code = "ma", language_name = "Manipuri" },
    { language_code = "mr", language_name = "Marathi" },
    { language_code = "mn", language_name = "Mongolian" },
    { language_code = "me", language_name = "Montenegrin" },
    { language_code = "nv", language_name = "Navajo" },
    { language_code = "ne", language_name = "Nepali" },
    { language_code = "se", language_name = "Northern Sami" },
    { language_code = "no", language_name = "Norwegian" },
    { language_code = "oc", language_name = "Occitan" },
    { language_code = "or", language_name = "Odia" },
    { language_code = "fa", language_name = "Persian" },
    { language_code = "pl", language_name = "Polish" },
    { language_code = "pt-pt", language_name = "Portuguese" },
    { language_code = "pt-br", language_name = "Portuguese (BR)" },
    { language_code = "pm", language_name = "Portuguese (MZ)" },
    { language_code = "ps", language_name = "Pushto" },
    { language_code = "ro", language_name = "Romanian" },
    { language_code = "ru", language_name = "Russian" },
    { language_code = "sx", language_name = "Santali" },
    { language_code = "sr", language_name = "Serbian" },
    { language_code = "sd", language_name = "Sindhi" },
    { language_code = "si", language_name = "Sinhalese" },
    { language_code = "sk", language_name = "Slovak" },
    { language_code = "sl", language_name = "Slovenian" },
    { language_code = "so", language_name = "Somali" },
    { language_code = "az-zb", language_name = "South Azerbaijani" },
    { language_code = "es", language_name = "Spanish" },
    { language_code = "sp", language_name = "Spanish (EU)" },
    { language_code = "ea", language_name = "Spanish (LA)" },
    { language_code = "sw", language_name = "Swahili" },
    { language_code = "sv", language_name = "Swedish" },
    { language_code = "sy", language_name = "Syriac" },
    { language_code = "tl", language_name = "Tagalog" },
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

-- Debug output. VLC shows it at verbosity 2 (Tools > Messages, or --verbose=2).
-- Never pass request or response bodies, passwords or tokens.
local function dbg(message)
  vlc.msg.dbg("[VLSub] " .. tostring(message))
end

-- macOS only: VLC's dialog there builds every label and HTML widget from
-- the text converted to Latin-1 (VLCExtensionsDialogProvider.m), so a text
-- with any character outside Latin-1 - "Hľadať", Cyrillic, Greek, CJK ... -
-- comes out as an EMPTY label. Buttons, drop-downs and text fields are not
-- affected. The widget parses its text as HTML, so numeric character
-- references get through: "H&#318;ada&#357;". Qt (Linux, Windows) shows
-- UTF-8 as it is and would show such references literally, hence macOS only.
local function html_entities(text)
  return (string.gsub(text, "[\194-\244][\128-\191]*", function(sequence)
    local first = string.byte(sequence)
    local code
    if first < 224 then code = first - 192
    elseif first < 240 then code = first - 224
    else code = first - 240 end
    for i = 2, #sequence do
      code = code * 64 + (string.byte(sequence, i) - 128)
    end
    return "&#" .. code .. ";"
  end))
end

local function on_macos()
  -- VLSUB_PLAIN_DIALOGS=1 switches the macOS handling off, to tell its
  -- effects apart from VLC's own when hunting a problem there
  if os.getenv("VLSUB_PLAIN_DIALOGS") == "1" then return false end
  local dir = vlc.config.userdatadir() or ""
  return string.find(dir, "/Library/Application Support/", 1, true) ~= nil
end

-- Break a long line of label text with <br> so that no line is wider than
-- `limit` columns. Tags are kept whole and count nothing; East Asian
-- characters count two columns and may be broken anywhere.
local function wrap_text(text, limit)
  local function columns_of(char)
    if string.sub(char, 1, 1) == "<" then return 0 end
    local first = string.byte(char)
    return (first >= 227 and first <= 237) and 2 or 1
  end
  local out, width, last_space = {}, 0, nil
  local position = 1
  while position <= #text do
    local piece = string.match(text, "^<[^>]*>", position)
      or string.match(text, "^[%z\1-\127\194-\244][\128-\191]*", position)
      or string.sub(text, position, position)
    local columns = columns_of(piece)
    if columns > 0 and piece ~= " " and width + columns > limit then
      if last_space then
        -- break at the last space of this line; what followed it starts the next
        out[last_space] = "<br>"
        width = 0
        for i = last_space + 1, #out do width = width + columns_of(out[i]) end
        last_space = nil
      end
      if width + columns > limit and width > 0 then
        -- no space to break at (Chinese, Japanese ...): break right here
        out[#out + 1] = "<br>"
        width = 0
      end
    end
    out[#out + 1] = piece
    if piece == " " then last_space = #out end
    width = width + columns
    position = position + #piece
  end
  return table.concat(out)
end

-- vlc.dialog(), with the macOS label problem handled in one place: the
-- returned dialog (and the labels it creates) take and return the text as
-- written; what reaches VLC is the encoded form.
local function new_dialog(title)
  local real = vlc.dialog(title)
  if not on_macos() then
    return real
  end
  -- VLSUB_TRACE_DIALOG=1 (tools/dev.sh run -v): log every widget before it
  -- is handed to VLC, so the last line names the one VLC did not survive
  local trace = os.getenv("VLSUB_TRACE_DIALOG") == "1"
  local originals = {} -- wrapped label -> real widget
  local function wrap_label(widget, text)
    local label = { text = text }
    originals[label] = widget
    return setmetatable(label, { __index = function(_, method)
      if method == "set_text" then
        return function(self, value)
          self.text = value
          if trace then vlc.msg.warn("[VLSub] label:set_text " .. html_entities(value)) end
          return widget:set_text(html_entities(value))
        end
      elseif method == "get_text" then
        return function(self) return self.text end
      end
      return function(_, ...) return widget[method](widget, ...) end
    end })
  end
  local function handler(method)
    if method == "add_label" or method == "add_html" then
      return function(_, text, ...)
        return wrap_label(real[method](real, html_entities(text or ""), ...), text or "")
      end
    elseif method == "del_widget" then
      return function(_, widget) return real:del_widget(originals[widget] or widget) end
    end
    return function(_, ...) return real[method](real, ...) end
  end
  return setmetatable({}, { __index = function(_, method)
    local call = handler(method)
    if not trace then
      return call
    end
    return function(self, ...)
      local first = ...
      vlc.msg.warn("[VLSub] dialog:" .. method .. " "
        .. (type(first) == "string" and html_entities(first) or tostring(first)))
      return call(self, ...)
    end
  end })
end

local json = nil

-- Decode a JSON object or array. Returns true and the table, or false (and
-- the decoder's error message if it raised). Everything the API, the caches
-- and the config file are expected to hold is an object, so a body such as
-- "1", "true" or "\"text\"" - valid JSON, but nothing that can be indexed -
-- counts as a failure to parse.
local function decode_object(text)
  local ok, value = pcall(json.decode, text, 1, true)
  if ok and type(value) == "table" then return true, value end
  return false, (not ok) and value or nil
end
local dlg = nil
local current_window_id = nil -- 1 = main, 2 = configuration, 3 = help (see trigger_menu)
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
    description = strings.int_descr,
    capabilities = {"menu", "input-listener" }
  }
end


-- First run only: copy the languages suggested by locale detection into the
-- three language settings (only the ones still empty) and save them.
-- `log` and `progress` write to the first-run progress window.
local function apply_detected_languages(detected_locale, log, progress)
  if not detected_locale then
    log(strings.ui_could_not_detect_user_locale)
    return
  end
  log(tr("ui_locale_detected_from", detected_locale.locale, detected_locale.source))

  local suggestions = detected_locale.suggested_languages
  if not suggestions or #suggestions == 0 then
    return
  end

  local lang_codes = {}
  for _, suggestion in ipairs(suggestions) do
    table.insert(lang_codes, suggestion.language)
  end
  log(tr("ui_found_suggested_languages", tostring(#suggestions), table.concat(lang_codes, ", ")))

  local slots = {
    { option = "language", message = "ui_set_primary_language" },
    { option = "language2", message = "ui_set_secondary_language" },
    { option = "language3", message = "ui_set_third_language" },
  }
  for i, suggestion in ipairs(suggestions) do
    local os_lang = map_to_opensubtitles_language(suggestion.language)
    local found_language = false
    for _, lang_pair in ipairs(openSub.conf.languages) do
      if lang_pair[1] == os_lang or lang_pair[1] == suggestion.language then
        found_language = true
        local slot = slots[i]
        if slot and (not openSub.option[slot.option] or openSub.option[slot.option] == "") then
          openSub.option[slot.option] = lang_pair[1]
          log(tr(slot.message, lang_pair[1]))
        end
        break
      end
    end
    if not found_language then
      log(tr("ui_language_not_available", os_lang))
    end
  end

  -- A new installation follows the detected language for the interface too
  if not openSub.option.interfaceLanguage then
    openSub.option.interfaceLanguage = "auto"
    openSub.option.detectedLanguage = map_to_opensubtitles_language(suggestions[1].language)
  end

  progress(strings.ui_saving_auto_detected_settings)
  if save_config() then
    log(strings.ui_auto_detected_settings_saved)
  else
    log(strings.ui_failed_to_save_auto_detected_settings)
  end
end

-- VLC calls this when the extension is opened from the menu.
-- The first run shows a progress window, tests the network, detects the
-- user's languages and checks for updates; later runs go straight to the
-- main (or configuration) window.
function activate()
  configurationPassed = false
  jsonModuleLoaded = false
  networkTestsFailed = false
  criticalFailure = false

  local first_run = is_first_run()

  -- Reports for the first-run progress window; silent on later runs
  local function progress(message) if first_run then update_debug_progress(message) end end
  local function status(message) if first_run then update_debug_status(message) end end
  local function log(message) if first_run then append_debug_log(message) end end

  if first_run then
    show_debug_window()
    progress(strings.ui_initializing_vlsub_first_run)
    log(strings.ui_vlsub_first_time_setup_started)
    if not test_network_connectivity() then
      networkTestsFailed = true
    end
  end

  -- JSON module (shipped with VLC)
  progress(strings.ui_loading_json_module)
  local json_ok, json_module = pcall(require, "dkjson")
  if not json_ok then
    status(strings.ui_error_failed_to_load_json_module)
    log(tr("ui_critical_json_module_load_failed", tostring(json_module)))
    criticalFailure = true
    return false
  end
  json = json_module
  jsonModuleLoaded = true
  log(strings.ui_json_module_loaded_successfully)

  progress(strings.ui_checking_dkjson_compatibility)
  if not check_dkjson_compatibility() then
    vlc.msg.err("[VLSub] Incompatible dkjson version detected")
    status(strings.ui_error_incompatible_dkjson_version)
    log(strings.ui_critical_dkjson_version_too_old_cannot_parse)
    show_dkjson_error_dialog()
    criticalFailure = true
    return false
  end
  log(tr("ui_dkjson_check_passed", tostring(json.version)))

  -- Paths, saved settings
  progress(strings.ui_checking_configuration)
  if not check_config() then
    status(strings.ui_error_unsupported_vlc_version)
    log(strings.ui_critical_vlc_version_not_supported)
    criticalFailure = true
    return false
  end
  configurationPassed = true
  pcall(load_interface_language) -- stored translation, no network
  log(strings.ui_configuration_check_passed)

  -- Subtitle languages: built-in list first, then cache or API
  progress(strings.ui_loading_subtitle_languages)
  convert_sub_languages()
  openSub.conf.languages = sub_languages
  if first_run and networkTestsFailed then
    status(strings.ui_using_offline_language_list)
    log(strings.ui_using_built_in_language_list_offline_mode)
  else
    status(strings.ui_initializing_languages_from_api)
    pcall(function()
      initialize_languages()
      log(strings.ui_language_list_loaded_from_api)
    end)
  end

  -- Preferred languages from the system locale
  if first_run then
    progress(strings.ui_detecting_user_locale)
    log(strings.ui_first_run_detected)
    log(strings.ui_starting_locale_detection)

    local saved_user_pref = openSub.option.language
    openSub.option.language = nil
    log(strings.ui_temporarily_cleared_user_preference_for_clean_de)
    local detected_locale = detect_user_locale()
    if saved_user_pref then
      openSub.option.language = saved_user_pref
    end
    apply_detected_languages(detected_locale, log, progress)

    -- Fetch the list of interface languages, and the translation for the
    -- detected one if there is one. The list is fetched even when the
    -- system language is English: otherwise the "Interface language"
    -- drop-down of this first window offers nothing but English.
    if not networkTestsFailed and not networkSlow then
      pcall(refresh_interface_language)
    end
  end

  -- What is playing (needed for auto-search)
  progress(strings.ui_getting_file_information)
  if vlc.input.item() then
    openSub.getFileInfo()
    openSub.getMovieInfo()
    log(strings.ui_file_info_loaded_for_current_media)
  else
    log(strings.ui_no_media_loaded)
  end

  progress(strings.ui_checking_authentication)
  local username = trim(openSub.option.os_username or "")
  local password = trim(openSub.option.os_password or "")
  is_authenticated = (username ~= "" and password ~= "") or has_valid_authentication()
  if is_authenticated then
    log(strings.ui_valid_authentication_found_credentials_available)
  else
    log(strings.ui_no_valid_authentication_missing_credentials)
  end

  init_results.is_first_run = first_run
  init_results.has_auth = is_authenticated
  initialization_complete = true

  if first_run then
    progress(strings.ui_initialization_complete)
    log(strings.ui_initialization_complete_checking_for_auto_close)
    if is_authenticated then
      log(strings.ui_ready_to_show_main_window_authenticated)
    else
      log(strings.ui_ready_to_show_configuration_window_no_auth)
    end
    checkInitializationStatus()

    progress(strings.ui_initializing_auto_update_system)
    log(strings.ui_setting_up_automatic_update_checking)
    initialize_auto_update()
  else
    -- The list of translations (and the one in use) is kept fresh at most
    -- once a week, when the daily update check is online anyway. An install
    -- that has no list at all, or a translation stored by another version
    -- (just upgraded: new texts would stay English), fetches right away -
    -- and before the first window is built, so that window is right too.
    local stale, fetch_now = interface_language_is_stale()
    if fetch_now then
      pcall(refresh_interface_language)
    end
    show_appropriate_window()
    local check_updates = should_check_for_updates()
    if check_updates and stale and not fetch_now then
      pcall(refresh_interface_language)
    end
    if check_updates then
      pcall(function()
        check_for_updates(false)
      end)
    end
  end
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
      dbg("No directory available for update check storage")
      return 0
    end

    -- Try to create the directory if it doesn't exist
    if not is_dir(check_dir) then
      mkdir_p(check_dir)
    end
  end

  local check_file_path = check_dir .. slash .. update_config.last_check_file

  if not file_exist(check_file_path) then
    return 0
  end

  local file = io.open(check_file_path, "rb")
  if not file then
    dbg("Cannot read update check file")
    return 0
  end

  local content = file:read("*all")
  file:close()

  local ok, data = decode_object(content)
  if ok and data and data.last_check then
    return tonumber(data.last_check) or 0
  end

  dbg("Invalid update check file format")
  return 0
end


-- Function to check if we should perform an update check
function should_check_for_updates()
  local last_check = get_last_update_check()
  local now = os.time()
  local time_since_last_check = now - last_check

  dbg("Last update check: " .. last_check .. ", time since: " .. time_since_last_check .. "s")

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

-- Compact function to show update available dialog (single dialog, VLC-compatible, compact)
function show_update_dialog(latest_version, release_notes, download_url)
  if not dlg then
    return -- No dialog available
  end


  -- Close current dialog and show update dialog
  close_dlg()

  dlg = new_dialog("VLSub Update Available - " .. latest_version)

  -- Row 1: Update notification header with link and version info in compact format
  dlg:add_label(tr("ui_update_available", update_config.current_version, latest_version), 1, 1, 6, 1)

  -- Row 2: Installation instructions
  dlg:add_label(strings.ui_installation_instructions, 1, 2, 6, 1)

  -- Detect OS and show appropriate instructions
  if openSub.conf.os == "win" then
    -- Windows instructions - compact with 2-line fallback
    dlg:add_label(strings.ui_open_powershell_as_administrator_and_run, 1, 3, 6, 1)
    dlg:add_label("iwr -useb https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/scripts/install.ps1 | iex", 1, 4, 6, 1)
    dlg:add_label(tr("ui_if_this_doesn_t_work_download", download_url), 1, 5, 6, 1)
    dlg:add_label("%APPDATA%\\vlc\\lua\\extensions\\vlsubcom.lua", 1, 6, 6, 1)

  else
    -- macOS/Linux instructions - compact with 2-line fallback
    local install_path = "~/.local/share/vlc/lua/extensions/vlsubcom.lua"

    -- Detect macOS
    if string.find(string.lower(os.getenv("HOME") or ""), "users") or
       string.find(string.lower(os.getenv("USER") or ""), "user") then
      install_path = "~/Library/Application Support/org.videolan.vlc/lua/extensions/vlsubcom.lua"
    end

    dlg:add_label(strings.ui_open_terminal_and_run, 1, 3, 6, 1)
    dlg:add_label("curl -sSL https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/scripts/install.sh | bash", 1, 4, 6, 1)
    dlg:add_label(tr("ui_if_this_doesn_t_work_download", download_url), 1, 5, 6, 1)
    dlg:add_label(install_path, 1, 6, 6, 1)
  end

  dlg:add_label(strings.ui_then_restart_vlc_and_access_via_view, 1, 7, 6, 1)

  -- Row 8: What's new section (compact - exactly 6 lines)
  dlg:add_label(tr("ui_whats_new_in", latest_version), 1, 8, 6, 1)

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
  dlg:add_button(strings.ui_skip_version, function()
    save_skipped_version(latest_version)
    close_dlg()
    show_appropriate_window()
  end, 2, 15, 1, 1)

  dlg:add_button(strings.ui_later, function()
    close_dlg()
    show_appropriate_window()
  end, 4, 15, 1, 1)

  dlg:add_button(strings.ui_close, function()
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
  for line_value in processed:gmatch("[^\n]+") do
    local line = line_value -- loop variables are read-only in Lua 5.5
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
      return true
    end
  end

  vlc.msg.err("[VLSub] Failed to save update check timestamp")
  return false
end


-- Main function to check for updates (ENHANCED)
function check_for_updates(force_check)

  -- Don't check if no internet connection (unless forced)
  if (networkTestsFailed or networkSlow) and not force_check then
    dbg("Skipping update check - no or slow internet connection")
    return
  end

  -- Check if we should perform the check (unless forced)
  if not force_check and not should_check_for_updates() then
    dbg("Skipping update check - too soon since last check")
    return
  end


  -- Make API request to GitHub
  local client = Curl.new()
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
  local ok, release_data = decode_object(res.body)
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

  dbg("Latest version: " .. latest_version)

  -- Save that we performed the check (IMPORTANT: do this regardless of result)
  save_last_update_check()

  -- Compare versions
  local version_comparison = compare_versions(latest_version, update_config.current_version)

  if version_comparison > 0 then
    -- New version available
    dbg("Update available: " .. latest_version)

    -- Check if this version was skipped (only if not forced)
    if is_version_skipped(latest_version) and not force_check then
      dbg("Version " .. latest_version .. " was previously skipped")
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
    dbg("No update available")
    if force_check then
      -- If manually triggered, show a message only if we have an interface
      if input_table and input_table["message"] then
        setMessage(success_tag(tr("ui_you_re_running_the_latest_version", update_config.current_version)))
      end
    end
  end
end

-- Function to initialize auto-update checking (FIXED)
function initialize_auto_update()

  -- Always attempt update check, regardless of config state
  -- The only requirements are: json module loaded and some network connectivity

  if not jsonModuleLoaded then
    dbg("Skipping auto-update: JSON module not loaded")
    return
  end

  -- Don't require full config - we can check for updates even without OpenSubtitles credentials

  -- Perform update check in background (non-blocking)
  pcall(function()
    check_for_updates(false) -- Don't force, respect timing
  end)
end


-- IP-based geolocation detection using api.myip.com
function detect_ip_based_locale(detected_locales)

  local ip_api_url = "https://api.myip.com"

  -- Use the same curl wrapper as other API calls
  local client = Curl.new()
  client:set_timeout(10) -- Short timeout for IP detection
  client:set_retries(1)  -- Single retry

  local res = client:get(ip_api_url)

  if not res then
    dbg("IP geolocation: No response from API")
    return
  end

if not res or res.status ~= 200 then
  local status = (res and res.status) or "N/A"
  dbg("IP geolocation: API request failed with status: " .. status)
  return
end

  if not res.body or res.body == "" then
    dbg("IP geolocation: Empty response body")
    return
  end

  -- Parse the JSON response
  local ok, ip_data = decode_object(res.body)
  if not ok or not ip_data then
    dbg("IP geolocation: Failed to parse response: " .. (res.body or "no body"))
    return
  end


  -- Extract country code and map to language
  local country_code = ip_data.cc
  local country_name = ip_data.country

  if country_code and country_code ~= "" then
    dbg("Detected country from IP: " .. country_name .. " (" .. country_code .. ")")

    -- Map country codes to primary languages
    local country_language_map = {
      -- Major countries with their primary languages. Multilingual countries
      -- appear once: Canada counts as French, Switzerland as Italian and
      -- Belgium (below) as Dutch. (They used to be listed under several
      -- languages; in a Lua table the last entry is the one that counts.)
      US = "en", GB = "en", AU = "en", NZ = "en", IE = "en", ZA = "en",
      DE = "de", AT = "de",
      FR = "fr", CA = "fr",
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
      table.insert(detected_locales, {source = "ip_geolocation", locale = primary_language})

      -- For some countries, add country-specific locale
      local country_specific = primary_language .. "_" .. country_code
      table.insert(detected_locales, {source = "ip_country_specific", locale = country_specific})
    else
      dbg("No language mapping found for country: " .. country_code)
    end
  else
    dbg("No country code in IP geolocation response")
  end
end


-- Improved initialize_languages with better error handling
function initialize_languages()
  local cache_file_path = openSub.conf.dirPath .. slash .. "cache_subtitle_languages.json"

  -- Check cache first
  if file_exist(cache_file_path) then
    local file_stat = vlc.net.stat(cache_file_path)
    if file_stat and (os.time() - file_stat.modification_time < config.cache_languages_duration_seconds) then

      local cache_file = io.open(cache_file_path, "rb")
      if cache_file then
        local cache_content = cache_file:read("*all")
        cache_file:close()

        local ok, parsed_data = decode_object(cache_content)
        if ok and parsed_data and type(parsed_data.data) == "table" then
          local formatted_langs = {}
          for _, lang_obj in ipairs(parsed_data.data) do
            if type(lang_obj.language_code) == "string" and type(lang_obj.language_name) == "string" then
              table.insert(formatted_langs, {lang_obj.language_code, lang_obj.language_name})
            end
          end

          if #formatted_langs > 0 then
            dbg("Successfully loaded " .. #formatted_langs .. " languages from cache")
            openSub.conf.languages = formatted_langs
            return
          end
        end
      end
    end
  end

  -- Use built-in languages as fallback
  openSub.conf.languages = sub_languages
  dbg("Using built-in language list (" .. #sub_languages .. " languages)")

  -- Try to fetch from API with aggressive timeouts

  local client = Curl.new()
  client:set_aggressive_timeouts()
  client:add_header("Api-Key", api_key())

  local res = client:get(api_url("/infos/languages"))

  if res and res.status == 200 and res.body then
    local ok, parsed_data = decode_object(res.body)
    if ok and parsed_data and type(parsed_data.data) == "table" then
      -- Save to cache
      if file_touch(cache_file_path) then
        local cache_file = io.open(cache_file_path, "wb")
        if cache_file then
          cache_file:write(res.body)
          cache_file:flush()
          cache_file:close()
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
        dbg("Updated with " .. #formatted_langs .. " languages from API")
      end
    else
      vlc.msg.err("[VLSub] Failed to parse API language response")
    end
  else
    vlc.msg.err("[VLSub] Failed to fetch languages from API, using built-in list")
  end

end


function close()
  vlc.deactivate()
end

function deactivate()
  if dlg then
    dlg:hide()
  end

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


            --[[ Early helpers ]]--

-- NOTE: these are `local function`s, so they MUST be declared above every
-- call site. A local declared further down the file is not in scope here and
-- the call silently resolves to a nil global (v1.3.1 crash: "attempt to call
-- global 'sanitize_filename' (a nil value)"). `luacheck` in CI guards this.

-- Sanitize filename for filesystem compatibility
-- Handles Windows forbidden characters, length limits, and UTF-8 boundaries
-- @param filename string - The filename to sanitize
-- @param max_length number - Maximum length (default 180, leaves room for extensions)
-- @return string - Sanitized filename safe for all platforms
local function sanitize_filename(filename, max_length)
  if not filename or filename == "" then
    return "subtitle"
  end

  max_length = max_length or 180

  -- Step 1: Remove trailing dots and spaces FIRST (Windows quirk - not allowed)
  local sanitized = string.gsub(filename, "[%. ]+$", "")

  -- Step 2: Replace Windows forbidden characters with underscores
  -- Forbidden: < > : " / \ | ? *
  sanitized = string.gsub(sanitized, "[<>:\"/\\|?*]", "_")

  -- Step 3: Collapse multiple spaces/underscores into single underscore
  sanitized = string.gsub(sanitized, "%s+", "_")
  sanitized = string.gsub(sanitized, "_+", "_")

  -- Step 4: Remove leading/trailing underscores
  sanitized = string.gsub(sanitized, "^_+", "")
  sanitized = string.gsub(sanitized, "_+$", "")

  -- Step 5: Truncate to max_length if needed
  if #sanitized > max_length then
    sanitized = string.sub(sanitized, 1, max_length)

    -- Step 6: Don't leave half of a multi-byte UTF-8 character at the cut
    -- UTF-8 continuation bytes: 10xxxxxx (128-191, \128-\191)
    -- UTF-8 start bytes: 11xxxxxx (192-255, \192-\255)
    -- This pattern removes any incomplete UTF-8 sequence at the end
    sanitized = string.gsub(sanitized, "[\192-\255][\128-\191]*$", "")

    -- Remove trailing underscore if truncation left one
    sanitized = string.gsub(sanitized, "_+$", "")
  end

  -- Step 7: Ensure we didn't create an empty filename
  if sanitized == "" then
    return "subtitle"
  end

  return sanitized
end


            --[[ Interface data ]]--


-- Shown instead of the main window when this VLC build has no vlc.net support
function interface_no_support()
  dlg:add_html(lang["int_no_support_mess"], 1, 1, 5, 7)
  return false
end

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

  -- Row 3: Year, IMDB ID
  dlg:add_label(strings.ui_year, 1, 3, 1, 1)
  input_table['year'] = dlg:add_text_input(
    openSub.movie.year or "", 2, 3, 1, 1)
  dlg:add_label(lang["int_imdb"]..":", 3, 3, 1, 1)
  input_table['imdbId'] = dlg:add_text_input(
    openSub.movie.imdbId or "", 4, 3, 1, 1)
  dlg:add_button("🔍 "..lang["int_search_name"],
    searchIMBD_v2, 6, 2, 1, 1)

  -- Row 4: Language selection
  dlg:add_label(lang["int_default_lang"]..":", 1, 4, 1, 1)
  input_table['language'] =  dlg:add_dropdown(2, 4, 4, 1)

  -- Row 5: Secondary language
  dlg:add_label(lang["int_second_lang"]..":", 1, 5, 1, 1)
  input_table['language2'] =  dlg:add_dropdown(2, 5, 4, 1)

  -- Row 6: Third language
  dlg:add_label(lang["int_third_lang"]..":", 1, 6, 1, 1)
  input_table['language3'] = dlg:add_dropdown(2, 6, 4, 1)

  -- Row 7: Sorting controls
  dlg:add_label(strings.ui_sort_by, 1, 7, 1, 1)
  input_table['sort_by'] = dlg:add_dropdown(2, 7, 3, 1)
  input_table['sort_direction'] = dlg:add_dropdown(5, 7, 1, 1)

  -- Row 8: Results list label
  dlg:add_label(strings.ui_search_results, 1, 8, 6, 1)

  -- Row 9: Results list
  input_table['mainlist'] = dlg:add_list(1, 9, 6, 1)

  -- Row 10: Status message
  input_table['message'] = nil
  input_table['message'] = dlg:add_label(strings.ui_ready_for_search, 1, 10, 6, 1)

  -- Row 11: Action buttons - MODIFIED HELP BUTTON
  dlg:add_button(
    strings.ui_download, download_subtitles_v2, 1, 11, 1, 1)

  dlg:add_button(
    strings.ui_link, open_subtitle_link, 2, 11, 1, 1)

  dlg:add_button(
    strings.ui_upload, show_upload, 3, 11, 1, 1)

  dlg:add_button(
    strings.ui_config, show_conf, 5, 11, 1, 1)
  dlg:add_button(
    strings.ui_help,
    function() show_help("main") end, -- "main" tells the help window where to return to
    6, 11, 1, 1)

  -- Set up language dropdowns
  assoc_select_conf('language', 'language', openSub.conf.languages, 2, lang["int_all"])
  assoc_select_conf('language2', 'language2', openSub.conf.languages, 2, strings.ui_none)
  assoc_select_conf('language3', 'language3', openSub.conf.languages, 2, strings.ui_none)
  -- same order as the option tables, so a drop-down id is an index into them
  local function shown(options)
    local list = {}
    for i, option in ipairs(options) do
      list[i] = { option[1], strings[option[2]] }
    end
    return list
  end
  assoc_select_conf('sort_by', 'sortBy', shown(openSub.conf.sortByOptions), 2, strings.ui_sort_default)
  assoc_select_conf('sort_direction', 'sortDirection', shown(openSub.conf.sortDirectionOptions), 2)

  -- Only call display_subtitles if we actually have search results to display
  if has_results() then
    display_subtitles()
  end
end

function interface_config()
  -- Grid: labels in column 1, every field starts in column 2 (two columns
  -- wide), so the fields line up under each other; the four buttons of the
  -- last row use columns 1 to 4.
  -- Row 1: OpenSubtitles username
  -- "OpenSubtitles.com" in the label is a link to the site (where an account
  -- is made); whatever the language, the name is written the same way
  local username_label = string.gsub(lang["int_os_username"], "OpenSubtitles%.com",
    "<a href='https://www.opensubtitles.com'>OpenSubtitles.com</a>", 1)
  dlg:add_label(username_label..":", 1, 1, 1, 1)
  input_table['os_username'] = dlg:add_text_input(
    type(openSub.option.os_username) == "string"
    and openSub.option.os_username or "", 2, 1, 2, 1)

  -- Row 2: OpenSubtitles password
  dlg:add_label(lang["int_os_password"]..":", 1, 2, 1, 1)
  input_table['os_password'] = dlg:add_password(
    type(openSub.option.os_password) == "string"
    and openSub.option.os_password or "", 2, 2, 2, 1)

  -- Row 3: Default primary language
  dlg:add_label(lang["int_default_lang"]..":", 1, 3, 1, 1)
  input_table['default_language'] = dlg:add_dropdown(2, 3, 2, 1)

  -- Row 4: Default secondary language
  dlg:add_label(lang["int_second_lang"]..":", 1, 4, 1, 1)
  input_table['default_language2'] = dlg:add_dropdown(2, 4, 2, 1)

  -- Row 5: Default third language
  dlg:add_label(lang["int_third_lang"]..":", 1, 5, 1, 1)
  input_table['default_language3'] = dlg:add_dropdown(2, 5, 2, 1)

  -- Row 6: Download behavior
  dlg:add_label(lang["int_dowload_behav"]..":", 1, 6, 1, 1)
  input_table['downloadBehaviour'] = dlg:add_dropdown(2, 6, 2, 1)

  -- Row 7: Display language code
  dlg:add_label(lang["int_display_code"]..":", 1, 7, 1, 1)
  input_table['langExt'] = dlg:add_dropdown(2, 7, 2, 1)

  -- Row 8: Remove tags
  dlg:add_label(lang["int_remove_tag"]..":", 1, 8, 1, 1)
  input_table['removeTag'] = dlg:add_dropdown(2, 8, 2, 1)


  -- Row 9: Interface language
  dlg:add_label(strings.ui_interface_language..":", 1, 9, 1, 1)
  input_table['interfaceLanguage'] = dlg:add_dropdown(2, 9, 2, 1)

  -- Row 10: AI credits (asked for on click: no request just for opening
  -- this window)
  dlg:add_label(strings.ui_filters..":", 1, 10, 1, 1)
  dlg:add_button(strings.ui_filters_open, show_filters, 2, 10, 1, 1)
  dlg:add_button(strings.ui_ai_show_credits, show_ai_credits, 3, 10, 1, 1)

  -- Row 11: Working directory
  if openSub.conf.dirPath then
    if openSub.conf.os == "lin" then
      dlg:add_label(lang["int_vlsub_work_dir"], 1, 11, 1, 1)
    elseif openSub.conf.os == "win" then
      dlg:add_label(
        "<a href='file:///"..openSub.conf.dirPath.."'>"..
        lang["int_vlsub_work_dir"].."</a>", 1, 11, 1, 1)
    else
      dlg:add_label(
        "<a href='"..openSub.conf.dirPath.."'>"..
        lang["int_vlsub_work_dir"].."</a>", 1, 11, 1, 1)
    end
  else
    dlg:add_label(lang["int_vlsub_work_dir"], 1, 11, 1, 1)
  end

  input_table['dir_path'] = dlg:add_text_input(
    openSub.conf.dirPath, 2, 11, 2, 1)

  -- Row 12: Status message
  input_table['message'] = nil
  -- macOS sizes the window when it is built and does not grow it: a message
  -- of three lines (account, AI credits, "saved") pushed the first row out
  -- of the window at the top. Reserve the lines there.
  local three_empty_lines = "&nbsp;<br>&nbsp;<br>&nbsp;"
  input_table['message'] = dlg:add_label(on_macos() and three_empty_lines or '', 1, 12, 4, 1)

  -- Row 13: Action buttons
  dlg:add_button(
    "💾 " .. lang["int_save"],
    apply_config, 1, 13, 1, 1)

  dlg:add_button(
    "❓ " .. lang["int_help"],
    function() show_help("config") end,
    2, 13, 1, 1)

  -- ("Check Updates" lives in the help window: updates are checked once a
  -- day by themselves, the button is only for "check right now")

  dlg:add_button(
    "❌ " .. lang["int_close"],
    show_main, 4, 13, 1, 1)

  -- Setup dropdown values for existing dropdowns
  input_table['langExt']:add_value(
    lang["int_bool_"..tostring(openSub.option.langExt)], 1)
  input_table['langExt']:add_value(
    lang["int_bool_"..tostring(not openSub.option.langExt)], 2)
  input_table['removeTag']:add_value(
    lang["int_bool_"..tostring(openSub.option.removeTag)], 1)
  input_table['removeTag']:add_value(
    lang["int_bool_"..tostring(not openSub.option.removeTag)], 2)


  assoc_select_conf('default_language', 'language', openSub.conf.languages, 2, lang["int_all"])
  assoc_select_conf('default_language2', 'language2', openSub.conf.languages, 2, strings.ui_none)
  assoc_select_conf('default_language3', 'language3', openSub.conf.languages, 2, strings.ui_none)
  assoc_select_conf('downloadBehaviour', 'downloadBehaviour', openSub.conf.downloadBehaviours, 1)

  -- English, automatic, then the reviewed translations known so far
  openSub.conf.interfaceLanguages = {
    -- every language under its own name, whatever the interface language:
    -- someone who ended up in a language they cannot read must find theirs
    { "en", "English" },
    { "auto", strings.ui_language_auto }
  }
  for _, language in ipairs(available_interface_languages()) do
    table.insert(openSub.conf.interfaceLanguages, language)
  end
  assoc_select_conf('interfaceLanguage', 'interfaceLanguage', openSub.conf.interfaceLanguages, 2)
end


-- Modified interface_help function with improved content
function interface_help()
  -- macOS does not widen the window for a long label: it cuts the line off.
  -- Wrap there; Qt sizes the window to its content and needs nothing.
  local wrap = on_macos()
  local function line(text)
    return wrap and wrap_text(text, 64) or text
  end

  -- Kept short on purpose: the window cannot scroll, and on a laptop screen
  -- anything longer does not fit. One heading and one to three lines per
  -- subject, nothing that the main window already says.
  local rows = {
    strings.ui_search_methods,
    strings.ui_help_search_hash,
    strings.ui_help_search_name,
    strings.ui_help_search_fallback,
    strings.ui_help_languages_title,
    strings.ui_choose_up_to_3_preferred_subtitle_languages,
    strings.ui_results_grouped_by_selected_languages_in_priorit,
    strings.ui_account_quotas,
    strings.ui_free_opensubtitles_com_account_required_for_down,
    strings.ui_help_ai_title,
    strings.ui_help_ai_what,
    strings.ui_help_ai_credits,
    strings.ui_support_opensubtitles_thank_you_very_much,
    strings.ui_github_opensubtitles_vlsub_opensubtitles_com_sou,
  }
  for row, text in ipairs(rows) do
    dlg:add_label(line(text), 1, row, 6, 1)
  end

  -- the answer of "Check Updates" when there is nothing newer
  input_table["message"] = dlg:add_label("", 1, #rows + 1, 6, 1)
  dlg:add_button(strings.ui_check_updates,
    function() check_for_updates(true) end, 1, #rows + 2, 2, 1)

  dlg:add_button(strings.ui_close,
    function()
      if previous_window == "config" then
        show_conf()
      else
        show_main()
      end
    end,
    5, #rows + 2, 2, 1)
end


function trigger_menu(dlg_id)
  current_window_id = dlg_id
  if dlg_id == 1 then
    close_dlg()
    dlg = new_dialog(
      openSub.conf.useragent)
    interface_main()
  elseif dlg_id == 2 then
    close_dlg()
    dlg = new_dialog(
      openSub.conf.useragent..': '..lang["int_configuration"])
    interface_config()
  elseif dlg_id == 3 then
    close_dlg()
    dlg = new_dialog(
      openSub.conf.useragent..': '..lang["int_help"])
    interface_help()
  elseif dlg_id == 4 then
    close_dlg()
    dlg = new_dialog(
      openSub.conf.useragent..': '..strings.ui_filters)
    interface_filters()
  elseif dlg_id == 5 then
    close_dlg()
    dlg = new_dialog(
      openSub.conf.useragent..': '..strings.ui_upload_title)
    interface_upload()
  end
  collectgarbage() --~ !important
end

function show_filters()
  trigger_menu(4)
end

-- The search filters the API offers, each with the values of its drop-down.
-- The value stored in the settings is the first field of a choice.
local FILTERS = {
  { option = "aiTranslations", label = "ui_ai_translations", default = true,
    choices = { { true, "int_bool_true" }, { false, "int_bool_false" } } },
  { option = "machineTranslations", label = "ui_filter_machine", default = false,
    choices = { { true, "int_bool_true" }, { false, "int_bool_false" } } },
  { option = "hearingImpaired", label = "ui_filter_hearing_impaired", default = "include",
    choices = { { "include", "ui_filter_include" }, { "exclude", "ui_filter_exclude" }, { "only", "ui_filter_only" } } },
  { option = "foreignPartsOnly", label = "ui_filter_foreign_parts", default = "include",
    choices = { { "include", "ui_filter_include" }, { "exclude", "ui_filter_exclude" }, { "only", "ui_filter_only" } } },
  { option = "trustedOnly", label = "ui_filter_trusted", default = false,
    choices = { { true, "int_bool_true" }, { false, "int_bool_false" } } },
}

-- What a filter is set to; anything unknown (an old or edited config file)
-- counts as its default.
local function filter_value(filter)
  local value = openSub.option[filter.option]
  for _, choice in ipairs(filter.choices) do
    if choice[1] == value then
      return value
    end
  end
  return filter.default
end

-- True when any filter differs from its default, i.e. can hide subtitles
-- that would be listed otherwise (machine translations: can add some).
function filters_active()
  for _, filter in ipairs(FILTERS) do
    if filter_value(filter) ~= filter.default then
      return true
    end
  end
  return false
end

-- The query parameters the filters add to a search. Defaults are not sent.
function filter_params(params)
  local function set(name, filter_index, sent)
    local value = filter_value(FILTERS[filter_index])
    if sent[value] then
      params[name] = sent[value]
    end
  end
  set("ai_translated", 1, { [false] = "exclude" })
  set("machine_translated", 2, { [true] = "include" })
  set("hearing_impaired", 3, { exclude = "exclude", only = "only" })
  set("foreign_parts_only", 4, { exclude = "exclude", only = "only" })
  set("trusted_sources", 5, { [true] = "only" })
end

function interface_filters()
  for row, filter in ipairs(FILTERS) do
    dlg:add_label(strings[filter.label] .. ":", 1, row, 1, 1)
    local dropdown = dlg:add_dropdown(2, row, 1, 1)
    -- the current choice first (VLC selects whatever is added first); the id
    -- of an entry is its position in the list of choices
    local current = filter_value(filter)
    for id, choice in ipairs(filter.choices) do
      if choice[1] == current then
        dropdown:add_value(strings[choice[2]], id)
      end
    end
    for id, choice in ipairs(filter.choices) do
      if choice[1] ~= current then
        dropdown:add_value(strings[choice[2]], id)
      end
    end
    input_table["filter_" .. filter.option] = dropdown
  end
  input_table["message"] = dlg:add_label("", 1, #FILTERS + 1, 2, 1)
  dlg:add_button("💾 " .. lang["int_save"], apply_filters, 1, #FILTERS + 2, 1, 1)
  dlg:add_button(strings.ui_back, show_conf, 2, #FILTERS + 2, 1, 1)
end

function apply_filters()
  for _, filter in ipairs(FILTERS) do
    local dropdown = input_table["filter_" .. filter.option]
    local choice = dropdown and filter.choices[dropdown:get_value()]
    if choice then
      openSub.option[filter.option] = choice[1]
    end
  end
  if save_config() then
    setMessage(success_tag(strings.ui_filters_saved))
  else
    setError(lang["mess_err_conf_access"])
  end
end

-- Enhanced show_main function with automatic search
function show_main()
  trigger_menu(1)

  -- After showing the main interface, check if we should auto-search
  if should_auto_search() then
    dbg("Auto-searching subtitles for loaded media...")

    -- Small delay to ensure interface is fully loaded
    local start_time = os.clock()
    while (os.clock() - start_time) < 0.1 do
    end

    -- Automatically trigger hash search (which includes name search fallback)
    searchHash()
  end
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

-- Function to determine if we should automatically search
function should_auto_search()
  -- Check if we have media loaded
  if not openSub.file.hasInput then
    dbg("No media loaded - skipping auto-search")
    return false
  end

  -- Check if we already have search results (avoid re-searching)
  if has_results() then
    dbg("Already have search results - skipping auto-search")
    return false
  end

  -- Check if we have authentication (required for searching)
  if not is_authenticated then
    dbg("No authentication - skipping auto-search")
    return false
  end

  -- Check if GuessIt returned useful data
  local has_useful_guessit_data = false
  if openSub.file.guessit_data then
    local guessit = openSub.file.guessit_data

    -- Consider it useful if we have a title, or season/episode info
    if (guessit.title and guessit.title ~= "") or
       (guessit.season and guessit.episode) then
      has_useful_guessit_data = true
    end
  end

  -- Also check if we have basic movie info (fallback if GuessIt didn't work)
  local has_basic_movie_info = false
  if openSub.movie.title and openSub.movie.title ~= "" then
    has_basic_movie_info = true
  end

  -- Auto-search if we have either GuessIt data or basic movie info
  if has_useful_guessit_data or has_basic_movie_info then
    return true
  end

  dbg("No useful metadata found - skipping auto-search")
  return false
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
      debug_messages.ok_button:set_text(strings.ui_continue)
    elseif allTestsPassed and not networkTestsFailed then
      -- All good - will auto-close
      debug_messages.ok_button:set_text(strings.ui_auto_close_2s)
    elseif allTestsPassed and networkTestsFailed then
      -- Core works but offline
      debug_messages.ok_button:set_text(strings.ui_continue_offline)
    else
      -- Has errors
      debug_messages.ok_button:set_text(strings.ui_continue_anyway)
    end
  end

  -- Update Cancel/Close button
  if debug_messages.cancel_button then
    debug_messages.cancel_button:set_text(strings.ui_close_vlsub)
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

  debug_dlg = new_dialog("VLSub - Initializing...")

  -- Create debug interface (6 columns, 16 rows)
  debug_dlg:add_label(strings.ui_vlsub_is_starting_up, 1, 1, 6, 1)
  debug_dlg:add_label("", 1, 2, 6, 1) -- Spacer

  -- Progress area
  debug_dlg:add_label(strings.ui_progress, 1, 3, 1, 1)
  debug_messages.progress = debug_dlg:add_label(strings.ui_starting, 2, 3, 5, 1)

  -- Status area
  debug_dlg:add_label(strings.ui_status, 1, 4, 1, 1)
  debug_messages.status = debug_dlg:add_label(strings.ui_initializing_components, 2, 4, 5, 1)

  -- Network status
  debug_dlg:add_label(strings.ui_network, 1, 5, 1, 1)
  debug_messages.network = debug_dlg:add_label(strings.ui_checking_connectivity, 2, 5, 5, 1)

  -- Empty row for spacing
  debug_dlg:add_label("", 1, 6, 6, 1)

  -- Debug log area - 8 individual rows for messages
  debug_dlg:add_label(strings.ui_debug_log, 1, 7, 6, 1)

  -- Create 8 individual log message rows (rows 8-15)
  for i = 1, 8 do
    local row_number = 7 + i -- Start at row 8
    debug_log_rows[i] = debug_dlg:add_label("", 1, row_number, 6, 1)
  end

  -- Initialize first message
  debug_log_rows[1]:set_text(strings.ui_vlsub_initialization_starting)

  -- Buttons (visible at row 16) - Store references for dynamic updates
  debug_messages.ok_button = debug_dlg:add_button(strings.ui_continue, function()
    close_debug_window()
    show_appropriate_window()
  end, 2, 16, 2, 1)

  debug_messages.cancel_button = debug_dlg:add_button(strings.ui_close, function()
    close_debug_window()
    vlc.deactivate()
  end, 4, 16, 2, 1)

  debug_dlg:show()
  collectgarbage()
end


function close_dlg()

  if dlg ~= nil then
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

-- Fill a drop-down. VLC shows whatever is added first as the selection and
-- offers no way to select an entry later, so the saved choice goes first,
-- then the default ("All" / "None", id 0), then everything else. Ids are
-- positions in `conf`, whatever the display order.
function display_select(select_id)
  local conf = select_conf[select_id].cf
  local option = openSub.option[select_conf[select_id].opt]
  local default = select_conf[select_id].dflt
  local widget = input_table[select_id]

  if not option and default then
    widget:add_value(default, 0)
    for k, l in ipairs(conf) do
      widget:add_value(l[2] or "", k)
    end
    return
  end

  for k, l in ipairs(conf) do
    if option and option == l[1] then
      widget:add_value(l[2], k)
      break
    end
  end
  if default then
    widget:add_value(default, 0)
  end
  for k, l in ipairs(conf) do
    if not option or option ~= l[1] then
      widget:add_value(l[2], k)
    end
  end
end


-- Enhanced display_subtitles function to show all-languages search info
function display_subtitles()
  local mainlist = input_table["mainlist"]
  mainlist:clear()

  -- Consume the transport diagnosis for this search only
  local transportError = openSub.lastTransportError
  openSub.lastTransportError = nil

  if has_no_results() then
    mainlist:add_value(lang["mess_no_res"], 1)

    -- Enhanced message for different search scenarios
    -- One whole sentence per situation, so a translation can order it freely
    local hash = openSub.file.hash
    local has_hash = hash and hash ~= ""
    local title = openSub.movie.title
    local has_title = title and title ~= ""
    local message
    if openSub.lastSearchMethod == "hash" and has_hash then
      message = tr("ui_search_none_hash", hash)
    elseif openSub.lastSearchMethod == "hash_fallback" then
      if has_hash and has_title then
        message = tr("ui_search_none_fallback_hash_title", hash, title)
      elseif has_hash then
        message = tr("ui_search_none_fallback_hash", hash)
      elseif has_title then
        message = tr("ui_search_none_fallback_title", title)
      else
        message = strings.ui_search_none_fallback
      end
    else
      message = strings.ui_search_none
    end

    if transportError then
      message = message .. "<br/>" .. error_tag(transportError)
    elseif filters_active() then
      -- nothing found, and a filter may be the reason: say so
      message = message .. "<br/>" .. strings.ui_filters_active
    end

    setMessage(message)

  elseif has_results() then
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
    local count = tostring(#(openSub.itemStore))
    local hash = openSub.file.hash
    local title = openSub.movie.title
    local has_title = title and title ~= ""
    local method = openSub.lastSearchMethod
    local message
    if method == "hash" and hash and hash ~= "" then
      message = tr("ui_search_found_hash", count, hash)
    elseif method == "imdb" then
      message = tr("ui_search_found_imdb", count, openSub.movie.imdbId or "")
    elseif method == "hash_fallback" then
      message = has_title and tr("ui_search_found_fallback_title", count, title)
                           or tr("ui_search_found_fallback", count)
    elseif method == "name" and has_title then
      message = tr("ui_search_found_title", count, title)
    else
      message = tr("ui_search_found", count)
    end

    setMessage(message)
  end
end


-- New function to open subtitle link in browser
function open_subtitle_link()
  if not has_results() then
    setMessage(error_tag(strings.ui_no_subtitles_available_please_search_first))
    return false
  end

  local index = get_first_sel(input_table["mainlist"])

  if index == 0 then
    setMessage(error_tag(strings.ui_please_select_a_subtitle_from_the_list))
    return false
  end

  local item = openSub.itemStore[index]

  -- Use the direct URL from API results
  local subtitle_url = item.url

  if not subtitle_url or subtitle_url == "" then
    setMessage(error_tag(strings.ui_no_url_available_for_this_subtitle))
    return false
  end


  -- Create clickable link message
  local link_message = "<span style='color:#181'>"
  link_message = link_message .. strings.ui_subtitle_link
  link_message = link_message .. "</span> &nbsp;"
  link_message = link_message .. "<a href='" .. subtitle_url .. "'>"
  link_message = link_message .. (item.SubFileName or strings.ui_view_subtitle) .. "</a>"

  setMessage(link_message)

  return true
end


-- Updated buildSubtitleDisplayText function without language brackets
function buildSubtitleDisplayText(item, langCode)
  -- Build display text starting with language code
  local displayText = ""

  -- Add language code at the beginning with spaces (e.g., "EN | ")
  displayText = string.upper(langCode) .. " | "

  -- An AI translation that does not exist yet: what matters comes first (the
  -- list cuts long rows off on the right) - that it is made by AI, from
  -- which language, and that it costs credits. Uploader, download count and
  -- date describe the source subtitle and would only mislead.
  if item.OnDemand then
    local label = item.OnDemandFrom and tr("ui_ai_on_demand_from", item.OnDemandFrom)
      or strings.ui_ai_on_demand
    return displayText .. "🤖 " .. label .. " | " .. (item.MovieReleaseName or item.SubFileName or "???")
  end

  -- Add filename/release name
  displayText = displayText .. (item.SubFileName or "???")


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

-- Check if dkjson version is compatible (can parse floats properly)
-- dkjson 2.1-2.3 have a bug where floats cannot be parsed in certain locales
-- This was fixed in version 2.4 (released 2013-09-28)
-- See: https://github.com/opensubtitles/vlsub-opensubtitles-com/issues/11#issuecomment-3391889129
function check_dkjson_compatibility()
  if not json then
    vlc.msg.err("[VLSub] JSON module not loaded")
    return false
  end

  local version_str = tostring(json.version or "unknown")


  -- Test integer parsing first (should always work)
  local int_json = '{"fps":25}'
  local ok_int, parsed_int = pcall(json.decode, int_json, 1, true)

  if not (ok_int and parsed_int) then
    vlc.msg.err("[VLSub] Integer parsing test failed: " .. tostring(parsed_int))
    return false
  end

  -- Test float parsing (this fails on old dkjson versions)
  local float_json = '{"fps":25.0}'
  local ok_float, parsed_float = pcall(json.decode, float_json, 1, true)

  if not (ok_float and parsed_float) then
    vlc.msg.err("[VLSub] Float parsing test failed: " .. tostring(parsed_float))
    vlc.msg.err("[VLSub] dkjson cannot parse floats - version too old")
    vlc.msg.err("[VLSub] Current version: " .. version_str)
    vlc.msg.err("[VLSub] Required: dkjson 2.4 or newer (with float parsing support)")
    return false
  end

  return true
end

-- Show error dialog for incompatible dkjson version
function show_dkjson_error_dialog()
  local error_dlg = new_dialog("VLSub - Incompatible dkjson Version")

  error_dlg:add_label(strings.ui_vlsub_cannot_start_due_to_incompatible_dkjson, 1, 1, 6, 1)
  error_dlg:add_label("", 1, 2, 6, 1)
  error_dlg:add_label(strings.ui_your_vlc_installation_includes_an_old_version, 1, 3, 6, 1)
  error_dlg:add_label(strings.ui_that_cannot_parse_floating_point_numbers_properl, 1, 4, 6, 1)
  error_dlg:add_label("", 1, 5, 6, 1)
  error_dlg:add_label(tr("ui_current_version", tostring(json.version or strings.ui_unknown)), 1, 6, 6, 1)
  error_dlg:add_label(strings.ui_required_version_2_4_or_newer, 1, 7, 6, 1)
  error_dlg:add_label("", 1, 8, 6, 1)
  error_dlg:add_label(strings.ui_solution_windows_macos, 1, 9, 6, 1)
  error_dlg:add_label(strings.ui_upgrade_vlc_to_version_3_0_22, 1, 10, 6, 1)
  error_dlg:add_label("", 1, 11, 6, 1)
  error_dlg:add_label(strings.ui_solution_ubuntu_debian_linux, 1, 12, 6, 1)
  error_dlg:add_label(strings.ui_ubuntu_ships_vlc_with_the_broken_dkjson, 1, 13, 6, 1)
  error_dlg:add_label(strings.ui_replace_the_bundled_dkjson_luac_with_the, 1, 14, 6, 1)
  error_dlg:add_label(strings.ui_1_download_dkjson_lua_from_dkolf_de, 1, 15, 6, 1)
  error_dlg:add_label(strings.ui_2_locate_vlc_s_modules_dir_e, 1, 16, 6, 1)
  error_dlg:add_label(strings.ui_3_back_up_dkjson_luac_and_replace, 1, 17, 6, 1)
  error_dlg:add_label(strings.ui_4_restart_vlc_requires_sudo, 1, 18, 6, 1)
  error_dlg:add_label("", 1, 19, 6, 1)
  error_dlg:add_label(strings.ui_more_info_issue_23_middot_issue_11, 1, 20, 6, 1)
  error_dlg:add_label("", 1, 21, 6, 1)
  error_dlg:add_button(strings.ui_close_2, function() error_dlg:delete() end, 3, 22, 2, 1)
end

            --[[ Interface translations ]]--

-- The script carries English only. Translations are JSON files in the
-- project's repository (locale/<code>.json, see locale/README.md); the one
-- the user needs is downloaded once, kept in <VLSub folder>/locale/ and
-- refreshed at most once a week. English is the fallback for every single
-- string, so a missing or damaged translation can never leave a label empty.
-- (Looked up when used, not when the script is loaded: VLC first runs the
-- file only to read descriptor(), in a state without the os and io libraries.)
local function locale_url()
  return os.getenv("VLSUB_LOCALE_URL")
    or "https://raw.githubusercontent.com/opensubtitles/vlsub-opensubtitles-com/main/locale/"
end
local LOCALE_REFRESH_SECONDS = 7 * 24 * 60 * 60

-- The English originals, copied on first use (strings is overwritten in
-- place when a translation is applied; nothing runs at load time, see above).
local english_strings
local function english()
  if not english_strings then
    english_strings = {}
    for key, value in pairs(strings) do
      english_strings[key] = value
    end
  end
  return english_strings
end

local function count_matches(text, pattern)
  return select(2, string.gsub(text, pattern, ""))
end

local function html_tags(text)
  local found = {}
  for tag in string.gmatch(text, "<[^>]+>") do
    table.insert(found, tag)
  end
  table.sort(found)
  return table.concat(found, "\n")
end

-- A downloaded file is not trusted. A translated string is used only if it
-- cannot break the interface: known key, a string of sane length, the same
-- %s placeholders, the same HTML tags (so no markup or link can be injected)
-- and the same leading/trailing space as the English original.
local function usable_translation(key, value)
  local english = english()[key]
  if not english or type(value) ~= "string" or value == "" then
    return false
  end
  if #value > #english * 4 + 60 then
    return false
  end
  local placeholders = count_matches(english, "%%s")
  if count_matches(value, "%%s") ~= placeholders then
    return false
  end
  if placeholders > 0 and string.find(string.gsub(value, "%%s", ""), "%", 1, true) then
    return false
  end
  if html_tags(value) ~= html_tags(english) then
    return false
  end
  if (string.sub(english, 1, 1) == " ") ~= (string.sub(value, 1, 1) == " ")
  or (string.sub(english, -1) == " ") ~= (string.sub(value, -1) == " ") then
    return false
  end
  return true
end

-- Switch the interface to `translation` (key -> text), or back to English
-- with nil. Returns how many strings were taken from the translation.
function apply_interface_strings(translation)
  for key, value in pairs(english()) do
    strings[key] = value
  end
  local used = 0
  if type(translation) == "table" then
    for key, value in pairs(translation) do
      if usable_translation(key, value) then
        strings[key] = value
        used = used + 1
      end
    end
  end
  -- lists built from strings
  if openSub.conf.downloadBehaviours then
    SetDownloadBehaviours()
  end
  return used
end

local function locale_dir()
  return openSub.conf.dirPath and (openSub.conf.dirPath .. slash .. "locale") or nil
end

local function read_locale_file(name)
  local dir = locale_dir()
  local file = dir and io.open(dir .. slash .. name, "rb")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()
  local ok, data = decode_object(content)
  return (ok and type(data) == "table") and data or nil
end

local function write_locale_file(name, data)
  local dir = locale_dir()
  if not dir then
    return false
  end
  if not is_dir(dir) then
    mkdir_p(dir)
  end
  local file = io.open(dir .. slash .. name, "wb")
  if not file then
    return false
  end
  file:write(json.encode(data))
  file:close()
  return true
end

-- GET a file of the repository's locale folder. https, no headers: this is
-- the one kind of request vlc.stream is good at. Returns the decoded JSON
-- object, or nil.
local function fetch_locale_file(name)
  local client = Curl.new()
  client:set_raw(true)
  client:set_timeout(15)
  client:set_retries(0)
  local res = client:get(locale_url() .. name)
  if not res or res.status ~= 200 or not res.body then
    return nil
  end
  -- a translation is a few kilobytes; refuse anything absurd
  if #res.body > 200000 then
    return nil
  end
  local ok, data = decode_object(res.body)
  return (ok and type(data) == "table") and data or nil
end

-- Languages that may be offered: { {code, name}, ... } from the stored
-- index. Only reviewed ("ready") translations, unless the config file has
-- "translationPreview": true (for people reviewing a translation).
function available_interface_languages()
  local index = read_locale_file("index.json")
  local languages = {}
  if index and type(index.languages) == "table" then
    for _, language in ipairs(index.languages) do
      if type(language) == "table" and type(language.code) == "string"
         and string.match(language.code, "^[a-z][a-z%-]+$")
         and type(language.name) == "string" and language.name ~= ""
         and #language.name <= 40 and not string.find(language.name, "[<>&]") then
        if language.status == "ready" then
          table.insert(languages, { language.code, language.name })
        elseif openSub.option.translationPreview == true then
          table.insert(languages, { language.code,
            language.name .. " " .. english().ui_translation_unreviewed })
        end
      end
    end
  end
  return languages
end

-- The language code the interface should be in, or nil for English.
-- "auto" follows the language detected on first run (the same detection
-- that picks the subtitle languages).
function wanted_interface_language()
  local choice = openSub.option.interfaceLanguage
  if choice == "auto" then
    choice = openSub.option.detectedLanguage or openSub.option.language
  end
  if not choice or choice == "" or choice == "en" then
    return nil
  end
  if not string.match(choice, "^[a-z][a-z%-]+$") then
    return nil
  end
  return choice
end

local function is_offered(code)
  for _, language in ipairs(available_interface_languages()) do
    if language[1] == code then
      return true
    end
  end
  return false
end

-- Use the stored translation for the wanted language, if there is one.
-- No network. Returns true when the interface is in the wanted language
-- (which includes "English wanted").
function load_interface_language()
  local code = wanted_interface_language()
  if not code then
    apply_interface_strings(nil)
    return true
  end
  local stored = read_locale_file(code .. ".json")
  if stored and type(stored.strings) == "table" and is_offered(code) then
    apply_interface_strings(stored.strings)
    return true
  end
  apply_interface_strings(nil)
  return false
end

-- Download the list of languages and, if one is wanted and offered, its
-- translation; store both. One or two small https requests. Returns true
-- when the wanted language is available afterwards.
function refresh_interface_language()
  local index = fetch_locale_file("index.json")
  if index and type(index.languages) == "table" then
    index.fetched = os.time()
    write_locale_file("index.json", index)
  end

  local code = wanted_interface_language()
  if code and is_offered(code) then
    local translation = fetch_locale_file(code .. ".json")
    if translation then
      write_locale_file(code .. ".json", { fetched = os.time(), version = app_version, strings = translation })
    end
    local count = 0
    for _ in pairs(translation or {}) do count = count + 1 end
    vlc.msg.info("[VLSub] Interface translation '" .. code .. "': "
      .. (translation and (count .. " texts fetched") or "could not be fetched, the stored one stays"))
  end
  return load_interface_language()
end

-- True when the stored list of languages is older than a week (or absent).
-- Returns: older than a week; must be fetched right away. The second is
-- true when there is no list at all, and when the translation in use was
-- stored by another version of the extension: a new version brings new
-- texts, which would stay English for up to a week otherwise (seen after the
-- update to 2.0: the AI texts in English inside a Slovak window).
function interface_language_is_stale()
  local index = read_locale_file("index.json")
  local fetched = index and tonumber(index.fetched) or 0
  local now = fetched == 0
  local code = wanted_interface_language()
  if code and not now then
    local stored = read_locale_file(code .. ".json")
    now = stored ~= nil and stored.version ~= app_version
  end
  return (os.time() - fetched) > LOCALE_REFRESH_SECONDS, now
end

function check_config()
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
    dbg("Working directory: " ..
      (openSub.conf.dirPath or "not found"))

    openSub.conf.filePath = openSub.conf.dirPath..filePath

    if config_saved
    and file_exist(openSub.conf.filePath) then
      dbg("Loading config file: "..openSub.conf.filePath)
      load_config()
    else
      dbg("No config file")
      getenv_lang()
      config_saved = save_config()
      if not config_saved then
        dbg("Unable to save config")
      end
    end

  else
    dbg("Unable to find a suitable path"..
      "to save config, please set it manually")
  end

  lang = nil
  lang = strings -- just a short cut

  if not vlc.net or not vlc.net.poll then
    dlg = new_dialog(
      openSub.conf.useragent..': '..lang["mess_error"])
    interface_no_support()
    dlg:show()
    return false
  end

  SetDownloadBehaviours()
  if not openSub.conf.dirPath then
    setError(lang["mess_err_conf_access"])
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
  local readable, option = decode_object(resp)
  if not readable then
    vlc.msg.warn("[VLSub] The config file is not readable; using the default settings")
    return false
  end

  -- Written by versions up to 1.3.2, which had an (unreachable) interface
  -- translation feature. Accepted in old files and ignored.
  local obsolete = {
    translation = true, translations_avail = true, intLang = true, debugLogging = true,
    -- settings no code reads any more
    showMediaInformation = true, requestTimeoutMs = true, requestPollIntervalMs = true,
    requestMaxRetries = true
  }

  for key, value in pairs(option) do
    if obsolete[key] then
      -- skipped
    elseif type(value) == "table" then
      openSub.option[key] = value
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

function getenv_lang()
  local os_lang = os.getenv("LANG")

  if os_lang then -- unix, mac
    -- "pt_BR.UTF-8" -> pt, br. Yields nothing for "C" / "POSIX".
    local language, country = parse_locale_string(os_lang)
    if language then
      -- Languages the API only knows with a region (there is no plain "pt"/"zh")
      local regional = {
        ["pt-br"] = true, ["pt-pt"] = true,
        ["zh-cn"] = true, ["zh-tw"] = true,
        ["az-az"] = true
      }
      local with_region = country and (language .. "-" .. country) or nil
      if with_region and regional[with_region] then
        openSub.option.language = with_region
      else
        openSub.option.language = map_to_opensubtitles_language(language)
      end
    end
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

-- Modified apply_config function to always save configuration settings
function apply_config()
  local language_before = openSub.option.interfaceLanguage
  local language_changed, language_missing = false, nil

  -- Last step: say so if the chosen interface language could not be fetched
  local function finish()
    if language_missing then
      local message = input_table["message"] and input_table["message"]:get_text() or ""
      setMessage(error_tag(tr("ui_translation_not_available", language_missing)) .. "<br>" .. message)
    end
  end
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

  -- Save boolean options (these should always be saved regardless of login status)
  if input_table["langExt"]:get_value() == 2 then
    openSub.option.langExt = not openSub.option.langExt
  end

  if input_table["removeTag"]:get_value() == 2 then
    openSub.option.removeTag = not openSub.option.removeTag
  end


  -- Handle working directory path
  local dir_path = input_table['dir_path']:get_text()
  local dir_path_err = false
  if trim(dir_path) == "" then dir_path = nil end

  if dir_path ~= openSub.conf.dirPath then
    if openSub.conf.os == "lin"
    or is_win_safe(dir_path)
    or not dir_path then
      local other_dirs = {}

      for path_value in
      vlc.config.get(
        "sub-autodetect-path"):gmatch("[^,]+"
      ) do
        local path = path_value -- loop variables are read-only in Lua 5.5
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
      else
        openSub.conf.filePath = nil
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

  -- ALWAYS SAVE CONFIGURATION FIRST (regardless of login status)
  local config_saved = false
  if openSub.conf.dirPath and not dir_path_err then
    config_saved = save_config()
    if not config_saved then
      setError(lang["mess_err_conf_access"])
      return -- Exit if we can't save config
    end
  else
    setError(lang["mess_err_conf_access"])
    return
  end

  -- A different interface language: fetch its translation now (the one
  -- moment a download is expected by the user)
  language_changed = (openSub.option.interfaceLanguage or "en") ~= (language_before or "en")
  if language_changed and not refresh_interface_language() then
    language_missing = wanted_interface_language()
  end
  if language_changed then
    -- Rebuild the window in the new language NOW, before this click has
    -- written anything to the old window; every message below goes to the
    -- new one. Order matters on macOS: VLC there renders label text through
    -- a slow helper process, and deleting a window while an update of one of
    -- its labels is still on its way took VLC down (seen with 3.0.24).
    trigger_menu(2)
  end


  -- NOW HANDLE LOGIN VALIDATION (after config is saved)
  -- Check if we have credentials for login test
  if username == "" or password == "" then
    -- No credentials provided - still show success for saved settings
    setMessage(success_tag(strings.ui_configuration_saved_please_enter_opensubtitles_c))
    is_authenticated = false
    return finish()
  end

  -- We have credentials, test login
  setMessage(loading_tag(strings.ui_testing_login_credentials))

  -- Clear any existing session to force fresh login for verification
  openSub.session.token = ""
  openSub.session.token_expires = 0
  openSub.session.user_info = nil

  local login_success = openSub.checkLoginAndUserInfo()

  if login_success then
    is_authenticated = true
    -- Keep the successful message that was set by checkLoginAndUserInfo
    local current_message = input_table["message"]:get_text()
    if current_message and string.find(current_message, strings.mess_success, 1, true) then
      -- the account line, completed with the AI credit balance
      local credits = ai_credits()
      if credits then
        current_message = current_message .. "<br>" .. tr("ui_ai_credits_balance", tostring(credits))
      end
      setMessage(current_message .. strings.ui_configuration_saved_you_can_now_close_this)
    else
      setMessage(success_tag(strings.ui_configuration_saved_and_login_successful_you_can))
    end

    -- Refresh the interface to show the enabled close button
    if dlg then
      dlg:update()
    end
  else
    -- Login failed, but config was still saved
    is_authenticated = false
    local current_message = input_table["message"]:get_text()

    -- Check if there's already an error message from the login attempt
    if current_message and (string.find(current_message, strings.mess_error, 1, true) or string.find(current_message, "failed")) then
      -- Append config saved notice to existing error message
      setMessage(current_message .. strings.ui_note_other_configuration_settings_were_saved_suc)
    else
      -- Generic login failure message with config saved notice
      setMessage(error_tag(strings.ui_login_failed_please_check_your_credentials_other))
    end

    dbg("Login failed but configuration was saved")
  end

  finish()
end


-- Make a file readable and writable by its owner only (Unix, macOS).
--
-- vlsub_conf.json holds the OpenSubtitles.com password and session_cache.json
-- the session token. VLC's Lua offers no keychain and no cryptography, so they
-- cannot be encrypted in a meaningful way; what can be done is to keep other
-- local users from reading them (files are created world-readable by default).
-- On Windows the user profile directory is already private to the user.
function restrict_to_owner(path)
  if not path or openSub.conf.os == "win" then
    return
  end
  local quoted = "'" .. string.gsub(path, "'", "'\\''") .. "'"
  pcall(os.execute, "chmod 600 " .. quoted .. " >/dev/null 2>&1")
end

function save_config()
-- Dump local config into config file
  if openSub.conf.dirPath
  and openSub.conf.filePath then
    dbg("Saving config file:  "..
      openSub.conf.filePath)

    if file_touch(openSub.conf.filePath) then
      restrict_to_owner(openSub.conf.filePath) -- before the password is written
      local tmpFile = assert(
        io.open(openSub.conf.filePath, "wb"))
        local resp = json.encode (openSub.option, { indent = true })
      tmpFile:write(resp)
      tmpFile:flush()
      tmpFile:close()
    else
      return false
    end
    collectgarbage()
    return true
  else
    dbg("Unable fount a suitable path "..
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

            --[[ Core ]]--

openSub = {
  itemStore = nil,
  actionLabel = "",
  lastSearchMethod = "",
  conf = {
    userAgentHTTP = app_useragent,
    useragent = app_useragent,
    downloadBehaviours = nil,
    languages = sub_languages,
    sortByOptions = subtitle_sort_by_options,
    sortDirectionOptions = subtitle_sort_direction_options
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
    imdbId = "",
    sublanguageid = ""
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
    file.last_guessit_filename = nil; -- Clear cached filename
  else
    dbg("Video URI: "..item:uri())
    local parsed_uri = vlc.net.url_parse(item:uri())
    file.uri = item:uri()
    file.protocol = parsed_uri["protocol"]
    file.path = parsed_uri["path"]

    -- Corrections

    -- Windows UNC / SMB share: file://host/share/path → //host/share/path
    -- Preserves hostname so save-with-video works on network drives (#32).
    -- Forward slashes used throughout this file; Windows accepts //server/share
    -- as an alias for \\server\share in io.open.
    local uri_host = parsed_uri["host"]
    if uri_host and uri_host ~= "" and uri_host ~= "localhost"
    and (file.protocol == "file" or file.protocol == "smb"
      or file.protocol == "cifs" or file.protocol == "nfs") then
      local path_for_host = file.path or ""
      if path_for_host:sub(1, 1) ~= "/" then
        path_for_host = "/" .. path_for_host
      end
      file.path = "//" .. uri_host .. path_for_host
      dbg("UNC/network path reconstructed: " .. file.path)
    end

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


-- Call GuessIt API when we have a valid filename (only if not already cached)
if file.completeName and file.completeName ~= "" then
  -- Ask GuessIt once per file. A lookup that failed is remembered too, and
  -- only repeated after a minute: getFileInfo() runs on every search, download
  -- and media change, and each retry blocks VLC's interface.
  local same_file = openSub.file.last_guessit_filename == file.completeName
  local needs_guessit
  if not same_file then
    needs_guessit = true
  elseif openSub.file.guessit_data then
    needs_guessit = false
  else
    needs_guessit = (os.time() - (openSub.file.guessit_failed_at or 0)) > 60
  end

  if needs_guessit then
    openSub.file.guessit_data = nil -- never keep the previous file's answer
    openSub.file.last_guessit_filename = file.completeName
    if openSub.callGuessIt(file.completeName) then
      openSub.file.guessit_failed_at = nil
    else
      openSub.file.guessit_failed_at = os.time()
    end
  end
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

    dbg("Using GuessIt data - Title: " .. (openSub.movie.title or "none") ..
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
    -- Year: the last stand-alone 4-digit number that is a plausible release
    -- year. "1080p", "2160p" and longer digit runs are not years.
    local yearMatch = nil
    for before, digits, after in string.gmatch(" " .. infoString .. " ", "(.)(%d%d%d%d)(.)") do
      local year = tonumber(digits)
      if not string.match(before, "%d") and not string.match(after, "[%dpPiI]")
         and year >= 1900 and year <= 2100 then
        yearMatch = digits
      end
    end
    if yearMatch then
      openSub.movie.year = yearMatch
    else
      openSub.movie.year = ""
    end

    dbg("Using fallback parsing - Title: " .. (openSub.movie.title or "none") ..
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
    setError(strings.ui_hash_search_only_works_with_local_video)
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

    local file = vlc.stream(openSub.file.uri)
    if not file then
      dbg("Cannot open stream for archive")
      setError(strings.ui_cannot_open_archive_stream_for_hashing)
      return false
    end

    local dataTmp1 = ""
    local dataTmp2 = ""
    size = chunk_size

    data_start = file:read(chunk_size)
    if not data_start then
      dbg("Cannot read start data from archive stream")
      setError(strings.ui_cannot_read_archive_data_for_hashing)
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
    dbg("File doesn't exist but has stat - this shouldn't happen with safety checks")
    setError(strings.ui_file_not_accessible_for_hashing)
    return false
  else
    local file = io.open(openSub.file.path, "rb")
    if not file then
      dbg("Cannot open local file")
      setError(strings.ui_cannot_open_local_file_for_hashing)
      return false
    end

    data_start = file:read(chunk_size)
    if not data_start then
      file:close()
      setError(strings.ui_cannot_read_file_data_for_hashing)
      return false
    end

    size = file:seek("end", -chunk_size)
    if not size then
      file:close()
      setError(strings.ui_cannot_seek_in_file_for_hashing)
      return false
    end
    size = size + chunk_size

    data_end = file:read(chunk_size)
    if not data_end then
      file:close()
      setError(strings.ui_cannot_read_end_data_for_hashing)
      return false
    end

    file:close()
  end

  -- Validate we have the data we need
  if not data_start or not data_end or #data_start == 0 or #data_end == 0 then
    setError(strings.ui_insufficient_data_for_hash_calculation)
    return false
  end

  -- Hash calculation
  local lo = size
  local hi = 0
  local a,b,c,d,e,f,g,h
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
  dbg("Video hash: "..openSub.file.hash)
  dbg("Video bytesize: "..size)
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
}

-- openSub.itemStore holds a non-empty result list
function has_results()
  local store = openSub.itemStore
  return type(store) == "table" and #store > 0
end

-- openSub.itemStore holds no results at all: nil, "0", 0 or an empty list
-- (the searches use different markers for "nothing found")
function has_no_results()
  local store = openSub.itemStore
  return not store or store == "0" or store == 0
      or (type(store) == "table" and #store == 0)
end

-- Hash search cannot be used or found nothing: get ready to search by name.
-- The title comes from the file name or, failing that, from the title field.
-- Returns true when there is a title to search for.
local function prepare_name_fallback()
  openSub.lastSearchMethod = "hash_fallback"
  openSub.getMovieInfo()

  if not openSub.movie.title or openSub.movie.title == "" then
    if input_table["title"] and input_table["title"]:get_text() then
      openSub.movie.title = trim(input_table["title"]:get_text())
    end
  end
  return openSub.movie.title and openSub.movie.title ~= ""
end

-- "Search by hash" button. Falls back to a name search when the media cannot
-- be hashed, when hashing fails, or when the hash is unknown to the API.
function searchHash()
  openSub.lastSearchMethod = "hash"
  openSub.getFileInfo()

  local function name_search(refresh_window)
    if refresh_window then
      openSub.movie.sublanguageid = getSelectedLanguages()
      if input_table["title"] then
        input_table["title"]:set_text(openSub.movie.title)
      end
    end
    openSub.checkSession()
    openSub.searchSubtitlesNewAPI()
  end

  -- Streams and other non-local media cannot be hashed
  if not openSub.isLocalFileForHashing() then
    dbg("File not suitable for hash search, falling back to name search")
    if prepare_name_fallback() then
      name_search(true)
    else
      dbg("Cannot perform search: no local file for hashing and no title for name search")
      openSub.itemStore = {}
      setError(strings.ui_hash_search_requires_local_files_please_enter)
    end
    display_subtitles()
    return
  end

  openSub.movie.sublanguageid = getSelectedLanguages()

  if not openSub.getMovieHash() then
    dbg("Hash calculation failed, attempting name search fallback")
    if prepare_name_fallback() then
      name_search(false)
    else
      openSub.itemStore = {}
      setError(strings.ui_hash_calculation_failed_and_no_title_available)
    end
    display_subtitles()
    return
  end

  openSub.checkSession()
  openSub.searchSubtitlesByHashNewAPI()

  if has_no_results() then
    dbg("Hash search returned 0 results, falling back to name search")
    if prepare_name_fallback() then
      openSub.itemStore = nil
      name_search(true)
    else
      dbg("Cannot perform name search fallback: no title available")
    end
  end

  display_subtitles()
end



-- Extract IMDB ID from various input formats
function extractIMDBId(input)
  if not input or input == "" then
    return nil
  end

  -- Trim whitespace
  input = trim(input)

  -- Match tt1234567 or 1234567 format
  -- Accepts: tt1234567, 1234567
  local numericMatch = string.match(input, "^tt?(%d+)$") or string.match(input, "^(%d+)$")
  if numericMatch then
    -- Return WITHOUT tt prefix - API expects numeric ID only
    return numericMatch
  end

  -- Match full IMDB URL formats:
  -- https://www.imdb.com/title/tt1234567/
  -- www.imdb.com/title/tt1234567/
  -- http://imdb.com/title/tt1234567
  -- imdb.com/title/tt1234567/
  local urlMatch = string.match(input, "/title/(tt%d+)")
  if urlMatch then
    -- Strip the "tt" prefix and return just the numeric ID
    return string.sub(urlMatch, 3)
  end

  -- Return nil if no valid format found
  return nil
end


-- Enhanced searchIMBD_v2 function with all-languages fallback
function searchIMBD_v2()
  -- Get IMDB ID from input field
  local imdbInput = trim(input_table["imdbId"]:get_text())

  -- If IMDB ID is provided, use IMDB search exclusively
  if imdbInput and imdbInput ~= "" then
    openSub.lastSearchMethod = "imdb"

    -- Extract IMDB ID from various formats
    local imdbId = extractIMDBId(imdbInput)

    if imdbId then
      openSub.movie.imdbId = imdbId

      -- Get selected languages
      openSub.movie.sublanguageid = getSelectedLanguages()

      -- Clear other search fields when using IMDB
      openSub.movie.title = ""
      openSub.movie.year = ""
      openSub.movie.seasonNumber = nil
      openSub.movie.episodeNumber = nil

      setMessage(loading_tag(strings.ui_searching_by_imdb_id))

      -- Perform IMDB-based search
      openSub.searchSubtitlesByIMDB(imdbId)

      display_subtitles()
      return
    else
      setMessage(error_tag(strings.ui_invalid_imdb_id_format))
      return
    end
  end

  -- No IMDB ID provided, use standard name search
  openSub.lastSearchMethod = "name" -- Track that this is a name search

  openSub.movie.title = trim(input_table["title"]:get_text())
  openSub.movie.year = trim(input_table["year"]:get_text())  -- Capture year from input
  openSub.movie.seasonNumber = tonumber(
    input_table["seasonNumber"]:get_text())
  openSub.movie.episodeNumber = tonumber(
    input_table["episodeNumber"]:get_text())
  openSub.movie.imdbId = nil  -- Clear IMDB ID for name searches


  openSub.movie.sublanguageid = getSelectedLanguages()

  if openSub.movie.title ~= "" then
    openSub.searchSubtitlesNewAPI()
    display_subtitles()
  end
end


-- Simplified GuessIt function with persistent disk caching
openSub.callGuessIt = function(filename)
  if not filename or filename == "" then
    dbg("GuessIt: No filename provided")
    return false
  end


  -- Check if we have a cached GuessIt result for this exact filename
  local cache_file = openSub.conf.dirPath .. slash .. "cache_guessit_" .. vlc.strings.encode_uri_component(filename) .. ".json"
  local cache_valid = false
  local cached_data = nil

  -- Try to read from cache
  if file_exist(cache_file) then
    local f = io.open(cache_file, "r")
    if f then
      local cache_content = f:read("*all")
      f:close()

      if cache_content and cache_content ~= "" then
        local ok, cache_json = decode_object(cache_content)
        if ok and cache_json and cache_json.timestamp then
          local cache_age = os.time() - cache_json.timestamp
          if cache_age < config.cache_guessit_duration_seconds then
            cache_valid = true
            cached_data = cache_json.data
            dbg("Using cached GuessIt data (age: " .. math.floor(cache_age / 3600) .. " hours)")
          else
            dbg("GuessIt cache expired (age: " .. math.floor(cache_age / 3600) .. " hours)")
          end
        end
      end
    end
  end

  -- Use cached data if valid
  if cache_valid and cached_data then
    openSub.file.guessit_data = cached_data
    return true
  end

  -- Prepare the GuessIt request
  local guessit_url = api_url("/utilities/guessit") .. "?filename=" .. vlc.strings.encode_uri_component(filename)

  -- Make the API request
  local client = Curl.new()
  client:add_header("Api-Key", api_key())

  -- Add Authorization header if user is logged in
  if openSub.session.token and openSub.session.token ~= "" then
    client:add_header("Authorization", "Bearer " .. openSub.session.token)
  end

  client:set_timeout(15)
  client:set_retries(1)

  local res = client:get(guessit_url)

  if not res then
    dbg("GuessIt: No response from API")
    return false
  end

  if res.status ~= 200 then
    local status = res.status or "N/A"
    dbg("GuessIt: API request failed with status: " .. tostring(status))
    return false
  end

  if not res.body then
    vlc.msg.err("[VLSub] GuessIt: Empty response body")
    return false
  end

  -- Parse the GuessIt response
  local ok, guessit_response = decode_object(res.body)
  if not ok or not guessit_response then
    vlc.msg.err("[VLSub] GuessIt: Failed to parse response: " .. (res.body or "no body"))
    return false
  end

  -- Store the GuessIt data in memory
  openSub.file.guessit_data = guessit_response

  -- Save to disk cache
  local cache_data = {
    timestamp = os.time(),
    filename = filename,
    data = guessit_response
  }

  local f = io.open(cache_file, "w")
  if f then
    f:write(json.encode(cache_data))
    f:close()
  else
    dbg("Failed to save GuessIt cache to disk")
  end

  -- Simple debug output - just the raw JSON response

  return true
end


function add_sub(subPath)
  if vlc.item or vlc.input.item() then
    subPath = decode_uri(subPath)
    vlc.var.set(vlc.object.input(), 'sub-file', subPath)

    -- This is the key fix - use the same method as your working script
    local success = vlc.input.add_subtitle(subPath, true)

    if success then
      -- Force enable subtitles like your working script does
      vlc.var.set(vlc.object.input(), "spu", true)
      dbg("Subtitle loaded and enabled successfully")
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

-- The API never redirects, so a redirect reaching the caller means something
-- on the network rewrote the plain-HTTP request: captive portal, ISP or
-- corporate proxy, content filter, or a VPN/antivirus web shield.
-- 310 is the internal sentinel for "redirect limit reached".
-- Text shown under the result list when a search request failed.
function api_error_message(status)
  if status == 429 then
    return strings.ui_too_many_requests_429
  elseif status == 401 then
    return strings.ui_authentication_failed_401_check_configuration
  elseif status == 403 then
    return strings.ui_access_forbidden_403
  elseif status and status >= 500 and status <= 599 then
    return tr("ui_server_error_try_again_later", tostring(status))
  end
  return network_redirect_message(status)
end

function network_redirect_message(status)
  if status == 301 or status == 302 or status == 303
  or status == 307 or status == 308 or status == 310 then
    return tr("ui_network_is_redirecting", tostring(status))
  end
  return nil
end

function loading_tag(str)
  return "<span style='color:#6c757d;font-weight:bold;'>"..
    strings.ui_loading..":</span> "..str..""
end


            --[[ Network utils]]--

function parse_url(url)
	local url_parsed = vlc.net.url_parse(url)
	return url_parsed["host"],
		url_parsed["path"],
		url_parsed["option"],
		url_parsed["scheme"] or url_parsed["protocol"],
		tonumber(url_parsed["port"]) -- 0 (or nil) when the URL names none
end


            --[[ XML utils]]--

            --[[ Misc utils]]--

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


-- 4. FIXED: mkdir_p function - use VLC built-in directory operations
function mkdir_p(path)
  if not path or trim(path) == "" then
    return false
  end

  -- VLC Lua has vlc.net.mkdir() function (available in some VLC versions)
  -- Try VLC built-in first, fallback to safe OS commands if needed

  -- Method 1: Try VLC's built-in mkdir (if available)
  if vlc.net and vlc.net.mkdir then
    local success = vlc.net.mkdir(path)
    if success then
      return true
    end
  end

  -- Method 2: Create parent directories recursively using VLC's file operations
  local path_parts = {}
  local current_path = ""

  -- Split path into components
  if openSub.conf.os == "win" then
    -- Windows path: C:\Users\Name\AppData\...
    for part in string.gmatch(path, "([^\\]+)") do
      table.insert(path_parts, part)
    end
    -- Reconstruct path step by step
    for i, part in ipairs(path_parts) do
      if i == 1 then
        current_path = part  -- C:
      else
        current_path = current_path .. "\\" .. part
      end

      -- Try to create each directory level
      if i > 1 and not is_dir(current_path) then
        -- Use VLC's file touch to test if we can create files (implies directory creation capability)
        local test_file = current_path .. "\\vlc_test_create.tmp"
        if file_touch(test_file) then
          os.remove(test_file)  -- Clean up test file
        end
      end
    end
  else
    -- Unix/Linux path: /home/user/.local/...
    for part in string.gmatch(path, "([^/]+)") do
      table.insert(path_parts, part)
    end
    current_path = ""
    for i, part in ipairs(path_parts) do
      current_path = current_path .. "/" .. part
      if not is_dir(current_path) then
        -- Similar test for Unix
        local test_file = current_path .. "/vlc_test_create.tmp"
        if file_touch(test_file) then
          os.remove(test_file)
        end
      end
    end
  end

  -- Method 3: Fallback to silent OS commands only if VLC methods fail
  if not is_dir(path) then
    if openSub.conf.os == "win" then
      os.execute('mkdir "' .. path .. '" >nul 2>&1')
    else
      os.execute("mkdir -p '" .. path .. "' >/dev/null 2>&1")
    end
  end

  return is_dir(path)
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
-- NOTE: This function has been moved to line 7792 with performance optimizations including:
-- - Alphabetically sorted URL parameters
-- - Lowercase parameter names and values
-- - Cleaned IMDB IDs (removed 'tt' prefix and leading zeros)
-- - Filtered default parameter values
-- - Using '+' instead of '%20' for URL encoding


-- Convert the new API response format to the old XML-RPC format for compatibility
-- Enhanced buildSubtitleDisplayText function with upload date


openSub.convertNewAPIResponse = function(newData)
  local convertedData = {}

  -- "AI translations: No": should the server send one anyway, it is not listed
  local no_ai = openSub.option.aiTranslations == false
  for i, item in ipairs(newData) do
    if item.type == "subtitle" and item.attributes
       and not (no_ai and item.attributes.ai_translated == true) then
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
        -- A translation that does not exist yet: the API makes it when it is
        -- downloaded, paid with the account's AI credits. Its ids are strings
        -- of 33 digits (ordinary ids are numbers) and must stay strings: a
        -- Lua number cannot hold them.
        OnDemand = (type(firstFile.file_id) == "string" and #firstFile.file_id > 10)
          or (type(attr.comments) == "string"
              and string.find(string.lower(attr.comments), "will be created on demand", 1, true) ~= nil),
        -- "... as AI translation from czech language." -> "Czech"
        OnDemandFrom = (function()
          local from = type(attr.comments) == "string"
            and string.match(attr.comments, "AI translation from (%a[%a %-]-) language")
          return from and (string.upper(string.sub(from, 1, 1)) .. string.sub(from, 2)) or nil
        end)(),
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
        -- the film this subtitle belongs to (an upload for the same video
        -- goes there too)
        convertedItem.FeatureID = tonumber(details.feature_id)
        convertedItem.FeatureTitle = details.title or details.movie_name
        convertedItem.FeatureYear = tonumber(details.year)
        convertedItem.SeriesSeason = tostring(details.season_number or "")
        convertedItem.SeriesEpisode = tostring(details.episode_number or "")
        convertedItem.SeriesIMDBParent = tostring(details.parent_imdb_id or "")
      end

      -- For the new API, we need to construct download URLs
      -- The download will be handled differently in the download function
      convertedItem.ZipDownloadLink = api_url("/download")
      convertedItem.SubDownloadLink = convertedItem.ZipDownloadLink

      table.insert(convertedData, convertedItem)
    end
  end

  return convertedData
end


-- Simplified loginWithRestAPI function (now that HTTP client handles response cleaning)
openSub.loginWithRestAPI = function()
  openSub.actionLabel = lang["action_login"]

  -- Check cached token first
  if openSub.session.token ~= "" and openSub.session.token_expires > os.time() then
    dbg("Using cached token")
    return true
  end

  -- Check credentials
  if not openSub.option.os_username or not openSub.option.os_password or
     openSub.option.os_username == "" or openSub.option.os_password == "" then
    dbg("No credentials - using anonymous access")
    openSub.session.token = ""
    openSub.session.user_info = nil
    openSub.session.token_expires = 0
    return true
  end

  dbg("Attempting login for: " .. openSub.option.os_username)

  local login_data = {
    username = openSub.option.os_username,
    password = openSub.option.os_password
  }

  local request_body = json.encode(login_data)

  -- Use aggressive timeouts for login
  local client = Curl.new()
  client:set_aggressive_timeouts()
  client:add_header("Api-Key", api_key())
  client:add_header("Content-Type", "application/json")

  local res = client:post(api_url("/login"), request_body)

  if not res then
    vlc.msg.err("[VLSub] Login request failed - network timeout")
    setError(strings.ui_login_failed_network_timeout_or_no_internet)
    return false
  end

  if res.status ~= 200 then
    vlc.msg.err("[VLSub] Login failed with status: " .. res.status)
    local redirect_mess = network_redirect_message(res.status)
    if redirect_mess then
      setError(tr("ui_login_failed", redirect_mess))
      return false
    end
    if res.body then
      local ok, error_data = decode_object(res.body)
      if ok and error_data and error_data.message then
        setError(tr("ui_login_failed_2", tostring(error_data.message)))
      else
        setError(tr("ui_login_failed_with_status", tostring(res.status)))
      end
    else
      setError(strings.ui_login_failed_network_error)
    end
    return false
  end

  if not res.body then
    vlc.msg.err("[VLSub] Login response has no body")
    setError(strings.ui_login_failed_empty_response)
    return false
  end

  -- Mask token in logs for security
  -- Parse JSON response (body is now pre-cleaned by HTTP client)
  local ok, login_response = decode_object(res.body)
  if not ok or not login_response then
    vlc.msg.err("[VLSub] Failed to parse login response")
    setError(strings.ui_login_failed_invalid_response_format)
    return false
  end

  if login_response.status and login_response.status ~= 200 then
    vlc.msg.err("[VLSub] Login failed, API status: " .. (login_response.status or "unknown"))
    setError(tr("ui_login_failed_2", tostring(login_response.message
      or tr("ui_status_2", tostring(login_response.status or strings.ui_unknown)))))
    return false
  end

  if not login_response.token then
    vlc.msg.err("[VLSub] No token in login response")
    setError(strings.ui_login_failed_no_authentication_token_received)
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

  dbg("Login successful")
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
    restrict_to_owner(cache_file_path) -- before the token is written
    local cache_file = io.open(cache_file_path, "wb")
    if cache_file then
      local cache_content = json.encode(session_data, { indent = true })
      cache_file:write(cache_content)
      cache_file:flush()
      cache_file:close()
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

  local ok, session_data = decode_object(cache_content)
  if not ok or not session_data then
    dbg("Failed to parse session cache")
    return false
  end

  -- Validate cache data
  if not session_data.token or not session_data.token_expires then
    dbg("Invalid session cache data")
    return false
  end

  -- Check if token is still valid
  if session_data.token_expires <= os.time() then
    dbg("Cached token expired")
    return false
  end

  -- Check if username matches (to handle account switching)
  if session_data.username ~= openSub.option.os_username then
    dbg("Cached session for different user")
    return false
  end

  -- Load cached session
  openSub.session.token = session_data.token
  openSub.session.user_info = session_data.user_info
  openSub.session.token_expires = session_data.token_expires
  openSub.session.base_url = session_data.base_url or "api.opensubtitles.com"
  openSub.session.loginTime = session_data.loginTime or os.time()

  return true
end


-- The server rejected the current token (401). The cached session must be
-- dropped as well: checkSession() would otherwise load the same rejected
-- token straight back from session_cache.json.
-- Returns true only if a new token was obtained.
openSub.refreshSession = function()
  openSub.session.token = ""
  openSub.session.token_expires = 0
  if openSub.conf.dirPath then
    os.remove(openSub.conf.dirPath .. slash .. "session_cache.json")
  end
  return openSub.loginWithRestAPI() and openSub.session.token ~= ""
end

-- Log an error, show it in the window, and report failure.
local function report_failure(message)
  vlc.msg.err("[VLSub] " .. message)
  setMessage(error_tag(message))
  return false
end

-- File name for a downloaded subtitle: the video's name (or, without one,
-- the subtitle's own name, the searched title or the end of the stream URL),
-- made safe for every file system, plus ".<language>" and ".<format>".
-- The name the API gives a subtitle file, without what is added again when
-- it is saved: a subtitle extension, and a language tag at the very end
-- ("Movie.2020.eng", "Episode 5 - Breakage-eng", "film.en.srt"). Most names
-- from the API have no extension at all, so nothing may be cut blindly
-- ("...h264-poke" lost its "poke" when four characters always were).
local SUBTITLE_EXTENSIONS = { ".srt", ".sub", ".ass", ".ssa", ".vtt", ".smi", ".txt" }
-- (a literal table: nothing may run when the file is loaded)
local LANGUAGE_TAGS = {
  en = true, eng = true, fr = true, fre = true, fra = true, de = true, ger = true, deu = true,
  es = true, spa = true, it = true, ita = true, pt = true, por = true, pob = true, ru = true,
  rus = true, pl = true, pol = true, cs = true, cze = true, ces = true, sk = true, slo = true,
  slk = true, hu = true, hun = true, nl = true, dut = true, nld = true, el = true, gre = true,
  ell = true, tr = true, tur = true, ar = true, ara = true, he = true, heb = true, zh = true,
  chi = true, zho = true, ja = true, jpn = true, ko = true, kor = true, sv = true, swe = true,
  da = true, dan = true, fi = true, fin = true, no = true, nor = true, ro = true, rum = true,
  ron = true, bg = true, bul = true, hr = true, hrv = true, sr = true, srp = true, uk = true,
  ukr = true, vi = true, vie = true, th = true, tha = true, ["id"] = true, ind = true,
}

local function api_file_base_name(file_name, drop_language_tag)
  local name = file_name
  local lower = string.lower(name)
  for _, extension in ipairs(SUBTITLE_EXTENSIONS) do
    if #name > #extension and string.sub(lower, -#extension) == extension then
      name = string.sub(name, 1, #name - #extension)
      break
    end
  end
  if drop_language_tag then
    local tag = string.match(name, "[%.%-_](%a%a%a?)$")
    if tag and LANGUAGE_TAGS[string.lower(tag)] and #name > #tag + 1 then
      name = string.sub(name, 1, #name - #tag - 1)
    end
  end
  return name
end

local function subtitle_file_name(item)
  local name = "subtitle"
  if openSub.file.name and openSub.file.name ~= '' then
    name = openSub.file.name
  elseif item.SubFileName then
    -- the language code is added below when the option is on
    name = api_file_base_name(item.SubFileName, openSub.option.langExt)
  elseif openSub.movie.title and openSub.movie.title ~= "" then
    name = openSub.movie.title
  else
    local inputItem = openSub.getInputItem()
    local uriName = inputItem and vlc.strings.encode_uri_component(inputItem:uri())
    if uriName then
      name = string.sub(uriName, -64, -1)
    end
  end

  -- Stream URLs can carry long tokens and characters Windows forbids
  local original_length = #name
  name = sanitize_filename(name, 180)
  if original_length > 180 then
    dbg("Filename truncated from " .. original_length .. " to " .. #name .. " characters")
  end

  if openSub.option.langExt then
    name = name .. "." .. item.SubLanguageID
  end
  return name .. "." .. item.SubFormat
end

-- Where to save `file_name`: next to the video; without a video (or if that
-- folder is read-only) in the Downloads folder; last the VLSub folder.
-- Returns the path, the kind of place ("video", "downloads", "vlsub") and
-- whether it is the Downloads folder - or false after reporting that nothing
-- is writable.
local function choose_save_target(file_name)
  local target, place, in_downloads

  if openSub.file.hasInput and openSub.file.dir and is_dir(openSub.file.dir) then
    target, place, in_downloads = openSub.file.dir .. file_name, "video", false
  else
    local downloads_folder = get_downloads_folder()
    if downloads_folder then
      target, place, in_downloads = downloads_folder .. slash .. file_name, "downloads", true
    elseif openSub.conf.dirPath then
      target, place, in_downloads = openSub.conf.dirPath .. slash .. file_name, "vlsub", false
    else
      return report_failure(strings.ui_cannot_determine_save_location_for_subtitle_file)
    end
  end
  if file_touch(target) then
    return target, place, in_downloads
  end

  dbg("Cannot write to primary target, trying fallbacks...")
  if not in_downloads then
    local downloads_folder = get_downloads_folder()
    if downloads_folder then
      target, place, in_downloads = downloads_folder .. slash .. file_name, "downloads", true
      if file_touch(target) then
        return target, place, in_downloads
      end
      dbg("Downloads folder also not writable")
    end
  end

  if openSub.conf.dirPath then
    target = openSub.conf.dirPath .. slash .. file_name
    if file_touch(target) then
      return target, "vlsub", false
    end
    return report_failure(tr("ui_cannot_write_to_any_available_location", target))
  end
  return report_failure(strings.ui_cannot_write_subtitle_file_to_any_location)
end

-- Save the subtitle text and, when a video is playing, load it into the
-- player. Sets the success or error message. Returns true on success.
openSub.saveAndLoadSubtitle = function(subtitle_content, item)
  if not subtitle_content or subtitle_content == "" then
    return report_failure(strings.ui_empty_subtitle_content_received)
  end

  if openSub.option.removeTag then
    subtitle_content = remove_tag(subtitle_content)
  end

  local target, place, in_downloads = choose_save_target(subtitle_file_name(item))
  if not target then
    return false
  end
  dbg("Final save target: " .. target)

  local subfile = io.open(target, "wb")
  if not subfile then
    return report_failure(tr("ui_cannot_open_file_for_writing", target))
  end
  subfile:write(subtitle_content)
  subfile:flush()
  subfile:close()

  local message
  if openSub.file.hasInput and add_sub(target) then
    dbg("Subtitle loaded successfully into VLC")
    message = strings[({ video = "ui_loaded_with_video", downloads = "ui_loaded_in_downloads",
                         vlsub = "ui_loaded_in_vlsub" })[place]]
  elseif in_downloads then
    message = strings.ui_subtitles_saved_to_downloads
  else
    message = strings[({ video = "ui_saved_with_video", vlsub = "ui_saved_in_vlsub" })[place]]
  end
  setMessage(success_tag(message))
  return true
end


-- Enhanced download_subtitles_v2 function with better no-video handling
-- `not_by_click` is true when the download was not asked for by the Download
-- button (see subtitle_list_click_handler).
function download_subtitles_v2(not_by_click)
  -- Refresh file info to get current playing item's directory
  openSub.getFileInfo()

  if not has_results() then
    setMessage(error_tag(strings.ui_no_subtitles_available_for_download_please_searc))
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

  -- AI credits are spent by the Download button only, never by anything
  -- that starts a download by itself.
  if not_by_click == true and item and item.OnDemand then
    dbg("AI on-demand entry: not downloaded without a click on Download")
    setMessage("")
    return false
  end

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

  local success = openSub.downloadFromNewAPI(item)

  return success
end


-- Languages chosen in the three drop-downs of the main window, in that
-- order, without duplicates. "All" / "None" (id 0) contribute nothing.
function getUserSelectedLanguages()
  local languages = {}

  for position, widget_id in ipairs({ "language", "language2", "language3" }) do
    local widget = input_table[widget_id]
    -- the first drop-down always exists in the main window; the others may not
    if position == 1 or widget then
      local selected = widget:get_value()
      local entry = selected > 0 and openSub.conf.languages[selected]
      if entry then
        local already_listed = false
        for _, code in ipairs(languages) do
          if code == entry[1] then
            already_listed = true
            break
          end
        end
        if not already_listed then
          table.insert(languages, entry[1])
        end
      end
    end
  end

  return languages
end

-- The same selection as the API wants it: sorted, comma separated, or 'all'
function getSelectedLanguages()
  local languages = getUserSelectedLanguages()
  table.sort(languages)

  local result = (#languages == 0) and 'all' or table.concat(languages, ',')
  dbg("Final language string: " .. result)
  return result
end

-- Read /subtitles sorting options from main-window controls.
function applySubtitleSortingSelection()
  local sort_by_options = openSub.conf.sortByOptions or {}
  local sort_dir_options = openSub.conf.sortDirectionOptions or {}

  local sort_by_value = input_table["sort_by"] and input_table["sort_by"]:get_value() or 0
  if sort_by_value > 0 and sort_by_options[sort_by_value] then
    openSub.option.sortBy = sort_by_options[sort_by_value][1]
  else
    openSub.option.sortBy = nil
  end

  local sort_dir_value = input_table["sort_direction"] and input_table["sort_direction"]:get_value() or 0
  if sort_dir_value > 0 and sort_dir_options[sort_dir_value] then
    openSub.option.sortDirection = sort_dir_options[sort_dir_value][1]
  elseif not openSub.option.sortDirection or openSub.option.sortDirection == "" then
    openSub.option.sortDirection = "desc"
  end

  -- Direction is meaningful only if order_by is provided.
  if not openSub.option.sortBy then
    openSub.option.sortDirection = "desc"
  end
end

-- Also add this debug function to check what languages are available



-- New function to search by hash using REST API
-- NOTE: This function has been moved to line 7767 with performance optimizations including:
-- - Alphabetically sorted URL parameters
-- - Lowercase parameter names and values
-- - Cleaned IMDB IDs (removed 'tt' prefix and leading zeros)
-- - Filtered default parameter values
-- - Using '+' instead of '%20' for URL encoding

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
    dbg("Double-click detected on item " .. selected_item .. ", triggering download")
    download_subtitles_v2(true)

    -- Reset to prevent triple-click issues
    last_click_time = 0
    last_click_item = 0
  else
    -- Single click - just update tracking
    last_click_time = current_time
    last_click_item = selected_item
  end
end


-- Refresh the main window fields after VLC switched to another media item.
-- Does nothing when the item is unchanged, so text typed by the user is kept.
function set_interface_main()
  if not dlg or not input_table or not input_table["title"] then
    return
  end

  local item = openSub.getInputItem()
  if not item then
    return
  end

  local previous_uri = openSub.file.uri
  openSub.getFileInfo()
  if openSub.file.uri == previous_uri then
    return
  end
  openSub.getMovieInfo()

  local fields = {
    title = openSub.movie.title,
    seasonNumber = openSub.movie.seasonNumber,
    episodeNumber = openSub.movie.episodeNumber,
    year = openSub.movie.year,
    imdbId = openSub.movie.imdbId
  }
  for name, value in pairs(fields) do
    if input_table[name] then
      input_table[name]:set_text(value or "")
    end
  end
  dlg:update()
end

function input_changed()
  collectgarbage()

  -- Only update interface if not in config mode, or preserve messages in config mode
  -- NOTE: VLC dialogs have set_title() but no get_title(); the open window is
  -- tracked in current_window_id instead.
  if dlg and current_window_id == 2 then
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

            --[[ Download ]]--

-- status -> key of the message in the strings table
local DOWNLOAD_STATUS_MESSAGE = {
  [403] = "ui_access_forbidden_403_insufficient_permissions",
  [404] = "ui_subtitle_not_found_404_file_may_have",
  [429] = "ui_too_many_requests_429_please_wait_and",
  [500] = "ui_server_error_500_please_try_again_later",
  [503] = "ui_service_unavailable_503_server_overloaded",
}

-- "Quota: 3/20 downloads, reset in: 5 hours" from the fields of a /download
-- answer; "" when the answer carried none of them.
local function quota_text(used, remaining, reset_time)
  local counted = used ~= nil and remaining ~= nil
  if counted and reset_time then
    return tr("ui_quota_downloads_reset", tostring(used), tostring(used + remaining), reset_time)
  elseif counted then
    return tr("ui_quota_downloads", tostring(used), tostring(used + remaining))
  elseif reset_time then
    return tr("ui_quota_reset_in", reset_time)
  end
  return ""
end

-- Fetch the subtitle a /download answer points to. Returns the content, or
-- false after reporting why there is none.
local function fetch_subtitle(link)
  local client = Curl.new()
  client:set_timeout(60)
  client:set_retries(3)
  client:set_raw(true) -- subtitle text must reach the file byte for byte

  local res = client:get(link)
  if not res then
    return report_failure(strings.ui_failed_to_download_from_provided_link)
  elseif res.status ~= 200 then
    return report_failure(tr("ui_failed_to_download_subtitle_http", tostring(res.status)))
  elseif not res.body then
    return report_failure(strings.ui_empty_subtitle_content_downloaded)
  end
  return res.body
end

            --[[ Upload: MD5, base64, deflate container ]]--

-- The upload API wants the file's MD5 and the file itself as base64 of a
-- deflate stream. VLC's Lua has none of the three, and on Lua 5.1 (VLC for
-- macOS) not even bit operations. Everything below is plain Lua; nothing
-- runs until an upload is made.

-- 32-bit AND / OR / XOR: the language's own operators where they exist
-- (compiled from text, so that this file still parses on Lua 5.1),
-- bit32 on Lua 5.2, else byte tables built on first use.
local bit_ops_cache
local function bit_ops()
  if bit_ops_cache then
    return bit_ops_cache
  end
  local compile = loadstring or load
  local native = compile and compile(
    "return function(a, b) return a & b end, function(a, b) return a | b end, function(a, b) return a ~ b end")
  if native then
    local band, bor, bxor = native()
    bit_ops_cache = { band = band, bor = bor, bxor = bxor }
  elseif type(bit32) == "table" then
    bit_ops_cache = { band = bit32.band, bor = bit32.bor, bxor = bit32.bxor }
  else
    -- 256 x 256 tables of the byte-wise result, then four look-ups per word
    local and_t, or_t, xor_t = {}, {}, {}
    for a = 0, 255 do
      for b = 0, 255 do
        local r_and, r_or, r_xor, x, y, m = 0, 0, 0, a, b, 1
        for _ = 1, 8 do
          local p, q = x % 2, y % 2
          if p == 1 and q == 1 then r_and = r_and + m end
          if p == 1 or q == 1 then r_or = r_or + m end
          if p ~= q then r_xor = r_xor + m end
          x, y, m = (x - p) / 2, (y - q) / 2, m * 2
        end
        local i = a * 256 + b
        and_t[i], or_t[i], xor_t[i] = r_and, r_or, r_xor
      end
    end
    local function by_bytes(t)
      return function(a, b)
        local r, m = 0, 1
        for _ = 1, 4 do
          local x, y = a % 256, b % 256
          r = r + t[x * 256 + y] * m
          a, b, m = (a - x) / 256, (b - y) / 256, m * 256
        end
        return r
      end
    end
    bit_ops_cache = { band = by_bytes(and_t), bor = by_bytes(or_t), bxor = by_bytes(xor_t) }
  end
  return bit_ops_cache
end

local MD5_K = {
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
}
local MD5_S = {
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
}

-- MD5 of a string, as 32 lowercase hex digits (RFC 1321)
local function md5_hex(message)
  local ops = bit_ops()
  local band, bor, bxor = ops.band, ops.bor, ops.bxor
  local floor = math.floor
  local TWO32 = 4294967296
  local MASK = 4294967295

  local length = #message
  local padding = 56 - (length + 1) % 64
  if padding < 0 then
    padding = padding + 64
  end
  local bits = length * 8
  local tail = {}
  for i = 1, 8 do
    tail[i] = string.char(bits % 256)
    bits = floor(bits / 256)
  end
  message = message .. "\128" .. string.rep("\0", padding) .. table.concat(tail)

  local a0, b0, c0, d0 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
  local X = {}
  for block = 1, #message, 64 do
    for i = 0, 15 do
      local p = block + i * 4
      local w1, w2, w3, w4 = string.byte(message, p, p + 3)
      X[i] = w1 + w2 * 256 + w3 * 65536 + w4 * 16777216
    end
    local a, b, c, d = a0, b0, c0, d0
    for i = 0, 63 do
      local f, g
      if i < 16 then
        f = bxor(d, band(b, bxor(c, d)))
        g = i
      elseif i < 32 then
        f = bxor(c, band(d, bxor(b, c)))
        g = (5 * i + 1) % 16
      elseif i < 48 then
        f = bxor(bxor(b, c), d)
        g = (3 * i + 5) % 16
      else
        f = bxor(c, bor(b, MASK - d))
        g = (7 * i) % 16
      end
      local sum = (a + f + MD5_K[i + 1] + X[g]) % TWO32
      local s = MD5_S[i + 1]
      local rotated = (sum * 2 ^ s) % TWO32 + floor(sum / 2 ^ (32 - s))
      a, d, c = d, c, b
      b = (b + rotated) % TWO32
    end
    a0, b0 = (a0 + a) % TWO32, (b0 + b) % TWO32
    c0, d0 = (c0 + c) % TWO32, (d0 + d) % TWO32
  end

  local hex = {}
  for _, word in ipairs({ a0, b0, c0, d0 }) do
    for _ = 1, 4 do
      local byte = word % 256
      hex[#hex + 1] = string.format("%02x", byte)
      word = (word - byte) / 256
    end
  end
  return table.concat(hex)
end

local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local x, y, z = string.byte(data, i, i + 2)
    local n = x * 65536 + (y or 0) * 256 + (z or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = string.sub(BASE64, c1 + 1, c1 + 1) .. string.sub(BASE64, c2 + 1, c2 + 1)
      .. (y and string.sub(BASE64, c3 + 1, c3 + 1) or "=")
      .. (z and string.sub(BASE64, c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

-- A raw deflate stream (RFC 1951) made of "stored" blocks: the data as it
-- is, in pieces of up to 65535 bytes, each with a 5-byte header. No
-- compression - the API accepts raw deflate, and this needs no compressor.
local function deflate_stored(data)
  local out, position, length = {}, 1, #data
  repeat
    local piece = string.sub(data, position, position + 65534)
    position = position + #piece
    local final = (position > length) and 1 or 0
    local n = #piece
    local inverted = 65535 - n
    out[#out + 1] = string.char(final, n % 256, math.floor(n / 256), inverted % 256, math.floor(inverted / 256))
    out[#out + 1] = piece
  until position > length
  return table.concat(out)
end

            --[[ Upload: window and requests ]]--

-- Decided by the owner (2026-11-22): a button in the main window opens an
-- Upload window; the file is one of the subtitle files next to the playing
-- video, or any file by its full path; a film the site does not have can
-- be registered from its IMDb / TMDb id; flags and a comment can be set.
-- The playing video's hash goes with a file that sits next to the video
-- (owner, 2026-11-22: "detect as much as possible"; hash may be sent).

local UPLOAD_EXTENSIONS = { srt = true, sub = true, ass = true, ssa = true, vtt = true, smi = true, txt = true, mpl = true }
-- the request body must stay under about 500 kB; base64 adds a third
local UPLOAD_MAX_BYTES = 350000

local upload_state = {}

local function upload_basename(path)
  return string.match(path, "([^/\\]+)$") or path
end

-- Subtitle files in the video's folder whose name starts like the video's
local function upload_candidates()
  local list = {}
  local dir, name = openSub.file.dir, openSub.file.name
  if not (openSub.file.hasInput and dir and name and name ~= "") then
    return list
  end
  local reader = (vlc.io and vlc.io.readdir) or (vlc.net and vlc.net.opendir)
  local ok, entries = pcall(reader, dir)
  if not ok or type(entries) ~= "table" then
    return list
  end
  local prefix = string.lower(name)
  for _, entry in ipairs(entries) do
    local extension = string.match(entry, "%.(%w+)$")
    if extension and UPLOAD_EXTENSIONS[string.lower(extension)]
       and string.sub(string.lower(entry), 1, #prefix) == prefix then
      list[#list + 1] = { name = entry, path = dir .. entry }
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- The language a file name ends with, if it is a known subtitle language
-- ("Film.2020.sk.srt" -> "sk")
local function upload_language_from_name(file_name)
  local tag = string.match(string.lower(file_name or ""), "[%._%-]([%a%-]+)%.%w+$")
  for _, language in ipairs(openSub.conf.languages or {}) do
    if language[1] == tag then
      return tag
    end
  end
  return nil
end

-- One request to the upload API. Returns the HTTP status (or nil) and the
-- decoded answer (a table, possibly empty).
local function upload_request(method, path, body, timeout)
  local client = Curl.new()
  client:add_header("Api-Key", api_key())
  local auth_header = openSub.getAuthHeader()
  if auth_header then
    client:add_header("Authorization", auth_header)
  end
  client:add_header("Accept", "application/json")
  client:set_timeout(timeout or 20)
  client:set_deadline(timeout or 20)
  client:set_retries(0) -- an upload is never sent twice by itself
  local res
  if method == "GET" then
    res = client:get(api_url(path))
  else
    client:add_header("Content-Type", "application/json")
    res = client:post(api_url(path), json.encode(body or {}))
  end
  if not res then
    return nil, {}
  end
  local ok, answer = decode_object(res.body or "")
  return res.status, ok and answer or {}
end

-- The server's own explanation of a refusal, or the HTTP status
local function upload_error_text(status, answer)
  if type(answer.message) == "string" and answer.message ~= "" then
    return answer.message
  end
  if type(answer.error_code) == "string" then
    return answer.error_code
  end
  return status and ("HTTP " .. tostring(status)) or strings.ui_no_response_from_download_server
end

local function imdb_number(film)
  return film and tonumber(film.imdbid or film.imdb_id and string.match(tostring(film.imdb_id), "%d+"))
end

-- The Film line: "Title (year)", a link to the film's IMDb page when known
local function film_text(film)
  if not film then
    return strings.ui_upload_film_unknown
  end
  local title = tostring(film.title or "?")
  local year = tonumber(film.year)
  if year and year > 0 then
    title = tr("ui_upload_film_year", title, tostring(year))
  end
  local imdb = imdb_number(film)
  if imdb and imdb > 0 then
    -- a link makes the label HTML: escape the title ("Fast & Furious")
    title = string.gsub(title, "[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" })
    return string.format("<a href='https://www.imdb.com/title/tt%07d/'>%s</a>", imdb, title)
  end
  return title
end

-- Full-text search of the site's films (GET /features): the best match for
-- a title, the year when known. Fills upload_state.film; returns the text
-- of the Film line, or nil when nothing was found.
local function upload_search_features(title, year)
  title = trim(title or "")
  if title == "" then
    return nil
  end
  local params = { query = title }
  if tonumber(year) then
    params.year = tostring(tonumber(year))
  end
  local client = Curl.new()
  client:add_header("Api-Key", api_key())
  client:set_timeout(15)
  client:set_deadline(15)
  client:set_retries(0)
  local res = client:get(build_sorted_url(api_url("/features"), params))
  local ok, answer = decode_object(res and res.status == 200 and res.body or "")
  local rows = ok and type(answer.data) == "table" and answer.data or {}
  local wanted = string.lower(title)
  local best
  for _, row in ipairs(rows) do
    local a = type(row) == "table" and row.attributes
    if type(a) == "table" and a.feature_id then
      local name = string.lower(tostring(a.original_title or a.title or ""))
      -- the first row, unless a later one has exactly the title asked for
      if not best or (name == wanted and string.lower(tostring(best.original_title or best.title or "")) ~= wanted) then
        best = a
      end
    end
  end
  if not best then
    return nil
  end
  upload_state.film = { feature_id = tonumber(best.feature_id), title = best.original_title or best.title,
    year = tonumber(best.year), imdbid = tonumber(best.imdb_id) }
  return film_text(upload_state.film)
end

-- Titles compared without case, punctuation or a leading article:
-- "The Matrix Reloaded" == "matrix reloaded"
local function plain_title(text)
  local t = string.lower(tostring(text or ""))
  t = string.gsub(t, "&", " and ")
  t = string.gsub(t, "[%c%p%s]+", " ")
  t = string.gsub(t, "^%s*(.-)%s*$", "%1")
  t = string.gsub(t, "^the ", "")
  t = string.gsub(t, "^an? ", "")
  return t
end

-- "matrix reloaded 2003" -> "matrix reloaded", 2003
local function split_year(text)
  local title, year = string.match(text, "^(.-)[%s%(%[%.,]+((%d%d%d%d))[%)%]]?%s*$")
  year = tonumber(year)
  if title and title ~= "" and year and year >= 1880 and year <= 2100 then
    return title, year
  end
  return text, nil
end

-- TODO(api): a film the site does not have yet can be found by its title
-- only on imdb.opensubtitles.org (plain HTTP, no key; the API's /features
-- knows only the site's films, from_id takes only ids). Move to the API once
-- it can do this itself (asked for: a title in /subtitles/upload/guess or
-- from_id answering like from_id does for an id). See docs/upload-brief.md.
local IMDB_TITLE_SEARCH = "http://imdb.opensubtitles.org/search/query-"
-- after no answer at all, left alone for a minute: a dead host costs
-- seconds of frozen window each time
local imdb_search_down_until = 0

-- The IMDb number (a string of digits) for a title, and whether its title
-- is exactly the one asked for. strict: only an exact title (and year when
-- one is known) counts - for what is found without the user asking.
local function upload_search_imdb(text, year, strict)
  local words = string.gsub(string.gsub(tostring(text or ""), "[%c%p%s]+", " "), "^%s*(.-)%s*$", "%1")
  if words == "" or os.time() < imdb_search_down_until then
    return nil
  end
  local query = string.gsub(words, "[^%w ]", function(c) return string.format("%%%02X", string.byte(c)) end)
  query = string.gsub(query, " ", "+")
  if year then
    query = query .. "+" .. tostring(year)
  end
  local client = Curl.new()
  client:set_timeout(10)
  client:set_deadline(10)
  client:set_retries(0)
  client:set_side_service()
  local res = client:get(IMDB_TITLE_SEARCH .. query)
  if not res or not res.status then
    imdb_search_down_until = os.time() + 60
  end
  local ok, rows = decode_object(res and res.status == 200 and res.body or "")
  if not ok then
    return nil
  end
  local wanted = plain_title(text)
  local best, best_score, best_exact
  for _, row in ipairs(rows) do
    if type(row) == "table" and string.match(tostring(row.id or ""), "^%d+$") then
      local exact = plain_title(row.title) == wanted
      local same_year = year and tonumber(row.year) == year
      -- films and series before single episodes, games ...; IMDb's own
      -- order (the better known first) decides the rest
      local kind = tostring(row.kind or "")
      local score = (exact and 4 or 0) + (same_year and 2 or 0)
        + ((kind == "movie" or string.find(kind, "series", 1, true)) and 1 or 0)
      if (not strict or (exact and (not year or same_year))) and (not best or score > best_score) then
        best, best_score, best_exact = row, score, exact
      end
    end
  end
  if best then
    return best.id, best_exact
  end
end

-- Something typed that is not an IMDb / TMDb id or link is a title
local function looks_like_id(text)
  return string.match(text, "^[Tt][Tt]%d+$") or string.match(text, "^%d+$")
    or string.find(text, "imdb.com", 1, true) or string.find(text, "themoviedb", 1, true)
end

-- Which film: from an IMDb / TMDb id or link if one is given, else guessed
-- from a file name. Fills upload_state.film (known here) or
-- upload_state.new_film (on IMDb / TMDb, not here yet). Returns the text
-- for the "Film" line.
local upload_find_title -- below: it looks ids up with upload_find_film

local function upload_find_film(id_text, file_name)
  upload_state.film, upload_state.new_film = nil, nil
  id_text = trim(id_text or "")
  if id_text ~= "" and not looks_like_id(id_text) then
    local title, year = split_year(id_text)
    return upload_find_title(title, year, false) or strings.ui_upload_film_unknown
  end
  if id_text ~= "" then
    local body = {}
    if string.find(id_text, "themoviedb", 1, true) then
      body.tmdb_id = id_text
    else
      body.imdb_id = id_text
    end
    local status, answer = upload_request("POST", "/subtitles/upload/features/from_id", body)
    if status == 200 and answer.exists_in_db and answer.feature_id then
      upload_state.film = answer
      return film_text(answer)
    elseif status == 200 and answer.found then
      -- not on the site yet: Upload adds it first (upload_register_film);
      -- nothing the user has to know or do
      upload_state.new_film = answer
      return film_text(answer)
    elseif status == 404 then
      return strings.ui_upload_film_not_on_imdb
    end
    return tr("ui_upload_failed", upload_error_text(status, answer))
  end
  if file_name and file_name ~= "" then
    local status, answer = upload_request("POST", "/subtitles/upload/guess", { filename = file_name })
    if status == 200 and type(answer.best_guess) == "table" and answer.best_guess.feature_id then
      upload_state.film = answer.best_guess
      return film_text(answer.best_guess)
    elseif status and status ~= 200 then
      return tr("ui_upload_failed", upload_error_text(status, answer))
    end
  end
  return strings.ui_upload_film_unknown
end

-- A title: the site's own films first, then IMDb (a film found there is
-- looked up by its id, and added on upload when the site lacks it).
-- Order: the site's exact title, IMDb's exact title, the site's best match,
-- IMDb's best match. strict: exact titles only on IMDb.
upload_find_title = function(title, year, strict)
  local site = upload_search_features(title, year)
  local site_film = upload_state.film
  if site and plain_title(site_film.title) == plain_title(title) then
    return site
  end
  local imdb_id, exact = upload_search_imdb(title, year, strict)
  if imdb_id and (exact or not site) then
    return upload_find_film("tt" .. imdb_id, nil)
  end
  upload_state.film = site_film
  return site
end

local function has_login()
  local username, password = openSub.option.os_username, openSub.option.os_password
  return type(username) == "string" and username ~= "" and type(password) == "string" and password ~= ""
end

-- The film of the playing video, without asking the user if at all
-- possible. In this order:
--   1. the search just made for this video: its results name their film
--      (after a hash search, the subtitles made for this very file);
--   2. the API's guess from the video's file name and movie hash;
--   3. an IMDb id the user searched for.
-- Fills upload_state.film / .new_film; returns the text of the Film line.
local function upload_detect_film()
  local items = openSub.itemStore
  if type(items) == "table" and #items > 0 and openSub.file.uri and openSub.lastSearchUri == openSub.file.uri then
    local pool = {}
    for _, item in ipairs(items) do
      if item.FeatureID and item.MoviehashMatch then pool[#pool + 1] = item end
    end
    if #pool == 0 then
      for _, item in ipairs(items) do
        if item.FeatureID then pool[#pool + 1] = item end
      end
    end
    local count, best = {}, nil
    for _, item in ipairs(pool) do
      count[item.FeatureID] = (count[item.FeatureID] or 0) + 1
      if not best or count[item.FeatureID] > count[best.FeatureID] then
        best = item
      end
    end
    -- only a clear majority counts: a name search can list several films,
    -- and the same hash is sometimes recorded for more than one
    if best and count[best.FeatureID] * 2 > #pool then
      upload_state.film = { feature_id = best.FeatureID, title = best.FeatureTitle,
        year = best.FeatureYear, imdbid = tonumber(best.MovieImdbID) }
      return film_text(upload_state.film)
    end
  end

  local video = openSub.file.hasInput and openSub.file.path and upload_basename(openSub.file.path) or nil
  if video then
    if not openSub.file.hash or openSub.file.hash == "" then
      pcall(openSub.getMovieHash)
    end
    local body = { filename = video }
    if openSub.file.hash and openSub.file.hash ~= "" then
      body.moviehash = openSub.file.hash
    end
    local status, answer = upload_request("POST", "/subtitles/upload/guess", body)
    if status == 200 and type(answer.best_guess) == "table" and answer.best_guess.feature_id then
      upload_state.film = answer.best_guess
      return film_text(answer.best_guess)
    end
  end

  local imdb = openSub.movie.imdbId
  if imdb and imdb ~= "" then
    return upload_find_film("tt" .. imdb, nil)
  end
  -- the title and year GuessIt read from the file name (the name search
  -- has them), searched in the site's films
  local episode = tostring(openSub.movie.seasonNumber or "") ~= "" or tostring(openSub.movie.episodeNumber or "") ~= ""
  local found
  if episode then -- IMDb would give the series, not the episode
    found = upload_search_features(openSub.movie.title, openSub.movie.year)
  else
    found = upload_find_title(trim(openSub.movie.title or ""), tonumber(openSub.movie.year), true)
  end
  if found then
    return found
  end
  local first = (upload_state.candidates or {})[1]
  return upload_find_film("", first and first.name)
end

-- "tt0133093" for the IMDb field
local function imdb_text(film)
  local number = imdb_number(film)
  return number and string.format("tt%07d", number) or ""
end

-- Words that only repeat what the film already says: its title, the year,
-- season / episode numbers.
local RELEASE_PLAIN = { s = true, e = true, ep = true, season = true, episode = true, part = true }
-- GuessIt keys that tell something the film does not: who made the video,
-- from which source, in which quality
local RELEASE_EXTRA = { "release_group", "source", "screen_size", "video_codec", "audio_codec",
  "streaming_service", "edition", "other", "video_profile", "audio_channels", "audio_profile" }

-- The release name to suggest: the video's file name when it tells more
-- than the film's title and year (a release group, source, quality ...),
-- otherwise empty - "Send.Help.2026" would only repeat the film.
local function upload_release_default(film)
  local name = openSub.file.name
  if type(name) ~= "string" or name == "" then
    return ""
  end
  local guess = openSub.file.last_guessit_filename == openSub.file.completeName and openSub.file.guessit_data
  if type(guess) == "table" then
    for _, key in ipairs(RELEASE_EXTRA) do
      local value = guess[key]
      if value ~= nil and value ~= "" and not (type(value) == "table" and next(value) == nil) then
        return name
      end
    end
  end
  local known = {}
  local titles = { film and film.title or "", film and film.original_title or "",
                   type(guess) == "table" and guess.title or "" }
  for _, text in ipairs(titles) do
    for word in string.gmatch(string.lower(tostring(text)), "[%w']+") do
      known[word] = true
    end
  end
  for word in string.gmatch(string.lower(name), "[^%s%._%-%(%)%[%]{},:;!?]+") do
    local plain = known[word] or known[(string.gsub(word, "'", ""))] or RELEASE_PLAIN[word]
      or string.match(word, "^%d+$") or string.match(word, "^s%d+e%d+$") or string.match(word, "^s%d+$")
      or string.match(word, "^e%d+$") or string.match(word, "^%d+x%d+$")
    if not plain then
      return name
    end
  end
  return ""
end

-- Main window button
function show_upload()
  if not has_login() or not openSub.checkSession() or not openSub.getAuthHeader() then
    setMessage(error_tag(strings.ui_upload_login_first))
    return
  end
  openSub.getFileInfo()
  upload_state = { candidates = upload_candidates() }
  setMessage(loading_tag(strings.ui_upload_checking))
  -- the film first, so that the window is built with it
  upload_state.film_line = upload_detect_film()
  upload_state.imdb = imdb_text(upload_state.film or upload_state.new_film)
  upload_state.release = upload_release_default(upload_state.film or upload_state.new_film)
  trigger_menu(5)
end

local CHOICE_AUTO = { { nil, "ui_upload_auto" }, { true, "int_bool_true" }, { false, "int_bool_false" } }
local CHOICE_TRANSLATION = {
  { "person", "ui_upload_by_person" }, { "machine", "ui_upload_by_machine" }, { "ai", "ui_upload_by_ai" } }

local function add_choices(dropdown, choices)
  for id, choice in ipairs(choices) do
    dropdown:add_value(strings[choice[2]], id)
  end
end

function interface_upload()
  local candidates = upload_state.candidates or {}
  local row = 0
  local function next_row() row = row + 1 return row end

  dlg:add_label(strings.ui_upload_file .. ":", 1, next_row(), 1, 1)
  input_table["upload_file"] = dlg:add_dropdown(2, row, 3, 1)
  for id, candidate in ipairs(candidates) do
    input_table["upload_file"]:add_value(candidate.name, id)
  end
  input_table["upload_file"]:add_value(#candidates == 0 and strings.ui_upload_no_files or strings.ui_none, 0)

  dlg:add_label(strings.ui_upload_other_path .. ":", 1, next_row(), 1, 1)
  input_table["upload_path"] = dlg:add_text_input("", 2, row, 3, 1)

  dlg:add_label(strings.ui_upload_language .. ":", 1, next_row(), 1, 1)
  input_table["upload_language"] = dlg:add_dropdown(2, row, 2, 1)
  local wanted = upload_language_from_name(candidates[1] and candidates[1].name) or openSub.option.language
  local languages = openSub.conf.languages or {}
  for id, language in ipairs(languages) do
    if language[1] == wanted then
      input_table["upload_language"]:add_value(language[2], id)
    end
  end
  for id, language in ipairs(languages) do
    if language[1] ~= wanted then
      input_table["upload_language"]:add_value(language[2], id)
    end
  end

  dlg:add_label(strings.ui_upload_film .. ":", 1, next_row(), 1, 1)
  input_table["upload_film"] = dlg:add_label(upload_state.film_line or strings.ui_upload_film_unknown, 2, row, 3, 1)

  dlg:add_label(strings.ui_upload_imdb .. ":", 1, next_row(), 1, 1)
  input_table["upload_imdb"] = dlg:add_text_input(upload_state.imdb or "", 2, row, 2, 1)
  dlg:add_button(strings.ui_upload_find, upload_find_clicked, 4, row, 1, 1)

  dlg:add_label(strings.ui_filter_hearing_impaired .. ":", 1, next_row(), 1, 1)
  input_table["upload_hi"] = dlg:add_dropdown(2, row, 1, 1)
  add_choices(input_table["upload_hi"], CHOICE_AUTO)

  dlg:add_label(strings.ui_filter_foreign_parts .. ":", 1, next_row(), 1, 1)
  input_table["upload_foreign"] = dlg:add_dropdown(2, row, 1, 1)
  add_choices(input_table["upload_foreign"], CHOICE_AUTO)

  dlg:add_label(strings.ui_upload_translation .. ":", 1, next_row(), 1, 1)
  input_table["upload_translation"] = dlg:add_dropdown(2, row, 2, 1)
  add_choices(input_table["upload_translation"], CHOICE_TRANSLATION)

  dlg:add_label(strings.ui_upload_release .. ":", 1, next_row(), 1, 1)
  input_table["upload_release"] = dlg:add_text_input(upload_state.release or "", 2, row, 3, 1)

  dlg:add_label(strings.ui_upload_comment .. ":", 1, next_row(), 1, 1)
  input_table["upload_comment"] = dlg:add_text_input("", 2, row, 3, 1)

  -- macOS does not grow a window for a longer message: keep three lines
  local three_empty_lines = "&nbsp;<br>&nbsp;<br>&nbsp;"
  input_table["message"] = dlg:add_label(on_macos() and three_empty_lines or "", 1, next_row(), 4, 1)

  next_row()
  dlg:add_button(strings.ui_upload_check, upload_check_clicked, 1, row, 1, 1)
  dlg:add_button(strings.ui_upload, upload_send_clicked, 2, row, 1, 1)
  dlg:add_button(strings.ui_back, show_main, 4, row, 1, 1)
end

-- The chosen file: the typed path wins over the list
-- The third value is true for a file next to the video: one made for it.
local function upload_chosen_file()
  local typed = trim(input_table["upload_path"] and input_table["upload_path"]:get_text() or "")
  if typed ~= "" then
    return typed, upload_basename(typed), false
  end
  local id = input_table["upload_file"] and input_table["upload_file"]:get_value() or 0
  local candidate = (upload_state.candidates or {})[id]
  if candidate then
    return candidate.path, candidate.name, true
  end
  return nil
end

function upload_find_clicked()
  local _, name = upload_chosen_file()
  setMessage(loading_tag(strings.ui_upload_checking))
  local text = upload_find_film(input_table["upload_imdb"]:get_text(), name)
  upload_state.film_line = text
  input_table["upload_film"]:set_text(text)
  local found = imdb_text(upload_state.film or upload_state.new_film)
  if found ~= "" then
    input_table["upload_imdb"]:set_text(found)
  end
  setMessage("")
end

-- Everything an upload or a check sends, without the file itself; or nil
-- and the reason. `with_file` also returns the file's bytes.
local function upload_fields()
  local path, name, beside_video = upload_chosen_file()
  if not path then
    return nil, strings.ui_upload_choose_file
  end
  local file = io.open(path, "rb")
  local data = file and file:read("*a")
  if file then
    file:close()
  end
  if not data then
    return nil, tr("ui_upload_cannot_read", name)
  end
  if #data < 100 then
    return nil, strings.ui_upload_too_small
  end
  if #data > UPLOAD_MAX_BYTES then
    return nil, tr("ui_upload_too_large", tostring(math.floor(#data / 1024)),
      tostring(math.floor(UPLOAD_MAX_BYTES / 1024)))
  end
  local language = openSub.conf.languages[input_table["upload_language"]:get_value()]
  if not language then
    return nil, strings.ui_upload_language_needed
  end
  if not upload_state.film and not upload_state.new_film then
    return nil, strings.ui_upload_film_needed
  end

  local fields = {
    subhash = md5_hex(data),
    subfilename = name,
    sublanguageid = language[1],
  }
  if upload_state.film then
    fields.feature_id = tonumber(upload_state.film.feature_id)
  end
  -- A subtitle that sits next to the video is taken to be made for it: the
  -- video's hash goes with it, so that the next person with this file finds
  -- it by hash search.
  if beside_video and openSub.file.hash and openSub.file.hash ~= "" then
    fields.moviehash = openSub.file.hash
    fields.moviebytesize = tonumber(openSub.file.bytesize)
    fields.moviefilename = openSub.file.path and upload_basename(openSub.file.path) or nil
  end
  local hi = CHOICE_AUTO[input_table["upload_hi"]:get_value()]
  if hi and hi[1] ~= nil then
    fields.hearing_impaired = hi[1]
  end
  local foreign = CHOICE_AUTO[input_table["upload_foreign"]:get_value()]
  if foreign and foreign[1] ~= nil then
    fields.foreign_parts_only = foreign[1]
  end
  local translation = CHOICE_TRANSLATION[input_table["upload_translation"]:get_value()]
  if translation and translation[1] == "machine" then
    fields.machine_translated = true
  elseif translation and translation[1] == "ai" then
    fields.automatic_translation = true
  end
  local release = trim(input_table["upload_release"]:get_text() or "")
  if release ~= "" then
    fields.release_name = release
  end
  local comment = trim(input_table["upload_comment"]:get_text() or "")
  if comment ~= "" then
    fields.author_comments = comment
  end
  return fields, nil, data
end

-- "<a href='url'>text</a>" for a plain https address of a page on the site,
-- otherwise the text alone
local function page_link(url, text)
  text = string.gsub(tostring(text or ""), "[<>&]", "")
  if type(url) == "string" and string.match(url, "^https://[%w%.%-]+/[%w%-%._~/%%]*$") then
    return "<a href='" .. url .. "'>" .. text .. "</a>"
  end
  return text
end

-- "Already on OpenSubtitles", with a link to that subtitle's page when it
-- can be found. The API gives only its id (duplicate_of); its page address
-- comes with the film's subtitles in that language (/subtitles?id= is the
-- film's feature id). One request, first page only.
local function upload_already_text(duplicate_of, feature_id, language)
  duplicate_of, feature_id = tonumber(duplicate_of), tonumber(feature_id)
  if duplicate_of and feature_id and language then
    local client = Curl.new()
    client:add_header("Api-Key", api_key())
    client:set_timeout(15)
    client:set_deadline(15)
    client:set_retries(0)
    local res = client:get(build_sorted_url(api_url("/subtitles"),
      { id = tostring(feature_id), languages = tostring(language) }))
    local ok, answer = decode_object(res and res.status == 200 and res.body or "")
    for _, row in ipairs(ok and type(answer.data) == "table" and answer.data or {}) do
      local a = type(row) == "table" and row.attributes
      if type(a) == "table" and tonumber(row.id or a.subtitle_id) == duplicate_of then
        local link = page_link(a.url, a.release ~= "" and a.release or tostring(duplicate_of))
        if string.find(link, "<a ", 1, true) then
          return tr("ui_upload_already_at", link)
        end
      end
    end
  end
  return strings.ui_upload_already
end

function upload_check_clicked()
  setMessage(loading_tag(strings.ui_upload_checking))
  local fields, problem = upload_fields()
  if not fields then
    setMessage(error_tag(problem))
    return
  end
  local status, answer = upload_request("POST", "/subtitles/upload/check", fields)
  if status ~= 200 then
    setMessage(error_tag(tr("ui_upload_failed", upload_error_text(status, answer))))
    return
  end
  if answer.already_in_db then
    local feature = type(answer.feature) == "table" and answer.feature.feature_id or fields.feature_id
    setMessage(error_tag(upload_already_text(answer.duplicate_of, feature, fields.sublanguageid)))
    return
  end
  local reasons = {}
  for _, reason in ipairs(type(answer.rejection_reasons) == "table" and answer.rejection_reasons or {}) do
    -- a film that is registered on upload is not "missing"
    if not (upload_state.new_film and string.find(tostring(reason), "^feature_")) then
      reasons[#reasons + 1] = tostring(reason)
    end
  end
  if #reasons > 0 then
    setMessage(error_tag(tr("ui_upload_would_be_rejected", table.concat(reasons, ", "))))
  elseif answer.would_be_flagged then
    setMessage(success_tag(strings.ui_upload_would_be_reviewed))
  else
    local left = type(answer.quota) == "table" and answer.quota.remaining
    setMessage(success_tag(tr("ui_upload_ok_to_upload", tostring(left or "?"))))
  end
end

-- Register the film that is on IMDb / TMDb but not here; its feature_id
local function upload_register_film()
  local new = upload_state.new_film
  local body = {
    title = new.title, year = tonumber(new.year), type = new.type,
    source = new.imdb_id and "imdb" or "tmdb", imdb_id = new.imdb_id, tmdb_id = tonumber(new.tmdb_id),
  }
  local status, answer = upload_request("POST", "/subtitles/upload/features/stub", body, 60)
  if status == 201 and answer.feature_id then
    return answer.feature_id
  elseif status == 409 and type(answer.details) == "table" and answer.details.feature_id then
    return answer.details.feature_id -- registered meanwhile
  end
  return nil, upload_error_text(status, answer)
end

function upload_send_clicked()
  setMessage(loading_tag(strings.ui_upload_working))
  local fields, problem, data = upload_fields()
  if not fields then
    setMessage(error_tag(problem))
    return
  end
  if not fields.feature_id and upload_state.new_film then
    local feature_id, failure = upload_register_film()
    if not feature_id then
      setMessage(error_tag(tr("ui_upload_failed", failure)))
      return
    end
    upload_state.film = { feature_id = feature_id, title = upload_state.new_film.title, year = upload_state.new_film.year,
                          imdb_id = upload_state.new_film.imdb_id, imdbid = upload_state.new_film.imdbid }
    upload_state.new_film = nil
    fields.feature_id = tonumber(feature_id)
    input_table["upload_film"]:set_text(film_text(upload_state.film))
  end
  fields.subcontent = base64_encode(deflate_stored(data))
  local status, answer = upload_request("POST", "/subtitles/upload", fields, 90)
  if status == 201 then
    -- the subtitle's page on the site, clickable
    local release = page_link(answer.download_url, answer.release_name or fields.subfilename)
    if answer.subtitle_status == "pending" then
      setMessage(success_tag(tr("ui_upload_done_review", release)))
    else
      setMessage(success_tag(tr("ui_upload_done", release)))
    end
    vlc.msg.info("[VLSub] Uploaded subtitle " .. tostring(answer.subtitle_id))
  elseif status == 409 then
    setMessage(error_tag(upload_already_text(answer.duplicate_of, fields.feature_id, fields.sublanguageid)))
  else
    setMessage(error_tag(tr("ui_upload_failed", upload_error_text(status, answer))))
  end
end

-- AI credits of the logged-in account (GET /ai/credits), or nil when they
-- cannot be read. One short request. (Global: the configuration code above
-- uses it.)
function ai_credits()
  local auth_header = openSub.getAuthHeader()
  if not auth_header then
    return nil
  end
  local client = Curl.new()
  client:add_header("Api-Key", api_key())
  client:add_header("Authorization", auth_header)
  client:set_timeout(10)
  client:set_retries(0)
  local res = client:get(api_url("/ai/credits"))
  if not res or res.status ~= 200 then
    return nil
  end
  local ok, answer = decode_object(res.body or "")
  if ok and type(answer.data) == "table" then
    return tonumber(answer.data.credits)
  end
  return nil
end

-- Links to the credit packages (GET /ai/credits/buy) as one line of HTML, or
-- "" when there are none. The checkout addresses carry a per-user tag: they
-- are shown to the user and never written to the log.
local function ai_buy_links()
  local auth_header = openSub.getAuthHeader()
  if not auth_header then
    return ""
  end
  local client = Curl.new()
  client:add_header("Api-Key", api_key())
  client:add_header("Authorization", auth_header)
  client:set_timeout(10)
  client:set_retries(0)
  local res = client:get(api_url("/ai/credits/buy"))
  local ok, answer = decode_object(res and res.status == 200 and res.body or "")
  if not ok or type(answer.data) ~= "table" then
    return ""
  end
  local links = {}
  for _, offer in ipairs(answer.data) do
    local url = type(offer) == "table" and offer.checkout_url
    -- only a plain https address of opensubtitles.com is made clickable
    if type(url) == "string" and string.match(url, "^https://[%w%.%-]*opensubtitles%.com/[%w%-%._~:/%?#%[%]@!%$&%(%)%*%+,;=%%]*$")
       and not string.find(url, "'", 1, true) and #links < 6 then
      local label = tostring(offer.name or "") .. " - " .. tostring(offer.value or "")
      label = string.gsub(label, "[<>&]", "")
      links[#links + 1] = "<a href='" .. url .. "'>" .. label .. "</a>"
    end
  end
  if #links == 0 then
    return ""
  end
  -- three packages per line (that much fits; one long line was cut off at
  -- the window's edge - macOS does not widen a window for its message)
  local rows = {}
  for i = 1, #links, 3 do
    local row = links[i]
    for j = i + 1, math.min(i + 2, #links) do
      row = row .. " &nbsp;|&nbsp; " .. links[j]
    end
    rows[#rows + 1] = row
  end
  return strings.ui_ai_buy_credits .. "<br>" .. table.concat(rows, "<br>")
end

-- Button of the configuration window: balance and where to buy more.
function show_ai_credits()
  -- Credits belong to an account: without a login there is nothing to ask.
  -- (A session can exist without one - searching needs none - so the stored
  -- username and password are what is looked at.)
  local username = openSub.option.os_username
  local password = openSub.option.os_password
  local has_login = type(username) == "string" and username ~= ""
    and type(password) == "string" and password ~= ""
  if not has_login or not openSub.checkSession() or not openSub.getAuthHeader() then
    setMessage(error_tag(strings.ui_ai_credits_login_first))
    return
  end
  local credits = ai_credits()
  if not credits then
    setMessage(error_tag(strings.ui_ai_credits_unavailable))
    return
  end
  -- three lines, the room the configuration window keeps for its message:
  -- "AI credits: 394 - Buy AI credits:" and two lines of packages
  local message = "<b>" .. tr("ui_ai_credits_balance", tostring(credits)) .. "</b>"
  local links = ai_buy_links()
  if links ~= "" then
    message = message .. " &nbsp;-&nbsp; " .. links
  end
  setMessage(message)
end

-- Ask the API for a download link for `item`, fetch the subtitle, save it and
-- load it into the player. Returns true on success.
openSub.downloadFromNewAPI = function(item, is_retry)
  if not item.FileID then
    return report_failure(strings.ui_no_file_id_available_for_download)
  end
  if not openSub.checkSession() then
    return report_failure(strings.ui_authentication_failed_please_check_your_opensubt)
  end

  dbg("Downloading subtitle file ID: " .. item.FileID)
  setMessage(openSub.actionLabel..": "..progressBarContent(50))

  local auth_header = openSub.getAuthHeader()
  if not auth_header then
    return report_failure(strings.ui_download_login_first)
  end

  local client = Curl.new()
  client:add_header("Api-Key", api_key())
  client:add_header("Content-Type", "application/json")
  client:add_header("Authorization", auth_header)
  client:set_timeout(30)
  client:set_retries(2)

  local request_body = json.encode({ file_id = item.FileID })
  if item.OnDemand then
    -- The server translates while the request is open. One long request,
    -- never repeated by itself: a repeat could be a second purchase.
    client:set_timeout(120)
    client:set_deadline(120)
    client:set_retries(0)
    -- the last answer can be the subtitle text itself: byte for byte
    client:set_raw(true)
    -- The server keeps each waiting request open for seconds (measured: 9 s
    -- twice for a whole film). Nothing can run beside it in VLC's Lua, but
    -- the message can count, so the window is seen to be working.
    local ordered_at = os.time()
    client:set_on_wait(function()
      setMessage(loading_tag(tr("ui_ai_still_translating", tostring(os.time() - ordered_at))))
    end)
    -- the id goes back digit for digit, as a JSON number (as the Kodi addon
    -- sends it)
    if type(item.FileID) == "string" and string.match(item.FileID, "^%d+$") then
      request_body = '{"file_id":' .. item.FileID .. '}'
    end
    -- the balance first, so the user sees it before anything is ordered.
    -- (Without credits the server still answers: with a preview, see below.)
    local credits = ai_credits()
    setMessage(loading_tag(credits and tr("ui_ai_creating_translation_credits", tostring(credits))
                                    or strings.ui_ai_creating_translation))
  else
    setMessage(openSub.actionLabel..": "..progressBarContent(60))
  end

  local trace = os.getenv("VLSUB_TRACE_HTTP") == "1"
  local function traced(what, answer)
    -- developer switch (tools/dev.sh run -v): the raw answer, to learn what
    -- the server says. Off in normal use: answers are never logged.
    if trace then
      vlc.msg.warn("[VLSub] trace " .. what .. " -> " .. (answer and (tostring(answer.status)
        .. " location=" .. tostring(answer.headers and answer.headers["location"])
        .. " body=" .. tostring(answer.body)) or "no answer"))
    end
    return answer
  end

  -- An on-demand translation that is not made yet (measured on the live
  -- API): the POST is answered with 302 to
  --   /api/v1/download/<id>?wait_for_translation=1
  -- and that again with 302 to ...=2, ...=3 and so on while the translation
  -- is being made; the last one answers 200 with the link. A translation
  -- that exists already ("file was cached") answers the POST with 200 at
  -- once. So: one POST, then the trail of redirects is followed - on the API
  -- host only, over plain HTTP, with the same credentials - for at most
  -- three minutes, the message line counting along.
  -- Follows the trail of redirects from `answer`; returns the first answer
  -- that is not a redirect (nil: no answer, false: gave up after 3 minutes).
  -- Without credits the server sends the request on to
  -- /download/preview-<id>...: the first lines translated, followed by lines
  -- saying where to get credits (measured with an account at 0).
  local is_preview = false
  local function follow_waiting(answer)
    local started = os.time()
    while answer and answer.status >= 301 and answer.status <= 308 do
      local location = answer.headers and answer.headers["location"]
      local root = string.gsub(api_root(), "%p", "%%%0")
      local path = location and (string.match(location, "^https?://api%.opensubtitles%.com(/.*)$")
        or string.match(location, "^" .. root .. "(/.*)$")
        or string.match(location, "^(/.*)$"))
      if not path then
        break
      end
      if os.time() - started > 180 then
        return false
      end
      if string.find(path, "/download/preview-", 1, true) then
        is_preview = true
      end
      -- a redirect that came back at once: do not hammer the server
      local asked = os.time()
      answer = traced("GET " .. path, client:get(api_root() .. path))
      if answer and answer.status >= 301 and answer.status <= 308 then
        while os.time() - asked < 3 do end
      end
    end
    return answer
  end

  local res = traced("POST /download", client:post(api_url("/download"), request_body))
  if item.OnDemand and res then
    res = follow_waiting(res)
    if res == false then
      return report_failure(strings.ui_ai_no_answer)
    end
  end
  if not res then
    return report_failure(item.OnDemand and strings.ui_ai_no_answer or strings.ui_no_response_from_download_server)
  end

  if res.status == 401 then
    -- The cached token was rejected: log in again and try once more
    if not is_retry and openSub.refreshSession() then
      return openSub.downloadFromNewAPI(item, true)
    end
    return report_failure(strings.ui_authentication_failed_401_please_check_your_cred)
  elseif DOWNLOAD_STATUS_MESSAGE[res.status] then
    return report_failure(strings[DOWNLOAD_STATUS_MESSAGE[res.status]])
  elseif res.status ~= 200 then
    local message = "Download failed with HTTP status: " .. res.status
    vlc.msg.err("[VLSub] " .. message)
    if res.body then
      vlc.msg.err("[VLSub] Error response: " .. res.body)
      local ok, error_data = decode_object(res.body)
      if ok and error_data and error_data.message then
        message = message .. " - " .. error_data.message
      end
    end
    setMessage(error_tag(message))
    return false
  end

  if not res.body or res.body == "" then
    return report_failure(strings.ui_empty_response_from_download_server)
  end

  setMessage(openSub.actionLabel..": "..progressBarContent(75))

  local ok, answer = decode_object(res.body)
  local subtitle_content
  local used, remaining, reset_time

  if ok and answer then
    if answer.requests ~= nil then used = tonumber(tostring(answer.requests)) end
    if answer.remaining ~= nil then remaining = tonumber(tostring(answer.remaining)) end
    reset_time = answer.reset_time or nil
    if reset_time == "N/A" then reset_time = nil end

    if answer.link then
      setMessage(openSub.actionLabel..": "..progressBarContent(80))
      -- A translation that exists already ("file was cached") comes with a
      -- link on ai.opensubtitles.com that VLC cannot use (measured: 404
      -- without a login, and https here cannot carry one):
      --   https://ai.opensubtitles.com/proxy/download/<id>
      --   https://ai.opensubtitles.com/proxy/download/preview-<id>?p=am   (no credits)
      -- The API hands the same thing out at /download/<that name>, the
      -- address a new translation is waited for. Exactly what the link names
      -- is asked for - a preview stays a preview.
      local name, extra = string.match(answer.link,
        "^https://ai%.opensubtitles%.com/proxy/download/([%w%-]+)%??([%w%-%._~=&%%]*)$")
      if item.OnDemand and name then
        if string.sub(name, 1, 8) == "preview-" then
          is_preview = true
        end
        local path = "/api/v1/download/" .. name .. "?wait_for_translation=1"
        if extra ~= "" then
          path = path .. "&" .. extra
        end
        local direct = follow_waiting(traced("GET " .. path, client:get(api_root() .. path)))
        if direct and direct.status == 200 and direct.body and direct.body ~= ""
           and not decode_object(direct.body) then
          subtitle_content = direct.body
        end
      end
      if not subtitle_content then
        subtitle_content = fetch_subtitle(answer.link)
      end
      if not subtitle_content then
        return false
      end
    elseif answer.content then
      subtitle_content = answer.content
      dbg("Got direct subtitle content from API response")
    elseif answer.error or answer.message then
      -- e.g. 200 {"message":"Invalid file_id"}: an answer without a link
      -- is an explanation, never the subtitle itself
      return report_failure(tr("ui_api_returned_error", tostring(answer.error or answer.message)))
    else
      subtitle_content = res.body
      dbg("Using entire response as subtitle content (fallback)")
    end
  else
    dbg("Response is not JSON, treating as direct subtitle content")
    subtitle_content = res.body
  end

  setMessage(openSub.actionLabel..": "..progressBarContent(90))

  local saved = openSub.saveAndLoadSubtitle(subtitle_content, item)
  if saved then
    -- saveAndLoadSubtitle has set a success message; append the quota to it
    local message = string.gsub(input_table["message"]:get_text(), "<[^>]*>", "")
    message = string.gsub(message, string.gsub(strings.mess_success, "%p", "%%%0") .. ":%s*", "")
    local quota = quota_text(used, remaining, reset_time)
    if item.OnDemand then
      -- paid with credits, not with the daily quota
      local credits = ai_credits()
      quota = credits and tr("ui_ai_credits_left", tostring(credits)) or ""
    end
    if quota ~= "" then
      message = tr("ui_message_with_quota", message, quota)
    end
    if is_preview then
      -- say plainly that this is not the whole subtitle, and where to buy
      local credits = ai_credits()
      local notice = error_tag(tr("ui_ai_preview_only", tostring(credits or 0)))
      local links = ai_buy_links()
      if links ~= "" then
        notice = notice .. "<br>" .. links
      end
      setMessage(notice)
    else
      setMessage(success_tag(message))
    end
  end

  return saved
end


-- Simple fix: is_first_run() that doesn't rely on openSub.conf.filePath
function is_first_run()
  -- Detect OS first
  local current_slash = is_window_path(vlc.config.datadir()) and "\\" or "/"

  -- Standard VLSub paths
  local userdatadir = vlc.config.userdatadir()
  local datadir = vlc.config.datadir()

  local vlsub_subdir = current_slash .. "lua" .. current_slash .. "extensions" .. current_slash .. "userdata" .. current_slash .. "vlsub.com"
  local config_filename = current_slash .. "vlsub_conf.json"

  -- Possible config file locations
  local possible_config_paths = {}

  if userdatadir then
    table.insert(possible_config_paths, userdatadir .. vlsub_subdir .. config_filename)
  end

  if datadir then
    table.insert(possible_config_paths, datadir .. vlsub_subdir .. config_filename)
  end

  -- Check if any config file exists
  for _, config_path in ipairs(possible_config_paths) do
    if file_exist(config_path) then
      dbg("Found existing config: " .. config_path .. " - NOT first run")
      return false
    end
  end

  -- Check for other VLSub files in possible directories
  local possible_dirs = {}
  if userdatadir then
    table.insert(possible_dirs, userdatadir .. vlsub_subdir)
  end
  if datadir then
    table.insert(possible_dirs, datadir .. vlsub_subdir)
  end

  for _, dir_path in ipairs(possible_dirs) do
    if is_dir(dir_path) then
      local vlsub_files = {
        "session_cache.json",
        "cache_subtitle_languages.json",
        "last_update_check.json",
        "first_run_complete.marker"
      }

      for _, filename in ipairs(vlsub_files) do
        local filepath = dir_path .. current_slash .. filename
        if file_exist(filepath) then
          dbg("Found existing VLSub file: " .. filepath .. " - NOT first run")
          return false
        end
      end
    end
  end

  -- Check VLC's sub-autodetect-path for vlsub_subtitles directory
  for path in vlc.config.get("sub-autodetect-path"):gmatch("[^,]+") do
    if path:match("vlsub_subtitles$") then
      dbg("Found vlsub_subtitles in VLC config - NOT first run")
      return false
    end
  end

  dbg("No VLSub files found anywhere - this IS first run")
  return true
end


-- Configuration window, after saving credentials: log in and show the
-- account's level and download quota. Returns true when both worked.
openSub.checkLoginAndUserInfo = function()
  local function fail(message)
    setMessage(error_tag(message))
    return false
  end

  openSub.actionLabel = strings.ui_checking_login_status
  setMessage(loading_tag(strings.ui_verifying_credentials))

  if trim(openSub.option.os_username or "") == "" or trim(openSub.option.os_password or "") == "" then
    return fail(strings.ui_username_and_password_are_required_for_authentic)
  end
  if not openSub.loginWithRestAPI() then
    return false -- loginWithRestAPI has set the message
  end

  setMessage(loading_tag(strings.ui_fetching_account_information))

  local auth_header = openSub.getAuthHeader()
  if not auth_header then
    return fail(strings.ui_no_authentication_token_available)
  end
  local client = Curl.new()
  client:add_header("Api-Key", api_key())
  client:add_header("Authorization", auth_header)
  client:set_timeout(30)
  client:set_retries(2)

  local res = client:get(api_url("/infos/user"))
  if not res then
    return fail(strings.ui_no_response_from_user_info_api)
  end

  if res.status == 401 then
    openSub.session.token = ""
    openSub.session.token_expires = 0
    return fail(strings.ui_authentication_failed_401_please_check_your_cred)
  elseif res.status == 403 then
    return fail(strings.ui_access_forbidden_403_insufficient_permissions)
  elseif res.status ~= 200 then
    local message = tr("ui_user_info_request_failed_with_http_status", tostring(res.status))
    if res.body then
      vlc.msg.err("[VLSub] Error response: " .. res.body)
      local ok, error_data = decode_object(res.body)
      if ok and error_data and error_data.message then
        message = message .. " - " .. error_data.message
      end
    end
    return fail(message)
  end

  if not res.body then
    return fail(strings.ui_empty_response_from_user_info_api)
  end
  local ok, user_response = decode_object(res.body)
  if not ok or not user_response then
    return fail(strings.ui_failed_to_parse_user_info_response)
  end
  if not user_response.data then
    return fail(strings.ui_invalid_user_info_response_format)
  end

  local user_data = user_response.data
  local downloads_count = user_data.downloads_count or 0
  local allowed_downloads = user_data.allowed_downloads or 0
  local username = user_data.username or strings.ui_unknown_2
  local level = user_data.level or strings.ui_unknown_2
  local reset_time = user_data.reset_time or user_data.reset_time_utc or strings.ui_unknown_2
  local user_info_html = success_tag(tr("ui_account_summary", username, level,
    tostring(downloads_count), tostring(allowed_downloads), reset_time))

  openSub.lastSuccessMessage = user_info_html
  setMessage(user_info_html)
  if dlg then
    dlg:update()
  end

  openSub.session.user_info = user_data
  dbg("User info check successful for: " .. (user_data.username or "unknown"))
  return true
end

-- Add this function to check if file is local and suitable for hashing
function openSub.isLocalFileForHashing()
  local file = openSub.file

  -- Check if we have valid file info
  if not file.hasInput or not file.protocol or not file.path then
    dbg("No valid file input for hashing")
    return false
  end

  -- Only allow local file protocols
  if file.protocol ~= "file" then
    dbg("File protocol '" .. file.protocol .. "' not supported for hashing")
    return false
  end

  -- Check if file actually exists locally (for file:// protocol)
  if file.protocol == "file" then
    if file.is_archive then
      return true
    end

    if not file.path or not file_exist(file.path) then
      dbg("File does not exist locally: " .. (file.path or "nil"))
      return false
    end
  end

  -- Additional check for minimum file size (very small files might not be valid)
  if file.stat and file.stat.size and file.stat.size < 65536 then
    dbg("File too small for reliable hashing: " .. file.stat.size .. " bytes")
    return false
  end

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


  -- Method 1: Environment variables (Unix/Linux/macOS)
  local env_vars = {"LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LC_CTYPE"}

  for _, var in ipairs(env_vars) do
    local value = os.getenv(var)
    if value and value ~= "" then
      dbg("Environment " .. var .. ": " .. value)
      table.insert(detected_locales, {source = "env_" .. var, locale = value})
    end
  end

  -- Method 2: VLC's own locale settings
  local vlc_lang = vlc.config.get("intf")
  if vlc_lang and vlc_lang ~= "" then
    dbg("VLC interface language: " .. vlc_lang)
    table.insert(detected_locales, {source = "vlc_intf", locale = vlc_lang})
  end

  -- Method 3: System locale via Lua's os.setlocale (works differently on different platforms)
  local sys_locale = os.setlocale(nil, "time")
  if sys_locale and sys_locale ~= "C" and sys_locale ~= "POSIX" then
    dbg("System locale (time): " .. sys_locale)
    table.insert(detected_locales, {source = "sys_time", locale = sys_locale})
  end

  local sys_locale_collate = os.setlocale(nil, "collate")
  if sys_locale_collate and sys_locale_collate ~= "C" and sys_locale_collate ~= "POSIX" then
    dbg("System locale (collate): " .. sys_locale_collate)
    table.insert(detected_locales, {source = "sys_collate", locale = sys_locale_collate})
  end

  local sys_locale_ctype = os.setlocale(nil, "ctype")
  if sys_locale_ctype and sys_locale_ctype ~= "C" and sys_locale_ctype ~= "POSIX" then
    dbg("System locale (ctype): " .. sys_locale_ctype)
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
    table.insert(detected_locales, {source = "user_pref", locale = openSub.option.language})
  end

  -- Method 6: IP-based geolocation - only as a last resort.
  -- The lookup goes through vlc.stream, which has no timeout, and the service
  -- (api.myip.com) is published on IPv6 only: without working IPv6 the request
  -- blocks VLC's interface until VLC gives up (24 s and 42 s measured on two
  -- machines). When the system already told us a locale it adds nothing.
  if #detected_locales == 0 then
    detect_ip_based_locale(detected_locales)
  else
    dbg("Locale known from the system, skipping IP geolocation")
  end

  -- Analyze and prioritize the detected locales
  local best_guess = analyze_detected_locales(detected_locales)

  if best_guess then
    dbg("Best guess locale: " .. best_guess.locale .. " (from " .. best_guess.source .. ")")
  else
    dbg("Could not determine user locale")
  end

  return best_guess
end


-- 2. FIXED: detect_windows_locale function - remove all PowerShell/cmd commands
function detect_windows_locale(detected_locales)

  -- Only use safe environment variables and VLC's own settings

  -- Method 1: Safe environment variables (no external commands)
  local win_env_vars = {
    "LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES",
    "USERPROFILE", -- Often contains username with locale hints
    "COMPUTERNAME", -- Sometimes contains region info
    "TZ" -- Timezone
  }

  for _, var in ipairs(win_env_vars) do
    local value = os.getenv(var)
    if value and value ~= "" then
      dbg("Windows env " .. var .. ": " .. value)
      if var == "LANG" or var == "LANGUAGE" or var == "LC_ALL" or var == "LC_MESSAGES" then
        table.insert(detected_locales, {source = "win_env_" .. var, locale = value})
      end
    end
  end

  -- Method 2: VLC's own language setting (safe, no external commands)
  local vlc_lang = vlc.config.get("intf")
  if vlc_lang and vlc_lang ~= "" then
    dbg("VLC Windows interface language: " .. vlc_lang)
    table.insert(detected_locales, {source = "win_vlc_intf", locale = vlc_lang})
  end

  -- Method 3: Check for English resources directory (safe file system check)
  local windir = os.getenv("WINDIR") or os.getenv("SystemRoot")
  if windir then
    local english_resources_path = windir .. "\\System32\\en-US"
    if is_dir(english_resources_path) then
      table.insert(detected_locales, {source = "win_english_resources", locale = "en_US"})
    end
  end

  -- Method 4: Check Windows system locale via file system (safe)
  -- Look for common locale indicators in system paths
  local possible_locales = {
    {path = "\\System32\\en-US", locale = "en_US"},
    {path = "\\System32\\de-DE", locale = "de_DE"},
    {path = "\\System32\\fr-FR", locale = "fr_FR"},
    {path = "\\System32\\es-ES", locale = "es_ES"},
    {path = "\\System32\\it-IT", locale = "it_IT"},
    {path = "\\System32\\pt-PT", locale = "pt_PT"},
    {path = "\\System32\\ru-RU", locale = "ru_RU"},
    {path = "\\System32\\ja-JP", locale = "ja_JP"},
    {path = "\\System32\\ko-KR", locale = "ko_KR"},
    {path = "\\System32\\zh-CN", locale = "zh_CN"},
    {path = "\\System32\\zh-TW", locale = "zh_TW"}
  }

  if windir then
    for _, locale_info in ipairs(possible_locales) do
      local full_path = windir .. locale_info.path
      if is_dir(full_path) then
        dbg("Found locale directory: " .. locale_info.locale)
        table.insert(detected_locales, {source = "win_locale_dir", locale = locale_info.locale})
        break -- Just take the first one found
      end
    end
  end
end


-- macOS-specific locale detection using safe methods (no special permissions)
function detect_macos_locale(detected_locales)

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

        if i == 1 then -- AppleLocale
          local locale = string.gsub(result, "%s+", "")
          locale = string.gsub(locale, "[\r\n]", "")
          if locale ~= "" and locale ~= "(null)" then
            dbg("Found safe AppleLocale: " .. locale)
            table.insert(detected_locales, {source = "macos_safe_locale", locale = locale})
          end
        elseif i == 2 then -- AppleLanguages (first few lines)
          -- Extract first language from array output
          local first_lang = string.match(result, '"([^"]+)"')
          if first_lang then
            dbg("Found safe AppleLanguage: " .. first_lang)
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
      dbg("macOS env " .. var .. ": " .. value)
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

      -- Simple timezone to locale mapping (very basic)
      local tz_locale_map = {
        EST = "en_US", PST = "en_US", MST = "en_US",
        CET = "en_GB", GMT = "en_GB", BST = "en_GB",
        JST = "ja_JP", KST = "ko_KR",
        CST = "zh_CN" -- China Standard Time; US Central shares the abbreviation
      }

      local mapped_locale = tz_locale_map[tz_result]
      if mapped_locale then
        dbg("Mapped timezone " .. tz_result .. " to locale: " .. mapped_locale)
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
        if i == 1 then -- say command available
          table.insert(detected_locales, {source = "macos_say_available", locale = "en_US"})
        end
      end
    end
  end
end

-- How much each source of locale information is trusted (higher wins)
local LOCALE_SOURCE_PRIORITY = {
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

-- Country -> languages commonly understood there, most likely first
local COUNTRY_LANGUAGES = {
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

-- Count one sighting of `key` (a language or a country) and remember the
-- most trusted source that reported it.
local function tally(found, key, priority, source)
  local entry = found[key]
  if not entry then
    found[key] = { priority = priority, source = source, count = 1 }
    return
  end
  if priority > entry.priority then
    entry.priority = priority
    entry.source = source
  end
  entry.count = entry.count + 1
end

-- Turn the raw detections ({source=..., locale=...}) into one answer: the
-- most trusted locale and up to a handful of suggested subtitle languages
-- (the locale's own language, then the languages of its country, then
-- English as a fallback).
function analyze_detected_locales(detected_locales)
  if #detected_locales == 0 then
    return nil
  end

  local best_locale = nil
  local best_priority = -1
  local languages_found = {}
  local countries_found = {}

  for _, detection in ipairs(detected_locales) do
    local priority = LOCALE_SOURCE_PRIORITY[detection.source] or 0
    local lang, country = parse_locale_string(detection.locale)
    if lang then
      tally(languages_found, lang, priority, detection.source)
    end
    if country then
      tally(countries_found, country, priority, detection.source)
    end
    if priority > best_priority then
      best_priority = priority
      best_locale = detection
    end
  end

  if not best_locale then
    return nil
  end

  local locale_str = best_locale.locale
  local language, country = parse_locale_string(locale_str)
  local suggested_languages = {}

  local function suggest(code, priority, source, reason)
    table.insert(suggested_languages, {
      language = code, priority = priority, source = source, reason = reason
    })
  end
  local function is_suggested(code)
    for _, existing in ipairs(suggested_languages) do
      if existing.language == code then
        return true
      end
    end
    return false
  end

  if language then
    suggest(language, best_priority, best_locale.source, "primary_detection")
  end

  -- The country: the most trusted one seen, unless IP geolocation is at
  -- least as trusted
  local most_likely_country = nil
  local highest_country_priority = -1
  for country_code, info in pairs(countries_found) do
    if info.priority > highest_country_priority then
      highest_country_priority = info.priority
      most_likely_country = country_code
    end
  end
  for _, detection in ipairs(detected_locales) do
    if detection.source == "ip_geolocation" or detection.source == "ip_country_specific" then
      local _, detected_country = parse_locale_string(detection.locale)
      if detected_country and (not most_likely_country
         or LOCALE_SOURCE_PRIORITY[detection.source] >= highest_country_priority) then
        most_likely_country = detected_country
        highest_country_priority = LOCALE_SOURCE_PRIORITY[detection.source] or 0
        dbg("Using IP-detected country: " .. detected_country)
      end
    end
  end

  local country_languages = most_likely_country and COUNTRY_LANGUAGES[most_likely_country]
  if country_languages then
    for i, lang_code in ipairs(country_languages) do
      if not is_suggested(lang_code) then
        suggest(lang_code, highest_country_priority, "country_multilingual",
                i == 1 and "country_native_language" or "country_understood_language")
      end
    end
  end

  -- English as a fallback when one or two other languages were found, and as
  -- the default when nothing was
  if not is_suggested("en") and #suggested_languages >= 1 and #suggested_languages <= 2 then
    dbg("Adding English as fallback language (detected " .. #suggested_languages .. " non-English languages)")
    suggest("en", 1, "english_fallback", "international_fallback")
  end
  if #suggested_languages == 0 then
    dbg("No languages detected, defaulting to English")
    suggest("en", 1, "english_default", "default_language")
  end

  for i, lang_suggestion in ipairs(suggested_languages) do
    dbg("  " .. i .. ": " .. lang_suggestion.language .. " (" .. lang_suggestion.reason .. ")")
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


-- Everything a shell command prints, or nil when it cannot be run.
local function shell_output(command)
  local handle = io.popen(command)
  if not handle then
    return nil
  end
  local result = handle:read("*all")
  handle:close()
  return result
end

-- The KEY=value lines of a shell-style configuration file as a list of
-- { key, value } (comment lines skipped, quotes and surrounding blanks
-- removed). Empty when the file cannot be read.
local function read_assignments(path)
  local assignments = {}
  local file = io.open(path, "r")
  if not file then
    return assignments
  end
  local content = file:read("*all")
  file:close()

  for line in content:gmatch("[^\r\n]+") do
    if not string.match(line, "^%s*#") and string.find(line, "=") then
      local var, value = string.match(line, "([^=]+)=(.+)")
      if var and value then
        var = string.gsub(var, "^%s*(.-)%s*$", "%1")
        value = string.gsub(value, '"', '')
        value = string.gsub(value, "^%s*(.-)%s*$", "%1")
        table.insert(assignments, { var, value })
      end
    end
  end
  return assignments
end

-- Timezones that hint at a locale when nothing better is known
local LINUX_TIMEZONE_LOCALE = {
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

-- Locale hints on Linux, BSD and macOS. Only reads world-readable files and
-- runs harmless commands; every finding is appended to detected_locales.
function detect_unix_locale(detected_locales)
  local function found(source, locale)
    table.insert(detected_locales, { source = source, locale = locale })
  end

  local system = shell_output("uname -s 2>/dev/null")
  if system and string.find(system, "Darwin") then
    detect_macos_locale(detected_locales)
  end

  -- 1. The `locale` command
  local locale_output = shell_output("locale 2>/dev/null")
  if locale_output and locale_output ~= "" then
    for line in locale_output:gmatch("[^\r\n]+") do
      local var, value = string.match(line, "([^=]+)=(.+)")
      if var and value then
        value = string.gsub(value, '"', '')
        if value ~= "C" and value ~= "POSIX" and value ~= "" then
          found("locale_cmd_" .. var, value)
        end
      end
    end
  end

  -- 2. System-wide settings: systemd, Debian/Ubuntu, Red Hat, others
  for _, file_path in ipairs({ "/etc/locale.conf", "/etc/default/locale",
                               "/etc/sysconfig/i18n", "/etc/environment" }) do
    for _, assignment in ipairs(read_assignments(file_path)) do
      local var, value = assignment[1], assignment[2]
      if (string.match(var, "LANG") or string.match(var, "LC_")) and
         value ~= "C" and value ~= "POSIX" and value ~= "" then
        dbg("Found in " .. file_path .. ": " .. var .. "=" .. value)
        found("file_" .. string.gsub(file_path, ".*/", ""), value)
      end
    end
  end

  -- 3. Environment as a login shell sees it, installed locales, timezone
  local commands = {
    'printenv LANG 2>/dev/null',
    'printenv LC_ALL 2>/dev/null',
    'printenv LANGUAGE 2>/dev/null',
    'locale -a 2>/dev/null | head -5',
    'timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null'
  }
  for i, command in ipairs(commands) do
    local result = shell_output(command)
    if result and result ~= "" then
      result = string.gsub(result, "[\r\n]", " ")
      result = string.gsub(result, "^%s*(.-)%s*$", "%1")

      if result == "" then
        -- nothing but line breaks
      elseif i <= 3 then
        found("linux_printenv_" .. i, result)
      elseif i == 4 then
        for locale in result:gmatch("([%w_%-%.]+)") do
          if string.match(locale, "^[a-z][a-z]_[A-Z][A-Z]") then
            dbg("Found available locale: " .. locale)
            found("linux_available_locale", locale)
            break -- the first usable one is enough
          end
        end
      elseif LINUX_TIMEZONE_LOCALE[result] then
        dbg("Mapped Linux timezone to: " .. LINUX_TIMEZONE_LOCALE[result])
        found("linux_timezone_hint", LINUX_TIMEZONE_LOCALE[result])
      end
    end
  end

  -- 4. Per-user settings
  local home = os.getenv("HOME")
  if home then
    for _, file_path in ipairs({ home .. "/.locale", home .. "/.config/locale.conf",
                                 home .. "/.dmrc" }) do
      for _, assignment in ipairs(read_assignments(file_path)) do
        local var, value = assignment[1], assignment[2]
        if (string.match(var:lower(), "lang") or string.match(var:lower(), "locale")) and
           value ~= "" and value ~= "C" then
          dbg("Found user locale: " .. var .. "=" .. value)
          found("linux_user_config", value)
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

  dbg("Could not parse locale string: " .. locale_str)
  return nil, nil
end


-- Language codes as the OpenSubtitles API spells them. Almost every two-letter
-- code is used as is; these are the ones that only exist with a region.
local REGIONAL_DEFAULT = {
  zh = "zh-cn", -- Chinese -> Chinese (simplified)
  pt = "pt-pt", -- Portuguese -> Portuguese (Portugal)
  az = "az-az", -- Azerbaijani
  tm = "tm-td"  -- Tetum
}

function map_to_opensubtitles_language(language_code)
  return REGIONAL_DEFAULT[language_code] or language_code
end


-- Enhanced show_appropriate_window with auto-search capability
function show_appropriate_window()
  -- Check if user has valid authentication (already configured)
  local has_valid_auth = has_valid_authentication()


  -- Use the stored authentication check from initialization
  if init_results.has_auth or has_valid_auth then
    dbg("User has valid authentication - showing main window")
    is_authenticated = true
    show_main() -- This will now auto-search if conditions are met
  else
    dbg("No valid authentication - showing configuration window")
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


-- 3. FIXED: get_downloads_folder function - remove PowerShell command
function get_downloads_folder()
  local downloads_path = nil

  if openSub.conf.os == "win" then
    -- FIXED: Remove PowerShell command that causes popup
    -- Windows: Use only environment variables and common paths
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

    -- If standard paths don't work, just use the first one anyway
    if not downloads_path and os.getenv("USERPROFILE") then
      downloads_path = os.getenv("USERPROFILE") .. "\\Downloads"
      -- Try to create it if it doesn't exist
      mkdir_p(downloads_path)
    end

  else
    -- macOS/Linux: Standard Downloads folder (unchanged)
    local home = os.getenv("HOME")
    if home then
      local unix_downloads_path = home .. "/Downloads"
      if is_dir(unix_downloads_path) then
        downloads_path = unix_downloads_path
      end
    end
  end

  dbg("Downloads folder detected: " .. (downloads_path or "not found"))
  return downloads_path
end


-- First run: can the API be reached?
--
-- Only the API itself is asked, over plain HTTP like every API request:
-- that goes through the extension's own socket client, which has a deadline
-- and tells VLC it is alive while it waits. (It used to ask
-- https://www.google.com first. https goes through vlc.stream, which cannot
-- be timed out: on a bad connection it sat there until VLC offered to kill
-- the extension - "Extension not responding" - before the first window was
-- even up.)
--
-- A reachable but slow network (the answer took 4 s or more) sets
-- networkSlow: the optional https fetches of this start - list of interface
-- translations, update check - are skipped then, because they cannot be
-- timed out either.
networkSlow = false
function test_network_connectivity()
  update_debug_network(strings.ui_testing_network_connectivity)

  local url = api_root()
  update_debug_network(tr("ui_testing_connection_n_of", "1", "1"))
  append_debug_log(tr("ui_testing", url))

  local test_client = Curl.new() -- This uses VLC's networking, not curl
  test_client:set_aggressive_timeouts()
  test_client:set_timeout(8)
  test_client:set_deadline(8)
  test_client:set_retries(0)

  local asked_at = os.time()
  local start_time = os.clock()
  local res = test_client:get(url)
  local elapsed_ms = math.floor((os.clock() - start_time) * 1000)
  networkSlow = (os.time() - asked_at) >= 4

  -- Any HTTP answer proves the API can be reached. Its root answers 403
  -- ("You cannot consume this service" - no API key is sent here), and that
  -- is an answer.
  if res and res.status then
    update_debug_network(tr("ui_connection_ok_ms", tostring(elapsed_ms)))
    append_debug_log(tr("ui_network_test_passed_ms", url, tostring(elapsed_ms)))
    return true
  end
  append_debug_log(tr("ui_network_test_failed_ms", url, tostring(elapsed_ms)))

  update_debug_network(strings.ui_offline_mode_limited_functionality)
  append_debug_log(strings.ui_warning_no_internet_connection_detected)
  append_debug_log(strings.ui_extension_uses_vlc_s_built_in_networking)
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
    append_debug_log(strings.ui_offline_extension_will_have_limited_functionalit)
    update_debug_status(strings.ui_warning_no_internet_limited_functionality)
    shouldStayOpen = true  -- Keep debug window open for offline mode
  else
    update_debug_status(strings.ui_network_connection_verified)
    append_debug_log(strings.ui_network_connection_successful)
  end

  -- Update button labels based on current status
  update_debug_buttons()

  -- Only auto-close if we have both: working core functionality AND network
  if allTestsPassed and not hasCriticalFailure and not networkTestsFailed then
    append_debug_log(strings.ui_all_tests_passed_auto_closing_in_3)

    -- Update button to show countdown
    if debug_messages and debug_messages.ok_button then
      for countdown = 3, 1, -1 do
        debug_messages.ok_button:set_text(tr("ui_auto_close", tostring(countdown)))
        if debug_dlg then
          debug_dlg:update()
        end

        -- Wait 1 second
        local start_time = os.clock()
        while (os.clock() - start_time) < 1 do
        end
      end
    end

    if debug_dlg then
      close_debug_window()
      show_appropriate_window()
    end
  else
    -- Keep debug window open for user information
    if shouldStayOpen then
      if networkTestsFailed and allTestsPassed then
        dbg("Core functionality OK but offline - keeping debug window open")
        append_debug_log(strings.ui_click_continue_offline_to_proceed_with_limited)
        update_debug_status(strings.ui_click_continue_offline_to_proceed)
      else
        dbg("Critical initialization failure - keeping debug window open")
        append_debug_log(strings.ui_critical_failures_detected_click_continue_anyway)
        update_debug_status(strings.ui_critical_errors_manual_intervention_needed)
      end
    end
  end
end


-- HTTP client. https:// goes through vlc.stream (GET only, no headers),
-- http:// through a raw socket so that headers and a body can be sent.
-- See docs/vlc-lua-environment.md for why.
local VLCHttpClient = {}
VLCHttpClient.__index = VLCHttpClient

function VLCHttpClient.new()
    local self = setmetatable({}, VLCHttpClient)
    self.headers = {}
    self.timeout = 30
    self.retries = 2
    self.raw = false
    return self
end

function VLCHttpClient:set_raw(flag)
    self.raw = flag and true or false
    return self
end

function VLCHttpClient:add_header(key, value)
    self.headers[key] = value
    return self
end

function VLCHttpClient:set_timeout(seconds)
    self.timeout = tonumber(seconds) or 30
    return self
end

-- How long one plain-HTTP request may take in all (15 s unless raised: VLC's
-- window is frozen for that long).
function VLCHttpClient:set_deadline(seconds)
    self.deadline = tonumber(seconds)
    return self
end

-- A side service (not the API): its host failing to connect says nothing
-- about the network, so it does not hold back the next requests
-- (network_down_until)
function VLCHttpClient:set_side_service()
    self.side_service = true
    return self
end

-- fn(seconds) is called about once a second while an answer is awaited
function VLCHttpClient:set_on_wait(fn)
    self.on_wait = fn
    return self
end

function VLCHttpClient:set_retries(count)
    self.retries = tonumber(count) or 2
    return self
end

function VLCHttpClient:set_aggressive_timeouts()
    self.timeout = 15
    self.retries = 1
    return self
end


-- Fix for OpenSubtitles.com API URL parameter sorting requirement
-- The API returns 301 redirects if parameters are not sorted alphabetically

-- Enhanced URL building function with parameter sorting
function build_sorted_url(base_url, params_table)
    if not params_table or next(params_table) == nil then
        return base_url
    end

    -- Filter out default values that don't need to be sent
    local filtered_params = {}
    for key, value in pairs(params_table) do
        -- Skip default values
        local is_default = (key == "ai_translated" and value == "include")
                        or (key == "machine_translated" and value == "exclude")
        if not is_default then
            filtered_params[key] = value
        end
    end

    -- Convert filtered params table to array for sorting
    local sorted_params = {}
    for key, value in pairs(filtered_params) do
        -- Check if this is an x-* parameter (should preserve case)
        local is_x_param = string.match(string.lower(key), "^x%-") ~= nil

        -- Convert parameter name to lowercase (except x-* params)
        local processed_key = is_x_param and key or string.lower(key)
        local processed_value = tostring(value)

        -- Only apply ID cleanup for non-x-* parameters
        if not is_x_param then
            -- Clean up IMDB IDs: remove 'tt' prefix and leading zeros
            if processed_key == "imdb_id" then
                -- Remove 'tt' prefix if present (case-insensitive)
                processed_value = string.gsub(processed_value, "^[Tt][Tt]", "")
                -- Remove leading zeros
                processed_value = string.gsub(processed_value, "^0+", "")
                -- Keep at least one digit if all zeros
                if processed_value == "" then
                    processed_value = "0"
                end
            end

            -- Remove leading zeros from other ID parameters
            if string.match(processed_key, "id$") or string.match(processed_key, "_number$") then
                processed_value = string.gsub(processed_value, "^0+", "")
                if processed_value == "" then
                    processed_value = "0"
                end
            end

            -- Convert value to lowercase (except for x-* params)
            processed_value = string.lower(processed_value)
        end

        table.insert(sorted_params, {key = processed_key, value = processed_value})
    end

    -- Sort parameters alphabetically by key
    table.sort(sorted_params, function(a, b)
        return a.key < b.key
    end)

    -- Build query string using our custom encoder
    local query_parts = {}
    for _, param in ipairs(sorted_params) do
        local encoded_key = url_encode(param.key)
        local encoded_value = url_encode(param.value)
        table.insert(query_parts, encoded_key .. "=" .. encoded_value)
    end

    local query_string = table.concat(query_parts, "&")
    local separator = string.find(base_url, "?") and "&" or "?"

    return base_url .. separator .. query_string
end




-- Enhanced _build_url_params method that decodes existing URL params and rebuilds with sorting
            --[[ Subtitle search ]]--


-- First steps of every search. Returns false when no session could be set up.
local function search_begin()
  -- which video the coming results are for (the upload window uses them)
  openSub.lastSearchUri = openSub.file.uri
  openSub.actionLabel = lang["action_search"]
  setMessage(openSub.actionLabel..": "..progressBarContent(0))
  applySubtitleSortingSelection()

  if not openSub.checkSession() then
    vlc.msg.err("[VLSub] Failed to establish session")
    return false
  end
  return true
end

-- GET /subtitles with `params` plus the selected languages and sort order.
-- The API redirects unless the query is canonical; build_sorted_url takes
-- care of that. Returns url, response (nil when nothing came back).
-- With `protected`, a Lua error raised by the request is caught and returned
-- as a third value instead of propagating.
local function search_get(params, protected)
  if openSub.movie.sublanguageid and openSub.movie.sublanguageid ~= "all" then
    params["languages"] = openSub.movie.sublanguageid
  end
  if openSub.option.sortBy and openSub.option.sortBy ~= "" then
    params["order_by"] = openSub.option.sortBy
    params["order_direction"] = (openSub.option.sortDirection == "asc") and "asc" or "desc"
  end

  -- (measured: ai_translated=exclude removes the on-demand entries and the
  -- AI uploads)
  filter_params(params)

  local url = build_sorted_url(api_url("/subtitles"), params)

  local client = Curl.new()
  client:add_header("Api-Key", api_key())
  local auth_header = openSub.getAuthHeader()
  if auth_header then
    client:add_header("Authorization", auth_header)
  end
  client:set_timeout(30)
  client:set_retries(2)

  if not protected then
    return url, client:get(url)
  end
  local request_ok, res = pcall(function()
    return client:get(url)
  end)
  if not request_ok then
    return url, nil, res
  end
  return url, res
end

-- The result list of a 200 answer, or nil (plus the decode error, if any).
local function search_results(res)
  local ok, parsed_data = decode_object(res.body)
  if ok and parsed_data.data then
    -- "data" that is not a list holds no subtitles
    return openSub.convertNewAPIResponse(type(parsed_data.data) == "table" and parsed_data.data or {})
  end
  return nil, (not ok) and parsed_data or nil
end

local function is_positive_number(value)
  return value and value ~= "" and tonumber(value) and tonumber(value) > 0
end

-- Search by title (plus year, season, episode). Leaves the result list, or
-- "0" when there is none, in openSub.itemStore.
openSub.searchSubtitlesNewAPI = function(is_retry)
  if not search_begin() then
    openSub.itemStore = "0"
    return
  end

  local params = {}
  if openSub.movie.title and openSub.movie.title ~= "" then
    params["query"] = openSub.movie.title
  end
  if openSub.movie.year and openSub.movie.year ~= "" then
    params["year"] = openSub.movie.year
  end
  if is_positive_number(openSub.movie.seasonNumber) then
    params["season_number"] = openSub.movie.seasonNumber
  end
  if is_positive_number(openSub.movie.episodeNumber) then
    params["episode_number"] = openSub.movie.episodeNumber
  end

  local url, res = search_get(params)
  local status = res and res.status

  if status == 200 and res.body then
    local items = search_results(res)
    if items then
      openSub.itemStore = items
      dbg("Found " .. #items .. " subtitles")
    else
      vlc.msg.err("[VLSub] Failed to parse API response: " .. (res.body or "no body"))
      openSub.itemStore = "0"
    end
  elseif status == 301 then
    vlc.msg.err("[VLSub] 301 Redirect - URL parameters may not be sorted correctly")
    vlc.msg.err("[VLSub] URL was: " .. url)
    openSub.itemStore = "0"
  elseif status == 401 then
    dbg("Authentication failed, attempting re-login")
    if not is_retry and openSub.refreshSession() then
      openSub.searchSubtitlesNewAPI(true)
    else
      openSub.lastTransportError = api_error_message(401)
      openSub.itemStore = "0"
    end
  elseif status then
    vlc.msg.err("[VLSub] API request failed with status: " .. status)
    if res.body then
      vlc.msg.err("[VLSub] Error response: " .. res.body)
    end
    openSub.lastTransportError = api_error_message(status)
    openSub.itemStore = "0"
  else
    vlc.msg.err("[VLSub] API request failed - no response")
    openSub.itemStore = "0"
  end
end

-- Statuses the IMDb search only logs (no explanation under the result list)
local IMDB_STATUS_LOG = {
  [403] = "Access forbidden (HTTP 403)",
  [404] = "Resource not found (HTTP 404)",
  [500] = "Server error (HTTP 500)",
  [503] = "Service unavailable (HTTP 503)",
}

-- Search by IMDb id. Result list, or "0", in openSub.itemStore.
openSub.searchSubtitlesByIMDB = function(imdbId, is_retry)
  if not search_begin() then
    openSub.itemStore = "0"
    return
  end

  if not imdbId or imdbId == "" then
    vlc.msg.err("[VLSub] No IMDB ID provided")
    openSub.itemStore = "0"
    return
  end

  local _, res, crash = search_get({ imdb_id = imdbId }, true)
  if crash then
    vlc.msg.err("[VLSub] HTTP request crashed with error: " .. tostring(crash))
    openSub.itemStore = "0"
    return
  end
  local status = res and res.status

  if status == 200 and res.body then
    local items = search_results(res)
    if items then
      openSub.itemStore = items
      dbg("Found " .. #items .. " subtitles by IMDB ID")
    else
      vlc.msg.err("[VLSub] Failed to parse API response: " .. (res.body or "no body"))
      openSub.itemStore = "0"
    end
  elseif status == 401 then
    dbg("Authentication failed, attempting re-login")
    if not is_retry and openSub.refreshSession() then
      openSub.searchSubtitlesByIMDB(imdbId, true)
    else
      openSub.lastTransportError = api_error_message(401)
      openSub.itemStore = "0"
    end
  elseif status == 429 then
    vlc.msg.err("[VLSub] Rate limit exceeded (HTTP 429)")
    openSub.lastTransportError = api_error_message(429)
    openSub.itemStore = "0"
  elseif IMDB_STATUS_LOG[status] then
    vlc.msg.err("[VLSub] " .. IMDB_STATUS_LOG[status])
    openSub.itemStore = "0"
  elseif status then
    vlc.msg.err("[VLSub] API request failed with status: " .. status)
    if res.body then
      vlc.msg.err("[VLSub] Error response: " .. res.body)
    end
    openSub.lastTransportError = api_error_message(status)
    openSub.itemStore = "0"
  else
    vlc.msg.err("[VLSub] API request failed - no response")
    openSub.itemStore = "0"
  end
end

-- Hash search: status -> { error log line, key of the message shown to the user }
local HASH_STATUS = {
  [429] = { "Rate limit exceeded (HTTP 429). Too many requests.", "ui_rate_limit_too_many_requests_please_wait" },
  [403] = { "Access forbidden (HTTP 403)", "ui_access_forbidden_check_your_api_permissions" },
  [404] = { "Resource not found (HTTP 404)", "ui_resource_not_found" },
  [500] = { "Server error (HTTP 500)", "ui_server_error_please_try_again_later" },
  [503] = { "Service unavailable (HTTP 503)", "ui_service_temporarily_unavailable" },
}

-- Search by file hash. Unlike the other two it reports its outcome itself:
-- the result list (or an empty table) goes to openSub.itemStore, a message is
-- set and the list is displayed.
openSub.searchSubtitlesByHashNewAPI = function(is_retry)
  local function nothing(message)
    openSub.itemStore = {}
    setMessage(error_tag(message))
  end

  if not search_begin() then
    nothing(lang["mess_no_res"])
    display_subtitles()
    return
  end

  if not openSub.file.hash or openSub.file.hash == "" then
    vlc.msg.err("[VLSub] No movie hash available")
    nothing(lang["mess_no_input"])
    display_subtitles()
    return
  end

  local params = { moviehash = openSub.file.hash }
  if openSub.file.bytesize and openSub.file.bytesize > 0 then
    params["moviebytesize"] = tostring(openSub.file.bytesize)
  end

  local url, res, crash = search_get(params, true)
  if crash then
    vlc.msg.err("[VLSub] HTTP request crashed with error: " .. tostring(crash))
    nothing(strings.ui_network_error_connection_failed)
    display_subtitles()
    return
  end
  local status = res and res.status

  if status == 200 and res.body then
    local items, decode_error = search_results(res)
    if items then
      openSub.itemStore = items
      dbg("Found " .. #items .. " subtitles by hash")
      if #items > 0 then
        setMessage(success_tag(tr("ui_search_complete_count", tostring(#items))))
      else
        setMessage(error_tag(lang["mess_no_res"]))
      end
    else
      if decode_error then
        vlc.msg.err("[VLSub] JSON decode error: " .. tostring(decode_error))
      end
      vlc.msg.err("[VLSub] Failed to parse hash search API response")
      nothing(lang["mess_no_res"])
    end
  elseif status == 301 then
    vlc.msg.err("[VLSub] 301 Redirect in hash search - URL parameters may not be sorted correctly")
    vlc.msg.err("[VLSub] URL was: " .. url)
    nothing(strings.ui_api_error_url_parameters_not_sorted_correctly)
  elseif status == 401 then
    dbg("Authentication failed during hash search, attempting re-login")
    if not is_retry and openSub.refreshSession() then
      openSub.searchSubtitlesByHashNewAPI(true)
      return
    end
    nothing(lang["mess_unauthorized"])
  elseif HASH_STATUS[status] then
    vlc.msg.err("[VLSub] " .. HASH_STATUS[status][1])
    nothing(strings[HASH_STATUS[status][2]])
  elseif status then
    vlc.msg.err("[VLSub] Hash search API request failed with status: " .. status)
    if res.body then
      vlc.msg.err("[VLSub] Hash search error response: " .. res.body)
    end
    openSub.itemStore = {}
    local redirect_mess = network_redirect_message(status)
    if redirect_mess then
      openSub.lastTransportError = redirect_mess
      setMessage(error_tag(redirect_mess))
    else
      setMessage(error_tag(tr("ui_error_http", tostring(status))))
    end
  else
    vlc.msg.err("[VLSub] Hash search API request failed - no response")
    nothing(lang["mess_no_response"])
  end

  display_subtitles()
end

function VLCHttpClient:_build_url_params(url, data)
    local all_params = {}

    -- Step 1: Extract base URL and existing parameters from the input URL
    local base_url = url
    local query_start = string.find(url, "?")

    if query_start then
        base_url = string.sub(url, 1, query_start - 1)
        local query_string = string.sub(url, query_start + 1)

        -- Decode existing parameters from the URL
        for param_pair in string.gmatch(query_string, "([^&]+)") do
            local key, value = string.match(param_pair, "([^=]+)=(.+)")
            if key and value then
                -- Decode the key and value using our custom decoder
                local decoded_key = url_decode(key)
                local decoded_value = url_decode(value)
                all_params[decoded_key] = decoded_value
            end
        end
    end

    -- Step 2: Add headers as URL parameters (these will override any existing ones with same names)
    for key, value in pairs(self.headers) do
        local param_name
        if key:lower() == "authorization" then
            param_name = "x-authorization"
        elseif key:lower() == "api-key" then
            param_name = "x-api-key"
        elseif key:lower() == "content-type" then
            param_name = "x-content-type"
        elseif key:lower() == "user-agent" then
            -- Also send user-agent as x-user-agent for server-side tracking
            param_name = "x-user-agent"
        else
            param_name = "x-" .. key:lower():gsub("-", "-")
        end
        if param_name then
            all_params[param_name] = value
        end
    end

    -- Step 3: Add POST data if present
    if data then
        all_params["x-post-data"] = data
    end

    -- Step 4: Build final URL with ALL parameters sorted alphabetically using custom encoder
    local final_url = build_sorted_url(base_url, all_params)


    return final_url
end


-- Custom URL decode function
function url_decode(str)
    if not str then return "" end
    str = string.gsub(str, "+", " ")  -- Convert + back to spaces first
    str = string.gsub(str, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end


-- Custom URL encode function (OpenSubtitles.com compatible - uses + for spaces)
function url_encode(str)
    if not str then return "" end
    -- First handle newlines
    str = string.gsub(str, "\n", "\r\n")
    -- Encode special characters but NOT spaces yet
    str = string.gsub(str, "([^%w %-%_%.%~])",
        function(c) return string.format("%%%02X", string.byte(c)) end)
    -- Convert spaces to + (OpenSubtitles.com preferred format)
    str = string.gsub(str, " ", "+")
    return str
end


-- Parse HTTP response headers
local function parse_response_headers(header_text)
    local headers = {}
    local status_line, remaining = string.match(header_text, "^([^\r\n]+)\r?\n(.*)$")

    if not status_line then
        return nil, {}
    end

    -- Extract status code from status line (e.g., "HTTP/1.1 200 OK")
    local status_code = tonumber(string.match(status_line, "HTTP/[%d%.]+%s+(%d+)"))

    -- Parse individual headers
    for line in string.gmatch(remaining, "([^\r\n]+)") do
        local key, value = string.match(line, "^([^:]+):%s*(.*)$")
        if key and value then
            headers[string.lower(key)] = value
        end
    end

    return status_code, headers
end

-- Function to decode chunked transfer encoding
local function decode_chunked_body(body)
    if not body or body == "" then
        return ""
    end


    local decoded = ""
    local pos = 1
    local chunk_count = 0

    while pos <= string.len(body) do
        -- Find the end of the chunk size line
        local chunk_size_end = string.find(body, "\r\n", pos)
        if not chunk_size_end then
            chunk_size_end = string.find(body, "\n", pos)
            if not chunk_size_end then
                break
            end
        end

        -- Extract chunk size (in hex)
        local chunk_size_str = string.sub(body, pos, chunk_size_end - 1)
        chunk_size_str = string.gsub(chunk_size_str, "%s", "") -- Remove whitespace

        -- Convert hex to decimal
        local chunk_size = tonumber(chunk_size_str, 16)

        if not chunk_size then
            -- Not a valid chunk size, might be the start of actual content
            dbg("Invalid chunk size, treating as regular content: " .. chunk_size_str)
            break
        end


        if chunk_size == 0 then
            -- End of chunks
            break
        end

        -- Move past the chunk size line
        pos = chunk_size_end + (string.sub(body, chunk_size_end, chunk_size_end + 1) == "\r\n" and 2 or 1)

        -- Extract the chunk data
        local chunk_data = string.sub(body, pos, pos + chunk_size - 1)
        decoded = decoded .. chunk_data


        -- Move past the chunk data and trailing CRLF
        pos = pos + chunk_size
        if string.sub(body, pos, pos + 1) == "\r\n" then
            pos = pos + 2
        elseif string.sub(body, pos, pos) == "\n" then
            pos = pos + 1
        end
        chunk_count = chunk_count + 1
    end

    return decoded
end

-- Function to clean response body (handles both chunked and regular responses)
local function clean_response_body(body, headers)
    if not body or body == "" then
        return ""
    end

    local transfer_encoding = headers and headers["transfer-encoding"]
    if transfer_encoding and string.find(string.lower(transfer_encoding), "chunked", 1, true) then
        return decode_chunked_body(body)
    end

    -- Not chunked: the body is the payload. (An earlier version cut out the
    -- first balanced {...} here, which truncated JSON containing "}" inside a
    -- string and dropped the brackets of a JSON array.)
    body = string.gsub(body, "^%s+", "")
    body = string.gsub(body, "%s+$", "")
    return body
end

-- True if any bit of `flag` is set in `value`. Lua 5.1/5.2 have no bitwise
-- operators, and the POLL* constants differ between platforms (POLLIN is two
-- bits on Windows), so the values cannot be hard-coded.
local function has_flag(value, flag)
    if not value or not flag then return false end
    while value > 0 and flag > 0 do
        if value % 2 == 1 and flag % 2 == 1 then return true end
        value = math.floor(value / 2)
        flag = math.floor(flag / 2)
    end
    return false
end

-- Send `request` to host:port over plain TCP and return everything the server
-- sends until it closes the connection (requests carry "Connection: close").
--
-- Returns the raw response, or nil plus a reason: "connect", "timeout",
-- "interrupted".
--
-- Two VLC quirks shape this function (see docs/vlc-lua-environment.md):
--   * vlc.net.connect_tcp returns a normal-looking descriptor even when the
--     connection failed; only send() returning a negative number shows it.
--   * vlc.net.poll ignores its timeout and blocks until a descriptor is
--     ready. Asking for POLLOUT as well makes it return at once (a connected
--     socket is always writable), which turns it into a non-blocking check so
--     the deadline below can be enforced. Polling a dead descriptor, or
--     polling for POLLIN alone on a silent server, freezes VLC's interface.
-- `on_wait(seconds)` is called about once a second while the answer is
-- awaited, so a long request can show that it is alive.
function socket_exchange(host, port, request, timeout_seconds, on_wait)
    local fd = vlc.net.connect_tcp(host, port)
    if not fd or fd < 0 then
        return nil, "connect"
    end

    local sent = vlc.net.send(fd, request)
    if not sent or sent < 0 then
        pcall(vlc.net.close, fd)
        return nil, "connect"
    end

    local events = vlc.net.POLLIN + vlc.net.POLLOUT
    local started = os.time()
    local deadline = started + (timeout_seconds or 15)
    local last_tick = started
    local parts = {}
    local failure = nil

    while true do
        local fds = {}
        fds[fd] = events
        local polled = pcall(vlc.net.poll, fds)
        if not polled then
            failure = "interrupted" -- VLC is shutting the extension down
            break
        end

        local revents = fds[fd] or 0
        if has_flag(revents, vlc.net.POLLIN) or has_flag(revents, vlc.net.POLLHUP)
           or has_flag(revents, vlc.net.POLLERR) or has_flag(revents, vlc.net.POLLNVAL) then
            local chunk = vlc.net.recv(fd, 8192)
            if not chunk or chunk == "" then
                break -- end of stream
            end
            parts[#parts + 1] = chunk
        elseif os.time() > deadline then
            failure = "timeout"
            break
        elseif os.time() ~= last_tick then
            last_tick = os.time()
            -- VLC offers to kill an extension that has been busy for 10 s
            -- ("Extension not responding"); tell it this one is alive
            if vlc.keep_alive then
                pcall(vlc.keep_alive)
            end
            if on_wait then
                on_wait(last_tick - started)
            end
        end
    end

    pcall(vlc.net.close, fd)

    if failure then
        return nil, failure
    end
    return table.concat(parts)
end

-- A connection that cannot be opened blocks VLC until the system gives up
-- (name lookup, connect: seconds each, and nothing in VLC's Lua can cut it
-- short). So when one fails, further requests are refused at once for a
-- short while instead of freezing the window again and again, and the failed
-- one is not retried: a second attempt at a dead network only doubles the
-- wait. The next click after that tries again.
local NETWORK_DOWN_SECONDS = 10
network_down_until = 0

function VLCHttpClient:_make_request_stream(method, url, data)

    -- Build final URL with minimal parameters to reduce URL length
    local final_url = self:_build_url_params(url, data)

    -- Single attempt with aggressive timeout
    -- vlc.stream cannot be timed out and nothing runs while it waits: at
    -- least start it with VLC's 10 s "not responding" clock at zero
    if vlc.keep_alive then
        pcall(vlc.keep_alive)
    end
    local asked_at = os.time()
    local stream = vlc.stream(final_url)
    if vlc.keep_alive then
        pcall(vlc.keep_alive)
    end
    if not stream then
        -- nil is also an HTTP error status, which comes back quickly; a
        -- network that is down takes VLC several seconds to give up on
        if os.time() - asked_at >= 4 then
            network_down_until = os.time() + NETWORK_DOWN_SECONDS
        end
        return nil
    end

    local response_data = ""
    local chunk_size = 16384  -- Larger chunks for better performance
    local max_size = 1048576  -- 1MB limit
    local bytes_read = 0

    -- Read with timeout
    local start_time = os.clock()
    while bytes_read < max_size do
        -- Aggressive timeout check
        if (os.clock() - start_time) > self.timeout then
            dbg("Stream timeout, breaking")
            break
        end

        local chunk = stream:read(chunk_size)
        if not chunk or chunk == "" then
            break
        end

        response_data = response_data .. chunk
        bytes_read = bytes_read + #chunk

        -- Early break if we detect end of JSON (skip for raw subtitle downloads)
        if not self.raw and string.find(chunk, "}$") and string.find(response_data, "^{") then
            break
        end
    end


    if bytes_read > 0 then
        local cleaned_body
        if self.raw then
            cleaned_body = response_data
        else
            cleaned_body = clean_response_body(response_data, {})
        end
        return {
            status = 200,
            headers = {},
            body = cleaned_body
        }
    end

    return nil
end

-- Use vlc.net.connect_tcp for HTTP requests
function VLCHttpClient:_make_request_tcp(method, url, data)
    local host, path, option, protocol, named_port = parse_url(url)
    local port = (protocol == "https") and 443 or 80
    -- a port in the URL (only a developer's test server has one)
    if named_port and named_port > 0 then
        port = named_port
    end
    if not protocol or not host then
        vlc.msg.err("[VLSub] Invalid URL: " .. url)
        return nil
    end

    -- Reconstruct full path with query string if present
    -- vlc.net.url_parse gives path = nil for a URL without one ("http://host")
    local full_path = (path and path ~= "") and path or "/"
    if option and option ~= "" then
        full_path = full_path .. "?" .. option
    end


    -- Build HTTP request
    local request_lines = {}
    table.insert(request_lines, method .. " " .. full_path .. " HTTP/1.1")
    table.insert(request_lines, "Host: " .. host .. ((port ~= 80 and port ~= 443) and (":" .. port) or ""))
    table.insert(request_lines, "User-Agent: " .. app_useragent)
    table.insert(request_lines, "Accept: */*")
    table.insert(request_lines, "Connection: close")

    -- Add custom headers (excluding ones already added above)
    for key, value in pairs(self.headers) do
        if string.lower(key) ~= "host"
           and string.lower(key) ~= "connection"
           and string.lower(key) ~= "user-agent" then
            table.insert(request_lines, key .. ": " .. value)
        end
    end

    -- Add Content-Length for POST/PUT requests
    if data and (method == "POST" or method == "PUT") then
        table.insert(request_lines, "Content-Length: " .. string.len(data))
    end

    -- End headers
    table.insert(request_lines, "")
    table.insert(request_lines, "")

    local request = table.concat(request_lines, "\r\n")

    -- Add POST data if present
    if data and (method == "POST" or method == "PUT") then
        request = request .. data
    end

    local attempt = 0
    while attempt <= self.retries do
        attempt = attempt + 1

        local response_data, failure = socket_exchange(host, port, request, self.deadline or math.min(self.timeout, 15), self.on_wait)

        if not response_data then
            vlc.msg.err("[VLSub] Request to " .. host .. ":" .. port .. " failed: " .. failure .. " (attempt " .. attempt .. ")")
            if failure == "interrupted" then
                return nil
            end
            if failure == "connect" then
                if not self.side_service then
                    network_down_until = os.time() + NETWORK_DOWN_SECONDS
                end
                return nil
            end
        elseif response_data == "" then
            vlc.msg.err("[VLSub] Empty response from server (attempt " .. attempt .. ")")
        else
            -- Split headers and body
            local header_end, body_start = string.find(response_data, "\r\n\r\n", 1, true)
            if not header_end then
                header_end, body_start = string.find(response_data, "\n\n", 1, true)
            end

            local headers_text, body
            if header_end then
                headers_text = string.sub(response_data, 1, header_end - 1)
                body = string.sub(response_data, body_start + 1)
            else
                headers_text = response_data
                body = ""
            end

            local status_code, headers = parse_response_headers(headers_text)

            if status_code then
                local decoded_body
                if self.raw then
                    -- Raw mode (subtitle download): only undo the transfer encoding
                    local te = headers and headers["transfer-encoding"]
                    if te and string.lower(te) == "chunked" then
                        decoded_body = decode_chunked_body(body)
                    else
                        decoded_body = body
                    end
                else
                    decoded_body = clean_response_body(body, headers)
                end

                -- Sizes only: bodies can contain the session token.
                dbg("HTTP " .. status_code .. ", " .. string.len(body) ..
                            " bytes on the wire, " .. string.len(decoded_body) .. " bytes decoded")

                return {
                    status = status_code,
                    headers = headers,
                    body = decoded_body
                }
            else
                vlc.msg.err("[VLSub] Failed to parse HTTP response")
            end
        end

        -- Small delay before retry
        if attempt <= self.retries then
            local delay_start = os.clock()
            while (os.clock() - delay_start) < 1 do end  -- 1 second delay
        end
    end

    return nil
end

-- Main request method - chooses implementation based on protocol
function VLCHttpClient:_make_request(method, url, data)
    -- Log the full URL for complete visibility
    vlc.msg.warn("[VLSub] " .. method .. " " .. url)

    -- The network just proved to be down: do not block VLC's window again
    -- for every further request of the same action (see network_down_until)
    if os.time() < network_down_until then
        vlc.msg.err("[VLSub] Not sent: the network was unreachable a moment ago")
        return nil
    end

    -- Parse URL to determine protocol
    local protocol = string.match(url, "^(https?)://")
    if not protocol then
        vlc.msg.err("[VLSub] Invalid URL: " .. url)
        return nil
    end

    -- Choose method based on protocol:
    -- HTTPS -> use vlc.stream
    -- HTTP -> use vlc.net.connect_tcp
    if protocol == "https" then
        return self:_make_request_stream(method, url, data)
    else
        return self:_make_request_tcp(method, url, data)
    end
end

-- Public HTTP methods
function VLCHttpClient:get(url)
    return self:_make_request("GET", url)
end

function VLCHttpClient:post(url, data)
    return self:_make_request("POST", url, data or "")
end

function VLCHttpClient:put(url, data)
    return self:_make_request("PUT", url, data or "")
end

function VLCHttpClient:delete(url)
    return self:_make_request("DELETE", url)
end

-- Update the global Curl reference
function Curl.new()
    return VLCHttpClient.new()
end
