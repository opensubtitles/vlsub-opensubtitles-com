# Interface translations

One file per language: `locale/<code>.json`, where `<code>` is the language
code OpenSubtitles uses (`sk`, `de`, `pt-br`, ...).

The extension itself carries English only. When a user picks another
language in the configuration window (or a new installation detects one), the
extension downloads `locale/<code>.json` from the `main` branch of this
repository, stores it in its own folder and refreshes it at most once a week.
A translation merged here therefore reaches users within a week, without a
release.

## Files

| File | What it is |
|---|---|
| `en.json` | The English strings, generated from `vlsubcom.lua`. Reference only - do not edit; run `lua tests/export_strings.lua` after changing a string in the script. |
| `<code>.json` | A translation: the same keys, translated values. Keys may be left out; English is used for them. |
| `index.json` | Which languages exist and whether they have been reviewed. |

## Status of a language

- `ready` - offered in the language drop-down. Every language in this
  directory is `ready`.
- `review` - held back: not offered to users. To look at one anyway, add
  `"translationPreview": true` to `vlsub_conf.json`; it then appears in the
  drop-down marked "(not reviewed)". `tools/locale.lua new` starts a language
  in this state, so a half-finished file is never offered.

The translations were machine-generated, using the wording of the
opensubtitles.org website (its translation database) for the common terms.
They were not read through by native speakers before release. **If something
reads wrong, please fix it**: edit `locale/<code>.json` and open a pull
request, or open an issue quoting the string. A correction reaches every user
within a week, without a new release of the extension.

## Rules for a translation (checked by `tests/run.sh`)

1. Only keys that exist in `en.json`.
2. Every value is a non-empty string.
3. `%s` placeholders: the same number as in the English string. They are
   filled in order, so keep the order. (`"Quota: %s/%s downloads"` - first is
   used, second is the total.)
4. HTML tags (`<b>`, `<a href='...'>`, `<br>`, `<tt>`, ...): the same tags as
   in the English string, unchanged. Translate the text between them, never
   the URL.
5. A leading or trailing space in the English string is part of the layout;
   keep it.
6. Emoji at the start of button labels stay.
7. Do not translate product names: VLSub, OpenSubtitles.com, VLC, GuessIt,
   dkjson, IMDB.

## What the extension does with a file

It does not trust it. A translated string is used only if its key exists, it
is a non-empty string of sane length, and its `%s` placeholders, HTML tags and
edge spaces match the English string. Anything else is ignored and the
English text is shown for that one string - so the rules above are enforced
twice, here by the tests and in VLC by the extension.

## Trying a translation before it is merged

```bash
VLSUB_LOCALE_URL=https://raw.githubusercontent.com/<you>/<fork>/<branch>/locale/ \
  tools/dev.sh run
```

`tools/dev.sh realvlc` does this automatically for the branch you are on.

## Contributing

`tools/locale.lua` does the bookkeeping (plain Lua, nothing to install):

```bash
lua tools/locale.lua status              # all languages: coverage, problems, status
lua tools/locale.lua new de "Deutsch" "German"   # start a language
lua tools/locale.lua missing de          # what is left to translate, with the English text
lua tools/locale.lua check de            # every rule above, with the exact string at fault
lua tools/locale.lua ready de            # offer it to users (must have 0 problems)
lua tools/locale.lua review de           # take it back out
lua tools/locale.lua export              # after changing English strings in vlsubcom.lua
```

1. `new` creates `locale/<code>.json` and the entry in `index.json`
   (status `review`). To improve an existing translation, just edit its file.
2. Translate. Keys may be left out; English is used for them.
3. `check` until it reports 0 problems, then `tests/run.sh` (it also starts
   the extension with your translation applied: all windows, a search, a
   download and a first run).
4. Open a pull request. A second pull request by (or confirmed by) a native
   speaker runs `ready`.

When English strings change in `vlsubcom.lua`: run `export`, then `status` -
new keys show up as missing in every language, removed keys as "unknown key".

Strings that look technical ("JSON module loaded successfully", "dkjson
compatibility check passed") belong to the progress window shown on first run
and to error dialogs. They are worth translating, but if in doubt leave the
key out and the English text is used.

## Where the old translations went

The original VLSub had translations in 22 languages. Only 28 of today's 271
strings still exist with the same English text, so they were not imported
wholesale; where a string is unchanged its old translation is a good starting
point (`https://github.com/exebetche/vlsub/tree/master/locale`, GPL).
