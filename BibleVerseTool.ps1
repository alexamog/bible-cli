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

function Write-BibleText {
    # Word-wraps on VISIBLE width (styling is applied at print time, never
    # baked into the string - ANSI codes would otherwise be counted as
    # characters and wreck the wrapping).
    param(
        [string]$Text,
        [string]$Prefix       = "",
        [string]$PrefixColor  = "AccentDim",
        [int]   $Width
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

    $indent = " " * $Prefix.Length
    $max    = [Math]::Max(10, $Width - $Prefix.Length - 1)
    $tokens = Split-BibleEmphasis -Text $Text

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
            $sb += $line[$j].Text
        }
        if ($open) { $sb += $italicOff }   # never leave italics on at line end
        Write-Host ($bodyCode + $sb + $reset)
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
    elseif ($first -and $Prefix) { Write-BibleStyled $Prefix -Color $PrefixColor }
}

function Write-BibleVerseLine {
    # Prints a verse with its number, wrapping long text with a hanging
    # indent so continuation lines line up under the verse text, not the number.
    param([string]$Number, [string]$Text, $Layout)

    Write-BibleText -Text $Text `
                    -Prefix ($Layout.Pad + ("{0,3}  " -f $Number)) `
                    -PrefixColor 'AccentDim' `
                    -Width $Layout.Text
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

                    # Nothing typed yet: N/P/S/Q fire instantly, no Enter.
                    # Book names also start with N/P/S (Numbers, Psalm,
                    # Samuel, Song of Songs), so "/" opens typing mode for
                    # those. Any other letter just starts typing normally,
                    # so "John 4" still works with no prefix.
                    if (-not $buffer) {
                        if ("$ch" -eq "/") {
                            Write-BibleStyled "reference: " -Color 'Accent' -NoNewline
                            $buffer = " "   # non-empty marker: typing mode is on
                            break
                        }
                        if ("$ch" -eq "?") {
                            return @{ Action = "Define" }
                        }
                        if ("$ch" -match '^[NnPpSsQq]$') {
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

        if ($key.Code -eq 40 -and $hasNext) { $index += $pageSize; continue }   # Down arrow
        if ($key.Code -eq 38 -and $hasPrev) { $index -= $pageSize; continue }   # Up arrow

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
        $probeHints  = @(, @("N", "next"), @("P", "prev"), @("S", "save"), @("?", "define"), @("Q", "quit"))
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
            $need = (Get-BibleWrappedLines -Text $verses[$i].text -PrefixLength $prefixLen -Width $layout.Text).Count + 1
            if (($linesUsed + $need) -gt $availableLines -and $i -gt $index) { break }
            $linesUsed += $need
            $pageEnd = $i
        }

        for ($i = $index; $i -le $pageEnd; $i++) {
            Write-BibleVerseLine -Number (Get-BibleVerseNumber -Verse $verses[$i] -Fallback ($i + 1)) `
                                 -Text $verses[$i].text -Layout $layout
            Write-Host ""
        }

        Write-BibleRule -Layout $layout

        $hasNext = ($pageEnd + 1) -lt $verses.Count
        $hasPrev = $index -gt 0
        $hints = @()
        if ($hasNext) { $hints += , @("N", "next") }
        if ($hasPrev) { $hints += , @("P", "prev") }
        $hints += , @("S", "save")
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
                        # One keypress picks a verse: label the verses on this
                        # page a, b, c... so no typing (and no multi-digit
                        # verse numbers) is needed.
                        $letters = [char[]]"abcdefghijklmnopqrstuvwxyz"
                        Write-Host ""
                        for ($i = $index; $i -le $pageEnd; $i++) {
                            $li = $i - $index
                            if ($li -ge $letters.Count) { break }
                            Write-Host ($layout.Pad +
                                        (Get-BibleStyled -Text ("{0}  " -f $letters[$li]) -Color 'Accent' -Bold) +
                                        (Get-BibleStyled -Text (Expand-BibleReference $verses[$i].ref) -Color 'Body'))
                        }
                        Write-Host ""
                        Write-BibleStyled ($layout.Pad + "press a letter to save, any other key cancels") -Color 'Muted'
                        Write-BiblePrompt -Layout $layout
                        $pk = "$((Read-BibleKey).Char)".ToLower()
                        Write-Host ""
                        $li = [Array]::IndexOf($letters, [char]$pk)
                        if ($li -ge 0 -and ($index + $li) -le $pageEnd) {
                            Write-Host ""
                            Save-LsmVerse -Reference $verses[$index + $li].ref -Layout $layout
                            Start-Sleep -Milliseconds 750
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
                        $newResult = Invoke-LsmApi -Reference $trimmed
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
