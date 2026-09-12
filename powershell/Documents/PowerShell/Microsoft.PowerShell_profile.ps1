# PowerShell 7 profile — the Windows counterpart to zsh/.zshrc.
# Symlinked to $PROFILE by setup.ps1.

# --- Version managers (must come before the prompt) ---

# pyenv-win (Python)
$env:PYENV_ROOT = "$HOME\.pyenv\pyenv-win"
if (Test-Path $env:PYENV_ROOT) {
    $env:PYENV = $env:PYENV_ROOT
    $env:PATH = "$env:PYENV_ROOT\bin;$env:PYENV_ROOT\shims;$env:PATH"
}

# Go — installed directly (goenv is Unix-only), so only the workspace bin needs adding
if (-not $env:GOPATH) { $env:GOPATH = "$HOME\go" }
$env:PATH = "$env:PATH;$env:GOPATH\bin"

# nvm-windows (Node.js) manages its own PATH via the NVM_SYMLINK machine variable.

# LLVM
$llvm = "$env:ProgramFiles\LLVM\bin"
if (Test-Path $llvm) { $env:PATH = "$llvm;$env:PATH" }

# npm global bin
if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmPrefix = npm config get prefix 2>$null
    if ($npmPrefix -and (Test-Path $npmPrefix)) { $env:PATH = "$npmPrefix;$env:PATH" }
}

# Deduplicate PATH entries, preserving order
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

# --- Shell enhancements ---

# PSReadLine covers what zsh-autosuggestions and zsh-syntax-highlighting do on macOS
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle InlineView
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
}

# File-type glyphs in ls output (needs the Nerd Font)
if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }

# zoxide — smarter cd
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# --- Prompt ---
$ompTheme = "$HOME\.config\oh-my-posh\kevinsaji.omp.json"
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $ompTheme)) {
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}

# --- Completions ---
if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh completion -s powershell | Out-String | Invoke-Expression
}
