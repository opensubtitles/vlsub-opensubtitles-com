# Open questions from the refactor

Things noticed while refactoring that would change what a user sees if they
were fixed. Under the unattended rule in `docs/refactor-brief.md` they were
left exactly as they are; each needs a decision.

## Locale detection

1. **US Central time is read as Chinese on macOS.** The macOS timezone table
   listed `CST` twice (`en_US` and `zh_CN`); in Lua the later entry wins, so
   `CST` has always meant `zh_CN`. It is only a weak hint
   (`macos_timezone_hint`), used when nothing better is known.
   Options: drop `CST` (ambiguous), or map it to `en_US`.
2. **Multilingual countries in the IP-geolocation table.** Canada, Switzerland
   and Belgium were each listed under several languages; the last entry won,
   so Canada counts as French, Switzerland as Italian, Belgium as Dutch.
   The separate `COUNTRY_LANGUAGES` table then adds the other languages as
   second and third choice, so the effect is only on which one comes first.
   Options: Canada -> English, Switzerland -> German, Belgium -> Dutch.
3. **`CET` (Central European Time) maps to `en_GB`** in the same macOS table.

## API answers

4. **A search or download answer that is valid JSON but not an object**
   (`true`, `1`, `"text"`) raises a Lua error instead of "no result".
   Recorded as `known_bug` tests in `tests/spec/03_search_spec.lua` and
   `05_download_spec.lua`.
5. **IMDb search shows no explanation for 403, 404, 500 and 503**, only "no
   result"; name search explains them. (The log has the status.)

## Windows

6. On the Windows-flavoured test run the settings are stored under VLC's
   program directory (`C:\Program Files\VideoLAN\VLC\lua\extensions\userdata`)
   rather than the user's profile. This is what v1.3.2 does when that
   directory is writable; on a real Windows it usually is not, and the user
   directory is used. Not verified on a real Windows machine.
