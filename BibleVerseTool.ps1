# ============================================================
# Bible lookup commands (Recovery Version text, api.lsm.org)
#
#   verse <reference>        e.g.  verse John 3:16
#   verse list               browse your saved references
#   bible <book> <chapter>   e.g.  bible John 3        (paged chapter reader)
#   Set-BibleEpub <path>     read from your Recovery Version EPUB instead of
#                            the API - adds footnotes (F in the reader)
#
# Word lookup lives INSIDE the chapter reader only: press ? while reading.
#   savedverses              print every saved verse in one go
#
# Credentials live in:  %USERPROFILE%\.lsm-verse.json
#   { "appid": "YOUR_APPID", "token": "YOUR_TOKEN" }
# Register at https://api.lsm.org to get an appid + token.
# With "epub": "C:\path\HolyBible.epub" in the same file, no API (and no
# credentials) are needed at all.
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

    if (Test-BibleAnsi) {
        switch ($Name) {
            'Rule'   { return [string][char]0x2500 }   # horizontal line
            'Prompt' { return [string][char]0x203A }   # single angle quote
            'Dash'   { return [string][char]0x2013 }   # en dash
        }
    }
    switch ($Name) {
        'Rule'   { return '-' }
        'Prompt' { return '>' }
        'Dash'   { return '-' }
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

function Write-BibleRule {
    param($Layout, [string]$Color = 'Rule')
    Write-BibleStyled ($Layout.Pad + ((Get-BibleGlyph 'Rule') * $Layout.Content)) -Color $Color
}

function Write-BibleHeader {
    # Title on the left, a quiet note on the right, a rule underneath.
    param(
        [string]$Title,
        [string]$Note = "",
        $Layout,
        [string]$TitleColor = 'Gold'
    )

    Write-Host ""
    $line = $Layout.Pad + (Get-BibleStyled -Text $Title -Color $TitleColor -Bold)
    if ($Note) {
        $gap = $Layout.Content - $Title.Length - $Note.Length
        if ($gap -ge 3) {
            $line += (" " * $gap) + (Get-BibleStyled -Text $Note -Color 'Muted')
        }
    }
    Write-Host $line
    Write-BibleRule -Layout $Layout
    Write-Host ""
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

function Write-BibleNote {
    param($Layout, [string]$Text, [string]$Color = 'Muted')

    foreach ($l in @(Get-BibleWrappedLines -Text $Text -PrefixLength $Layout.Margin -Width $Layout.Text)) {
        Write-BibleStyled ($Layout.Pad + $l) -Color $Color
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

$script:BibleBookMap   = $null
$script:BibleBookNames = $null

function Get-BibleBookMap {
    if ($script:BibleBookMap) { return $script:BibleBookMap }

    # Canonical order matters: the EPUB numbers its files 01-66 in this order.
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

    $script:BibleBookNames = @($books.Keys)
    $script:BibleBookMap   = $map
    return $map
}

function Get-BibleBookNumber {
    # "John" -> 43. Full names only - run Expand-BibleReference first.
    param([string]$Name)

    Get-BibleBookMap | Out-Null
    $i = [Array]::IndexOf($script:BibleBookNames, $Name)
    if ($i -lt 0) { return 0 }
    return $i + 1
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
    # api.dictionaryapi.dev - no key, no account. Returns $null when the word
    # is not found (the API answers 404 for that, which is not an error worth
    # shouting about).
    param([Parameter(Mandatory)][string]$Word)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://api.dictionaryapi.dev/api/v2/entries/en/{0}" -f [uri]::EscapeDataString($Word)

    try {
        return Invoke-RestMethod -Uri $url -TimeoutSec 15
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        $layout = Get-BibleLayout
        Write-Host ""
        if ($status -eq 404) {
            Write-BibleNote -Layout $layout -Text "No dictionary entry for '$Word'." -Color 'Warn'
        } else {
            Write-BibleNote -Layout $layout -Text "Lookup failed: $($_.Exception.Message)" -Color 'Danger'
        }
        return $null
    }
}

function Get-BiblePassage {
    # The one place that decides where verse text comes from: your EPUB when
    # one is configured, otherwise api.lsm.org. Both hand back the same shape
    # - { verses; copyright; message } - so the commands never need to care.
    param([Parameter(Mandatory)][string]$Reference)

    if (Get-BibleEpubPath) { return Invoke-BibleEpub -Reference $Reference }
    return Invoke-LsmApi -Reference $Reference
}


# ------------------------------------------------------------
# EPUB source
#
# With "epub" set in .lsm-verse.json, verses come from your own copy of the
# Recovery Version EPUB instead of the API - no credentials needed, and the
# EPUB carries the footnotes and cross-references the API does not. It is
# read live, straight out of the zip; nothing is extracted to disk.
#
# Layout inside the zip: one file per chapter, NN_Book_C.htm (NN = 01-66 in
# canonical order), and its notes alongside as NN_Book_nC.htm.
# ------------------------------------------------------------

$script:BibleEpubIndex = $null
$script:BibleEpubCache = @{}

function Get-BibleConfigPath {
    return (Join-Path $HOME ".lsm-verse.json")
}

function Get-BibleEpubPath {
    # The configured path, or $null when no EPUB is set (= use the API). A
    # path that no longer exists is still returned, so the reader can say so
    # instead of silently falling back to the API.
    $configPath = Get-BibleConfigPath
    if (-not (Test-Path $configPath)) { return $null }
    try   { $config = Get-Content $configPath -Raw | ConvertFrom-Json }
    catch { return $null }
    if (-not $config -or -not $config.epub) { return $null }
    return [Environment]::ExpandEnvironmentVariables("$($config.epub)")
}

function Open-BibleEpubZip {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    return [IO.Compression.ZipFile]::OpenRead($Path)
}

function Get-BibleEpubIndex {
    # Maps "book|chapter" -> the zip entries holding its text and its notes.
    # Cached until the file changes.
    param([string]$Path)

    $stamp = (Get-Item -LiteralPath $Path).LastWriteTimeUtc.Ticks
    $key   = "$Path|$stamp"
    if ($script:BibleEpubIndex -and $script:BibleEpubIndex.Key -eq $key) {
        return $script:BibleEpubIndex
    }

    $chapters = @{}
    $zip = Open-BibleEpubZip -Path $Path
    try {
        foreach ($e in $zip.Entries) {
            if ($e.FullName -notmatch '^(?:.*/)?(\d{2})_[^_/]+_(n?)(\d+)\.htm$') { continue }
            $id = "{0}|{1}" -f [int]$matches[1], [int]$matches[3]
            if (-not $chapters.ContainsKey($id)) { $chapters[$id] = @{ Text = $null; Notes = $null } }
            if ($matches[2]) { $chapters[$id].Notes = $e.FullName }
            else             { $chapters[$id].Text  = $e.FullName }
        }
    } finally {
        $zip.Dispose()
    }

    $script:BibleEpubCache = @{}
    $script:BibleEpubIndex = [PSCustomObject]@{ Key = $key; Chapters = $chapters }
    return $script:BibleEpubIndex
}

function Read-BibleEpubEntry {
    param($Zip, [string]$Name)

    $entry = $Zip.GetEntry($Name)
    if (-not $entry) { return "" }
    $reader = New-Object IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8)
    try     { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

function ConvertFrom-BibleEpubHtml {
    # A fragment of the EPUB's XHTML -> one line of plain text. With
    # -Supplied, <i> (words the translators supplied) becomes the same
    # [bracket] notation the API uses, so the italics rendering is shared.
    param([string]$Html, [switch]$Supplied)

    $t = $Html
    if ($Supplied) {
        $t = $t -replace '<i>', '[' -replace '</i>', ']'
    }
    $t = $t -replace '<br\s*/?>', ' '
    $t = $t -replace '<[^>]+>', ''
    $t = [Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace [string][char]0xA0, ' '
    $t = ($t -replace '\s+', ' ').Trim()
    if ($Supplied) {
        $t = $t -replace '\[\s*\]', ''
        # Pull touching punctuation inside the brackets - "[He]," would
        # otherwise print as "He ," - which is also how the API writes it.
        $t = [regex]::Replace($t, '([^\s\[\]]*)\[([^\]]*)\]([^\s\[\]]*)', {
            param($m) "[" + $m.Groups[1].Value + $m.Groups[2].Value.Trim() + $m.Groups[3].Value + "]"
        })
    }
    return $t
}

function Get-BibleNoteKey {
    # Normalised form for matching a note's word against verse text.
    param([string]$Word)
    return ($Word -replace '[^\p{L}\p{N}]', '').ToLower()
}

function Find-BibleTokenRun {
    # First position at or after $Start where $Want appears as a run of
    # consecutive tokens. -1 if it does not.
    param([string[]]$Keys, [string[]]$Want, [int]$Start)

    for ($i = [Math]::Max(0, $Start); $i -le ($Keys.Count - $Want.Count); $i++) {
        $ok = $true
        for ($j = 0; $j -lt $Want.Count; $j++) {
            if ($Keys[$i + $j] -ne $Want[$j]) { $ok = $false; break }
        }
        if ($ok) { return $i }
    }
    return -1
}

function Set-BibleVerseMarks {
    # Works out which word each footnote/cross-reference hangs on, as
    # token index -> label, using the same tokens Write-BibleText prints.
    #
    # The notes only name the word ("born"), not its position, so a repeated
    # word is ambiguous. Footnote numbers and cross-reference letters each run
    # in reading order, so each sequence keeps its own cursor and searches on
    # from its last hit - that lands on the right "God" in John 3:2.
    param($Verse)

    $tokens = @(Split-BibleEmphasis -Text $Verse.text)
    $keys   = @($tokens | ForEach-Object { Get-BibleNoteKey $_.Text })
    $parts  = @($tokens | ForEach-Object { , @(($_.Text -split '[-\u2014]') | ForEach-Object { Get-BibleNoteKey $_ }) })
    $marks     = @{}
    $numCursor = 0
    $letCursor = 0

    foreach ($n in @($Verse.notes)) {
        if ($n.NoMark -or -not $n.Word) { continue }
        $want = @(($n.Word -split '\s+') | ForEach-Object { Get-BibleNoteKey $_ } | Where-Object { $_ })
        if ($want.Count -eq 0 -or $want.Count -gt $keys.Count) { continue }

        $hasNum = $n.Label -match '\d|\*'
        $hasLet = $n.Label -match '[a-z]'
        $start  = 0
        if ($hasNum) { $start = [Math]::Max($start, $numCursor) }
        if ($hasLet) { $start = [Math]::Max($start, $letCursor) }

        $hit = Find-BibleTokenRun -Keys $keys -Want $want -Start $start
        if ($hit -lt 0) { $hit = Find-BibleTokenRun -Keys $keys -Want $want -Start 0 }
        if ($hit -lt 0 -and $want.Count -eq 1) {
            # Half of a hyphenated word: "out" in "out-resurrection".
            for ($i = 0; $i -lt $parts.Count; $i++) {
                if ($parts[$i] -contains $want[0]) { $hit = $i; break }
            }
        }
        if ($hit -lt 0) { continue }

        $last = $hit + $want.Count - 1
        if ($marks.ContainsKey($last)) { $marks[$last] += $n.Label }
        else                           { $marks[$last]  = $n.Label }
        if ($hasNum) { $numCursor = $last + 1 }
        if ($hasLet) { $letCursor = $last + 1 }
    }

    $Verse.marks = $marks
}

function Read-BibleEpubChapter {
    # Parses one chapter and its notes into verse objects:
    #   { ref; num; text; notes; marks }
    # where each note is { Label; Word; Paragraphs; Xref; NoMark }.
    # Returns $null if the EPUB has no such chapter.
    param([string]$Path, [int]$Book, [int]$Chapter)

    $index = Get-BibleEpubIndex -Path $Path
    $id    = "$Book|$Chapter"
    if ($script:BibleEpubCache.ContainsKey($id)) { return $script:BibleEpubCache[$id] }

    $entry = $index.Chapters[$id]
    if (-not $entry -or -not $entry.Text) { return $null }

    $zip = Open-BibleEpubZip -Path $Path
    try {
        $html  = Read-BibleEpubEntry -Zip $zip -Name $entry.Text
        $notes = if ($entry.Notes) { Read-BibleEpubEntry -Zip $zip -Name $entry.Notes } else { "" }
    } finally {
        $zip.Dispose()
    }

    Get-BibleBookMap | Out-Null   # fills $script:BibleBookNames
    $bookName = $script:BibleBookNames[$Book - 1]
    $verses   = New-Object System.Collections.Generic.List[object]
    $byNum    = @{}

    $opts = [Text.RegularExpressions.RegexOptions]::Singleline
    foreach ($m in [regex]::Matches($html, '<p class="(verse|nnverse)"([^>]*)>(.*?)</p>', $opts)) {
        # Drop the leading <b>Jn 3:16</b> - the verse number comes from the id.
        $body = $m.Groups[3].Value -replace '^\s*<b>.*?</b>', ''
        $text = ConvertFrom-BibleEpubHtml -Html $body -Supplied

        if ($m.Groups[1].Value -eq 'nnverse') {
            # A new paragraph that is still the same verse (no number).
            if ($verses.Count -gt 0) {
                $last = $verses[$verses.Count - 1]
                $last.text = "$($last.text) $text".Trim()
            }
            continue
        }

        if ($m.Groups[2].Value -notmatch 'id="[^"]*-(\d+)"') { continue }
        $num = [int]$matches[1]
        $v = [PSCustomObject]@{
            ref   = "$bookName ${Chapter}:$num"
            num   = $num
            text  = $text
            notes = $null
            marks = $null
        }
        $verses.Add($v)
        $byNum[$num] = $v
    }

    $copyright = $null
    if ($html -match '(?s)<p class="bottom-copyright">(.*?)</p>') {
        $copyright = ConvertFrom-BibleEpubHtml -Html $matches[1]
    }

    # Notes: one <div> each. "n3_3_1" is footnote 1 on verse 3, "c3_5_a" is
    # cross-reference a on verse 5. A footnote with its own cross-reference
    # carries both in its label ("1a").
    $noteLists = @{}
    foreach ($d in [regex]::Matches($notes, '<div id="[nc]\d+_(\d+)_[^"]*">(.*?)</div>', $opts)) {
        $vnum  = [int]$d.Groups[1].Value
        $inner = $d.Groups[2].Value

        $label = ""
        $word  = ""
        if ($inner -match '(?s)<p class="note-head"[^>]*>.*?<sup>(.*?)</sup>(.*?)</a>') {
            $label = ConvertFrom-BibleEpubHtml -Html $matches[1]
            $word  = ConvertFrom-BibleEpubHtml -Html $matches[2]
        }
        $xref = ""
        if ($inner -match '(?s)<span class="xref"[^>]*>(.*?)</span>') {
            $xref = ConvertFrom-BibleEpubHtml -Html $matches[1]
        }
        $paras = @(foreach ($p in [regex]::Matches($inner, '<p class="note">(.*?)</p>', $opts)) {
            $pt = ConvertFrom-BibleEpubHtml -Html $p.Groups[1].Value
            if ($pt) { $pt }
        })

        # Psalm titles are verse 0, which is not a verse here - keep those
        # notes on verse 1, but don't try to place a marker for them.
        $noMark = $false
        if (-not $byNum.ContainsKey($vnum)) {
            if ($verses.Count -eq 0) { continue }
            $vnum   = $verses[0].num
            $noMark = $true
        }

        if (-not $noteLists.ContainsKey($vnum)) {
            $noteLists[$vnum] = New-Object System.Collections.Generic.List[object]
        }
        $noteLists[$vnum].Add([PSCustomObject]@{
            Label      = $label
            Word       = $word
            Paragraphs = $paras
            Xref       = $xref
            NoMark     = $noMark
        })
    }

    foreach ($v in $verses) {
        if ($noteLists.ContainsKey($v.num)) {
            $v.notes = $noteLists[$v.num].ToArray()
            Set-BibleVerseMarks -Verse $v
        }
    }

    $chapterObj = [PSCustomObject]@{
        Verses    = $verses.ToArray()
        Copyright = $copyright
    }
    $script:BibleEpubCache[$id] = $chapterObj
    return $chapterObj
}

function Invoke-BibleEpub {
    # EPUB counterpart of Invoke-LsmApi. Understands "Book C", "Book C:V" and
    # "Book C:V-V"; anything fancier gets an explanatory message back.
    param([Parameter(Mandatory)][string]$Reference)

    $path   = Get-BibleEpubPath
    $layout = Get-BibleLayout
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host ""
        Write-BibleNote -Layout $layout -Text "EPUB not found: $path" -Color 'Warn'
        Write-BibleNote -Layout $layout -Text 'Point at it again with  Set-BibleEpub "C:\path\HolyBible.epub"  (or Set-BibleEpub "" to use the API).'
        return $null
    }

    $say = {
        param($Msg)
        [PSCustomObject]@{ verses = @(); copyright = $null; message = $Msg }
    }

    $ref = Expand-BibleReference $Reference
    $dash = [string][char]0x2013
    if ($ref -match '[;,]' -or $ref -notmatch"^(?<book>.+?)\s+(?<ch>\d+)(?:\s*:\s*(?<v1>\d+)(?:\s*[-$dash]\s*(?<v2>\d+))?)?$") {
        return (& $say "EPUB mode reads 'Book Chapter', 'Book Chapter:Verse' or 'Book Chapter:Verse-Verse' - e.g. John 3:16-18.")
    }
    $bookName = $matches['book'].Trim()
    $ch = [int]$matches['ch']
    $v1 = if ($matches['v1']) { [int]$matches['v1'] } else { 0 }
    $v2 = if ($matches['v2']) { [int]$matches['v2'] } else { $v1 }

    $book = Get-BibleBookNumber -Name $bookName
    if (-not $book) { return (& $say "Unknown book '$bookName'.") }

    try {
        $index = Get-BibleEpubIndex -Path $path
        # Single-chapter books are usually cited by verse alone: "Jude 5".
        if (-not $v1 -and $ch -gt 1 -and -not $index.Chapters.ContainsKey("$book|$ch") -and
            $index.Chapters.ContainsKey("$book|1") -and -not $index.Chapters.ContainsKey("$book|2")) {
            $v1 = $ch; $v2 = $ch; $ch = 1
        }
        $chapter = Read-BibleEpubChapter -Path $path -Book $book -Chapter $ch
    } catch {
        Write-Host ""
        Write-BibleNote -Layout $layout -Text "Could not read the EPUB: $($_.Exception.Message)" -Color 'Danger'
        return $null
    }
    if (-not $chapter) { return (& $say "$bookName has no chapter $ch.") }

    $verses = @($chapter.Verses)
    if ($v1) {
        if ($v2 -lt $v1) { $t = $v1; $v1 = $v2; $v2 = $t }
        $verses = @($verses | Where-Object { $_.num -ge $v1 -and $_.num -le $v2 })
        if ($verses.Count -eq 0) { return (& $say "$bookName $ch has no verse $v1.") }
    }

    return [PSCustomObject]@{
        verses    = $verses
        copyright = $chapter.Copyright
        message   = $null
    }
}

function Set-BibleEpub {
    # Set-BibleEpub "C:\Users\me\Downloads\HolyBible.epub"   read from the EPUB
    # Set-BibleEpub ""                                         back to the API
    # Writes the "epub" key into .lsm-verse.json, leaving appid/token alone.
    param([string]$Path = "")

    $layout     = Get-BibleLayout
    $configPath = Get-BibleConfigPath

    $config = [ordered]@{}
    if (Test-Path $configPath) {
        try {
            $existing = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($existing) {
                foreach ($p in $existing.PSObject.Properties) { $config[$p.Name] = $p.Value }
            }
        } catch {
            Write-Host ""
            Write-BibleNote -Layout $layout -Text "Could not read $configPath - is it valid JSON? Left it untouched." -Color 'Danger'
            return
        }
    }

    if ($Path) {
        $Path = $Path.Trim('"', "'", ' ')
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Host ""
            Write-BibleNote -Layout $layout -Text "No file at $Path" -Color 'Warn'
            return
        }
        $full = (Resolve-Path -LiteralPath $Path).ProviderPath
        try {
            $count = (Get-BibleEpubIndex -Path $full).Chapters.Count
        } catch {
            $count = 0
        }
        if ($count -eq 0) {
            Write-Host ""
            Write-BibleNote -Layout $layout -Text "$full doesn't look like the Recovery Version EPUB (no chapter files found)." -Color 'Warn'
            return
        }
        $config['epub'] = $full
    } else {
        $config['epub'] = ""
    }

    $config | ConvertTo-Json | Set-Content -Path $configPath -Encoding utf8
    $script:BibleEpubIndex = $null
    $script:BibleEpubCache = @{}

    Write-Host ""
    if ($Path) {
        Write-BibleStyled ($layout.Pad + "reading from EPUB  ($count chapters)") -Color 'Accent'
        Write-BibleNote -Layout $layout -Text $config['epub']
    } else {
        Write-BibleStyled ($layout.Pad + "EPUB cleared - using api.lsm.org") -Color 'Accent'
    }
    Write-Host ""
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

$script:BibleSuperscripts = @{
    '0' = 0x2070; '1' = 0x00B9; '2' = 0x00B2; '3' = 0x00B3; '4' = 0x2074
    '5' = 0x2075; '6' = 0x2076; '7' = 0x2077; '8' = 0x2078; '9' = 0x2079
    'a' = 0x1D43; 'b' = 0x1D47; 'c' = 0x1D9C; 'd' = 0x1D48; 'e' = 0x1D49
    'f' = 0x1DA0; 'g' = 0x1D4D; 'h' = 0x02B0; 'i' = 0x2071; 'j' = 0x02B2
    'k' = 0x1D4F; 'l' = 0x02E1; 'm' = 0x1D50; 'n' = 0x207F; 'o' = 0x1D52
    'p' = 0x1D56; 'r' = 0x02B3; 's' = 0x02E2; 't' = 0x1D57; 'u' = 0x1D58
    'v' = 0x1D5B; 'w' = 0x02B7; 'x' = 0x02E3; 'y' = 0x02B8; 'z' = 0x1DBB
}

function Get-BibleSuperscript {
    # "1a" -> superscript one + superscript a, for footnote markers. Built
    # from code points so the file stays ASCII. Unicode has no superscript q,
    # so a label with one (or anything unmapped) falls back to "^1q", as does
    # a terminal without ANSI support.
    param([string]$Label)

    if (-not $Label) { return "" }
    if (-not (Test-BibleAnsi)) { return "^$Label" }
    $out = ""
    foreach ($c in $Label.ToCharArray()) {
        $cp = $script:BibleSuperscripts["$c"]
        if ($c -eq '*') { $out += '*'; continue }
        if (-not $cp)   { return "^$Label" }
        $out += [string][char]$cp
    }
    return $out
}

function Get-BibleMarkedTokens {
    # Split-BibleEmphasis tokens, each with the superscript for any footnote
    # marker that follows it. $Marks maps token index -> label.
    param([string]$Text, [hashtable]$Marks)

    $tokens = @(Split-BibleEmphasis -Text $Text)
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $m = ""
        if ($Marks -and $Marks.ContainsKey($i)) { $m = Get-BibleSuperscript $Marks[$i] }
        $tokens[$i] | Add-Member -NotePropertyName Mark -NotePropertyValue $m -Force
    }
    return @($tokens)
}

function Get-BibleVerseDisplayText {
    # The verse as it will appear on screen (no brackets, with markers) -
    # what to measure when working out how many lines a verse will take.
    param($Verse)

    $parts = @(Get-BibleMarkedTokens -Text $Verse.text -Marks $Verse.marks | ForEach-Object { $_.Text + $_.Mark })
    return ($parts -join " ")
}

function Write-BibleText {
    # Word-wraps on VISIBLE width (styling is applied at print time, never
    # baked into the string - ANSI codes would otherwise be counted as
    # characters and wreck the wrapping).
    param(
        [string]$Text,
        [string]$Prefix       = "",
        [string]$PrefixColor  = "AccentDim",
        [int]   $Width,
        [hashtable]$Marks
    )

    if ($Width -le 0) {
        try { $Width = $Host.UI.RawUI.WindowSize.Width } catch { $Width = 80 }
    }

    $ansi      = Test-BibleAnsi
    $esc       = $script:BibleEsc
    $bodyCode  = Get-BibleAnsiCode 'Body'
    $reset     = Get-BibleReset
    # Supplied words get italics AND a cooler tint, so they read as an aside
    # even where the terminal ignores italics.
    $italicOn  = if ($ansi) { "$esc[3m" + (Get-BibleAnsiCode 'Emph') } else { "" }
    $italicOff = if ($ansi) { "$esc[23m" + $bodyCode } else { "" }
    # Footnote markers: upright periwinkle, then back to whatever was on.
    $markOn    = if ($ansi) { "$esc[23m" + (Get-BibleAnsiCode 'Accent') } else { "" }

    $indent = " " * $Prefix.Length
    $max    = [Math]::Max(10, $Width - $Prefix.Length - 1)
    $tokens = Get-BibleMarkedTokens -Text $Text -Marks $Marks

    $line   = @()   # tokens on the current line
    $len    = 0
    $first  = $true

    $flush = {
        if ($first) {
            if ($Prefix) { Write-BibleStyled $Prefix -Color $PrefixColor -NoNewline }
        } else {
            Write-Host $indent -NoNewline
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
            if ($line[$j].Mark) {
                # Marker hugs the word, inside any trailing punctuation:
                # "teacher," -> "teacher" + marker + ",".
                $word = $line[$j].Text
                $tail = ""
                if ($word -match '^(.*?[\p{L}\p{N}])([^\p{L}\p{N}]+)$') { $word = $matches[1]; $tail = $matches[2] }
                $sb += $word + $markOn + $line[$j].Mark
                if ($ansi) { $sb += $(if ($open) { $italicOn } else { $bodyCode }) }
                $sb += $tail
            } else {
                $sb += $line[$j].Text
            }
        }
        if ($open) { $sb += $italicOff }   # never leave italics on at line end
        Write-Host ($bodyCode + $sb + $reset)
    }

    foreach ($t in $tokens) {
        $w   = $t.Text.Length + $t.Mark.Length
        $add = if ($len -eq 0) { $w } else { $w + 1 }
        if ($len -gt 0 -and ($len + $add) -gt $max) {
            & $flush
            $first = $false
            $line  = @()
            $len   = 0
            $add   = $w
        }
        $line += $t
        $len  += $add
    }
    if ($line.Count -gt 0) { & $flush }
    elseif ($first -and $Prefix) { Write-BibleStyled $Prefix -Color $PrefixColor }
}

function Write-BibleVerseLine {
    # Prints a verse with its number, wrapping long text with a hanging
    # indent so continuation lines line up under the verse text, not the number.
    param([string]$Number, [string]$Text, $Layout, [hashtable]$Marks)

    Write-BibleText -Text $Text `
                    -Prefix ($Layout.Pad + ("{0,3}  " -f $Number)) `
                    -PrefixColor 'AccentDim' `
                    -Width $Layout.Text `
                    -Marks $Marks
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
                34 { if (-not $buffer) { return @{ Action = "Submit"; Text = "N" } } } # PageDown
                33 { if (-not $buffer) { return @{ Action = "Submit"; Text = "P" } } } # PageUp
                39 { if (-not $buffer) { return @{ Action = "Submit"; Text = "N" } } } # Right arrow
                37 { if (-not $buffer) { return @{ Action = "Submit"; Text = "P" } } } # Left arrow
                32 {
                    # Space pages forward only when nothing typed yet;
                    # otherwise it is a real space inside "John 4".
                    if (-not $buffer) { return @{ Action = "Submit"; Text = "N" } }
                    $buffer += " "
                    Write-Host " " -NoNewline
                }
                9  { if (-not $buffer) { return @{ Action = "Submit"; Text = "S" } } } # Tab
                27 { return @{ Action = "Submit"; Text = "Q" } }                       # Esc
                13 { Write-Host ""; return @{ Action = "Submit"; Text = $buffer } } # Enter
                8  {
                    if ($buffer.Length -gt 0) {
                        $buffer = $buffer.Substring(0, $buffer.Length - 1)
                        Write-Host "`b `b" -NoNewline
                    } else {
                        # Nothing typed: Backspace means "go back to where I
                        # was reading before I jumped".
                        return @{ Action = "Back" }
                    }
                }
                default {
                    $ch = $keyInfo.Character
                    if (-not $ch -or [int]$ch -lt 32 -or [int]$ch -eq 127) { break }

                    # Nothing typed yet: N/P/S/F/Q fire instantly, no Enter.
                    # Book names also start with N/P/S (Numbers, Psalm,
                    # Samuel, Song of Songs), so "/" opens typing mode for
                    # those. No book starts with F. Any other letter just
                    # starts typing normally, so "John 4" still works with
                    # no prefix.
                    if (-not $buffer) {
                        if ("$ch" -eq "/") {
                            Write-BibleStyled "reference: " -Color 'Accent' -NoNewline
                            $buffer = " "   # non-empty marker: typing mode is on
                            break
                        }
                        if ("$ch" -eq "?") {
                            return @{ Action = "Define" }
                        }
                        if ("$ch" -match '^[NnPpSsFfQq]$') {
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
        Write-BibleUsageRow -Layout $layout -Command "verse list"        -Detail "browse your saved verses"
        Write-Host ""
        return
    }

    # "verse list" opens the saved-reference browser instead of a lookup.
    if ($Reference.Count -eq 1 -and $Reference[0] -in @("list", "saved", "ls")) {
        verselist
        return
    }

    $rawRef = ($Reference -join " ").Trim()
    $result = Get-BiblePassage -Reference $rawRef
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
        Write-BibleVerseLine -Number (Get-BibleVerseNumber -Verse $v -Fallback $i) -Text $v.text -Layout $layout -Marks $v.marks
        Write-Host ""
        # Clipboard keeps the original brackets - plain text, no escape codes.
        $clipLines += "$(Expand-BibleReference $v.ref) - $($v.text)"
        $i++
    }

    if ($clipLines.Count -gt 0) {
        $clipLines -join "`r`n`r`n" | Set-Clipboard
    }

    # Superscripts with nowhere to read them would be a tease - point at the
    # reader, which has the notes view.
    $annotated = @(@($result.verses) | Where-Object { $_.notes })
    if ($annotated.Count -gt 0 -and $annotated[0].ref -match '^(.+?):\d+$') {
        Write-BibleNote -Layout $layout -Text ("footnotes: bible {0}, then press F" -f $matches[1])
        Write-Host ""
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
    # Browse saved references. Every action is ONE keypress - no Enter.
    $pageSize = 9   # items labelled 1-9 so a single digit picks one
    $index = 0

    while ($true) {
        $layout = Get-BibleLayout
        $saved = @(Get-LsmSavedRefs)
        if ($saved.Count -eq 0) {
            Write-BibleHeader -Title "Saved verses" -Layout $layout
            Write-BibleNote -Layout $layout -Text "Nothing saved yet. Open a chapter with 'bible John 3' and press S." -Color 'Warn'
            Write-Host ""
            return
        }
        if ($index -ge $saved.Count) { $index = [Math]::Max(0, $saved.Count - $pageSize) }

        Clear-Host
        $plural = if ($saved.Count -eq 1) { "verse" } else { "verses" }
        Write-BibleHeader -Title "Saved verses" -Note "$($saved.Count) $plural" -Layout $layout

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

        # Down / Right arrow: next page.  Up / Left arrow: previous page.
        if (($key.Code -eq 40 -or $key.Code -eq 39) -and $hasNext) { $index += $pageSize; continue }
        if (($key.Code -eq 38 -or $key.Code -eq 37) -and $hasPrev) { $index -= $pageSize; continue }

        switch ($ch) {
            "N" { if ($hasNext) { $index += $pageSize } }
            "P" { if ($hasPrev) { $index = [Math]::Max(0, $index - $pageSize) } }
            "Q" { return }
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
    $layout = Get-BibleLayout
    $saved  = @(Get-LsmSavedRefs)
    if ($saved.Count -eq 0) {
        Write-BibleHeader -Title "Saved verses" -Layout $layout
        Write-BibleNote -Layout $layout -Text "Nothing saved yet." -Color 'Warn'
        Write-Host ""
        return
    }

    $plural = if ($saved.Count -eq 1) { "verse" } else { "verses" }
    Write-BibleHeader -Title "Saved verses" -Note "$($saved.Count) $plural" -Layout $layout

    $copyright = $null
    foreach ($v in $saved) {
        $result = Get-BiblePassage -Reference $v.ref

        $ref  = Expand-BibleReference $v.ref
        $line = $layout.Pad + (Get-BibleStyled -Text $ref -Color 'Gold' -Bold)
        $gap  = $layout.Content - $ref.Length - $v.savedAt.Length
        if ($gap -ge 3) {
            $line += (" " * $gap) + (Get-BibleStyled -Text $v.savedAt -Color 'Muted')
        }
        Write-Host $line

        if ($result -and $result.verses -and $result.verses.Count -gt 0) {
            foreach ($verseObj in $result.verses) {
                Write-BibleText -Text $verseObj.text -Prefix ($layout.Pad + "  ") -Width $layout.Text -Marks $verseObj.marks
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


# ------------------------------------------------------------
# Footnotes (EPUB only)
# ------------------------------------------------------------

function Select-BiblePageVerse {
    # One keypress picks a verse: the candidates are labelled a, b, c... so
    # no typing (and no multi-digit verse numbers) is needed. Returns the
    # chosen index into $Verses, or -1 if cancelled.
    param($Verses, [int[]]$Indices, $Layout, [string]$Action = "save")

    $letters = [char[]]"abcdefghijklmnopqrstuvwxyz"
    $Indices = @($Indices | Select-Object -First $letters.Count)

    Write-Host ""
    for ($li = 0; $li -lt $Indices.Count; $li++) {
        Write-Host ($Layout.Pad +
                    (Get-BibleStyled -Text ("{0}  " -f $letters[$li]) -Color 'Accent' -Bold) +
                    (Get-BibleStyled -Text (Expand-BibleReference $Verses[$Indices[$li]].ref) -Color 'Body'))
    }
    Write-Host ""
    Write-BibleStyled ($Layout.Pad + "press a letter to $Action, any other key cancels") -Color 'Muted'
    Write-BiblePrompt -Layout $Layout
    $pk = "$((Read-BibleKey).Char)".ToLower()
    Write-Host ""

    if ($pk.Length -ne 1) { return -1 }
    $li = [Array]::IndexOf($letters, [char]$pk)
    if ($li -ge 0 -and $li -lt $Indices.Count) { return $Indices[$li] }
    return -1
}

function Show-BiblePagedLines {
    # A small pager for pre-styled lines. $Build is called with the current
    # layout on every draw and returns the lines, so a resize re-wraps them.
    # N / Space / PgDn / Right page forward and P / PgUp / Left page back;
    # Down / Up scroll a line. Anything else returns.
    param([string]$Title, [string]$Note, [scriptblock]$Build, [string]$Copyright)

    $top = 0
    while ($true) {
        Clear-Host
        $layout = Get-BibleLayout
        $lines  = @(& $Build $layout)

        try   { $termHeight = $Host.UI.RawUI.WindowSize.Height }
        catch { $termHeight = 25 }

        # Same chrome budget as the chapter reader: 4 lines of header, then
        # rule + status + copyright + blank + prompt.
        $probeStatus = "lines {0}{1}{0} of {0}" -f $lines.Count, (Get-BibleGlyph 'Dash')
        $probeHints  = @(, @("N", "next"), @("P", "prev"), @("Q", "back"))
        $chrome = 7 + @(Get-BibleStatusLines -Layout $layout -Status $probeStatus -Hints $probeHints).Count
        if ($Copyright) {
            $chrome += @(Get-BibleWrappedLines -Text $Copyright -PrefixLength $layout.Margin -Width $layout.Text).Count
        }
        $avail = [Math]::Max(3, $termHeight - $chrome)

        if ($top -ge $lines.Count) { $top = [Math]::Max(0, $lines.Count - $avail) }
        $end = [Math]::Min($top + $avail, $lines.Count) - 1

        Write-BibleHeader -Title $Title -Note $Note -Layout $layout
        for ($i = $top; $i -le $end; $i++) { Write-Host $lines[$i] }
        Write-BibleRule -Layout $layout

        $hasNext = ($end + 1) -lt $lines.Count
        $hasPrev = $top -gt 0
        $hints = @()
        if ($hasNext) { $hints += , @("N", "next") }
        if ($hasPrev) { $hints += , @("P", "prev") }
        $hints += , @("Q", "back")
        $status = ""
        if ($hasNext -or $hasPrev) {
            $status = "lines {0}{1}{2} of {3}" -f ($top + 1), (Get-BibleGlyph 'Dash'), ($end + 1), $lines.Count
        }
        Write-BibleStatusBar -Layout $layout -Status $status -Hints $hints
        if ($Copyright) { Write-BibleNote -Layout $layout -Text $Copyright }
        Write-Host ""
        Write-BiblePrompt -Layout $layout

        $key = Read-BibleKey
        $ch  = "$($key.Char)".ToUpper()
        # Everything fits on one screen: any key at all goes back.
        if (-not $hasNext -and -not $hasPrev) { return }
        if ($ch -eq 'N' -or $key.Code -eq 32 -or $key.Code -eq 34 -or $key.Code -eq 39) {
            if ($hasNext) { $top = $end + 1 }
        } elseif ($key.Code -eq 40) {
            if ($hasNext) { $top++ }
        } elseif ($ch -eq 'P' -or $key.Code -eq 33 -or $key.Code -eq 37) {
            $top = [Math]::Max(0, $top - $avail)
        } elseif ($key.Code -eq 38) {
            if ($hasPrev) { $top-- }
        } else {
            return
        }
    }
}

function Get-BibleVerseNoteLines {
    # The notes view for one verse, as styled lines wrapped to $Layout:
    # footnotes first (label, word, paragraphs), then cross-references.
    param($Verse, $Layout)

    $out = New-Object System.Collections.Generic.List[string]
    $notes = @($Verse.notes)

    # "1a" is footnote 1 and cross-reference a on the same word.
    $footnotes = @($notes | Where-Object { $_.Paragraphs.Count -gt 0 })
    $xrefs     = @($notes | Where-Object { $_.Xref })

    foreach ($n in $footnotes) {
        $label  = $n.Label -replace '[a-z]', ''
        if (-not $label) { $label = $n.Label }
        $prefix = $Layout.Pad + ("{0,3}  " -f $label)
        $indent = " " * $prefix.Length
        $word   = if ($n.Word) { $n.Word } else { "" }
        $out.Add((Get-BibleStyled -Text $prefix -Color 'GoldDim') + (Get-BibleStyled -Text $word -Color 'Accent' -Bold))
        $firstPara = $true
        foreach ($p in $n.Paragraphs) {
            if (-not $firstPara) { $out.Add("") }
            $firstPara = $false
            foreach ($l in @(Get-BibleWrappedLines -Text $p -PrefixLength $prefix.Length -Width $Layout.Text)) {
                $out.Add($indent + (Get-BibleStyled -Text $l -Color 'Body'))
            }
        }
        $out.Add("")
    }

    if ($xrefs.Count -gt 0) {
        $out.Add($Layout.Pad + (Get-BibleStyled -Text "cross-references" -Color 'Gold' -Bold))
        # Line the references up in a column, unless one long word would
        # push them all off to the right.
        $col = [Math]::Min(16, (@($xrefs | ForEach-Object { "$($_.Word)".Length }) | Measure-Object -Maximum).Maximum)
        foreach ($n in $xrefs) {
            $label  = $n.Label -replace '[\d\*]', ''
            if (-not $label) { $label = $n.Label }
            $prefix = $Layout.Pad + ("{0,3}  " -f $label)
            $indent = " " * $prefix.Length
            $word   = if ($n.Word) { $n.Word.PadRight($col) } else { "".PadRight($col) }
            $room   = $Layout.Text - $prefix.Length - 1

            $head = (Get-BibleStyled -Text $prefix -Color 'GoldDim') + (Get-BibleStyled -Text $word -Color 'Accent')
            if (($word.Length + 2 + $n.Xref.Length) -le $room) {
                $out.Add($head + "  " + (Get-BibleStyled -Text $n.Xref -Color 'Muted'))
            } else {
                $out.Add($head)
                foreach ($l in @(Get-BibleWrappedLines -Text $n.Xref -PrefixLength $prefix.Length -Width $Layout.Text)) {
                    $out.Add($indent + (Get-BibleStyled -Text $l -Color 'Muted'))
                }
            }
        }
        $out.Add("")
    }

    # No trailing blank above the closing rule.
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq "") { $out.RemoveAt($out.Count - 1) }
    return $out.ToArray()
}

function Show-BibleVerseNotes {
    param($Verse, [string]$Copyright)

    # The pager calls $build from inside itself, where $notesVerse is still
    # in scope (PowerShell scoping is dynamic).
    $notesVerse = $Verse
    $build = {
        param($Layout)
        Get-BibleVerseNoteLines -Verse $notesVerse -Layout $Layout
    }
    Show-BiblePagedLines -Title (Expand-BibleReference $Verse.ref) -Note "notes" -Copyright $Copyright -Build $build
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
    if (-not $chapterRef -or $chapterRef -notmatch '\d') {
        Write-BibleHeader -Title "bible" -Note "usage" -Layout $layout
        Write-BibleUsageRow -Layout $layout -Command "bible <book> <chapter>" -Detail "read a chapter   e.g. bible John 3" -Column 26
        Write-Host ""
        return
    }

    $result = Get-BiblePassage -Reference $chapterRef
    if (-not $result) { return }

    if (-not $result.verses -or $result.verses.Count -eq 0) {
        $msg = if ($result.message) { $result.message } else { "No verses returned for '$chapterRef'." }
        Write-Host ""
        Write-BibleNote -Layout $layout -Text $msg -Color 'Warn'
        Write-Host ""
        return
    }

    $verses = @($result.verses)

    $index = 0
    $pageHistory = New-Object System.Collections.Generic.List[int]

    # Where you were reading before each jump, so Backspace can return you to
    # the exact chapter AND scroll position - not just the top of it.
    $readingHistory = New-Object System.Collections.Generic.List[object]

    while ($true) {
        Clear-Host
        $layout = Get-BibleLayout   # re-read every draw so resizing is honoured

        try   { $termHeight = $Host.UI.RawUI.WindowSize.Height }
        catch { $termHeight = 25 }

        # Reserve the chrome before deciding how many verses fit: blank +
        # title + rule + blank above, and rule + status + copyright + blank +
        # prompt below. The status strip is measured, not guessed, because it
        # wraps onto extra lines in a narrow pane - measured with the widest
        # status text and the full hint set so a page can never overflow.
        $probeStatus = "verses {0}{1}{0} of {0}" -f $verses.Count, (Get-BibleGlyph 'Dash')
        $probeHints  = @(, @("N", "next"), @("P", "prev"), @("S", "save"), @("F", "notes"), @("?", "define"), @("Q", "quit"))
        $chrome = 7 + @(Get-BibleStatusLines -Layout $layout -Status $probeStatus -Hints $probeHints).Count
        if ($result.copyright) {
            $chrome += @(Get-BibleWrappedLines -Text $result.copyright -PrefixLength $layout.Margin -Width $layout.Text).Count
        }
        $availableLines = [Math]::Max(3, $termHeight - $chrome)

        Write-BibleHeader -Title (Expand-BibleReference $chapterRef) -Note "Recovery Version" -Layout $layout

        # Figure out how many verses fit, counting wrapped lines + a spacer
        # line per verse, so a page never overflows a small/narrow window.
        $prefixLen = $layout.Margin + 5
        $pageEnd   = $index
        $linesUsed = 0
        for ($i = $index; $i -lt $verses.Count; $i++) {
            $need = (Get-BibleWrappedLines -Text (Get-BibleVerseDisplayText $verses[$i]) -PrefixLength $prefixLen -Width $layout.Text).Count + 1
            if (($linesUsed + $need) -gt $availableLines -and $i -gt $index) { break }
            $linesUsed += $need
            $pageEnd = $i
        }

        for ($i = $index; $i -le $pageEnd; $i++) {
            Write-BibleVerseLine -Number (Get-BibleVerseNumber -Verse $verses[$i] -Fallback ($i + 1)) `
                                 -Text $verses[$i].text -Layout $layout -Marks $verses[$i].marks
            Write-Host ""
        }

        Write-BibleRule -Layout $layout

        $hasNext = ($pageEnd + 1) -lt $verses.Count
        $hasPrev = $index -gt 0
        # Verses on this page that have footnotes or cross-references (EPUB
        # only - the API carries none).
        $withNotes = @(for ($i = $index; $i -le $pageEnd; $i++) { if ($verses[$i].notes) { $i } })
        $hints = @()
        if ($hasNext) { $hints += , @("N", "next") }
        if ($hasPrev) { $hints += , @("P", "prev") }
        $hints += , @("S", "save")
        if ($withNotes.Count -gt 0) { $hints += , @("F", "notes") }
        $hints += , @("?", "define")
        $hints += , @("Q", "quit")

        $dash   = Get-BibleGlyph 'Dash'
        $status = "verses {0}{1}{2} of {3}" -f ($index + 1), $dash, ($pageEnd + 1), $verses.Count
        Write-BibleStatusBar -Layout $layout -Status $status -Hints $hints
        if ($result.copyright) {
            # api.lsm.org's terms require this to be visible wherever verse
            # text is - quiet, but never dimmed into the background.
            Write-BibleNote -Layout $layout -Text $result.copyright
        }
        Write-Host ""

        Write-BiblePrompt -Layout $layout
        $input = Read-BibleInput

        switch ($input.Action) {
            "ScrollDown" {
                if ($index -lt ($verses.Count - 1)) { $index++ }
            }
            "ScrollUp" {
                if ($index -gt 0) { $index-- }
            }
            "Back" {
                if ($readingHistory.Count -gt 0) {
                    $prev = $readingHistory[$readingHistory.Count - 1]
                    $readingHistory.RemoveAt($readingHistory.Count - 1)
                    $chapterRef = $prev.Ref
                    $result     = $prev.Result
                    $verses     = @($prev.Result.verses)
                    $index      = $prev.Index
                    $pageHistory.Clear()
                    foreach ($h in @($prev.PageHistory)) { $pageHistory.Add($h) }
                }
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
                switch ($trimmed.ToUpper()) {
                    "N" {
                        if ($hasNext) {
                            $pageHistory.Add($index)
                            $index = $pageEnd + 1
                        }
                    }
                    "P" {
                        if ($pageHistory.Count -gt 0) {
                            $index = $pageHistory[$pageHistory.Count - 1]
                            $pageHistory.RemoveAt($pageHistory.Count - 1)
                        } elseif ($hasPrev) {
                            $index = 0
                        }
                    }
                    "S" {
                        $pick = Select-BiblePageVerse -Verses $verses -Indices @($index..$pageEnd) -Layout $layout -Action "save"
                        if ($pick -ge 0) {
                            Write-Host ""
                            Save-LsmVerse -Reference $verses[$pick].ref -Layout $layout
                            Start-Sleep -Milliseconds 750
                        }
                    }
                    "F" {
                        # Only the annotated verses get a letter; with just
                        # one on the page there is nothing to choose.
                        $pick = -1
                        if ($withNotes.Count -eq 1) {
                            $pick = $withNotes[0]
                        } elseif ($withNotes.Count -gt 1) {
                            $pick = Select-BiblePageVerse -Verses $verses -Indices $withNotes -Layout $layout -Action "read its notes"
                        }
                        if ($pick -ge 0) {
                            Show-BibleVerseNotes -Verse $verses[$pick] -Copyright $result.copyright
                        }
                    }
                    "Q" {
                        return
                    }
                    "" {
                        # empty input, just redraw
                    }
                    default {
                        # anything else is treated as a new "Book Chapter" reference to jump to
                        $newResult = Get-BiblePassage -Reference $trimmed
                        if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                            # Remember where we were so Backspace can return.
                            $readingHistory.Add([PSCustomObject]@{
                                Ref         = $chapterRef
                                Result      = $result
                                Index       = $index
                                PageHistory = @($pageHistory.ToArray())
                            })
                            $result     = $newResult
                            $verses     = @($newResult.verses)
                            $chapterRef = $trimmed
                            $index      = 0
                            $pageHistory.Clear()
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
