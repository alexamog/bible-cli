# ============================================================
# Bible lookup commands (Recovery Version text, api.lsm.org)
#
#   verse <reference>        e.g.  verse John 3:16
#   verse list               browse your saved references
#   bible <book> <chapter>   e.g.  bible John 3        (paged chapter reader)
#
# Word lookup lives INSIDE the chapter reader only: press ? while reading.
#   savedverses              print every saved verse in one go
#
# Credentials live in:  %USERPROFILE%\.lsm-verse.json
#   { "appid": "YOUR_APPID", "token": "YOUR_TOKEN" }
# Register at https://api.lsm.org to get an appid + token.
#
# Saved references are stored in: %USERPROFILE%\.lsm-saved-verses.txt
#
# "define" uses api.dictionaryapi.dev - free, no key needed. Its data comes
# from Wiktionary under CC BY-SA 3.0, so the source link is always shown.
# ============================================================


# ------------------------------------------------------------
# Colour + layout
#
# Everything is drawn with 24-bit ANSI colour rather than the 16 console
# colours, because the palette (periwinkle + its warm complement) simply
# doesn't exist in the console 16. Each entry carries a console fallback for
# terminals that can't do ANSI, so nothing breaks - it just gets blockier.
# ------------------------------------------------------------

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$script:BibleEsc = [char]27
$script:BibleAnsi = $null

$script:BiblePalette = @{
    # Periwinkle - the primary accent: prompts, key hints, chapter titles.
    'Accent'    = @{ Ansi = '38;2;180;174;249'; Console = 'Magenta' }
    'AccentDim' = @{ Ansi = '38;2;134;128;196'; Console = 'DarkMagenta' }
    # Warm gold - periwinkle's complement, pulled a little toward amber so it
    # stays legible on a dark background instead of washing out to pale yellow.
    'Gold'      = @{ Ansi = '38;2;247;209;138'; Console = 'Yellow' }
    'GoldDim'   = @{ Ansi = '38;2;186;153;96';  Console = 'DarkYellow' }
    'Body'      = @{ Ansi = '38;2;222;222;232'; Console = 'Gray' }
    'Emph'      = @{ Ansi = '38;2;173;168;226'; Console = 'DarkMagenta' }
    'Muted'     = @{ Ansi = '38;2;122;124;148'; Console = 'DarkGray' }
    'Rule'      = @{ Ansi = '38;2;79;80;102';   Console = 'DarkGray' }
    'Warn'      = @{ Ansi = '38;2;231;178;101'; Console = 'Yellow' }
    'Danger'    = @{ Ansi = '38;2;232;138;138'; Console = 'Red' }
}

function Test-BibleAnsi {
    # Cached - this is called for every styled fragment on screen.
    if ($null -ne $script:BibleAnsi) { return $script:BibleAnsi }
    $ok = $true
    if ($env:NO_COLOR)          { $ok = $false }
    elseif ($Host.Name -like '*ISE*') { $ok = $false }
    $script:BibleAnsi = $ok
    return $ok
}

function Get-BibleAnsiCode {
    # Raw escape sequence for a palette entry - used where colour has to be
    # embedded mid-string (see Write-BibleText).
    param([string]$Color)

    if (-not (Test-BibleAnsi)) { return "" }
    $p = $script:BiblePalette[$Color]
    if (-not $p) { return "" }
    return "$script:BibleEsc[$($p.Ansi)m"
}

function Get-BibleReset {
    if (-not (Test-BibleAnsi)) { return "" }
    return "$script:BibleEsc[0m"
}

function Get-BibleStyled {
    # Returns a styled string. Its VISIBLE length is unchanged, but escape
    # codes make .Length lie - measure with the plain text, never with this.
    param(
        [string]$Text,
        [string]$Color = 'Body',
        [switch]$Italic,
        [switch]$Bold
    )

    if (-not (Test-BibleAnsi)) { return $Text }
    $p = $script:BiblePalette[$Color]
    if (-not $p) { return $Text }

    $codes = @()
    if ($Bold)   { $codes += '1' }
    if ($Italic) { $codes += '3' }
    $codes += $p.Ansi
    return "$script:BibleEsc[" + ($codes -join ';') + "m" + $Text + "$script:BibleEsc[0m"
}

function Write-BibleStyled {
    param(
        [string]$Text,
        [string]$Color = 'Body',
        [switch]$Italic,
        [switch]$Bold,
        [switch]$NoNewline
    )

    if (Test-BibleAnsi) {
        Write-Host (Get-BibleStyled -Text $Text -Color $Color -Italic:$Italic -Bold:$Bold) -NoNewline:$NoNewline
    } else {
        $fallback = 'Gray'
        if ($script:BiblePalette[$Color]) { $fallback = $script:BiblePalette[$Color].Console }
        Write-Host $Text -ForegroundColor $fallback -NoNewline:$NoNewline
    }
}

function Get-BibleGlyph {
    # Box-drawing characters are built from code points at runtime, never
    # typed into this file - that keeps the script pure ASCII on disk and
    # immune to PowerShell 5.1's encoding guessing.
    param([string]$Name)

    $utf8Ready = $false
    try { $utf8Ready = ([Console]::OutputEncoding.CodePage -eq 65001) } catch { }

    if ((Test-BibleAnsi) -and $utf8Ready) {
        switch ($Name) {
            'Rule'   { return [string][char]0x2500 }   # horizontal line
            'Prompt' { return [string][char]0x203A }   # single angle quote
            'Dash'   { return [string][char]0x2013 }   # en dash
            'Track'  { return [string][char]0x2501 }   # heavy horizontal bar
            'Knob'   { return [string][char]0x25CF }   # solid circle
        }
    }
    switch ($Name) {
        'Rule'   { return '-' }
        'Prompt' { return '>' }
        'Dash'   { return '-' }
        'Track'  { return '-' }
        'Knob'   { return '*' }
    }
    return ''
}

function Get-BibleLayout {
    # One place decides the margin and the text measure. Long lines are hard
    # to read, so content is capped at 92 columns however wide the window is,
    # and the margin collapses on very narrow panes rather than squeezing text.
    param([int]$Width = 0)

    if ($Width -le 0) {
        try { $Width = $Host.UI.RawUI.WindowSize.Width } catch { $Width = 80 }
    }

    $margin = if ($Width -ge 46) { 2 } else { 0 }
    $content = [Math]::Min($Width - ($margin * 2) - 1, 92)
    if ($content -lt 24) {
        $margin  = 0
        $content = [Math]::Max(20, $Width - 1)
    }

    return [PSCustomObject]@{
        Width   = $Width
        Margin  = $margin
        Content = $content
        Pad     = (" " * $margin)
        # Width to hand to the wrappers: margin + measure, since prefixes
        # passed to them already include the margin.
        Text    = $margin + $content
    }
}

function Get-BibleRuleLine {
    param($Layout, [string]$Color = 'Rule')
    return (Get-BibleStyled -Text ($Layout.Pad + ((Get-BibleGlyph 'Rule') * $Layout.Content)) -Color $Color)
}

function Write-BibleRule {
    param($Layout, [string]$Color = 'Rule')
    Write-Host (Get-BibleRuleLine -Layout $Layout -Color $Color)
}

function Get-BibleHeaderLines {
    # Returns the header lines for the chapter reader or verse command.
    param(
        [string]$Title,
        [string]$Note = "",
        $Layout,
        [string]$TitleColor = 'Gold'
    )

    $line = $Layout.Pad + (Get-BibleStyled -Text $Title -Color $TitleColor -Bold)
    if ($Note) {
        $gap = $Layout.Content - $Title.Length - $Note.Length
        if ($gap -ge 3) {
            $line += (" " * $gap) + (Get-BibleStyled -Text $Note -Color 'Muted')
        }
    }
    return @(
        "",
        $line,
        (Get-BibleRuleLine -Layout $Layout),
        ""
    )
}

function Write-BibleHeader {
    # Title on the left, a quiet note on the right, a rule underneath.
    param(
        [string]$Title,
        [string]$Note = "",
        $Layout,
        [string]$TitleColor = 'Gold'
    )

    foreach ($l in @(Get-BibleHeaderLines -Title $Title -Note $Note -Layout $Layout -TitleColor $TitleColor)) {
        Write-Host $l
    }
}

function Get-BibleStatusLines {
    # Status on the left, key hints on the right - each hint's key in
    # periwinkle, its label muted, so the screen reads as one quiet strip.
    # $Hints is an array of @("N", "next") pairs.
    #
    # Returns finished lines rather than printing them, so the chapter reader
    # can count them and reserve exactly that much room before it decides how
    # many verses fit on the page.
    param($Layout, [string]$Status, [array]$Hints)

    $items = @(@($Hints) | ForEach-Object {
        [PSCustomObject]@{
            Plain  = "$($_[0]) $($_[1])"
            Styled = (Get-BibleStyled -Text $_[0] -Color 'Accent' -Bold) +
                     (Get-BibleStyled -Text " $($_[1])" -Color 'Muted')
        }
    })

    $plain  = (@($items | ForEach-Object { $_.Plain })  -join "   ")
    $styled = (@($items | ForEach-Object { $_.Styled }) -join "   ")

    $gap = $Layout.Content - $Status.Length - $plain.Length
    if ($gap -ge 3) {
        return @($Layout.Pad + (Get-BibleStyled -Text $Status -Color 'Muted') + (" " * $gap) + $styled)
    }

    # Too narrow to sit side by side - stack them, packing the hints onto as
    # many lines as it takes rather than letting the terminal wrap mid-hint.
    $lines = @($Layout.Pad + (Get-BibleStyled -Text $Status -Color 'Muted'))

    $lineStyled = ""
    $lineLen    = 0
    foreach ($h in $items) {
        $add = if ($lineLen -eq 0) { $h.Plain.Length } else { $h.Plain.Length + 3 }
        if ($lineLen -gt 0 -and ($lineLen + $add) -gt $Layout.Content) {
            $lines += ($Layout.Pad + $lineStyled)
            $lineStyled = ""
            $lineLen    = 0
            $add        = $h.Plain.Length
        }
        if ($lineLen -gt 0) { $lineStyled += "   " }
        $lineStyled += $h.Styled
        $lineLen    += $add
    }
    if ($lineLen -gt 0) { $lines += ($Layout.Pad + $lineStyled) }

    return @($lines)
}

function Write-BibleStatusBar {
    param($Layout, [string]$Status, [array]$Hints)

    foreach ($l in @(Get-BibleStatusLines -Layout $Layout -Status $Status -Hints $Hints)) {
        Write-Host $l
    }
}

function Get-BibleNoteLines {
    param($Layout, [string]$Text, [string]$Color = 'Muted')

    $lines = @()
    foreach ($l in @(Get-BibleWrappedLines -Text $Text -PrefixLength $Layout.Margin -Width $Layout.Text)) {
        $lines += (Get-BibleStyled -Text ($Layout.Pad + $l) -Color $Color)
    }
    return @($lines)
}

function Write-BibleNote {
    param($Layout, [string]$Text, [string]$Color = 'Muted')

    foreach ($l in @(Get-BibleNoteLines -Layout $Layout -Text $Text -Color $Color)) {
        Write-Host $l
    }
}

function Write-BibleUsageRow {
    # Command on the left, what it does on the right. Never word-wrapped -
    # the wrapper collapses runs of spaces, which would eat the columns.
    param($Layout, [string]$Command, [string]$Detail, [int]$Column = 24)

    if ($Layout.Content -lt ($Column + 16)) {
        Write-BibleStyled ($Layout.Pad + $Command) -Color 'Accent'
        Write-BibleStyled ($Layout.Pad + "  " + $Detail) -Color 'Muted'
        return
    }
    Write-Host ($Layout.Pad +
                (Get-BibleStyled -Text $Command.PadRight($Column) -Color 'Accent') +
                (Get-BibleStyled -Text $Detail -Color 'Muted'))
}

function Write-BiblePrompt {
    param($Layout)
    Write-Host ($Layout.Pad + (Get-BibleStyled -Text (Get-BibleGlyph 'Prompt') -Color 'Accent' -Bold) + " ") -NoNewline
}

function Wait-BibleKey {
    param($Layout, [string]$Text = "press any key to go back")
    Write-Host ""
    Write-BibleStyled ($Layout.Pad + $Text) -Color 'Muted'
    Read-BibleKey | Out-Null
}


# ------------------------------------------------------------
# Book names
#
# The API answers in abbreviations ("Rom. 13:1") and people type even shorter
# ones ("rom 13"). Both get expanded to the full name for display only - what
# gets saved to disk and sent back to the API is always the API's own form.
# ------------------------------------------------------------

$script:BibleBookMap = $null

function Get-BibleBookMap {
    if ($script:BibleBookMap) { return $script:BibleBookMap }

    $books = [ordered]@{
        'Genesis'         = 'gen ge gn'
        'Exodus'          = 'exo ex exod exd'
        'Leviticus'       = 'lev le lv'
        'Numbers'         = 'num nu nm nb'
        'Deuteronomy'     = 'deut deu dt de'
        'Joshua'          = 'josh jos jsh'
        'Judges'          = 'judg jdg jg jdgs'
        'Ruth'            = 'rut rth ru'
        '1 Samuel'        = '1sam 1sa 1sm 1s'
        '2 Samuel'        = '2sam 2sa 2sm 2s'
        '1 Kings'         = '1kings 1kgs 1kin 1ki 1k'
        '2 Kings'         = '2kings 2kgs 2kin 2ki 2k'
        '1 Chronicles'    = '1chron 1chr 1ch 1cr'
        '2 Chronicles'    = '2chron 2chr 2ch 2cr'
        'Ezra'            = 'ezr ez'
        'Nehemiah'        = 'neh ne'
        'Esther'          = 'esth est es'
        'Job'             = 'jb'
        'Psalms'          = 'ps psa psalm psalms pss psm'
        'Proverbs'        = 'prov pro prv pr'
        'Ecclesiastes'    = 'eccl eccles ecc ec'
        'Song of Songs'   = 'songofsongs songofsolomon song songs ss sos cant canticles'
        'Isaiah'          = 'isa isai is'
        'Jeremiah'        = 'jer je jr'
        'Lamentations'    = 'lam la'
        'Ezekiel'         = 'ezek eze ezk'
        'Daniel'          = 'dan da dn'
        'Hosea'           = 'hos ho'
        'Joel'            = 'joe jl'
        'Amos'            = 'amo am'
        'Obadiah'         = 'obad oba ob'
        'Jonah'           = 'jon jnh'
        'Micah'           = 'mic mi'
        'Nahum'           = 'nah na'
        'Habakkuk'        = 'hab'
        'Zephaniah'       = 'zeph zep zph'
        'Haggai'          = 'hag hg'
        'Zechariah'       = 'zech zec zch'
        'Malachi'         = 'mal ml'
        'Matthew'         = 'matt mat mt'
        'Mark'            = 'mrk mar mk mr'
        'Luke'            = 'luk lk'
        'John'            = 'joh jhn jn'
        'Acts'            = 'act ac'
        'Romans'          = 'rom ro rm'
        '1 Corinthians'   = '1cor 1co 1c'
        '2 Corinthians'   = '2cor 2co 2c'
        'Galatians'       = 'gal ga'
        'Ephesians'       = 'eph ep'
        'Philippians'     = 'phil php phi pp'
        'Colossians'      = 'col'
        '1 Thessalonians' = '1thess 1thes 1th 1ts'
        '2 Thessalonians' = '2thess 2thes 2th 2ts'
        '1 Timothy'       = '1tim 1ti 1tm'
        '2 Timothy'       = '2tim 2ti 2tm'
        'Titus'           = 'tit ti tts'
        'Philemon'        = 'philem phlm phm pm'
        'Hebrews'         = 'heb hb'
        'James'           = 'jas jam jm'
        '1 Peter'         = '1pet 1pe 1pt 1p'
        '2 Peter'         = '2pet 2pe 2pt 2p'
        '1 John'          = '1john 1joh 1jn 1jo 1j'
        '2 John'          = '2john 2joh 2jn 2jo 2j'
        '3 John'          = '3john 3joh 3jn 3jo 3j'
        'Jude'            = 'jud jde jd'
        'Revelation'      = 'revelations rev re rv apocalypse apoc'
    }

    $map = @{}
    $add = {
        param($Key, $Name)
        if ($Key -and -not $map.ContainsKey($Key)) { $map[$Key] = $Name }
    }

    $aliasesOf = {
        param($Name)
        @(($Name -replace '[^A-Za-z0-9]', '').ToLower()) + ($books[$Name] -split '\s+')
    }

    # Real aliases first, in two passes, because the roman-numeral twins below
    # collide with genuine abbreviations: "1sa" would otherwise claim "isa"
    # out from under Isaiah, and "1s" would claim "is".
    foreach ($name in $books.Keys) {
        foreach ($k in (& $aliasesOf $name)) { & $add $k $name }
    }

    # "I Cor" / "II Tim" / "III John" are as common in print as the digit
    # forms, so each numbered book gets a roman-numeral twin - but only where
    # nothing real already owns that key.
    foreach ($name in $books.Keys) {
        foreach ($k in (& $aliasesOf $name)) {
            if ($k -match '^([123])(.+)$') {
                $roman = @('i', 'ii', 'iii')[[int]$matches[1] - 1]
                & $add ($roman + $matches[2]) $name
            }
        }
    }

    $script:BibleBookMap = $map
    return $map
}

function Expand-BibleReference {
    # "rom 13" -> "Romans 13".  "1 Cor. 2:3" -> "1 Corinthians 2:3".
    # Anything it doesn't recognise comes back tidied but otherwise untouched,
    # so an odd reference still displays rather than vanishing.
    param([string]$Reference)

    if (-not $Reference) { return $Reference }
    $ref = ($Reference -replace '\s+', ' ').Trim()

    if ($ref -notmatch '^(?<book>(?:[1-3]|I{1,3})?\s*[A-Za-z][A-Za-z\.\s]*?)\s*(?<rest>\d[^A-Za-z]*)?$') {
        return $ref
    }

    $key  = (($matches['book']) -replace '[^A-Za-z0-9]', '').ToLower()
    $rest = "$($matches['rest'])".Trim()

    $map = Get-BibleBookMap
    if (-not $map.ContainsKey($key)) { return $ref }

    if ($rest) { return "$($map[$key]) $rest" }
    return $map[$key]
}

function Resolve-BibleBook {
    # Given an input like "rom", "Ephesians", or "1cor", returns the canonical book name or $null.
    param([string]$Name)

    if (-not $Name) { return $null }
    $clean = ($Name -replace '[^A-Za-z0-9]', '').ToLower()
    $map = Get-BibleBookMap
    if ($map.ContainsKey($clean)) {
        return $map[$clean]
    }
    return $null
}

function Get-BibleNextChapterRef {
    # Returns the next or previous chapter reference (e.g. "Ephesians 1" + 1 -> "Ephesians 2")
    param([string]$Reference, [int]$Delta = 1)

    if ($Reference -match '^(?<book>.+?)\s+(?<chapter>\d+)$') {
        $b = $matches['book'].Trim()
        $c = [int]$matches['chapter'] + $Delta
        if ($c -ge 1) {
            return "$b $c"
        }
    }
    return $null
}


# ------------------------------------------------------------
# APIs
# ------------------------------------------------------------

function Get-LsmCredential {
    $configPath = Join-Path $HOME ".lsm-verse.json"
    $layout = Get-BibleLayout
    if (-not (Test-Path $configPath)) {
        Write-Host ""
        Write-BibleNote -Layout $layout -Text "Credentials file not found: $configPath" -Color 'Warn'
        Write-BibleNote -Layout $layout -Text 'Create it containing:  { "appid": "YOUR_APPID", "token": "YOUR_TOKEN" }'
        return $null
    }
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host ""
        Write-BibleNote -Layout $layout -Text "Could not read $configPath - is it valid JSON?" -Color 'Danger'
        return $null
    }
    if (-not $config.appid -or -not $config.token -or
        $config.appid -like "YOUR_*" -or $config.token -like "YOUR_*") {
        Write-Host ""
        Write-BibleNote -Layout $layout -Text "Open $configPath and fill in your real appid and token from api.lsm.org" -Color 'Warn'
        return $null
    }
    return $config
}

function Invoke-LsmApi {
    param([Parameter(Mandatory)][string]$Reference)

    $config = Get-LsmCredential
    if (-not $config) { return $null }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $url = "https://api.lsm.org/recver/txo.php?String={0}&Out=json&appid={1}&token={2}" -f
        [uri]::EscapeDataString("'$Reference'"),
        [uri]::EscapeDataString($config.appid),
        [uri]::EscapeDataString($config.token)

    $authBytes  = [Text.Encoding]::ASCII.GetBytes("$($config.appid):$($config.token)")
    $authHeader = @{ Authorization = "Basic " + [Convert]::ToBase64String($authBytes) }

    try {
        # This API replies "Content-Type: application/json" with no charset,
        # so PowerShell 5.1's Invoke-RestMethod assumes Latin-1 and turns the
        # UTF-8 copyright sign into "A(c)". Read the raw bytes and decode as
        # UTF-8 ourselves instead.
        $resp = Invoke-WebRequest -Uri $url -Headers $authHeader -TimeoutSec 15 -UseBasicParsing
        $json = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        return ($json | ConvertFrom-Json)
    } catch {
        Write-Host ""
        Write-BibleNote -Layout (Get-BibleLayout) -Text "Request failed: $($_.Exception.Message)" -Color 'Danger'
        return $null
    }
}

function Invoke-DictApi {
    # Looks up a word definition using api.dictionaryapi.dev with an instant
    # fallback to Datamuse (free, highly available, fast) if the primary API
    # times out or is unreachable.
    param([Parameter(Mandatory)][string]$Word)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $cleanWord = $Word.Trim().ToLower()

    # 1. Try api.dictionaryapi.dev first (fast 3s timeout)
    try {
        $url = "https://api.dictionaryapi.dev/api/v2/entries/en/{0}" -f [uri]::EscapeDataString($cleanWord)
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 3 -ErrorAction Stop
        if ($resp -and @($resp).Count -gt 0) {
            return $resp
        }
    } catch { }

    # 2. Resilient fallback to Datamuse
    try {
        $dmUrl = "https://api.datamuse.com/words?sp={0}&md=d" -f [uri]::EscapeDataString($cleanWord)
        $dm = Invoke-RestMethod -Uri $dmUrl -TimeoutSec 4 -ErrorAction Stop
        if ($dm -and @($dm).Count -gt 0 -and $dm[0].defs) {
            $byPos = @{}
            foreach ($d in $dm[0].defs) {
                $parts = $d -split '\t', 2
                $pos = $parts[0].Trim()
                $def = if ($parts.Count -gt 1) { $parts[1].Trim() } else { $d }
                if (-not $byPos.ContainsKey($pos)) { $byPos[$pos] = @() }
                $byPos[$pos] += [PSCustomObject]@{ definition = $def }
            }
            $meanings = @()
            foreach ($k in $byPos.Keys) {
                $posName = switch ($k) {
                    'n'   { 'noun' }
                    'v'   { 'verb' }
                    'adj' { 'adjective' }
                    'adv' { 'adverb' }
                    default { $k }
                }
                $meanings += [PSCustomObject]@{
                    partOfSpeech = $posName
                    definitions  = $byPos[$k]
                }
            }
            $entry = [PSCustomObject]@{
                word       = $dm[0].word
                phonetic   = ''
                meanings   = $meanings
                sourceUrls = @('https://www.datamuse.com/')
                license    = [PSCustomObject]@{ name = 'WordNet / Wiktionary' }
            }
            return @($entry)
        }
    } catch { }

    $layout = Get-BibleLayout
    Write-Host ""
    Write-BibleNote -Layout $layout -Text "No dictionary entry found for '$Word'." -Color 'Warn'
    return $null
}


# ------------------------------------------------------------
# Text rendering
# ------------------------------------------------------------

function Get-BibleWrappedLines {
    # Word-wraps $Text to fit ($Width - $PrefixLength) characters per line.
    # Returns an array of lines (always at least one, even for empty text).
    param([string]$Text, [int]$PrefixLength, [int]$Width)

    $maxLineWidth = [Math]::Max(10, $Width - $PrefixLength - 1)
    $words = $Text -split '\s+'
    $lines = @()
    $current = ""
    foreach ($w in $words) {
        if ($current.Length -eq 0) {
            $current = $w
        } elseif (($current.Length + 1 + $w.Length) -le $maxLineWidth) {
            $current += " $w"
        } else {
            $lines += $current
            $current = $w
        }
    }
    if ($current) { $lines += $current }
    if ($lines.Count -eq 0) { $lines = @("") }
    return $lines
}

function Split-BibleEmphasis {
    # The Recovery Version brackets words supplied by the translators - e.g.
    # "[He] [said,]" - which print in italics on paper. Split the text into
    # words, each flagged as emphasised or not, so the brackets themselves
    # never have to be shown.
    param([string]$Text)

    $tokens = @()
    foreach ($m in [regex]::Matches($Text, '\[[^\]]*\]|[^\[\]]+')) {
        $seg  = $m.Value
        $emph = $seg.StartsWith('[')
        $body = if ($emph) { $seg.Trim('[', ']') } else { $seg }
        foreach ($w in ($body -split '\s+')) {
            if ($w -ne '') {
                $tokens += [PSCustomObject]@{ Text = $w; Emph = $emph }
            }
        }
    }
    return @($tokens)
}

function Get-BibleTextLines {
    # Word-wraps on VISIBLE width (styling is applied at print time, never
    # baked into the string - ANSI codes would otherwise be counted as
    # characters and wreck the wrapping).
    param(
        [string]$Text,
        [string]$Prefix       = "",
        [string]$PrefixColor  = "AccentDim",
        [int]   $Width,
        [switch]$Highlight
    )

    if ($Width -le 0) {
        try { $Width = $Host.UI.RawUI.WindowSize.Width } catch { $Width = 80 }
    }

    $ansi        = Test-BibleAnsi
    $esc         = $script:BibleEsc
    $textColor   = if ($Highlight) { 'Gold' } else { 'Body' }
    $bodyCode    = Get-BibleAnsiCode $textColor
    $reset       = Get-BibleReset
    # Supplied words get italics AND a cooler tint, so they read as an aside
    # even where the terminal ignores italics.
    $italicColor = if ($Highlight) { 'GoldDim' } else { 'Emph' }
    $italicOn    = if ($ansi) { "$esc[3m" + (Get-BibleAnsiCode $italicColor) } else { "" }
    $italicOff   = if ($ansi) { "$esc[23m" + $bodyCode } else { "" }

    $indent = " " * $Prefix.Length
    $max    = [Math]::Max(10, $Width - $Prefix.Length - 1)
    $tokens = Split-BibleEmphasis -Text $Text

    $line   = @()   # tokens on the current line
    $len    = 0
    $first  = $true
    $resultLines = New-Object System.Collections.Generic.List[string]

    $flush = {
        $prefixStr = if ($first) {
            if ($Prefix) { Get-BibleStyled -Text $Prefix -Color $PrefixColor } else { "" }
        } else {
            $indent
        }

        # Build the line as one string, opening/closing italics only when the
        # emphasis actually changes, so "[a period of]" is a single run.
        $sb   = ""
        $open = $false
        for ($j = 0; $j -lt $line.Count; $j++) {
            # Close italics before the separating space, open them after it,
            # so the styling hugs the words instead of the gap.
            if (-not $line[$j].Emph -and $open) { $sb += $italicOff; $open = $false }
            if ($j -gt 0) { $sb += " " }
            if ($line[$j].Emph -and -not $open) { $sb += $italicOn; $open = $true }
            $sb += $line[$j].Text
        }
        if ($open) { $sb += $italicOff }   # never leave italics on at line end
        $resultLines.Add($prefixStr + $bodyCode + $sb + $reset)
    }

    foreach ($t in $tokens) {
        $add = if ($len -eq 0) { $t.Text.Length } else { $t.Text.Length + 1 }
        if ($len -gt 0 -and ($len + $add) -gt $max) {
            & $flush
            $first = $false
            $line  = @()
            $len   = 0
            $add   = $t.Text.Length
        }
        $line += $t
        $len  += $add
    }
    if ($line.Count -gt 0) { & $flush }
    elseif ($first -and $Prefix) { $resultLines.Add((Get-BibleStyled -Text $Prefix -Color $PrefixColor)) }

    return @($resultLines)
}

function Write-BibleText {
    param(
        [string]$Text,
        [string]$Prefix       = "",
        [string]$PrefixColor  = "AccentDim",
        [int]   $Width,
        [switch]$Highlight
    )
    foreach ($l in @(Get-BibleTextLines -Text $Text -Prefix $Prefix -PrefixColor $PrefixColor -Width $Width -Highlight:$Highlight)) {
        Write-Host $l
    }
}

function Get-BibleVerseLines {
    param(
        [string]$Number,
        [string]$Text,
        $Layout,
        [switch]$Selected
    )

    $prefixColor = 'AccentDim'
    $numStr = "{0,3}  " -f $Number
    if ($Selected) {
        $numStr = "{0}{1,2}  " -f (Get-BibleGlyph 'Prompt'), $Number
        $prefixColor = 'Gold'
    }

    return @(Get-BibleTextLines -Text $Text `
                                -Prefix ($Layout.Pad + $numStr) `
                                -PrefixColor $prefixColor `
                                -Width $Layout.Text `
                                -Highlight:$Selected)
}

function Write-BibleVerseLine {
    # Prints a verse with its number, wrapping long text with a hanging
    # indent so continuation lines line up under the verse text, not the number.
    param(
        [string]$Number,
        [string]$Text,
        $Layout,
        [switch]$Selected
    )

    foreach ($l in @(Get-BibleVerseLines -Number $Number -Text $Text -Layout $Layout -Selected:$Selected)) {
        Write-Host $l
    }
}

function Get-BibleVerseNumber {
    param($Verse, [int]$Fallback)
    if ($Verse.ref -match ':(\d+)') { return $matches[1] }
    return $Fallback
}


# ------------------------------------------------------------
# Dictionary display
# ------------------------------------------------------------

function Show-Definition {
    # Prints one dictionary entry, wrapped to the window with a hanging indent
    # so long definitions stay readable in a narrow pane.
    param($Entry, $Layout)

    if (-not $Layout) { $Layout = Get-BibleLayout }

    $note = ""
    if ($Entry.phonetic) { $note = $Entry.phonetic }
    Write-BibleHeader -Title $Entry.word -Note $note -Layout $Layout -TitleColor 'Gold'

    $bodyIndent = $Layout.Margin + 2

    foreach ($meaning in $Entry.meanings) {
        Write-BibleStyled ($Layout.Pad + $meaning.partOfSpeech) -Color 'Accent'
        Write-Host ""

        $n = 1
        foreach ($d in @($meaning.definitions | Select-Object -First 3)) {
            $prefix = $Layout.Pad + ("  {0}. " -f $n)
            $indent = " " * $prefix.Length
            $lines  = @(Get-BibleWrappedLines -Text $d.definition -PrefixLength $prefix.Length -Width $Layout.Text)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($i -eq 0) { Write-BibleStyled $prefix -Color 'GoldDim' -NoNewline }
                else          { Write-Host $indent -NoNewline }
                Write-BibleStyled $lines[$i] -Color 'Body'
            }
            if ($d.example) {
                $exLines = @(Get-BibleWrappedLines -Text $d.example -PrefixLength ($indent.Length + 2) -Width $Layout.Text)
                foreach ($ex in $exLines) {
                    Write-BibleStyled ("$indent  " + $ex) -Color 'Muted' -Italic
                }
            }
            $n++
        }

        if ($meaning.synonyms) {
            $syn = (@($meaning.synonyms) | Select-Object -First 6) -join ", "
            foreach ($sl in @(Get-BibleWrappedLines -Text "synonyms: $syn" -PrefixLength $bodyIndent -Width $Layout.Text)) {
                Write-BibleStyled ($Layout.Pad + "  " + $sl) -Color 'Muted'
            }
        }
        Write-Host ""
    }

    # CC BY-SA 3.0 requires crediting the source.
    if ($Entry.sourceUrls) {
        Write-BibleRule -Layout $Layout
        Write-BibleNote -Layout $Layout -Text ("source: {0}  ({1})" -f (@($Entry.sourceUrls)[0], $Entry.license.name))
    }
}

function Show-LsmWordLookup {
    # Internal helper for the chapter reader's "?" key. There is deliberately
    # no top-level "def"/"dict" command - word lookup is only offered while
    # reading a chapter.
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Word
    )

    if (-not $Word -or $Word.Count -eq 0) { return }

    $term = ($Word -join " ").Trim()
    $result = Invoke-DictApi -Word $term
    if (-not $result) { return }

    $entry = @($result)[0]
    Show-Definition -Entry $entry -Layout (Get-BibleLayout)

    # Deliberately no clipboard copy here - pressing ? mid-chapter should not
    # clobber whatever verse you copied with "verse".
}


# ------------------------------------------------------------
# Input
# ------------------------------------------------------------

function Read-BibleKey {
    # Single keypress, no Enter needed. Returns a small object describing the
    # key. Falls back to Read-Host (first character) if the console has no raw
    # key support (e.g. redirected input, ISE).
    try {
        $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return [PSCustomObject]@{
            Char = $k.Character
            Code = $k.VirtualKeyCode
        }
    } catch {
        $line = Read-Host
        $c = if ($line) { $line[0] } else { [char]13 }
        return [PSCustomObject]@{ Char = $c; Code = 0 }
    }
}

function Read-BibleInput {
    # Reads keys one at a time so Up/Down arrow can act immediately (no Enter
    # needed), while any typed text is still collected until Enter is pressed.
    # Falls back to plain Read-Host if the console doesn't support raw key reads.
    try {
        $buffer = ""
        while ($true) {
            $keyInfo = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            switch ($keyInfo.VirtualKeyCode) {
                38 { if (-not $buffer) { return @{ Action = "ScrollUp" } } }   # Up arrow
                40 { if (-not $buffer) { return @{ Action = "ScrollDown" } } } # Down arrow
                34 { if (-not $buffer) { return @{ Action = "PageDown" } } } # PageDown
                33 { if (-not $buffer) { return @{ Action = "PageUp" } } }   # PageUp
                32 {
                    # Space pages forward only when nothing typed yet;
                    # otherwise it is a real space inside "John 4".
                    if (-not $buffer) { return @{ Action = "PageDown" } }
                    $buffer += " "
                    Write-Host " " -NoNewline
                }
                9  { if (-not $buffer) { return @{ Action = "Submit"; Text = "S" } } } # Tab
                27 {
                    if ($buffer) { return @{ Action = "Cancel" } }
                    return @{ Action = "Submit"; Text = "Q" }                          # Esc
                }
                13 { Write-Host ""; return @{ Action = "Submit"; Text = $buffer } } # Enter
                8  {
                    if ($buffer.Length -gt 0) {
                        $buffer = $buffer.Substring(0, $buffer.Length - 1)
                        Write-Host "`b `b" -NoNewline
                        if ($buffer.Length -eq 0) {
                            return @{ Action = "Cancel" }
                        }
                    } else {
                        # Nothing typed: Backspace means "go back to where I
                        # was reading before I jumped".
                        return @{ Action = "Back" }
                    }
                }
                default {
                    $ch = $keyInfo.Character
                    if (-not $ch -or [int]$ch -lt 32 -or [int]$ch -eq 127) { break }

                    # Nothing typed yet: N/P/S/Q fire instantly, no Enter.
                    # Book names also start with N/P/S (Numbers, Psalm,
                    # Samuel, Song of Songs), so "/" opens typing mode for
                    # those. Any other letter just starts typing normally,
                    # so "John 4" still works with no prefix.
                    if (-not $buffer) {
                        if ("$ch" -eq "/") {
                            Write-BibleStyled "search: /" -Color 'Accent' -NoNewline
                            $buffer = "/"
                            break
                        }
                        if ("$ch" -eq ":") {
                            Write-BibleStyled "jump to verse: :" -Color 'Accent' -NoNewline
                            $buffer = ":"
                            break
                        }
                        if ("$ch" -eq "]") {
                            return @{ Action = "NextChapter" }
                        }
                        if ("$ch" -eq "[") {
                            return @{ Action = "PrevChapter" }
                        }
                        if ("$ch" -eq "?") {
                            return @{ Action = "Define" }
                        }
                        if ("$ch" -match '^[NnPpSsQqCc]$') {
                            Write-Host ""
                            return @{ Action = "Submit"; Text = "$ch" }
                        }
                    }
                    $buffer += $ch
                    Write-Host $ch -NoNewline
                }
            }
        }
    } catch {
        return @{ Action = "Submit"; Text = (Read-Host) }
    }
}


# ------------------------------------------------------------
# verse
# ------------------------------------------------------------

function verse {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Reference
    )

    $layout = Get-BibleLayout

    if (-not $Reference -or $Reference.Count -eq 0) {
        Write-BibleHeader -Title "verse" -Note "usage" -Layout $layout
        Write-BibleUsageRow -Layout $layout -Command "verse <reference>" -Detail "look it up and copy it   e.g. verse John 3:16"
        Write-BibleUsageRow -Layout $layout -Command "verse list [filter]" -Detail "browse your saved verses (optional book filter)"
        Write-BibleUsageRow -Layout $layout -Command "verse random"        -Detail "look up an encouraging verse"
        Write-Host ""
        return
    }

    # "verse list" opens the saved-reference browser with optional filter.
    if ($Reference.Count -ge 1 -and $Reference[0] -in @("list", "saved", "ls")) {
        $filter = if ($Reference.Count -gt 1) { ($Reference[1..($Reference.Count - 1)] -join " ").Trim() } else { "" }
        verselist -Filter $filter
        return
    }

    # "verse random" / "verse today" picks an encouraging verse
    if ($Reference.Count -eq 1 -and $Reference[0] -in @("random", "rand", "today")) {
        $curatedVerses = @(
            'John 3:16', 'John 14:6', 'Romans 8:28', 'Romans 8:38-39', 'Romans 12:1-2',
            'Ephesians 1:17-18', 'Ephesians 2:8-10', 'Ephesians 3:16-19', 'Philippians 4:6-7',
            'Philippians 4:13', 'Colossians 3:16', 'Galatians 2:20', 'Hebrews 11:1',
            'Hebrews 12:1-2', 'James 1:5', '1 Peter 5:7', 'Psalm 23:1-3', 'Psalm 119:105',
            'Proverbs 3:5-6', 'Isaiah 40:31', 'Jeremiah 29:11', 'Lamentations 3:22-23',
            'Matthew 6:33', 'Matthew 11:28', '2 Timothy 1:7', '2 Corinthians 5:17',
            '1 Corinthians 13:4-8', 'Revelation 21:4', 'Psalm 46:1', 'Psalm 91:1-2'
        )
        $picked = $curatedVerses | Get-Random
        verse $picked
        return
    }

    $rawRef = ($Reference -join " ").Trim()
    $result = Invoke-LsmApi -Reference $rawRef
    if (-not $result) { return }

    Write-BibleHeader -Title (Expand-BibleReference $rawRef) -Note "Recovery Version" -Layout $layout

    if ($result.message) {
        Write-BibleNote -Layout $layout -Text $result.message -Color 'Warn'
        Write-Host ""
    } elseif (-not $result.verses -or @($result.verses).Count -eq 0) {
        Write-BibleNote -Layout $layout -Text "Nothing came back for '$rawRef' - try a format like 'John 3:16'." -Color 'Warn'
        Write-Host ""
    }

    $clipLines = @()
    $i = 1
    foreach ($v in $result.verses) {
        Write-BibleVerseLine -Number (Get-BibleVerseNumber -Verse $v -Fallback $i) -Text $v.text -Layout $layout
        Write-Host ""
        # Clipboard keeps the original brackets - plain text, no escape codes.
        $clipLines += "$(Expand-BibleReference $v.ref) - $($v.text)"
        $i++
    }

    if ($clipLines.Count -gt 0) {
        $clipLines -join "`r`n`r`n" | Set-Clipboard
    }

    Write-BibleRule -Layout $layout
    $status = if ($clipLines.Count -gt 0) { "copied to clipboard" } else { "" }
    if ($result.copyright) {
        $gap = $layout.Content - $result.copyright.Length - $status.Length
        if ($status -and $gap -ge 3) {
            Write-Host ($layout.Pad +
                        (Get-BibleStyled -Text $result.copyright -Color 'Muted') +
                        (" " * $gap) +
                        (Get-BibleStyled -Text $status -Color 'AccentDim'))
        } else {
            Write-BibleNote -Layout $layout -Text $result.copyright
            if ($status) { Write-BibleStyled ($layout.Pad + $status) -Color 'AccentDim' }
        }
    } elseif ($status) {
        Write-BibleStyled ($layout.Pad + $status) -Color 'AccentDim'
    }
    Write-Host ""
}


# ------------------------------------------------------------
# Saved references
#
# Saved references live in a plain text file, one per line:
#     Rom. 8:26|2026-07-21 08:17:49
# Deliberately NOT JSON: PowerShell 5.1's ConvertTo-Json/ConvertFrom-Json
# round-trip wraps arrays as {"value":[...],"Count":N} and re-nests the store
# on every write. A line-based file has no such quirks and you can open and
# edit it in Notepad.
# ------------------------------------------------------------

function Get-LsmStorePath {
    # A function, not a $script: variable - scope resolution for $script: vars
    # differs depending on whether the caller is the script or another
    # function, which silently sent writes to the wrong place.
    return (Join-Path $HOME ".lsm-saved-verses.txt")
}

function Get-LsmSavedRefs {
    # One-time migration from the old .json store, if it is still around.
    $legacy = Join-Path $HOME ".lsm-saved-verses.json"
    if ((Test-Path $legacy) -and -not (Test-Path (Get-LsmStorePath))) {
        $rescued = @()
        # Pull every "ref": "..." out of the old file, however deeply the
        # JSON bug nested it, and keep the first occurrence of each.
        foreach ($m in [regex]::Matches((Get-Content $legacy -Raw), '"ref"\s*:\s*"([^"]+)"')) {
            $r = $m.Groups[1].Value
            if ($rescued -notcontains $r) { $rescued += $r }
        }
        if ($rescued.Count -gt 0) {
            Set-Content -Path (Get-LsmStorePath) -Encoding utf8 -Value (
                $rescued | ForEach-Object { "$_|(migrated)" }
            )
        }
    }

    if (-not (Test-Path (Get-LsmStorePath))) { return @() }

    $out = @()
    foreach ($line in (Get-Content (Get-LsmStorePath) -Encoding utf8)) {
        if (-not $line -or -not $line.Trim()) { continue }
        $parts = $line -split '\|', 2
        $out += [PSCustomObject]@{
            ref     = $parts[0].Trim()
            savedAt = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
        }
    }
    return @($out)
}

function Set-LsmSavedRefs {
    param($Entries)

    $lines = @()
    foreach ($e in @($Entries)) { $lines += "$($e.ref)|$($e.savedAt)" }
    if ($lines.Count -eq 0) {
        Set-Content -Path (Get-LsmStorePath) -Value "" -Encoding utf8
    } else {
        Set-Content -Path (Get-LsmStorePath) -Value $lines -Encoding utf8
    }
}

function Save-LsmVerse {
    # Stores only the reference, never the verse text - api.lsm.org's terms
    # of service prohibit storing any amount of the Recovery Version text for
    # offline use. The text is re-fetched live every time it is displayed.
    param([string]$Reference, $Layout)

    if (-not $Layout) { $Layout = Get-BibleLayout }
    $shown = Expand-BibleReference $Reference

    $saved = @(Get-LsmSavedRefs)
    if ($saved | Where-Object { $_.ref -eq $Reference }) {
        Write-BibleStyled ($Layout.Pad + "already saved  $shown") -Color 'Warn'
        return
    }
    $saved += [PSCustomObject]@{
        ref     = $Reference
        savedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    Set-LsmSavedRefs -Entries $saved
    Write-BibleStyled ($Layout.Pad + "saved  $shown") -Color 'Accent'
}

function Remove-LsmSavedRef {
    param([string]$Reference)

    Set-LsmSavedRefs -Entries @(Get-LsmSavedRefs | Where-Object { $_.ref -ne $Reference })
}

function verselist {
    # Browse saved references with optional book filter. Every action is ONE keypress - no Enter.
    param([string]$Filter = "")

    $pageSize = 9   # items labelled 1-9 so a single digit picks one
    $index = 0

    while ($true) {
        $layout = Get-BibleLayout
        $saved = @(Get-LsmSavedRefs)
        if ($Filter) {
            $saved = @($saved | Where-Object { $_.ref -like "*$Filter*" -or (Expand-BibleReference $_.ref) -like "*$Filter*" })
        }
        if ($saved.Count -eq 0) {
            Write-BibleHeader -Title "Saved verses" -Layout $layout
            $msg = if ($Filter) { "No saved verses match '$Filter'." } else { "Nothing saved yet. Open a chapter with 'bible John 3' and press S." }
            Write-BibleNote -Layout $layout -Text $msg -Color 'Warn'
            Write-Host ""
            return
        }
        if ($index -ge $saved.Count) { $index = [Math]::Max(0, $saved.Count - $pageSize) }

        Clear-Host
        $plural = if ($saved.Count -eq 1) { "verse" } else { "verses" }
        $titleNote = if ($Filter) { "$($saved.Count) $plural (filter: $Filter)" } else { "$($saved.Count) $plural" }
        Write-BibleHeader -Title "Saved verses" -Note $titleNote -Layout $layout

        $pageEnd = [Math]::Min($index + $pageSize, $saved.Count) - 1
        for ($i = $index; $i -le $pageEnd; $i++) {
            $label = $i - $index + 1
            $ref   = Expand-BibleReference $saved[$i].ref
            $stamp = $saved[$i].savedAt

            $line = $layout.Pad +
                    (Get-BibleStyled -Text ("{0,2}  " -f $label) -Color 'AccentDim') +
                    (Get-BibleStyled -Text $ref -Color 'Body')
            $gap = $layout.Content - 4 - $ref.Length - $stamp.Length
            if ($gap -ge 3) {
                $line += (" " * $gap) + (Get-BibleStyled -Text $stamp -Color 'Muted')
            }
            Write-Host $line
        }

        Write-Host ""
        Write-BibleRule -Layout $layout

        $hasNext = ($pageEnd + 1) -lt $saved.Count
        $hasPrev = $index -gt 0
        $hints = @(, @("1-9", "read"))
        if ($hasNext) { $hints += , @("N", "next") }
        if ($hasPrev) { $hints += , @("P", "prev") }
        $hints += , @("C", "copy")
        $hints += , @("D", "delete")
        $hints += , @("Q", "quit")

        $dash   = Get-BibleGlyph 'Dash'
        $status = "{0}{1}{2} of {3}" -f ($index + 1), $dash, ($pageEnd + 1), $saved.Count
        Write-BibleStatusBar -Layout $layout -Status $status -Hints $hints
        Write-Host ""
        Write-BiblePrompt -Layout $layout

        $key = Read-BibleKey
        $ch  = "$($key.Char)".ToUpper()
        Write-Host ""

        if ($key.Code -eq 40 -and $hasNext) { $index += $pageSize; continue }   # Down arrow
        if ($key.Code -eq 38 -and $hasPrev) { $index -= $pageSize; continue }   # Up arrow

        switch ($ch) {
            "N" { if ($hasNext) { $index += $pageSize } }
            "P" { if ($hasPrev) { $index = [Math]::Max(0, $index - $pageSize) } }
            "Q" { return }
            "C" {
                Write-Host ""
                Write-BibleStyled ($layout.Pad + "press a number to copy, any other key cancels") -Color 'Accent'
                Write-BiblePrompt -Layout $layout
                $ck = Read-BibleKey
                Write-Host ""
                if ("$($ck.Char)" -match '^[1-9]$') {
                    $pick = $index + [int]"$($ck.Char)" - 1
                    if ($pick -le $pageEnd) {
                        $targetRef = $saved[$pick].ref
                        $res = Invoke-LsmApi -Reference $targetRef
                        if ($res -and $res.verses -and $res.verses.Count -gt 0) {
                            $verseTexts = ($res.verses | ForEach-Object { $_.text }) -join " "
                            "$(Expand-BibleReference $targetRef) - $verseTexts" | Set-Clipboard
                            Write-BibleStyled ($layout.Pad + "copied to clipboard: $(Expand-BibleReference $targetRef)") -Color 'Accent'
                        } else {
                            Write-BibleStyled ($layout.Pad + "could not fetch $targetRef") -Color 'Danger'
                        }
                        Start-Sleep -Milliseconds 700
                    }
                }
            }
            "D" {
                Write-Host ""
                Write-BibleStyled ($layout.Pad + "press a number to delete, any other key cancels") -Color 'Danger'
                Write-BiblePrompt -Layout $layout
                $dk = Read-BibleKey
                Write-Host ""
                if ("$($dk.Char)" -match '^[1-9]$') {
                    $pick = $index + [int]"$($dk.Char)" - 1
                    if ($pick -le $pageEnd) {
                        $gone = Expand-BibleReference $saved[$pick].ref
                        Remove-LsmSavedRef -Reference $saved[$pick].ref
                        Write-BibleStyled ($layout.Pad + "deleted  $gone") -Color 'Accent'
                        Start-Sleep -Milliseconds 650
                    }
                }
            }
            default {
                if ($ch -match '^[1-9]$') {
                    $pick = $index + [int]$ch - 1
                    if ($pick -le $pageEnd) {
                        Clear-Host
                        verse $saved[$pick].ref
                        Wait-BibleKey -Layout $layout -Text "press any key to go back to the list"
                    }
                }
            }
        }
    }
}

function savedverses {
    param(
        [Alias("md")]
        [switch]$Markdown
    )

    $layout = Get-BibleLayout
    $saved  = @(Get-LsmSavedRefs)
    if ($saved.Count -eq 0) {
        Write-BibleHeader -Title "Saved verses" -Layout $layout
        Write-BibleNote -Layout $layout -Text "Nothing saved yet." -Color 'Warn'
        Write-Host ""
        return
    }

    if ($Markdown) {
        $mdLines = @()
        $lastCopyright = $null
        foreach ($v in $saved) {
            $result = Invoke-LsmApi -Reference $v.ref
            $ref  = Expand-BibleReference $v.ref
            if ($result -and $result.verses -and $result.verses.Count -gt 0) {
                $vText = ($result.verses | ForEach-Object { $_.text }) -join " "
                $mdLines += "> **$ref**`r`n> $vText`r`n"
                if ($result.copyright) { $lastCopyright = $result.copyright }
            }
        }
        if ($lastCopyright) {
            $mdLines += "> *$lastCopyright*`r`n"
        }
        $finalMd = $mdLines -join "`r`n"
        $finalMd | Set-Clipboard
        Write-Host $finalMd
        Write-BibleStyled ($layout.Pad + "copied markdown to clipboard") -Color 'AccentDim'
        Write-Host ""
        return
    }

    $plural = if ($saved.Count -eq 1) { "verse" } else { "verses" }
    Write-BibleHeader -Title "Saved verses" -Note "$($saved.Count) $plural" -Layout $layout

    $copyright = $null
    foreach ($v in $saved) {
        $result = Invoke-LsmApi -Reference $v.ref

        $ref  = Expand-BibleReference $v.ref
        $line = $layout.Pad + (Get-BibleStyled -Text $ref -Color 'Gold' -Bold)
        $gap  = $layout.Content - $ref.Length - $v.savedAt.Length
        if ($gap -ge 3) {
            $line += (" " * $gap) + (Get-BibleStyled -Text $v.savedAt -Color 'Muted')
        }
        Write-Host $line

        if ($result -and $result.verses -and $result.verses.Count -gt 0) {
            foreach ($verseObj in $result.verses) {
                Write-BibleText -Text $verseObj.text -Prefix ($layout.Pad + "  ") -Width $layout.Text
            }
            if ($result.copyright) { $copyright = $result.copyright }
        } else {
            Write-BibleStyled ($layout.Pad + "  (could not fetch text right now)") -Color 'Danger'
        }
        Write-Host ""
    }

    if ($copyright) {
        Write-BibleRule -Layout $layout
        Write-BibleNote -Layout $layout -Text $copyright
        Write-Host ""
    }
}

function Get-BibleProgressBar {
    param(
        [int]$Current,     # 0-based focused verse index
        [int]$Total,       # Total verses in chapter
        [int]$Width = 8    # Length of track
    )

    if ($Total -le 0) { return "" }
    $pct = [Math]::Min(100, [Math]::Max(1, [Math]::Round((($Current + 1) / $Total) * 100)))
    $track = Get-BibleGlyph 'Track'
    $knob  = Get-BibleGlyph 'Knob'
    $knobPos = [Math]::Min($Width - 1, [Math]::Max(0, [Math]::Round(($Current / [Math]::Max(1, $Total - 1)) * ($Width - 1))))
    $left  = $track * $knobPos
    $right = $track * ($Width - 1 - $knobPos)

    return "[$left$knob$right] {0,2}%" -f $pct
}

function Get-BiblePageEnd {
    param($StartIndex, $Verses, $AvailableLines, $Layout)
    $prefixLen = $Layout.Margin + 5
    $linesUsed = 0
    $end = $StartIndex
    for ($i = $StartIndex; $i -lt $Verses.Count; $i++) {
        $need = (Get-BibleWrappedLines -Text $Verses[$i].text -PrefixLength $prefixLen -Width $Layout.Text).Count + 1
        if (($linesUsed + $need) -gt $AvailableLines -and $i -gt $StartIndex) { break }
        $linesUsed += $need
        $end = $i
    }
    return $end
}

function Get-BibleCenteredIndex {
    param($TargetIndex, $Verses, $AvailableLines, $Layout)
    $prefixLen = $Layout.Margin + 5
    $start = $TargetIndex
    $end   = $TargetIndex
    $lines = (Get-BibleWrappedLines -Text $Verses[$TargetIndex].text -PrefixLength $prefixLen -Width $Layout.Text).Count + 1

    $canBefore = $start -gt 0
    $canAfter  = $end -lt ($Verses.Count - 1)
    while ($canBefore -or $canAfter) {
        if ($canBefore) {
            $needB = (Get-BibleWrappedLines -Text $Verses[$start - 1].text -PrefixLength $prefixLen -Width $Layout.Text).Count + 1
            if (($lines + $needB) -le $AvailableLines) {
                $start--
                $lines += $needB
                $canBefore = ($start -gt 0)
            } else { $canBefore = $false }
        }
        if ($canAfter) {
            $needA = (Get-BibleWrappedLines -Text $Verses[$end + 1].text -PrefixLength $prefixLen -Width $Layout.Text).Count + 1
            if (($lines + $needA) -le $AvailableLines) {
                $end++
                $lines += $needA
                $canAfter = ($end -lt ($Verses.Count - 1))
            } else { $canAfter = $false }
        }
    }
    return $start
}


# ------------------------------------------------------------
# bible - the chapter reader
# ------------------------------------------------------------

function bible {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Reference
    )

    $layout = Get-BibleLayout

    $chapterRef = ($Reference -join " ").Trim()
    if (-not $chapterRef) {
        Write-BibleHeader -Title "bible" -Note "usage" -Layout $layout
        Write-BibleUsageRow -Layout $layout -Command "bible <book> <chapter>" -Detail "read a chapter   e.g. bible John 3" -Column 26
        Write-BibleUsageRow -Layout $layout -Command "bible <book>"           -Detail "opens chapter 1   e.g. bible Ephesians" -Column 26
        Write-Host ""
        return
    }

    # If only a book name is passed without a chapter number, default to chapter 1
    if ($chapterRef -notmatch '\d') {
        $resolvedBook = Resolve-BibleBook $chapterRef
        if ($resolvedBook) {
            $chapterRef = "$resolvedBook 1"
        } else {
            Write-BibleHeader -Title "bible" -Note "usage" -Layout $layout
            Write-BibleUsageRow -Layout $layout -Command "bible <book> <chapter>" -Detail "read a chapter   e.g. bible John 3" -Column 26
            Write-BibleUsageRow -Layout $layout -Command "bible <book>"           -Detail "opens chapter 1   e.g. bible Ephesians" -Column 26
            Write-Host ""
            return
        }
    }

    $result = Invoke-LsmApi -Reference $chapterRef
    if (-not $result) { return }

    if (-not $result.verses -or $result.verses.Count -eq 0) {
        $msg = if ($result.message) { $result.message } else { "No verses returned for '$chapterRef'." }
        Write-Host ""
        Write-BibleNote -Layout $layout -Text $msg -Color 'Warn'
        Write-Host ""
        return
    }

    $verses = @($result.verses)

    $selectedVerseIndex = 0
    $index = 0
    $pageHistory = New-Object System.Collections.Generic.List[int]

    # Where you were reading before each jump, so Backspace can return you to
    # the exact chapter AND scroll position - not just the top of it.
    $readingHistory = New-Object System.Collections.Generic.List[object]

    # In-chapter keyword search state
    $searchMatches = @()
    $searchQuery = ""
    $searchMatchIndex = -1

    $useAltBuffer = Test-BibleAnsi
    if ($useAltBuffer) {
        [Console]::Out.Write("$script:BibleEsc[?1049h")
    }

    try {
        while ($true) {
            $layout = Get-BibleLayout   # re-read every draw so resizing is honoured

            try   { $termHeight = $Host.UI.RawUI.WindowSize.Height }
            catch { $termHeight = 25 }

            # Keep selected verse bounded
            if ($selectedVerseIndex -lt 0) { $selectedVerseIndex = 0 }
            if ($selectedVerseIndex -ge $verses.Count) { $selectedVerseIndex = [Math]::Max(0, $verses.Count - 1) }

            # Reserve chrome: blank + title + rule + blank above, rule + status + copyright + prompt below
            $focusedNum = Get-BibleVerseNumber -Verse $verses[$selectedVerseIndex] -Fallback ($selectedVerseIndex + 1)
            $bar = Get-BibleProgressBar -Current $selectedVerseIndex -Total $verses.Count -Width 8
            $dash = Get-BibleGlyph 'Dash'
            $probeStatus = "verses {0}{1}{0} of {0}   {2}   [v.{3} focused]" -f $verses.Count, $dash, $bar, $focusedNum
            $probeHints  = @(, @("n/N", "match 99/99"), @("[ ]", "ch"), @("/", "search"), @(":", "jump"), @("S", "save"), @("C", "copy"), @("?", "define"), @("Q", "quit"))
            $chrome = 7 + @(Get-BibleStatusLines -Layout $layout -Status $probeStatus -Hints $probeHints).Count
            if ($result.copyright) {
                $chrome += @(Get-BibleWrappedLines -Text $result.copyright -PrefixLength $layout.Margin -Width $layout.Text).Count
            }
            $availableLines = [Math]::Max(3, $termHeight - $chrome)

            # Viewport anchoring: keep $index stationary when moving within viewport
            if ($index -lt 0) { $index = 0 }
            if ($index -ge $verses.Count) { $index = [Math]::Max(0, $verses.Count - 1) }
            if ($selectedVerseIndex -lt $index) { $index = $selectedVerseIndex }

            $pageEnd = Get-BiblePageEnd -StartIndex $index -Verses $verses -AvailableLines $availableLines -Layout $layout
            while ($selectedVerseIndex -gt $pageEnd -and $index -lt $selectedVerseIndex) {
                $index++
                $pageEnd = Get-BiblePageEnd -StartIndex $index -Verses $verses -AvailableLines $availableLines -Layout $layout
            }

            $frameLines = New-Object System.Collections.Generic.List[string]

            foreach ($hl in @(Get-BibleHeaderLines -Title (Expand-BibleReference $chapterRef) -Note "Recovery Version" -Layout $layout)) {
                $frameLines.Add($hl)
            }

            for ($i = $index; $i -le $pageEnd; $i++) {
                $isSel = ($i -eq $selectedVerseIndex)
                $vNum = Get-BibleVerseNumber -Verse $verses[$i] -Fallback ($i + 1)
                foreach ($vl in @(Get-BibleVerseLines -Number $vNum -Text $verses[$i].text -Layout $layout -Selected:$isSel)) {
                    $frameLines.Add($vl)
                }
                $frameLines.Add("")
            }

            $frameLines.Add((Get-BibleRuleLine -Layout $layout))

            $hasNext = ($pageEnd + 1) -lt $verses.Count
            $hasPrev = $index -gt 0
            $hints = @()
            if ($searchMatches.Count -gt 0) {
                $hints += , @("n/N", "match $($searchMatchIndex + 1)/$($searchMatches.Count)")
            } else {
                if ($hasNext) { $hints += , @("N", "next") }
                if ($hasPrev) { $hints += , @("P", "prev") }
            }
            $hints += , @("[ ]", "ch")
            $hints += , @("/", "search")
            $hints += , @(":", "jump")
            $hints += , @("S", "save")
            $hints += , @("C", "copy")
            $hints += , @("?", "define")
            $hints += , @("Q", "quit")

            $status = "verses {0}{1}{2} of {3}   {4}   [v.{5} focused]" -f ($index + 1), $dash, ($pageEnd + 1), $verses.Count, $bar, $focusedNum
            foreach ($sl in @(Get-BibleStatusLines -Layout $layout -Status $status -Hints $hints)) {
                $frameLines.Add($sl)
            }
            if ($result.copyright) {
                foreach ($cl in @(Get-BibleNoteLines -Layout $layout -Text $result.copyright)) {
                    $frameLines.Add($cl)
                }
            }
            $frameLines.Add("")

            $prompt = $layout.Pad + (Get-BibleStyled -Text (Get-BibleGlyph 'Prompt') -Color 'Accent' -Bold) + " "

            if (Test-BibleAnsi) {
                $el = "$script:BibleEsc[K"
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.Append("$script:BibleEsc[?25l$script:BibleEsc[H")
                foreach ($fl in $frameLines) {
                    [void]$sb.Append($fl)
                    [void]$sb.Append($el)
                    [void]$sb.Append("`r`n")
                }
                [void]$sb.Append($prompt)
                [void]$sb.Append($el)
                [void]$sb.Append("$script:BibleEsc[J$script:BibleEsc[?25h")
                [Console]::Out.Write($sb.ToString())
            } else {
                Clear-Host
                foreach ($fl in $frameLines) { Write-Host $fl }
                Write-Host $prompt -NoNewline
            }

            $input = Read-BibleInput

        switch ($input.Action) {
            "ScrollDown" {
                if ($selectedVerseIndex -lt ($verses.Count - 1)) {
                    $selectedVerseIndex++
                    if ($selectedVerseIndex -gt $pageEnd) {
                        $index++
                    }
                }
            }
            "ScrollUp" {
                if ($selectedVerseIndex -gt 0) {
                    $selectedVerseIndex--
                    if ($selectedVerseIndex -lt $index) {
                        $index--
                    }
                }
            }
            "PageDown" {
                if ($pageEnd -lt ($verses.Count - 1)) {
                    $pageHistory.Add($selectedVerseIndex)
                    $index = $pageEnd + 1
                    $selectedVerseIndex = $index
                } else {
                    $nextRef = Get-BibleNextChapterRef -Reference $chapterRef -Delta 1
                    if ($nextRef) {
                        $newResult = Invoke-LsmApi -Reference $nextRef
                        if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                            $readingHistory.Add([PSCustomObject]@{
                                Ref         = $chapterRef
                                Result      = $result
                                Index       = $selectedVerseIndex
                                PageHistory = @($pageHistory.ToArray())
                            })
                            $result     = $newResult
                            $verses     = @($newResult.verses)
                            $chapterRef = $nextRef
                            $selectedVerseIndex = 0
                            $index      = 0
                            $pageHistory.Clear()
                            $searchMatches = @()
                            $searchQuery   = ""
                            $searchMatchIndex = -1
                        }
                    }
                }
            }
            "PageUp" {
                if ($index -gt 0) {
                    if ($pageHistory.Count -gt 0) {
                        $selectedVerseIndex = $pageHistory[$pageHistory.Count - 1]
                        $pageHistory.RemoveAt($pageHistory.Count - 1)
                    } else {
                        $selectedVerseIndex = [Math]::Max(0, $index - 1)
                    }
                    $index = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                } else {
                    $prevRef = Get-BibleNextChapterRef -Reference $chapterRef -Delta -1
                    if ($prevRef) {
                        $newResult = Invoke-LsmApi -Reference $prevRef
                        if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                            $readingHistory.Add([PSCustomObject]@{
                                Ref         = $chapterRef
                                Result      = $result
                                Index       = $selectedVerseIndex
                                PageHistory = @($pageHistory.ToArray())
                            })
                            $result     = $newResult
                            $verses     = @($newResult.verses)
                            $chapterRef = $prevRef
                            $selectedVerseIndex = [Math]::Max(0, $newResult.verses.Count - 1)
                            $index      = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                            $pageHistory.Clear()
                            $searchMatches = @()
                            $searchQuery   = ""
                            $searchMatchIndex = -1
                        }
                    }
                }
            }
            "NextChapter" {
                $nextRef = Get-BibleNextChapterRef -Reference $chapterRef -Delta 1
                if ($nextRef) {
                    $newResult = Invoke-LsmApi -Reference $nextRef
                    if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                        $readingHistory.Add([PSCustomObject]@{
                            Ref         = $chapterRef
                            Result      = $result
                            Index       = $selectedVerseIndex
                            PageHistory = @($pageHistory.ToArray())
                        })
                        $result     = $newResult
                        $verses     = @($newResult.verses)
                        $chapterRef = $nextRef
                        $selectedVerseIndex = 0
                        $index      = 0
                        $pageHistory.Clear()
                        $searchMatches = @()
                        $searchQuery   = ""
                        $searchMatchIndex = -1
                    } else {
                        Write-Host ""
                        Write-BibleStyled ($layout.Pad + "Reached end of book") -Color 'Warn'
                        Start-Sleep -Milliseconds 700
                    }
                }
            }
            "PrevChapter" {
                $prevRef = Get-BibleNextChapterRef -Reference $chapterRef -Delta -1
                if ($prevRef) {
                    $newResult = Invoke-LsmApi -Reference $prevRef
                    if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                        $readingHistory.Add([PSCustomObject]@{
                            Ref         = $chapterRef
                            Result      = $result
                            Index       = $selectedVerseIndex
                            PageHistory = @($pageHistory.ToArray())
                        })
                        $result     = $newResult
                        $verses     = @($newResult.verses)
                        $chapterRef = $prevRef
                        $selectedVerseIndex = 0
                        $index      = 0
                        $pageHistory.Clear()
                        $searchMatches = @()
                        $searchQuery   = ""
                        $searchMatchIndex = -1
                    }
                }
            }
            "Back" {
                if ($readingHistory.Count -gt 0) {
                    $prev = $readingHistory[$readingHistory.Count - 1]
                    $readingHistory.RemoveAt($readingHistory.Count - 1)
                    $chapterRef = $prev.Ref
                    $result     = $prev.Result
                    $verses     = @($prev.Result.verses)
                    $selectedVerseIndex = if ($null -ne $prev.Index) { $prev.Index } else { 0 }
                    $index      = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                    $pageHistory.Clear()
                    foreach ($h in @($prev.PageHistory)) { $pageHistory.Add($h) }
                    $searchMatches = @()
                    $searchQuery   = ""
                    $searchMatchIndex = -1
                }
            }
            "Cancel" {
                continue
            }
            "Define" {
                Write-Host ""
                Write-BibleStyled ($layout.Pad + "define: ") -Color 'Accent' -NoNewline
                $word = Read-Host
                if ($word -and $word.Trim()) {
                    Clear-Host
                    Show-LsmWordLookup $word.Trim()
                    Wait-BibleKey -Layout $layout -Text "press any key to go back to the chapter"
                }
            }
            "Submit" {
                $trimmed = $input.Text.Trim()
                if ($trimmed -eq "Q" -or $trimmed -eq "q") {
                    return
                }

                # In-chapter search / book reference via /
                if ($trimmed -match '^/(.*)$') {
                    $q = $matches[1].Trim()
                    if (-not $q) {
                        $searchMatches = @()
                        $searchQuery   = ""
                        $searchMatchIndex = -1
                        Write-Host ""
                        Write-BibleStyled ($layout.Pad + "search cleared") -Color 'Muted'
                        Start-Sleep -Milliseconds 600
                        continue
                    }

                    $resolved = $null
                    if ($q -match '^(?<book>(?:[1-3]|I{1,3})?\s*[A-Za-z][A-Za-z\.\s]*?)\s*(?<chapter>\d+)$') {
                        $rb = Resolve-BibleBook $matches['book']
                        if ($rb) { $resolved = "$rb $($matches['chapter'])" }
                    }

                    if ($resolved) {
                        $newResult = Invoke-LsmApi -Reference $resolved
                        if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                            $readingHistory.Add([PSCustomObject]@{
                                Ref         = $chapterRef
                                Result      = $result
                                Index       = $selectedVerseIndex
                                PageHistory = @($pageHistory.ToArray())
                            })
                            $result     = $newResult
                            $verses     = @($newResult.verses)
                            $chapterRef = $resolved
                            $selectedVerseIndex = 0
                            $index      = 0
                            $pageHistory.Clear()
                            $searchMatches = @()
                            $searchQuery   = ""
                            $searchMatchIndex = -1
                        } else {
                            Write-Host ""
                            Write-BibleStyled ($layout.Pad + "could not find '$resolved'") -Color 'Danger'
                            Wait-BibleKey -Layout $layout -Text "press any key to continue"
                        }
                        continue
                    }

                    $searchQuery = $q
                    $escPattern  = [regex]::Escape($searchQuery)
                    $matchesFound = @()
                    for ($vi = 0; $vi -lt $verses.Count; $vi++) {
                        if ($verses[$vi].text -match $escPattern) {
                            $matchesFound += $vi
                        }
                    }
                    $searchMatches = $matchesFound
                    if ($searchMatches.Count -gt 0) {
                        $mPos = -1
                        for ($mi = 0; $mi -lt $searchMatches.Count; $mi++) {
                            if ($searchMatches[$mi] -ge $selectedVerseIndex) {
                                $mPos = $mi
                                break
                            }
                        }
                        if ($mPos -eq -1) { $mPos = 0 }
                        $searchMatchIndex = $mPos
                        $selectedVerseIndex = $searchMatches[$searchMatchIndex]
                        if ($selectedVerseIndex -lt $index -or $selectedVerseIndex -gt $pageEnd) {
                            $index = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                        }
                    } else {
                        $searchMatchIndex = -1
                        Write-Host ""
                        Write-BibleStyled ($layout.Pad + "no matches for '$searchQuery' in $(Expand-BibleReference $chapterRef)") -Color 'Warn'
                        Start-Sleep -Milliseconds 850
                    }
                    continue
                }

                # Next search match (n)
                if ($trimmed -eq "n" -and $searchMatches.Count -gt 0) {
                    $searchMatchIndex = ($searchMatchIndex + 1) % $searchMatches.Count
                    $selectedVerseIndex = $searchMatches[$searchMatchIndex]
                    if ($selectedVerseIndex -lt $index -or $selectedVerseIndex -gt $pageEnd) {
                        $index = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                    }
                    continue
                }

                # Previous search match (N)
                if ($trimmed -eq "N" -and $searchMatches.Count -gt 0) {
                    $searchMatchIndex = ($searchMatchIndex - 1 + $searchMatches.Count) % $searchMatches.Count
                    $selectedVerseIndex = $searchMatches[$searchMatchIndex]
                    if ($selectedVerseIndex -lt $index -or $selectedVerseIndex -gt $pageEnd) {
                        $index = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                    }
                    continue
                }

                # Direct verse jump (:14 or : 14)
                if ($trimmed -match '^:?\s*(\d+)$' -and ($trimmed.StartsWith(":") -or $input.Text.StartsWith(":"))) {
                    $targetNum = [int]$matches[1]
                    $found = -1
                    for ($vi = 0; $vi -lt $verses.Count; $vi++) {
                        $vn = Get-BibleVerseNumber -Verse $verses[$vi] -Fallback ($vi + 1)
                        if ($vn -eq $targetNum) {
                            $found = $vi
                            break
                        }
                    }
                    if ($found -ge 0) {
                        $selectedVerseIndex = $found
                        $index = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                    } else {
                        Write-Host ""
                        Write-BibleStyled ($layout.Pad + "Verse $targetNum not found in $(Expand-BibleReference $chapterRef)") -Color 'Warn'
                        Start-Sleep -Milliseconds 800
                    }
                    continue
                }

                switch ($trimmed.ToUpper()) {
                    "N" {
                        if ($pageEnd -lt ($verses.Count - 1)) {
                            $pageHistory.Add($selectedVerseIndex)
                            $index = $pageEnd + 1
                            $selectedVerseIndex = $index
                        } else {
                            $nextRef = Get-BibleNextChapterRef -Reference $chapterRef -Delta 1
                            if ($nextRef) {
                                $newResult = Invoke-LsmApi -Reference $nextRef
                                if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                                    $readingHistory.Add([PSCustomObject]@{
                                        Ref         = $chapterRef
                                        Result      = $result
                                        Index       = $selectedVerseIndex
                                        PageHistory = @($pageHistory.ToArray())
                                    })
                                    $result     = $newResult
                                    $verses     = @($newResult.verses)
                                    $chapterRef = $nextRef
                                    $selectedVerseIndex = 0
                                    $index      = 0
                                    $pageHistory.Clear()
                                    $searchMatches = @()
                                    $searchQuery   = ""
                                    $searchMatchIndex = -1
                                }
                            }
                        }
                    }
                    "P" {
                        if ($index -gt 0) {
                            if ($pageHistory.Count -gt 0) {
                                $selectedVerseIndex = $pageHistory[$pageHistory.Count - 1]
                                $pageHistory.RemoveAt($pageHistory.Count - 1)
                            } else {
                                $selectedVerseIndex = [Math]::Max(0, $index - 1)
                            }
                            $index = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                        } else {
                            $prevRef = Get-BibleNextChapterRef -Reference $chapterRef -Delta -1
                            if ($prevRef) {
                                $newResult = Invoke-LsmApi -Reference $prevRef
                                if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                                    $readingHistory.Add([PSCustomObject]@{
                                        Ref         = $chapterRef
                                        Result      = $result
                                        Index       = $selectedVerseIndex
                                        PageHistory = @($pageHistory.ToArray())
                                    })
                                    $result     = $newResult
                                    $verses     = @($newResult.verses)
                                    $chapterRef = $prevRef
                                    $selectedVerseIndex = [Math]::Max(0, $newResult.verses.Count - 1)
                                    $index      = Get-BibleCenteredIndex -TargetIndex $selectedVerseIndex -Verses $verses -AvailableLines $availableLines -Layout $layout
                                    $pageHistory.Clear()
                                    $searchMatches = @()
                                    $searchQuery   = ""
                                    $searchMatchIndex = -1
                                }
                            }
                        }
                    }
                    "C" {
                        $letters = [char[]]"abcdefghijklmnopqrstuvwxyz"
                        Write-Host ""
                        for ($i = $index; $i -le $pageEnd; $i++) {
                            $li = $i - $index
                            if ($li -ge $letters.Count) { break }
                            $marker = if ($i -eq $selectedVerseIndex) { "*" } else { " " }
                            Write-Host ($layout.Pad +
                                        (Get-BibleStyled -Text ("{0}{1} " -f $marker, $letters[$li]) -Color 'Accent' -Bold) +
                                        (Get-BibleStyled -Text (Expand-BibleReference $verses[$i].ref) -Color 'Body'))
                        }
                        Write-Host ""
                        Write-BibleStyled ($layout.Pad + "copy verse or range (Enter for focused, 'a-c', '16-18', or Esc to cancel): ") -Color 'Accent' -NoNewline
                        $copyInput = Read-Host
                        $targetRangeStr = if ($copyInput) { $copyInput.Trim() } else { "" }

                        $sIdx = -1
                        $eIdx = -1

                        if (-not $targetRangeStr) {
                            $sIdx = $selectedVerseIndex
                            $eIdx = $selectedVerseIndex
                        } elseif ($targetRangeStr -match '^([a-z])\s*(?:[-–\.]+\s*([a-z]))?$') {
                            $c1 = [Array]::IndexOf($letters, [char]$matches[1].ToLower())
                            if ($matches[2]) {
                                $c2 = [Array]::IndexOf($letters, [char]$matches[2].ToLower())
                                if ($c1 -ge 0 -and $c2 -ge 0) {
                                    $sIdx = [Math]::Min($c1, $c2) + $index
                                    $eIdx = [Math]::Min([Math]::Max($c1, $c2) + $index, $pageEnd)
                                }
                            } elseif ($c1 -ge 0 -and ($index + $c1) -le $pageEnd) {
                                $sIdx = $index + $c1
                                $eIdx = $sIdx
                            }
                        } elseif ($targetRangeStr -match '^(\d+)\s*(?:[-–\.]+\s*(\d+))?$') {
                            $v1 = [int]$matches[1]
                            $v2 = if ($matches[2]) { [int]$matches[2] } else { $v1 }
                            $minV = [Math]::Min($v1, $v2)
                            $maxV = [Math]::Max($v1, $v2)

                            $foundIndices = @()
                            for ($vi = 0; $vi -lt $verses.Count; $vi++) {
                                $vn = Get-BibleVerseNumber -Verse $verses[$vi] -Fallback ($vi + 1)
                                if ($vn -ge $minV -and $vn -le $maxV) {
                                    $foundIndices += $vi
                                }
                            }
                            if ($foundIndices.Count -gt 0) {
                                $sIdx = $foundIndices[0]
                                $eIdx = $foundIndices[-1]
                            }
                        }

                        if ($sIdx -ge 0 -and $eIdx -ge $sIdx -and $eIdx -lt $verses.Count) {
                            $startRef = Expand-BibleReference $verses[$sIdx].ref
                            if ($sIdx -eq $eIdx) {
                                $copiedRef = $startRef
                                $copiedText = $verses[$sIdx].text
                            } else {
                                $sNum = Get-BibleVerseNumber -Verse $verses[$sIdx] -Fallback ($sIdx + 1)
                                $eNum = Get-BibleVerseNumber -Verse $verses[$eIdx] -Fallback ($eIdx + 1)
                                if ($startRef -match '^(.*?):(\d+)$') {
                                    $copiedRef = "$($matches[1]):$sNum-$eNum"
                                } else {
                                    $copiedRef = "$startRef-$eNum"
                                }
                                $copiedText = ($verses[$sIdx..$eIdx] | ForEach-Object { $_.text }) -join " "
                            }
                            $clipContent = "$copiedRef - $copiedText"
                            $clipContent | Set-Clipboard
                            Write-Host ""
                            Write-BibleStyled ($layout.Pad + "copied to clipboard: $copiedRef") -Color 'Accent'
                            Start-Sleep -Milliseconds 850
                        } else {
                            Write-Host ""
                            Write-BibleStyled ($layout.Pad + "copy cancelled") -Color 'Muted'
                            Start-Sleep -Milliseconds 500
                        }
                    }
                    "S" {
                        $letters = [char[]]"abcdefghijklmnopqrstuvwxyz"
                        Write-Host ""
                        for ($i = $index; $i -le $pageEnd; $i++) {
                            $li = $i - $index
                            if ($li -ge $letters.Count) { break }
                            $marker = if ($i -eq $selectedVerseIndex) { "*" } else { " " }
                            Write-Host ($layout.Pad +
                                        (Get-BibleStyled -Text ("{0}{1} " -f $marker, $letters[$li]) -Color 'Accent' -Bold) +
                                        (Get-BibleStyled -Text (Expand-BibleReference $verses[$i].ref) -Color 'Body'))
                        }
                        Write-Host ""
                        Write-BibleStyled ($layout.Pad + "press a letter to save (Enter for focused verse, any other key cancels)") -Color 'Muted'
                        Write-BiblePrompt -Layout $layout
                        $pk = Read-BibleKey
                        Write-Host ""
                        $chKey = "$($pk.Char)".ToLower()
                        $targetIdx = -1
                        if ($pk.Code -eq 13 -or $chKey -eq "`r" -or $chKey -eq "`n") {
                            $targetIdx = $selectedVerseIndex
                        } else {
                            $li = [Array]::IndexOf($letters, [char]$chKey)
                            if ($li -ge 0 -and ($index + $li) -le $pageEnd) {
                                $targetIdx = $index + $li
                            }
                        }
                        if ($targetIdx -ge 0 -and $targetIdx -lt $verses.Count) {
                            Write-Host ""
                            Save-LsmVerse -Reference $verses[$targetIdx].ref -Layout $layout
                            Start-Sleep -Milliseconds 750
                        }
                    }
                    "" {
                        # empty input, just redraw
                    }
                    default {
                        # anything else is treated as a new "Book Chapter" reference to jump to
                        $targetRef = $trimmed
                        if ($targetRef -notmatch '\d') {
                            $rb = Resolve-BibleBook $targetRef
                            if ($rb) { $targetRef = "$rb 1" }
                        }
                        $newResult = Invoke-LsmApi -Reference $targetRef
                        if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                            $readingHistory.Add([PSCustomObject]@{
                                Ref         = $chapterRef
                                Result      = $result
                                Index       = $selectedVerseIndex
                                PageHistory = @($pageHistory.ToArray())
                            })
                            $result     = $newResult
                            $verses     = @($newResult.verses)
                            $chapterRef = $targetRef
                            $selectedVerseIndex = 0
                            $index      = 0
                            $pageHistory.Clear()
                            $searchMatches = @()
                            $searchQuery   = ""
                            $searchMatchIndex = -1
                        } else {
                            Write-Host ""
                            Write-BibleStyled ($layout.Pad + "could not find '$trimmed' - try a format like 'John 4'") -Color 'Danger'
                            Wait-BibleKey -Layout $layout -Text "press any key to continue"
                        }
                    }
                }
            }
        }
        }
    }
    finally {
        if ($useAltBuffer) {
            [Console]::Out.Write("$script:BibleEsc[?1049l$script:BibleEsc[?25h")
        }
    }
}

# ------------------------------------------------------------
# Aliases, Tab Completion, and Direct Book Invocations
# ------------------------------------------------------------

Set-Alias -Name v -Value verse -Description "Bible verse lookup"
Set-Alias -Name b -Value bible -Description "Bible chapter reader"

if (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue) {
    $script:BibleCompleter = {
        param($wordToComplete, $commandAst, $cursorPosition)
        $books = (Get-BibleBookMap).Values | Select-Object -Unique
        $books | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    Register-ArgumentCompleter -CommandName @('verse', 'v', 'bible', 'b') -Native -ScriptBlock $script:BibleCompleter
}

function Register-BibleBookFunctions {
    $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($cmd in (Get-Command -CommandType Alias,Function,Cmdlet -ErrorAction SilentlyContinue)) {
        $null = $existing.Add($cmd.Name)
    }

    $map = Get-BibleBookMap
    $canonicalBooks = $map.Values | Select-Object -Unique
    foreach ($book in $canonicalBooks) {
        $cmdName = $book -replace '\s+', ''
        if (-not $existing.Contains($cmdName)) {
            $target = $book
            Set-Item "function:global:$cmdName" -Value {
                param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Ref)
                $argStr = if ($Ref) { ($Ref -join " ").Trim() } else { "" }
                if (-not $argStr) {
                    bible "$target 1"
                } elseif ($argStr -match '^\d+$') {
                    bible "$target $argStr"
                } else {
                    verse "$target $argStr"
                }
            }.GetNewClosure()
            $null = $existing.Add($cmdName)
        }
    }

    $commonAbbrs = @{
        'Gen' = 'Genesis'; 'Exo' = 'Exodus'; 'Lev' = 'Leviticus'; 'Num' = 'Numbers'; 'Deut' = 'Deuteronomy';
        'Josh' = 'Joshua'; 'Judg' = 'Judges'; 'Psa' = 'Psalms'; 'Ps' = 'Psalms'; 'Prov' = 'Proverbs';
        'Eccl' = 'Ecclesiastes'; 'Isa' = 'Isaiah'; 'Jer' = 'Jeremiah'; 'Lam' = 'Lamentations';
        'Ezek' = 'Ezekiel'; 'Dan' = 'Daniel'; 'Hos' = 'Hosea'; 'Hab' = 'Habakkuk'; 'Mal' = 'Malachi';
        'Matt' = 'Matthew'; 'Mk' = 'Mark'; 'Lk' = 'Luke'; 'Jn' = 'John'; 'Act' = 'Acts';
        'Rom' = 'Romans'; 'Gal' = 'Galatians'; 'Eph' = 'Ephesians'; 'Phil' = 'Philippians';
        'Col' = 'Colossians'; 'Thess' = '1 Thessalonians'; 'Tim' = '1 Timothy'; 'Heb' = 'Hebrews';
        'Jas' = 'James'; 'Pet' = '1 Peter'; 'Rev' = 'Revelation'
    }
    foreach ($abbr in $commonAbbrs.Keys) {
        $targetBook = $commonAbbrs[$abbr]
        if (-not $existing.Contains($abbr)) {
            $target = $targetBook
            Set-Item "function:global:$abbr" -Value {
                param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Ref)
                $argStr = if ($Ref) { ($Ref -join " ").Trim() } else { "" }
                if (-not $argStr) {
                    bible "$target 1"
                } elseif ($argStr -match '^\d+$') {
                    bible "$target $argStr"
                } else {
                    verse "$target $argStr"
                }
            }.GetNewClosure()
            $null = $existing.Add($abbr)
        }
    }
}

Register-BibleBookFunctions
