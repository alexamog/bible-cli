# Bible Verse Lookup Tool

A tiny PowerShell add-on that lets you pull Bible verses (Recovery Version
text) straight from your terminal, read a whole chapter with paging, save
verses you like, and copy verse text straight to your clipboard.

It talks to the free `txo.php` API at `api.lsm.org`. You need your own
`appid` and `token` from [api.lsm.org](https://api.lsm.org) - registration is
free.

**Or read from your own EPUB instead.** If you have the Recovery Version
EPUB, point the tool at it and it reads straight from the file - no API, no
credentials - and you get the **footnotes and cross-references** too. See
[Reading from your EPUB](#reading-from-your-epub-with-footnotes).

## Want a free study Bible?

- Canada: [biblesforcanada.org/order](https://www.biblesforcanada.org/order)
- USA: [biblesforamerica.org/place-order](https://biblesforamerica.org/place-order)

## Commands

| Command | What it does |
|---|---|
| `verse John 3:16` | Prints the verse(s) and **copies the text to your clipboard**. |
| `bible John 3` | Opens a full-chapter reader, one screen-page at a time, sized to your terminal window. |
| `verse list` | Browse your saved verses. Press a number to read one - no Enter needed. |
| `savedverses` | Prints every saved verse in one go (non-interactive). |
| `Set-BibleEpub <path>` | Read from your Recovery Version EPUB instead of the API (adds footnotes). `Set-BibleEpub ""` switches back. |

### The chapter reader (`bible`)

Run `bible <book> <chapter>` (e.g. `bible Ephesians 4`). You'll see a page of
verses framed by a header and a status strip:

```
  Romans 13                                          Recovery Version
  ───────────────────────────────────────────────────────────────────

    1  Let every person be subject to the authorities over him, for
       there is no authority except from God, and those which exist
       are ordained by God.

    2  So then he who resists the authority opposes the ordination
       of God, and those who oppose will receive judgment.

  ───────────────────────────────────────────────────────────────────
  verses 1–2 of 14              N next   S save   ? define   Q quit
  © 2003 Living Stream Ministry
  ›
```

Single keypress, **no Enter needed**:

| Key | Does |
|---|---|
| `N`, `Space`, `PgDn` or `Right` arrow | Next page |
| `P`, `PgUp` or `Left` arrow | Previous page |
| `S` or `Tab` | Save a verse - labels the verses `a`, `b`, `c`... press one letter |
| `F` | Read a verse's footnotes and cross-references (EPUB only) - pick it by letter, as with `S` |
| `Q` or `Esc` | Quit |
| `Up` / `Down` arrow | Scroll one verse at a time (best in a small window) |
| `?` | Look up a word - type it, press Enter, then any key to return to your place (clipboard untouched) |
| `Backspace` | Go back to where you were reading before you jumped to another chapter |

**Jumping to another chapter:** type the reference and press Enter, e.g.
`John 4`.

One catch: `N`, `P`, `S`, `F`, and `Q` now fire instantly, so a book starting with
those letters can't be typed directly. Press `/` first to open typing mode:

```
/Psalm 23        /Numbers 3        /Samuel 1        /Song of Songs 2
```

Everything else (`John`, `Acts`, `Romans`, `Ephesians`...) types normally with
no prefix.

**Getting back after a jump:** press `Backspace`. You return to the chapter
you came from *and* the exact scroll position you left, not the top of it.
Jumps stack, so pressing it repeatedly walks back through everything you
looked up. (While you're typing a reference, `Backspace` still deletes
characters as usual - it only means "go back" when the line is empty.)

Long verses wrap with a hanging indent so continuation lines line up under
the verse text (not the number), with a blank line between verses. The page
size adapts to your window's actual width and height, so it never overflows
even in a small or narrow pane.

**Supplied words show in italics.** The Recovery Version brackets words the
translators added for English readability - `[He] [said,]`, `[a period of]`.
Rather than printing the brackets, the tool renders those words in *italics*,
matching how they appear in the printed edition. Clipboard copies keep the
original bracket notation, so pasted text stays faithful to the source.

If your terminal doesn't support italics the words simply appear normal -
nothing breaks.

Tip: this reader is much nicer in a **tall, narrow terminal pane** - split
your terminal vertically before running `bible`.

### Book names are spelled out

Type whatever's quickest - the heading always shows the full name. `bible
rom 13` reads `Romans 13`, `verse 1 cor 13:4` reads `1 Corinthians 13:4`.
Abbreviations, roman numerals and the API's own short forms all expand:

| You type | You see |
|---|---|
| `rom 13` | Romans 13 |
| `ss 1:2` | Song of Songs 1:2 |
| `II Tim 3:16` | 2 Timothy 3:16 |
| `ps 23` | Psalms 23 |

This is display only. Saved references and clipboard copies keep working
whatever you typed, and anything the tool doesn't recognise is shown as you
typed it rather than dropped.

### Reading from your EPUB (with footnotes)

If you own the Recovery Version EPUB (`HolyBible.epub`), run this once:

```powershell
Set-BibleEpub "C:\Users\<you>\Downloads\HolyBible.epub"
```

It saves the path as `"epub"` in `%USERPROFILE%\.lsm-verse.json`, next to
your appid/token, which it leaves alone. From then on `verse`, `bible` and
`savedverses` read from the EPUB, and api.lsm.org isn't contacted at all.
`Set-BibleEpub ""` goes back to the API.

**Footnote markers.** In the reader, words that have a footnote or
cross-reference get a small superscript, the same way the printed edition
marks them:

```
    3  Jesus answered and said to him, Truly, truly, I say to you, Unless
       one is born¹ᵃ anew, he cannot see² the kingdom³ᵇ of God.
```

Numbers are footnotes and letters are cross-references. The EPUB names the
word each note belongs to but not where it sits in the verse, so where a
word repeats in a verse the tool works out which one is meant from the
order of the notes. That's right in all but a handful of the ~36,000 notes.

**Reading the notes.** Press `F`. The verses on the page that have notes
get the letters `a`, `b`, `c`..., and you press one to pick a verse. If only
one verse on the page has notes, it opens straight away. You get:

```
  John 3:3                                                         notes
  ───────────────────────────────────────────────────────────────────────

    1  born
       Or, born from above. So in v. 7. To be born anew is to be born
       from above, from heaven, that is, to be born from God...

    2  see
       In spiritual things, to see is to enter into (v. 5).

  cross-references
    a  born     1 Pet. 1:23
    b  kingdom  John 3:5
```

A long note pages with `N`/`P` (or the arrow keys). Any other key takes you
back to the same place in the chapter.

`verse John 3:16` shows the markers too, plus a pointer to open the chapter
in the reader to read them.

In EPUB mode references take the forms `John 3`, `John 3:16` and
`John 3:16-18` (single-chapter books also take `Jude 5`). Lists like
`John 3:16; 4:1` are API-only.

### Colours

The palette is periwinkle for anything you can act on - prompts, key hints,
verse numbers - and a warm gold, periwinkle's complement, for headings and
references. Everything else stays quiet and grey so the verse text is the
brightest thing on screen.

It's drawn with 24-bit colour, which every modern terminal handles (Windows
Terminal, VS Code, PowerShell 7). On anything older it falls back to the
16 console colours automatically. Set `NO_COLOR=1` to turn styling off
entirely; the layout still lines up, using `-` and `>` in place of the
box-drawing characters.

### Your saved verses (`verse list`)

`verse list` opens a numbered list of everything you've saved:

```
  Saved verses                                              4 verses
  ──────────────────────────────────────────────────────────────────

   1  Romans 8:26                              2026-07-21 08:17:49
   2  John 3:16                                2026-07-21 09:20:02
   3  1 Corinthians 13:4                       2026-07-22 11:02:10

  ──────────────────────────────────────────────────────────────────
  1–3 of 4                        1-9 read   N next   D delete   Q quit
  ›
```

Press a **number** to pull that verse from the API and read it (it also lands
on your clipboard). Press **D** then a number to delete one. **Q** goes back.
The arrow keys (or **N** / **P**) turn the pages. All single keypresses - no
Enter.

## Install

1. Clone or unzip this folder anywhere (keep it somewhere permanent - the
   installer points your profile at the tool *in place*, so don't delete the
   folder afterwards).
2. Open PowerShell **in this folder** and run:
   ```powershell
   .\Install.ps1
   ```
   If PowerShell refuses ("running scripts is disabled on this system"), run it
   this way instead, then re-open a normal window afterwards:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install.ps1
   ```
   (Optional, so scripts work permanently:
   `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.)

   The installer adds one line to your PowerShell profile that loads the tool
   automatically in every new window (both Windows PowerShell 5.1 and
   PowerShell 7). It also creates a blank credentials file for you if one
   doesn't exist.
3. Open your **credentials file** - `%USERPROFILE%\.lsm-verse.json` (i.e.
   `C:\Users\<you>\.lsm-verse.json`) - and replace the placeholders with your
   real credentials from api.lsm.org:
   ```json
   {
     "appid": "YOUR_APPID",
     "token": "YOUR_TOKEN"
   }
   ```
   ⚠️ Put them in `.lsm-verse.json`, **not** in `.lsm-verse.example.json`. The
   example file is tracked by git - real credentials pasted there can get
   pushed and made public.
4. Close and reopen PowerShell. Try:
   ```powershell
   verse John 3:16
   ```

### Manual install (if you'd rather not run Install.ps1)

1. Copy `BibleVerseTool.ps1` anywhere you like (e.g. next to your `$PROFILE`).
2. Add this line to your PowerShell profile (find its path by typing
   `$PROFILE`):
   ```powershell
   . "C:\path\to\BibleVerseTool.ps1"
   ```
3. Create `%USERPROFILE%\.lsm-verse.json` with your `appid` and `token` (copy
   `.lsm-verse.example.json` and fill it in).

## Files this tool uses

| File | Purpose |
|---|---|
| `%USERPROFILE%\.lsm-verse.json` | Your API credentials, and optionally the path to your EPUB (`"epub"`). **Never share this file or commit it anywhere.** |
| `%USERPROFILE%\.lsm-saved-verses.txt` | References (not verse text) you've saved. One per line as `Reference\|timestamp` - open it in Notepad and edit freely. An older `.json` store is migrated automatically the first time you run the tool. |

### Looking up words (`?` while reading)

Word lookup is **only available inside the chapter reader** - there's no
standalone command. While reading, press `?`, type the word, press Enter:

```
bible John 15
  ... press ?
define: abide
```

Shows pronunciation, each part of speech with up to three definitions,
examples, and synonyms. Press any key to return to exactly where you were in
the chapter.

Lookups deliberately **don't** touch your clipboard, so checking a word
mid-chapter won't wipe a verse you copied with `verse`.

Unknown words report `No dictionary entry for '...'` rather than erroring.

Note this is general modern English (Wiktionary), not a biblical lexicon -
`abide` gives you "endure, tolerate, dwell", not the Greek sense behind
John 15. For that you want a lexicon or interlinear instead.

## A note on the API's terms of service

Two APIs are involved, with different rules.

**Dictionary (`?` in the reader)** - api.dictionaryapi.dev is free and needs no key. Its
data comes from Wiktionary under **CC BY-SA 3.0**, so the tool always prints
the source link and licence with each definition. It's community-run with no
uptime guarantee or documented rate limit - fine for personal use, don't
build anything critical on it.

**Bible text (`verse` / `bible`)** -
api.lsm.org's terms prohibit storing the Recovery Version text offline, and
require the `copyright` attribution to be shown wherever verses are
displayed. This tool follows both: `savedverses` only ever stores the
*reference* on disk and re-fetches the actual text live from the API each
time you run it, and every command that displays verse text also displays
the attribution line. Clipboard copies (from `verse`) are a transient,
in-memory convenience rather than a stored file.

**EPUB mode** uses your own copy of the book. It's read live, straight out
of the `.epub`, every time. Nothing is extracted or cached on disk, and the
EPUB's own copyright line is shown wherever its text is shown.
