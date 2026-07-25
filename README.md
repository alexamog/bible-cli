# Bible Verse Lookup Tool

A tiny PowerShell add-on that lets you pull Bible verses (Recovery Version
text) straight from your terminal, read a whole chapter with paging, save
verses you like, and copy verse text straight to your clipboard.

It talks to the free `txo.php` API at `api.lsm.org`. You need your own
`appid` and `token` from [api.lsm.org](https://api.lsm.org) - registration is
free.

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

### The chapter reader (`bible`)

Run `bible <book> <chapter>` (e.g. `bible Ephesians 4`). You'll see a page of
verses with:

```
[N]ext page   [P]revious page   [S]ave verse   [Q]uit
```

Single keypress, **no Enter needed**:

| Key | Does |
|---|---|
| `N` or `Space` or `PgDn` | Next page |
| `P` or `PgUp` | Previous page |
| `S` or `Tab` | Save a verse - labels the verses `a`, `b`, `c`... press one letter |
| `Q` or `Esc` | Quit |
| `Up` / `Down` arrow | Scroll one verse at a time (best in a small window) |
| `?` | Look up a word - type it, press Enter, then any key to return to your place (clipboard untouched) |
| `Backspace` | Go back to where you were reading before you jumped to another chapter |

**Jumping to another chapter:** type the reference and press Enter, e.g.
`John 4`.

One catch: `N`, `P`, `S`, and `Q` now fire instantly, so a book starting with
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

### Your saved verses (`verse list`)

`verse list` opens a numbered list of everything you've saved:

```
  1) Rom. 8:26    saved 2026-07-21 08:17:49
  2) John 3:16    saved 2026-07-21 09:20:02

press 1-9 to read   [N]ext   [D]elete   [Q]uit
```

Press a **number** to pull that verse from the API and read it (it also lands
on your clipboard). Press **D** then a number to delete one. **Q** goes back.
All single keypresses - no Enter.

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
| `%USERPROFILE%\.lsm-verse.json` | Your API credentials. **Never share this file or commit it anywhere.** |
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
