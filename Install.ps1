<#
.SYNOPSIS
    One-time setup for the Bible Verse Lookup Tool.

.DESCRIPTION
    1. Dot-sources this repo's BibleVerseTool.ps1 directly from where you cloned
       it, so the "verse", "bible", and "savedverses" commands are available in
       every new PowerShell window. No copy is made - "git pull" updates the
       live tool. Safe to re-run; it will not add the line twice.
    2. Writes that line to BOTH the Windows PowerShell 5.1 and PowerShell 7
       profiles, so it works whichever one you open.
    3. Creates your personal credentials file (%USERPROFILE%\.lsm-verse.json)
       from the example template if it does not already exist.

.NOTES
    If PowerShell refuses to run this ("running scripts is disabled"), start it
    with:
        powershell -ExecutionPolicy Bypass -File .\Install.ps1
    and enable local scripts for future sessions:
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

    This script does NOT fill in your API token for you. Open the credentials
    file afterwards and paste in your own appid/token from https://api.lsm.org.
    Put them in %USERPROFILE%\.lsm-verse.json - NOT in the tracked
    .lsm-verse.example.json (that one is committed to git).
#>

$here       = $PSScriptRoot
$toolSource = Join-Path $here "BibleVerseTool.ps1"

if (-not (Test-Path $toolSource)) {
    Write-Host "Cannot find BibleVerseTool.ps1 next to this installer ($toolSource)." -ForegroundColor Red
    Write-Host "Run Install.ps1 from inside the cloned repo folder." -ForegroundColor Yellow
    return
}

# Files cloned/downloaded can carry a Mark-of-the-Web that blocks them under
# RemoteSigned. Clear it so the profile can dot-source the tool.
try { Unblock-File -Path $toolSource -ErrorAction Stop } catch { }

# The line the profile will run. Absolute path to the tool in this repo, so it
# does not matter where the profile lives or which PowerShell edition loads it.
$dotSourceLine = ". `"$toolSource`""

# Figure out both profile locations (5.1 = WindowsPowerShell, 7 = PowerShell).
# Derive the Documents folder from the running host's own $PROFILE so OneDrive
# folder redirection is handled correctly.
$psDir = Split-Path $PROFILE -Parent
$docs  = Split-Path $psDir  -Parent
$targets = @(
    (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')
) | Select-Object -Unique

foreach ($profilePath in $targets) {
    $profileDir = Split-Path $profilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath | Out-Null
    }

    $profileText = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($profileText -and $profileText -match [regex]::Escape("BibleVerseTool.ps1")) {
        Write-Host "Profile already loads the tool - left untouched: $profilePath" -ForegroundColor Yellow
        continue
    }

    try {
        Add-Content -Path $profilePath -Value "`n# Bible Verse Lookup Tool`nClear-Host`n$dotSourceLine`n" -Encoding utf8 -ErrorAction Stop
    } catch {
        Write-Host "Could not write to $profilePath : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Add this line to it yourself:  $dotSourceLine" -ForegroundColor Yellow
        continue
    }

    # Verify the line actually landed (OneDrive sync or a lock can silently
    # eat the write - the original bug this installer had).
    $verifyText = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($verifyText -and $verifyText -match [regex]::Escape("BibleVerseTool.ps1")) {
        Write-Host "Added tool to profile: $profilePath" -ForegroundColor Green
    } else {
        Write-Host "Wrote to $profilePath but the line is not there afterwards - something (maybe OneDrive sync) blocked it." -ForegroundColor Red
        Write-Host "Open it yourself and add:  $dotSourceLine" -ForegroundColor Yellow
    }
}

# Personal credentials file, created from the example if missing.
$credPath = Join-Path $HOME ".lsm-verse.json"
if (-not (Test-Path $credPath)) {
    Copy-Item -Path (Join-Path $here ".lsm-verse.example.json") -Destination $credPath
    Write-Host "Created $credPath - open it and paste in your real appid/token." -ForegroundColor Yellow
} else {
    Write-Host "Credentials file already exists at $credPath - left untouched." -ForegroundColor Yellow
}

# The example file is tracked by git. If real credentials get typed into it by
# mistake instead of into $credPath, they are one "git push" away from being
# public - so say so loudly rather than letting it slide.
$examplePath = Join-Path $here ".lsm-verse.example.json"
try {
    $example = Get-Content $examplePath -Raw -ErrorAction Stop | ConvertFrom-Json
    if (($example.appid -and $example.appid -notlike "YOUR_*") -or
        ($example.token -and $example.token -notlike "YOUR_*")) {
        Write-Host ""
        Write-Host "WARNING: $examplePath appears to contain real credentials." -ForegroundColor Red
        Write-Host "That file is tracked by git - committing it would publish your token." -ForegroundColor Red
        Write-Host "Move them into $credPath and reset the example back to YOUR_APPID / YOUR_TOKEN." -ForegroundColor Yellow
    }
} catch {
    # Example file missing or unparseable - nothing to warn about.
}

Write-Host ""
Write-Host "Setup complete. Close and reopen PowerShell, then try:  verse John 3:16" -ForegroundColor Cyan
