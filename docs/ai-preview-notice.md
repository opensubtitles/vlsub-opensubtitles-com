# AI on-demand preview: the notice inside the subtitle

For the developer of the AI translation service (server side). The VLC
extension only saves what the server sends; this text is produced by the
server.

## What a user without credits gets today

Preview of "Coherence" (2013) in Slovak, 2026-11-20. The first cues are the
real translation; cues 5 to 9 are the notice:

```
5
00:00:18,503 --> 00:00:21,503
Ak chcete získať kompletný preklad na požiadanie

6
00:00:21,503 --> 00:00:24,503
v tomto podtitule doplniť zoznam účinkujúcich

7
00:00:24,503 --> 00:00:27,503
na váš účet na stránke ai.OpenSubtitles.com

8
00:00:27,503 --> 00:00:30,503
Kliknite na tento odkaz, aby ste vykonali platbu

9
00:00:35,503 --> 00:05:35,503
https://y1.to/ax
```

Word for word in English:

```
5  If you want to get the complete translation on demand
6  in this sub-heading to add the list of performers
7  to your account on the page ai.OpenSubtitles.com
8  Click this link to carry out the payment
9  https://y1.to/ax
```

The same notice in Hungarian and Polish (seen the same day) has the same
faults.

## What is wrong

1. **"Credits" is translated as film credits.** Slovak "zoznam
   účinkujúcich" = cast list; Hungarian "stáblista" = end credits. The
   sentence asks the user to add a cast list to the subtitle.
2. **One sentence is cut into four cues and each piece is translated on its
   own**, so the grammar falls apart ("in this sub-heading to add ...").
3. **"Subtitle" is translated as "sub-heading"** ("podtitul"); the word for
   film subtitles is "titulky".
4. **Nobody can click a link in a subtitle.** "Click this link" does not
   work on a video; the address has to be typed, so it must be short,
   readable and shown long enough.
5. **The last cue is only a short link.** It stays on screen for five
   minutes and says nothing: not what happened, not why the film has no more
   subtitles, not what it costs, not what to do afterwards.
7. The cause is "not enough credits", which is not the same as "no credits":
   an account with 10 credits also gets the preview for a film that costs 20.
   The text must give both numbers.
6. Nothing says that this is a **preview** and that the rest of the film
   will have no subtitles.

## Proposed text (English source)

Rules for the text:

- every cue is a complete sentence that makes sense alone;
- at most 2 lines, about 42 characters per line;
- "AI credits" is a product term: keep the word "AI" next to it in every
  language and use the word the website uses for its credits, never the
  word for film credits;
- no "click"; the address is written out;
- the last cue repeats everything, because it is the one that stays.

```
N
(3 s)
This is only a preview
of the AI translation.

N+1
(5 s)
The rest of this film is not translated:
your account does not have enough AI credits.

N+2
(5 s)
The full translation costs about {price}
AI credits. You have {balance}.

N+3
(5 s)
Add AI credits to your account at
ai.opensubtitles.com

N+4
(5 s)
Then download this subtitle again
in your player - it will be complete.

N+5
(5 minutes)
PREVIEW ONLY - not enough AI credits.
Needed: about {price}. You have: {balance}.
Add credits at {short_url} (ai.opensubtitles.com),
then download this subtitle again.
```

`{price}` = credits the full translation would cost, `{balance}` = the
user's balance (it may be more than 0), `{short_url}` = the short payment link (today
`https://y1.to/..`).

Notes for the implementation:

- The last cue has four lines; if that is too many for a player, drop the
  second line rather than shortening the instructions.
- Translate each cue as a whole, with the placeholders and the address
  protected from translation.
- Have the notice checked once per language by a native speaker, or reuse
  the wording of the website (`subs_locale_target`) for "subtitle",
  "credits", "account", "download".
- A fixed, human-made translation per language is safer than translating
  the notice by machine on every request.

## Also noticed on the server side (not about the text)

- The link in the answer for an existing translation
  (`https://ai.opensubtitles.com/proxy/download/<id>`) answers 404.
- `GET /api/v1/download/<id>?wait_for_translation=1` (the id without
  `preview-`) gives the **full** text of an existing translation to an
  account without credits.
- With several languages asked, only the first one is served and the real
  results of the others are missing.
- "The Man from Earth" (IMDb 756683) in Ukrainian is offered from a source
  named "The Event - 02 - To Keep us Safe": a different title.
