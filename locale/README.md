# Interface translations

One file per language: `locale/<code>.json`, where `<code>` is the language
code OpenSubtitles uses (`sk`, `de`, `pt-br`, ...).

> **Status:** the files here are data only. The extension does not load them
> yet; that is phase 2 of `docs/refactor-brief.md` (a language drop-down in the
> configuration window, files fetched from this folder on demand, English as
> the fallback for every string that is missing).

## Files

| File | What it is |
|---|---|
| `en.json` | The English strings, generated from `vlsubcom.lua`. Reference only - do not edit; run `lua tests/export_strings.lua` after changing a string in the script. |
| `<code>.json` | A translation: the same keys, translated values. Keys may be left out; English is used for them. |
| `index.json` | Which languages exist and whether they have been reviewed. |

## Status of a language

- `review` - translated, but nobody who speaks the language has read it
  through. **Not offered to users.**
- `ready` - a native speaker has read every string in context. Offered in the
  language drop-down.

A translation goes from `review` to `ready` by a pull request that changes
the status and says who reviewed it.

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

## Contributing

1. Copy `en.json` to `<code>.json` and translate the values (or improve an
   existing file).
2. Add the language to `index.json` with `"status": "review"`.
3. Run `tests/run.sh` - it reports any key, placeholder or tag that does not
   match.
4. Open a pull request.

Strings that look technical ("JSON module loaded successfully", "dkjson
compatibility check passed") belong to the progress window shown on first run
and to error dialogs. They are worth translating, but if in doubt leave the
key out and the English text is used.

## Where the old translations went

The original VLSub had translations in 22 languages. Only 28 of today's 271
strings still exist with the same English text, so they were not imported
wholesale; where a string is unchanged its old translation is a good starting
point (`https://github.com/exebetche/vlsub/tree/master/locale`, GPL).
