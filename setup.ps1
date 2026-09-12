#Requires -Version 5.1
<#
  Windows counterpart to setup.sh.

  Run from a NORMAL (non-elevated) PowerShell:
    irm https://raw.githubusercontent.com/kevinksaji/dotfiles/main/setup.ps1 | iex

  Do not run the whole script as Administrator: PowerShell 7 and Windows Terminal
  ship as MSIX packages, and MSIX per-user installs fail from an elevated context.

  Creating symlinks does need privilege, so if Developer Mode is off the script
  elevates just that one step via a UAC prompt. Turning on Developer Mode
  (Settings > System > For developers) skips the prompt entirely.
#>
param(
    # Internal: re-runs only the linking step, elevated. Not meant to be passed by hand.
    [switch]$LinkOnly
)

$ErrorActionPreference = 'Stop'

$Dotfiles = Join-Path $HOME 'dotfiles'
$Repo     = 'https://github.com/kevinksaji/dotfiles.git'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string]$Message) Write-Host "    ! $Message" -ForegroundColor Yellow }

# Reload PATH from the registry so tools installed earlier in this run are callable now.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:PATH = (($machine, $user) -join ';')
}

function Test-Command { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Symlinking needs Developer Mode or elevation; probe once rather than guessing.
function Test-SymlinkCapable {
    $ok     = $false
    $probe  = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-linkprobe-' + [guid]::NewGuid())
    $target = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-linktarget-' + [guid]::NewGuid())
    try {
        New-Item -ItemType File -Path $target | Out-Null
        New-Item -ItemType SymbolicLink -Path $probe -Target $target -ErrorAction Stop | Out-Null
        $ok = $true
    } catch { }
    Remove-Item $probe, $target -Force -ErrorAction SilentlyContinue
    $ok
}

# ============================================================ install phase
if (-not $LinkOnly) {

    Write-Step 'Checking prerequisites'
    if (-not (Test-Command winget)) {
        throw "winget not found. Install 'App Installer' from the Microsoft Store, then re-run this script."
    }
    Write-Note "winget $(winget --version)"
    if (Test-Elevated) {
        Write-Warn 'Running elevated. PowerShell 7 and Windows Terminal are MSIX packages and'
        Write-Warn 'may fail to install here - prefer a normal PowerShell window for this script.'
    }

    Write-Step 'Installing git (if missing)'
    if (-not (Test-Command git)) {
        winget install --id Git.Git --exact --silent --accept-package-agreements --accept-source-agreements
        Update-SessionPath
    }

    Write-Step 'Cloning or updating dotfiles repo'
    if (-not (Test-Path (Join-Path $Dotfiles '.git'))) {
        if (Test-Path $Dotfiles) { Remove-Item $Dotfiles -Recurse -Force }
        git clone $Repo $Dotfiles
    } else {
        git -C $Dotfiles pull
    }

    Write-Step 'Installing packages from Wingetfile'
    foreach ($line in Get-Content (Join-Path $Dotfiles 'Wingetfile')) {
        $id = ($line -split '#')[0].Trim()
        if (-not $id) { continue }
        Write-Note "installing $id"
        winget install --id $id --exact --silent --source winget --accept-package-agreements --accept-source-agreements | Out-Null
        # -1978335189 is winget's "already installed, nothing to do" code.
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
            Write-Warn "winget exited $LASTEXITCODE for $id - continuing"
        }
    }
    Update-SessionPath

    Write-Step 'Installing FiraCode Nerd Font (per-user)'
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if (Get-ChildItem $fontDir -Filter 'FiraCodeNerdFont*' -ErrorAction SilentlyContinue) {
        Write-Note 'already installed'
    } else {
        $zip     = Join-Path ([IO.Path]::GetTempPath()) 'FiraCode.zip'
        $extract = Join-Path ([IO.Path]::GetTempPath()) 'FiraCodeNF'
        Invoke-WebRequest -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip' -OutFile $zip
        Expand-Archive $zip -DestinationPath $extract -Force
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
        $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
        foreach ($font in Get-ChildItem $extract -Filter '*.ttf' -Recurse) {
            $dest = Join-Path $fontDir $font.Name
            Copy-Item $font.FullName $dest -Force
            Set-ItemProperty -Path $fontKey -Name "$($font.BaseName) (TrueType)" -Value $dest
        }
        Remove-Item $zip -Force
        Remove-Item $extract -Recurse -Force
        Write-Note 'font installed'
    }

    Write-Step 'Installing PowerShell modules'
    foreach ($module in @('PSReadLine', 'Terminal-Icons')) {
        if (Get-Module -ListAvailable $module) {
            Write-Note "$module already present"
        } else {
            Install-Module $module -Scope CurrentUser -Force -AllowClobber -AcceptLicense
            Write-Note "installed $module"
        }
    }

    Write-Step 'Installing Python via pyenv-win'
    $pyenvRoot = Join-Path $HOME '.pyenv'
    if (-not (Test-Path $pyenvRoot)) { git clone https://github.com/pyenv-win/pyenv-win.git $pyenvRoot }
    $pyenvWin = Join-Path $pyenvRoot 'pyenv-win'
    foreach ($name in @('PYENV', 'PYENV_ROOT', 'PYENV_HOME')) {
        [Environment]::SetEnvironmentVariable($name, $pyenvWin, 'User')
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    foreach ($dir in @((Join-Path $pyenvWin 'bin'), (Join-Path $pyenvWin 'shims'))) {
        if ($userPath -notlike "*$dir*") { $userPath = "$dir;$userPath" }
    }
    [Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
    Update-SessionPath

    $pyenvExe = Join-Path $pyenvWin 'bin\pyenv.bat'
    $pythonLatest = & $pyenvExe install --list |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^3\.\d+\.\d+$' } |
        Sort-Object { [version]$_ } |
        Select-Object -Last 1
    Write-Note "python $pythonLatest"
    & $pyenvExe install $pythonLatest --skip-existing
    & $pyenvExe global $pythonLatest
    & $pyenvExe rehash

    Write-Step 'Installing Node.js LTS via nvm-windows'
    if (Test-Command nvm) {
        nvm install lts
        nvm use lts
    } else {
        Write-Warn 'nvm not on PATH yet - open a new terminal and run: nvm install lts'
    }

    Write-Step 'Verifying Go and Java'
    if (Test-Command go)   { Write-Note (go version) }            else { Write-Warn 'go not on PATH yet - recheck after reopening the terminal' }
    if (Test-Command java) { Write-Note (java -version 2>&1)[0] } else { Write-Warn 'java not on PATH yet - recheck after reopening the terminal' }

    Write-Step 'Git identity'
    $gitName  = Read-Host '    Name '
    $gitEmail = Read-Host '    Email'
    $gitLocal = Join-Path $HOME '.gitconfig.local'
    git config -f $gitLocal user.name  $gitName
    git config -f $gitLocal user.email $gitEmail
}

# ============================================================= linking phase
Write-Step 'Linking dotfiles'

$canSymlink = Test-SymlinkCapable
$linkedElsewhere = $false

# Elevate just this step when symlinks are unavailable. Elevating the whole
# script would break the MSIX installs above, so the relaunch is scoped to -LinkOnly.
if (-not $canSymlink -and -not $LinkOnly) {
    Write-Note 'Symlinks need Developer Mode or Administrator; requesting elevation for this step.'
    $self  = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $Dotfiles 'setup.ps1' }
    $psExe = if (Test-Command pwsh) { 'pwsh' } else { 'powershell' }
    try {
        $proc = Start-Process $psExe -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`"", '-LinkOnly')
        if ($proc.ExitCode -eq 0) {
            Write-Note 'linked via elevated helper'
            $linkedElsewhere = $true
        } else {
            Write-Warn "elevated helper exited $($proc.ExitCode) - falling back to copying"
        }
    } catch {
        Write-Warn 'Elevation declined - falling back to copying.'
        Write-Warn 'Configs will work, but edits will not flow back to the repo.'
    }
}

if (-not $linkedElsewhere) {

# Explicit source -> target table. GNU Stow has no Windows equivalent, and the
# targets do not all mirror $HOME anyway (Documents can be redirected to OneDrive).
$documents = [Environment]::GetFolderPath('MyDocuments')
$links = @(
    @{ Source = 'powershell\Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
       Target = (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1') }
    @{ Source = 'ohmyposh\.config\oh-my-posh\kevinsaji.omp.json'
       Target = (Join-Path $HOME '.config\oh-my-posh\kevinsaji.omp.json') }
    @{ Source = 'git\.gitconfig'          ; Target = (Join-Path $HOME '.gitconfig') }
    @{ Source = 'git\.gitignore_global'   ; Target = (Join-Path $HOME '.gitignore_global') }
    @{ Source = 'ssh-windows\.ssh\config' ; Target = (Join-Path $HOME '.ssh\config') }
    @{ Source = 'claude\.claude\settings.json'
       Target = (Join-Path $HOME '.claude\settings.json') }
)

foreach ($link in $links) {
    $source = Join-Path $Dotfiles $link.Source
    if (-not (Test-Path $source)) { Write-Warn "missing in repo: $($link.Source)"; continue }
    $dest = $link.Target

    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null

    if (Test-Path $dest) {
        $existing = Get-Item $dest -Force
        if ($existing.LinkType -eq 'SymbolicLink' -and @($existing.Target) -contains $source) {
            Write-Note "ok: $($link.Source)"
            continue
        }
        # In copy mode the target is a plain file, so an unchanged copy is already
        # correct - without this check a re-run would "back up" its own last copy.
        if (-not $existing.LinkType -and
            (Get-FileHash $dest).Hash -eq (Get-FileHash $source).Hash) {
            Write-Note "ok: $($link.Source)"
            continue
        }
        # Back up whatever is there - the macOS script leans on `stow --adopt` for this.
        # Never clobber an older backup: that is the only copy of the original.
        $backup = "$dest.dotfiles-backup"
        if (Test-Path $backup) {
            $backup = "$dest.$(Get-Date -Format 'yyyyMMdd-HHmmss').dotfiles-backup"
        }
        Move-Item $dest $backup -Force
        Write-Note "backed up existing file to $backup"
    }

    if ($canSymlink) {
        New-Item -ItemType SymbolicLink -Path $dest -Target $source | Out-Null
        Write-Note "linked: $($link.Source)"
    } else {
        Copy-Item $source $dest -Force
        Write-Note "copied: $($link.Source)"
    }
}

}

# The elevated helper only does the linking; everything below is per-user config.
if ($LinkOnly) { exit 0 }

# ----------------------------------------------- windows terminal settings
Write-Step 'Configuring Windows Terminal'
$wtCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
)
$wtSettings = $wtCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $wtSettings) {
    Write-Warn 'Windows Terminal settings.json not found - launch Windows Terminal once, then re-run this script.'
} else {
    # Merge rather than overwrite: settings.json also holds machine-generated
    # profile GUIDs that must not be clobbered.
    Copy-Item $wtSettings "$wtSettings.dotfiles-backup" -Force
    $partial = Get-Content (Join-Path $Dotfiles 'windows-terminal\settings.partial.json') -Raw | ConvertFrom-Json
    $current = Get-Content $wtSettings -Raw | ConvertFrom-Json

    if (-not $current.PSObject.Properties['profiles']) {
        $current | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{})
    }
    if (-not $current.profiles.PSObject.Properties['defaults']) {
        $current.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
    }
    foreach ($property in $partial.profiles.defaults.PSObject.Properties) {
        if ($current.profiles.defaults.PSObject.Properties[$property.Name]) {
            $current.profiles.defaults.PSObject.Properties.Remove($property.Name)
        }
        $current.profiles.defaults | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
    }

    $schemes = @()
    if ($current.PSObject.Properties['schemes']) {
        $schemes = @($current.schemes | Where-Object { $_.name -ne 'kevinsaji' })
        $current.PSObject.Properties.Remove('schemes')
    }
    $schemes += $partial.schemes
    $current | Add-Member -NotePropertyName schemes -NotePropertyValue $schemes

    # Make PowerShell 7 the default profile when Windows Terminal knows about it.
    if ($current.profiles.PSObject.Properties['list']) {
        $pwshProfile = $current.profiles.list |
            Where-Object { $_.PSObject.Properties['name'] -and $_.name -eq 'PowerShell' } |
            Select-Object -First 1
        if ($pwshProfile) { $current.defaultProfile = $pwshProfile.guid }
    }

    $current | ConvertTo-Json -Depth 32 | Set-Content $wtSettings -Encoding utf8
    Write-Note "updated $wtSettings (backup written alongside it)"
}

Write-Host ''
Write-Host 'Done. Close this window and open a new Windows Terminal tab.' -ForegroundColor Green
if (-not $canSymlink -and -not $linkedElsewhere) {
    Write-Warn 'Configs were copied, not linked. Enable Developer Mode and re-run for live-linked configs.'
}
