# PowerShell 7 profile.
#
# This is the real profile; $PROFILE itself is a one-line stub that dot-sources
# this file, written by setup.ps1. A stub rather than a symlink because writing
# a plain file into your own Documents needs no administrator rights.
#
# Toolchain PATH entries and JAVA_HOME live in the *user environment*, set once
# by setup.ps1, so that GUI apps and cmd.exe see them too. This file only adds
# what is specific to an interactive PowerShell session.

$Dotfiles = "$HOME\dotfiles"

# --- Toolchains ---

# Python: the py launcher (PEP 397) dispatches between installed interpreters.
# Bare `py` follows the PY_PYTHON user variable that setup.ps1 sets; `py -3.12`
# and friends still reach the older ones. Nothing to configure here.

# Go - installed from the official MSI, which puts go on PATH itself.
# Only the workspace bin needs adding.
if (-not $env:GOPATH) { $env:GOPATH = "$HOME\go" }
$env:PATH = "$env:PATH;$env:GOPATH\bin"

# Node - fnm switches versions by rewriting PATH, so it needs a shell hook.
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell power-shell | Out-String | Invoke-Expression
}

# npm global bin
if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmPrefix = npm config get prefix 2>$null
    if ($npmPrefix -and (Test-Path $npmPrefix)) { $env:PATH = "$npmPrefix;$env:PATH" }
}

# Deduplicate PATH entries, preserving order
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

# --- Java version switching ---
# Windows has no jenv or SDKMAN equivalent; the native idiom is several JDKs
# installed side by side with JAVA_HOME picking one. setup.ps1 points JAVA_HOME
# at Temurin 21; this switches the current shell to any other installed JDK.

function Get-JavaHomes {
    # Vendors disagree on layout: Temurin nests under "Eclipse Adoptium",
    # Microsoft under "Microsoft", Oracle under "Java" or straight into
    # Program Files. Scan all of them one level deep.
    @(
        (Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
        (Join-Path $env:ProgramFiles 'Java'),
        (Join-Path $env:ProgramFiles 'Microsoft'),
        $env:ProgramFiles
    ) | Where-Object { $_ -and (Test-Path $_) } |
        ForEach-Object { Get-ChildItem $_ -Directory -ErrorAction SilentlyContinue } |
        Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } |
        Sort-Object Name -Unique
}

function Use-Java {
    <#
      .SYNOPSIS
        Point JAVA_HOME at another installed JDK, for this shell only.
      .EXAMPLE
        Use-Java          # list what is installed
        Use-Java 17       # switch to the first JDK whose name matches 17
    #>
    param([string]$Version)

    $homes = Get-JavaHomes
    if (-not $homes) { Write-Warning 'No JDKs found under Program Files.'; return }

    if (-not $Version) {
        $homes | ForEach-Object {
            $marker = if ($_.FullName -eq $env:JAVA_HOME) { '*' } else { ' ' }
            "$marker $($_.Name)"
        }
        return
    }

    $match = $homes | Where-Object { $_.Name -match [regex]::Escape($Version) } | Select-Object -First 1
    if (-not $match) { Write-Warning "No JDK matching '$Version'. Run Use-Java with no argument to list."; return }

    # Drop any previous JDK bin from PATH before prepending the new one.
    $env:PATH = ($env:PATH -split ';' |
        Where-Object { $_ -and $_ -notmatch '\\(jdk|jre)[^\\]*\\bin$' }) -join ';'
    $env:JAVA_HOME = $match.FullName
    $env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
    Write-Host "JAVA_HOME -> $env:JAVA_HOME" -ForegroundColor DarkGray
}

# --- Shell enhancements ---

# PSReadLine covers what zsh-autosuggestions and zsh-syntax-highlighting do on macOS
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    # Prediction needs a real console and fails when output is redirected - a
    # script, CI, `pwsh -File`, anything piped. There is no reliable property to
    # test for this ($Host.UI.SupportsVirtualTerminal reports true even when
    # redirected), so attempt it and move on if the host refuses.
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete

    # Resizing a terminal while the prompt is wrapped leaves PSReadLine's idea of
    # where input starts out of sync with what is on screen, so the cursor lands
    # in the wrong place. This is PSReadLine issue #3637, still open, and no
    # option avoids it. F5 redraws the prompt in place to recover - unlike Ctrl+L
    # (ClearScreen) it does not wipe the scrollback.
    Set-PSReadLineKeyHandler -Key F5 -BriefDescription RedrawPrompt `
        -LongDescription 'Redraw the prompt after a terminal resize' -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
}

# File-type glyphs in ls output (needs the Nerd Font)
if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }

# zoxide - smarter cd
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# --- Prompt ---
# Starship - read straight from the repo, same config the zsh profile uses.
# No Nerd Font glyphs in it, so it renders correctly even before the font lands.
$env:STARSHIP_CONFIG = "$Dotfiles\starship\.config\starship.toml"
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# --- Completions ---
if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh completion -s powershell | Out-String | Invoke-Expression
}
