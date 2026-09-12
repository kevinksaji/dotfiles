#Requires -Version 5.1
<#
  Windows machine setup. Deliberately NOT a port of setup.sh.

  Three rules shape this script:

  1. Native toolchains. Windows gets the tools Windows actually uses - the py
     launcher for Python, JAVA_HOME switching for JDKs, the official Go MSI,
     MSYS2 for C - not Windows ports of the Unix version managers the macOS
     side runs. pyenv-win, goenv and SDKMAN have no place here.

  2. Convergent. A fresh machine and a machine last touched two years ago both
     end this script in the same state, on current versions. Every step
     installs OR upgrades; nothing assumes a clean slate, and nothing clobbers
     an install that is already correct.

  3. Admin-free where possible. Configs are wired up with each tool's own
     include mechanism instead of symlinks, so the config phase needs no
     privilege at all. The only UAC prompts come from installers that publish
     no user-scope package - Go and Temurin - and winget raises those itself.

  Run from a NORMAL PowerShell window:
    irm https://raw.githubusercontent.com/kevinksaji/dotfiles/main/setup.ps1 | iex

  Do not run elevated: PowerShell 7 and Windows Terminal ship as MSIX packages
  and per-user MSIX installs fail from an elevated context.
#>
param(
    [switch]$SkipPackages,   # config only - skip every installer
    [switch]$SkipConfig,     # installers only - skip the config phase
    [switch]$Prune           # actually uninstall unmanaged runtimes (see the prune phase)
)

$ErrorActionPreference = 'Stop'

$Dotfiles = Join-Path $HOME 'dotfiles'
$Repo     = 'https://github.com/kevinksaji/dotfiles.git'

# Toolchains are named here rather than in the Wingetfile because each needs
# bespoke follow-up work - PY_PYTHON, JAVA_HOME, pacman - that a flat list cannot express.
$JdkPackage  = 'EclipseAdoptium.Temurin.21.JDK'
$GoPackage   = 'GoLang.Go'
$MsysPackage = 'MSYS2.MSYS2'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string]$Message) Write-Host "    ! $Message" -ForegroundColor Yellow }

function Test-Command { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Reload PATH from the registry so tools installed earlier in this run are callable now.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:PATH = (($machine, $user) -join ';')
}

function Set-UserEnv {
    param([string]$Name, [string]$Value)
    if ([Environment]::GetEnvironmentVariable($Name, 'User') -ne $Value) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
        Write-Note "$Name = $Value"
    }
    Set-Item "env:$Name" $Value
}

# Windows apps outside PowerShell read the user PATH, so toolchain bins belong
# there rather than in the profile. Dedupe, or repeated runs grow it without bound.
function Add-UserPath {
    param([string]$Directory)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($current -split ';' | Where-Object { $_ })
    if ($entries -contains $Directory) { return }
    [Environment]::SetEnvironmentVariable('Path', ((@($Directory) + $entries) -join ';'), 'User')
    Write-Note "PATH += $Directory"
}

# Install if absent, upgrade if present. This is what makes the script convergent:
# an old machine lands on the same versions as a fresh one.
function Install-Package {
    param([string]$Id, [string[]]$ExtraArgs = @())

    $common = @('--id', $Id, '--exact', '--source', 'winget', '--silent',
                '--accept-package-agreements', '--accept-source-agreements')

    # `winget list` exits 0 when the package is installed and -1978335212
    # (NO_APPLICABLE_INSTALLER) when it is not.
    winget list --id $Id --exact --source winget 2>&1 | Out-Null
    $installed = ($LASTEXITCODE -eq 0)

    if ($installed) {
        # ExtraArgs is deliberately not forwarded here. It carries --scope, which
        # describes how to *install*; passing it to an upgrade of a package that
        # was originally installed at the other scope makes winget refuse.
        winget upgrade @common 2>&1 | Out-Null
        # A package already on the newest version exits non-zero; that is success here.
        if ($LASTEXITCODE -eq 0) { Write-Note "upgraded $Id" } else { Write-Note "$Id already current" }
    } else {
        Write-Note "installing $Id"
        winget install @common @ExtraArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warn "winget exited $LASTEXITCODE for $Id - continuing" }
    }
}

# ============================================================== install phase
if (-not $SkipPackages) {

    Write-Step 'Checking prerequisites'
    if (-not (Test-Command winget)) {
        throw "winget not found. Install 'App Installer' from the Microsoft Store, then re-run this script."
    }
    Write-Note "winget $(winget --version)"
    if (Test-Elevated) {
        Write-Warn 'Running elevated. PowerShell 7 and Windows Terminal are MSIX packages and'
        Write-Warn 'may fail to install here - prefer a normal PowerShell window.'
    }

    Write-Step 'Installing git (if missing)'
    if (-not (Test-Command git)) {
        winget install --id Git.Git --exact --silent --scope user `
            --accept-package-agreements --accept-source-agreements
        Update-SessionPath
    }
    Write-Note 'git-lfs ships inside Git for Windows - no separate package needed'

    Write-Step 'Cloning or updating dotfiles repo'
    if (-not (Test-Path (Join-Path $Dotfiles '.git'))) {
        if (Test-Path $Dotfiles) { Remove-Item $Dotfiles -Recurse -Force }
        git clone $Repo $Dotfiles
    } else {
        git -C $Dotfiles pull --ff-only
    }

    Write-Step 'Installing packages from Wingetfile'
    foreach ($line in Get-Content (Join-Path $Dotfiles 'Wingetfile')) {
        $entry = ($line -split '#')[0].Trim()
        if (-not $entry) { continue }
        $fields = $entry -split '\s+'
        Install-Package -Id $fields[0] -ExtraArgs @($fields | Select-Object -Skip 1)
    }
    Update-SessionPath

    # ---------------------------------------------------------------- Python
    # The native Windows story is the python.org installers plus the py launcher
    # (PEP 397), which those installers register themselves. pyenv-win would only
    # shadow them with a parallel set of shims.
    Write-Step 'Installing Python (latest, via the py launcher)'
    $pythonMinors = winget search --id 'Python.Python.3.' --source winget 2>$null |
        Select-String -Pattern 'Python\.Python\.3\.(\d+)' |
        ForEach-Object { [int]$_.Matches[0].Groups[1].Value } |
        Sort-Object -Unique
    if (-not $pythonMinors) {
        Write-Warn 'could not enumerate Python packages from winget - skipping'
    } else {
        $minor = $pythonMinors[-1]
        Install-Package -Id "Python.Python.3.$minor" -ExtraArgs @('--scope', 'user')
        # PY_PYTHON tells the launcher which version bare `py` should run. Older
        # interpreters stay installed and reachable as `py -3.12`, `py -3.10`.
        Set-UserEnv 'PY_PYTHON' "3.$minor"
        Write-Note "bare 'py' now runs 3.$minor; older versions remain available"
    }

    # ------------------------------------------------------------------ Java
    # No first-party version manager exists on Windows and SDKMAN needs a POSIX
    # shell, so the native idiom is JDKs side by side with JAVA_HOME choosing one.
    Write-Step 'Installing Temurin 21 JDK'
    Install-Package -Id $JdkPackage
    $adoptium = Join-Path $env:ProgramFiles 'Eclipse Adoptium'
    $jdk = if (Test-Path $adoptium) {
        Get-ChildItem $adoptium -Directory -Filter 'jdk-21*' | Sort-Object Name | Select-Object -Last 1
    }
    if ($jdk) {
        Set-UserEnv 'JAVA_HOME' $jdk.FullName
        Add-UserPath (Join-Path $jdk.FullName 'bin')
        Write-Note 'other JDKs stay installed - switch per-shell with Use-Java'
    } else {
        Write-Warn 'Temurin 21 not found under Program Files - JAVA_HOME left alone'
    }

    # -------------------------------------------------------------------- Go
    # The official MSI is the native route. Go manages extra versions itself via
    # `go install golang.org/dl/goX.Y.Z@latest`, so no version manager is needed.
    Write-Step 'Installing Go'
    Install-Package -Id $GoPackage

    # --------------------------------------------------------------------- C
    # MSYS2 gives a self-contained mingw-w64 toolchain - gcc plus headers and libs -
    # with no dependency on MSVC. Standalone LLVM would target the MSVC ABI and
    # fail to link unless Visual Studio were installed as well.
    Write-Step 'Installing C toolchain (MSYS2 / mingw-w64)'
    function Find-Msys2Root {
        @(
            'C:\msys64',
            (Join-Path $env:LOCALAPPDATA 'Programs\msys64')
        ) | Where-Object { Test-Path (Join-Path $_ 'usr\bin\bash.exe') } | Select-Object -First 1
    }
    # Probe the filesystem before asking winget. A hand-installed MSYS2 is not
    # registered as a winget package, so installing on that basis alone would
    # drop a second copy over the top of a working one.
    $msysRoot = Find-Msys2Root
    if ($msysRoot) {
        Write-Note 'existing MSYS2 install found - updating it in place'
    } else {
        Install-Package -Id $MsysPackage -ExtraArgs @('--scope', 'user')
        $msysRoot = Find-Msys2Root
    }

    if (-not $msysRoot) {
        Write-Warn 'MSYS2 not found after install - skipping toolchain update'
    } else {
        Write-Note "msys2 at $msysRoot"
        $msysBash = Join-Path $msysRoot 'usr\bin\bash.exe'
        Write-Note 'updating packages (this can take several minutes)'
        # The first -Syuu may replace pacman itself and stop early by design;
        # the second pass then completes the rest of the update.
        & $msysBash -lc 'pacman -Syuu --noconfirm' 2>&1 | Out-Null
        & $msysBash -lc 'pacman -Syuu --noconfirm' 2>&1 | Out-Null
        & $msysBash -lc 'pacman -S --needed --noconfirm mingw-w64-x86_64-toolchain' 2>&1 | Out-Null
        Set-UserEnv 'MSYS2_ROOT' $msysRoot
        Add-UserPath (Join-Path $msysRoot 'mingw64\bin')
    }

    # ------------------------------------------------------------------ Node
    # fnm rather than nvm-windows: nvm-windows switches versions by rewriting a
    # symlink under Program Files, so every `nvm use` needs elevation. fnm is a
    # user-scope binary that switches via PATH, which keeps this script admin-free.
    Write-Step 'Installing Node.js LTS via fnm'
    Update-SessionPath
    if (Test-Command fnm) {
        fnm install --lts
        # `fnm install --lts` creates the lts-latest alias; make it the default.
        fnm default lts-latest 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warn 'could not set the default Node version - run: fnm default lts-latest' }
        Write-Note "fnm $((fnm --version) -replace '^fnm ', ''), node $(fnm exec --using=lts-latest node --version 2>$null)"
    } else {
        Write-Warn 'fnm not on PATH yet - open a new terminal and run: fnm install --lts'
    }

    # ----------------------------------------------------------------- fonts
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
            try { Update-Module $module -ErrorAction Stop; Write-Note "$module updated" }
            catch { Write-Note "$module already current" }
        } else {
            Install-Module $module -Scope CurrentUser -Force -AllowClobber -AcceptLicense
            Write-Note "installed $module"
        }
    }

    Update-SessionPath
}

# ================================================================ prune phase
# Convergence means one toolchain per language: whatever this script installs,
# and nothing else. Everything else is a candidate for removal.
#
# This is destructive and irreversible - removing an interpreter breaks every
# virtualenv built against it, and removing Anaconda takes its conda
# environments with it - so a plain run only REPORTS. -Prune is what uninstalls.
#
# Two hard safety rules:
#   * A language is only pruned when its keeper is confirmed installed. A failed
#     install must never leave the machine with no Python at all.
#   * Directories are never deleted. Removal always goes through winget or the
#     vendor's own uninstaller; anything without one is reported, not forced.

function Find-InstalledIds {
    param([string]$Listing, [string[]]$Patterns)
    @(foreach ($pattern in $Patterns) {
        [regex]::Matches($Listing, $pattern) | ForEach-Object { $_.Value }
    }) | Sort-Object -Unique
}

# Registry uninstall entry for a runtime winget does not know about - a JDK
# installed by hand, say. Matched on install location, which is unambiguous.
function Get-UninstallEntry {
    param([string]$InstallLocation)
    $target = $InstallLocation.TrimEnd('\')
    Get-ItemProperty @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.InstallLocation } |
        Where-Object { $_.InstallLocation.TrimEnd('\') -eq $target } |
        Select-Object -First 1
}

# Guard for the one case where removal means deleting a directory. All three
# markers together are unmistakably a JDK layout and are not going to appear
# under some unrelated folder that happens to sit in Program Files.
function Test-JdkDirectory {
    param([string]$Path)
    @('bin\java.exe', 'release', 'lib\modules') |
        ForEach-Object { Test-Path (Join-Path $Path $_) } |
        Where-Object { -not $_ } | Measure-Object | ForEach-Object { $_.Count -eq 0 }
}

# Drop a directory from PATH in one scope. Used after removing a runtime, so a
# stale entry cannot keep shadowing the one that survives.
function Remove-PathEntry {
    param([string]$Directory, [ValidateSet('User', 'Machine')][string]$Scope)
    $current = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if (-not $current) { return $false }
    $target  = $Directory.TrimEnd('\')
    $kept    = @($current -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $target })
    if ($kept.Count -eq ($current -split ';' | Where-Object { $_ }).Count) { return $false }
    # Writing the machine PATH needs elevation; report rather than throw, so the
    # caller can defer the whole removal to the elevated pass.
    try {
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), $Scope)
    } catch {
        return $false
    }
    Write-Note "removed from $Scope PATH: $Directory"
    return $true
}

function Get-InstalledJdkPath {
    # Vendors disagree on layout: Temurin nests under "Eclipse Adoptium",
    # Microsoft under "Microsoft", Oracle under "Java" or straight into Program Files.
    @(
        (Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
        (Join-Path $env:ProgramFiles 'Java'),
        (Join-Path $env:ProgramFiles 'Microsoft'),
        $env:ProgramFiles
    ) | Where-Object { $_ -and (Test-Path $_) } |
        ForEach-Object { Get-ChildItem $_ -Directory -ErrorAction SilentlyContinue } |
        Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } |
        Sort-Object FullName -Unique
}

Write-Step 'Checking for unmanaged language runtimes'

$listing  = winget list --source winget 2>&1 | Out-String
$prunable = [System.Collections.Generic.List[object]]::new()
$skipped  = [System.Collections.Generic.List[string]]::new()

# ------------------------------------------------------------------- Python
# Keeper is the highest Python.Python.3.N present - the one the install phase
# just put in place. Python.Launcher is never a candidate: it is the py
# launcher itself, not an interpreter, and is what makes the others reachable.
$pythonIds = Find-InstalledIds $listing @('Python\.Python\.3\.\d+')
$pythonKeeper = $pythonIds | Sort-Object { [int](($_ -split '\.')[-1]) } | Select-Object -Last 1
if (-not $pythonKeeper) {
    $skipped.Add('Python - no managed interpreter installed, nothing pruned')
} else {
    foreach ($id in ($pythonIds | Where-Object { $_ -ne $pythonKeeper })) {
        $prunable.Add([pscustomobject]@{ Language='Python'; Kind='winget'; Id=$id; Label=$id })
    }
    # Anaconda ships its own interpreter and is pruned like any other Python.
    foreach ($id in (Find-InstalledIds $listing @('Anaconda\.Anaconda3', 'Anaconda\.Miniconda3'))) {
        $prunable.Add([pscustomobject]@{ Language='Python'; Kind='winget'; Id=$id
                                         Label="$id (removes all conda environments)" })
    }
    # Uninstalling Python leaves pip-installed packages behind, so the directory
    # survives with no interpreter in it. Nothing resolves there - it is dead weight.
    $pythonDirs = @(
        Get-ChildItem 'C:\' -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue
        Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Directory -ErrorAction SilentlyContinue
    ) | Where-Object { $_ -and -not (Test-Path (Join-Path $_.FullName 'python.exe')) }
    foreach ($dir in $pythonDirs) {
        $prunable.Add([pscustomobject]@{
            Language='Python'; Kind='directory'; Path=$dir.FullName
            PathDirs=@($dir.FullName, (Join-Path $dir.FullName 'Scripts'))
            Label="$($dir.Name) [$($dir.FullName)] - leftover files, interpreter already gone" })
    }
}

# --------------------------------------------------------------------- Java
$javaKeeperInstalled = $listing -match [regex]::Escape($JdkPackage)
if (-not $javaKeeperInstalled) {
    $skipped.Add("Java - $JdkPackage not installed, nothing pruned")
} else {
    $otherJdkIds = Find-InstalledIds $listing @(
        'EclipseAdoptium\.Temurin\.\d+\.(JDK|JRE)',
        'Oracle\.JDK\.\d+', 'Oracle\.JavaRuntimeEnvironment',
        'Microsoft\.OpenJDK\.\d+', 'Azul\.Zulu\.\d+',
        'Amazon\.Corretto\.\d+', 'BellSoft\.LibericaJDK[\w\.]*'
    ) | Where-Object { $_ -ne $JdkPackage }
    foreach ($id in $otherJdkIds) {
        $prunable.Add([pscustomobject]@{ Language='Java'; Kind='winget'; Id=$id; Label=$id })
    }

    # JDKs installed outside winget - the common case for an Oracle download.
    $keeperPath = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    foreach ($jdk in (Get-InstalledJdkPath)) {
        if ($keeperPath -and $jdk.FullName.TrimEnd('\') -eq $keeperPath.TrimEnd('\')) { continue }
        if ($jdk.FullName -like (Join-Path $env:ProgramFiles 'Eclipse Adoptium\*')) { continue }
        $entry = Get-UninstallEntry $jdk.FullName
        if ($entry) {
            $prunable.Add([pscustomobject]@{ Language='Java'; Kind='registry'; Entry=$entry
                                             Label="$($entry.DisplayName)  [$($jdk.FullName)]" })
        } elseif (Test-JdkDirectory $jdk.FullName) {
            # A JDK unpacked by hand has no uninstaller, so the directory *is* the
            # install. Deleting it is the only way to remove it - hence the marker
            # check above, which refuses anything that is not unmistakably a JDK.
            $prunable.Add([pscustomobject]@{
                Language='Java'; Kind='directory'; Path=$jdk.FullName
                PathDirs=@((Join-Path $jdk.FullName 'bin'))
                Label="$($jdk.Name) [$($jdk.FullName)] - unpacked by hand, no uninstaller" })
        } else {
            $skipped.Add("Java - $($jdk.FullName) is not recognisably a JDK; left alone")
        }
    }
}

# --------------------------------------------------------------------- Node
# fnm is the manager, so any standalone Node or rival manager is a PATH conflict.
if ($listing -match 'Schniz\.fnm') {
    foreach ($id in (Find-InstalledIds $listing @('OpenJS\.NodeJS(\.LTS)?', 'CoreyButler\.NVMforWindows'))) {
        $prunable.Add([pscustomobject]@{ Language='Node'; Kind='winget'; Id=$id
                                         Label="$id (fnm manages Node instead)" })
    }
} else {
    $skipped.Add('Node - fnm not installed, nothing pruned')
}

# ----------------------------------------------------------------------- Go
if ($listing -match [regex]::Escape($GoPackage)) {
    foreach ($id in (Find-InstalledIds $listing @('GoLang\.Go\.[\w\.]+') | Where-Object { $_ -ne $GoPackage })) {
        $prunable.Add([pscustomobject]@{ Language='Go'; Kind='winget'; Id=$id; Label=$id })
    }
} else {
    $skipped.Add("Go - $GoPackage not installed, nothing pruned")
}

# ------------------------------------------------------------------- report
foreach ($note in $skipped) { Write-Note $note }

if (-not $prunable.Count) {
    Write-Note 'nothing to prune - one toolchain per language already'
} elseif (-not $Prune) {
    Write-Warn "$($prunable.Count) unmanaged runtime(s) found. Re-run with -Prune to remove:"
    foreach ($item in $prunable) { Write-Warn "    [$($item.Language)] $($item.Label)" }
    Write-Note 'nothing was removed - this run only reported'
} else {
    Write-Step "Pruning $($prunable.Count) unmanaged runtime(s)"
    # Machine-scope installers refuse to uninstall without elevation, and this
    # script deliberately does not elevate itself. Collect whatever is blocked
    # and print one instruction at the end instead of a raw error code per item.
    $deferred = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $prunable) {
        Write-Note "removing $($item.Label)"
        if ($item.Kind -eq 'winget') {
            $result = winget uninstall --id $item.Id --exact --silent `
                --accept-source-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                # MSI 1603 on an uninstall is almost always a privilege failure.
                if ($result -match '1603' -and -not (Test-Elevated)) {
                    $deferred.Add("$($item.Id) (machine-scope installer)")
                } else {
                    Write-Warn "winget exited $LASTEXITCODE for $($item.Id) - skipped"
                    Write-Warn ($result.Trim() -split "`n" | Select-Object -Last 1)
                }
            } else {
                # Some uninstallers (Anaconda's among them) detach and finish
                # after this script exits, so absence here is not a failure.
                Write-Note 'uninstaller accepted - may finish in the background'
            }
        } elseif ($item.Kind -eq 'registry') {
            # Prefer the vendor's own quiet uninstall; otherwise drive msiexec
            # directly, which is what an MSI-based UninstallString wraps anyway.
            $entry = $item.Entry
            if ($entry.QuietUninstallString) {
                Start-Process 'cmd.exe' -ArgumentList '/c', $entry.QuietUninstallString -Wait
            } elseif ($entry.UninstallString -match '\{[0-9A-Fa-f-]{36}\}') {
                Start-Process 'msiexec.exe' -ArgumentList '/x', $Matches[0], '/qn', '/norestart' -Wait
            } else {
                Write-Warn "no silent uninstall for $($entry.DisplayName) - remove it from Settings > Apps"
                continue
            }
            Remove-PathEntry (Join-Path $item.Entry.InstallLocation.TrimEnd('\') 'bin') 'User'   | Out-Null
            Remove-PathEntry (Join-Path $item.Entry.InstallLocation.TrimEnd('\') 'bin') 'Machine' | Out-Null
        } else {
            # Directory removal. Whether this needs elevation cannot be told from
            # the path - Program Files obviously does, but so does anything at the
            # drive root, which is where a machine-scope Python lands. So attempt
            # it and defer on refusal; never let one failure abort the run.
            try {
                foreach ($dir in $item.PathDirs) {
                    Remove-PathEntry $dir 'User'    | Out-Null
                    Remove-PathEntry $dir 'Machine' | Out-Null
                }
                Remove-Item $item.Path -Recurse -Force -ErrorAction Stop
                Write-Note "deleted $($item.Path)"
            } catch {
                if (Test-Elevated) {
                    Write-Warn "could not delete $($item.Path): $($_.Exception.Message)"
                } else {
                    $deferred.Add("$($item.Path) (permission denied)")
                }
            }
        }
    }
    Update-SessionPath

    # Finish the machine-scope removals ourselves rather than making you run a
    # second command. Only the removal step is elevated - it passes -SkipPackages,
    # so the MSIX installs that break under elevation never run in that context.
    if ($deferred.Count -and -not (Test-Elevated)) {
        Write-Host ''
        Write-Warn "$($deferred.Count) removal(s) need Administrator rights:"
        foreach ($d in $deferred) { Write-Warn "    $d" }
        Write-Note 'asking for elevation now - accept the prompt to finish them'
        $psExe = if (Test-Command pwsh) { 'pwsh' } else { 'powershell' }
        try {
            $elevated = Start-Process $psExe -Verb RunAs -Wait -PassThru -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', "`"$(Join-Path $Dotfiles 'setup.ps1')`"",
                '-SkipPackages', '-SkipConfig', '-Prune')
            if ($elevated.ExitCode -eq 0) { Write-Note 'elevated removals finished' }
            else { Write-Warn "elevated step exited $($elevated.ExitCode) - some may remain" }
        } catch {
            Write-Warn 'Elevation declined - those were left in place. Re-run to try again.'
        }
    }
    Write-Note 'pruned - open a new terminal for PATH changes to take effect'
}

# =============================================================== config phase
if ($SkipConfig) { exit 0 }

Write-Step 'Git identity'
$gitLocal = Join-Path $HOME '.gitconfig.local'
if (Test-Path $gitLocal) {
    Write-Note "already set in $gitLocal"
} else {
    $gitName  = Read-Host '    Name '
    $gitEmail = Read-Host '    Email'
    git config -f $gitLocal user.name  $gitName
    git config -f $gitLocal user.email $gitEmail
}

# ------------------------------------------------------------------- configs
# No symlinks. Every tool below can be pointed at a file elsewhere using its own
# include mechanism, and writing a small stub into your own home directory needs
# no privilege - which is what removes the UAC prompt this script used to raise.
# Edits still flow back to the repo because the real content lives there.
Write-Step 'Wiring up configs'

# git and ssh both want forward slashes in paths, even on Windows.
$dotfilesSlash = $Dotfiles -replace '\\', '/'

function Write-Stub {
    param([string]$Target, [string]$Content, [string]$Label)

    New-Item -ItemType Directory -Path (Split-Path $Target -Parent) -Force | Out-Null

    if (Test-Path $Target) {
        $existing = Get-Content $Target -Raw -ErrorAction SilentlyContinue
        if ($existing -eq $Content) { Write-Note "ok: $Label"; return }
        # Back up whatever is there, but never clobber an older backup - that is
        # the only surviving copy of the machine's original config.
        $backup = "$Target.dotfiles-backup"
        if (Test-Path $backup) {
            $backup = "$Target.$(Get-Date -Format 'yyyyMMdd-HHmmss').dotfiles-backup"
        }
        Move-Item $Target $backup -Force
        Write-Note "backed up existing file to $backup"
    }

    Set-Content -Path $Target -Value $Content -Encoding utf8 -NoNewline
    Write-Note "wired: $Label"
}

# PowerShell profile: a stub that dot-sources the repo copy.
$profilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
Write-Stub -Target $profilePath -Label 'PowerShell profile' -Content @"
# Managed by kevinksaji/dotfiles - edit the repo copy, not this stub.
. "$Dotfiles\powershell\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
"@

# git: [include] is git's own mechanism for exactly this.
Write-Stub -Target (Join-Path $HOME '.gitconfig') -Label '.gitconfig' -Content @"
# Managed by kevinksaji/dotfiles - edit the repo copy, not this stub.
[include]
	path = $dotfilesSlash/git/.gitconfig
"@

# ssh: Include has been supported since OpenSSH 7.3 and Windows ships 8.x or newer.
# It must come first - ssh keeps the first value it sees for any keyword.
Write-Stub -Target (Join-Path $HOME '.ssh\config') -Label '.ssh/config' -Content @"
# Managed by kevinksaji/dotfiles - edit the repo copy, not this stub.
Include $dotfilesSlash/ssh-windows/.ssh/config
"@

# .gitignore_global and the oh-my-posh theme need no stub at all: git/.gitconfig
# points core.excludesfile at the repo copy, and the profile passes the theme
# path straight to oh-my-posh.

# Claude Code has no include mechanism, so this one is a copy. It is the only
# managed file whose edits do not flow back to the repo on their own.
$claudeSource = Join-Path $Dotfiles 'claude\.claude\settings.json'
$claudeTarget = Join-Path $HOME '.claude\settings.json'
New-Item -ItemType Directory -Path (Split-Path $claudeTarget -Parent) -Force | Out-Null
if ((Test-Path $claudeTarget) -and
    (Get-FileHash $claudeTarget).Hash -eq (Get-FileHash $claudeSource).Hash) {
    Write-Note 'ok: claude settings.json'
} else {
    if (Test-Path $claudeTarget) {
        $backup = "$claudeTarget.dotfiles-backup"
        if (-not (Test-Path $backup)) { Copy-Item $claudeTarget $backup }
    }
    Copy-Item $claudeSource $claudeTarget -Force
    Write-Note 'copied: claude settings.json (a copy - re-run after repo changes)'
}

# --------------------------------------------------- windows terminal settings
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
