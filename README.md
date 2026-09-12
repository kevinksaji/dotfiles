# dotfiles

Personal machine configuration for **macOS** and **Windows**. One script per platform sets up a new machine or syncs an existing one.

The two platforms are deliberately kept separate, and Windows is **not** a port of the macOS setup. macOS uses zsh, Homebrew, GNU Stow and the Unix version managers; Windows uses PowerShell 7, winget, native Windows toolchains and each tool's own config-include mechanism. The genuinely portable configs — `git`, `claude`, and the prompt — are shared.

| | macOS | Windows |
|---|---|---|
| Setup script | `setup.sh` | `setup.ps1` |
| Package list | `Brewfile` | `Wingetfile` |
| Shell | zsh (`zsh/`) | PowerShell 7 (`powershell/`) |
| Prompt | Starship (`starship/`, shared) | Starship (`starship/`, shared) |
| Terminal | Terminal.app (`terminal/`) | Windows Terminal (`windows-terminal/`) |
| SSH | `ssh/` | `ssh-windows/` |
| Wiring | GNU Stow symlinks | native include stubs (no admin) |

## What gets configured

| Package | Platform | Files | What it does |
|---|---|---|---|
| `zsh` | macOS | `.zshrc`, `.zprofile` | Shell config — PATH, version managers, plugins, prompt |
| `terminal` | macOS | `kevinsaji.terminal` | Terminal.app profile — font, colours |
| `ssh` | macOS | `.ssh/config` | SSH settings with macOS Keychain integration |
| `powershell` | Windows | `Microsoft.PowerShell_profile.ps1` | Shell config — PATH, `Use-Java`, PSReadLine, prompt |
| `windows-terminal` | Windows | `settings.partial.json` | Font and colour scheme, **merged** into Windows Terminal's settings |
| `ssh-windows` | Windows | `.ssh/config` | SSH settings without the Apple-only `UseKeychain` keyword |
| `git` | both | `.gitconfig`, `.gitignore_global` | Git settings and global ignore rules. Identity is set per-machine and never stored in the repo |
| `claude` | both | `.claude/settings.json` | Claude Code model and effort settings |
| `starship` | both | `starship.toml` | One prompt config for zsh, PowerShell, and Git Bash — path, git status, `❯` on its own line |
| `gitbash` | Windows | `.bashrc` | Wires the shared Starship config into Git Bash |

---

## Setup — macOS

You need **Xcode Command Line Tools** to use `git`. If you have never set up a Mac for development before, open Terminal and run:

```sh
xcode-select --install
```

A dialog will appear. Click **Install** and wait for it to finish (a few minutes).

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/kevinksaji/dotfiles/main/setup.sh)
```

This clones the repo to `~/dotfiles` (or pulls the latest if it's already there) and configures everything in one shot — you don't clone anything yourself first.

> **If you already have this repo cloned somewhere else** (e.g. `~/code/dotfiles`), move or re-clone it to `~/dotfiles` before running the script. The path is hardcoded, and if something other than a git checkout of this repo is already sitting at `~/dotfiles`, the script deletes it before cloning fresh.

The script will:

1. Clone or update the repo at `~/dotfiles`
2. Install [Homebrew](https://brew.sh) if not already installed
3. `brew update`, install everything in the `Brewfile`, then `brew upgrade` — so an existing Mac converges to the same versions a fresh one gets:

   | Tool | Description |
   |---|---|
   | `starship` | Shell prompt — shared config with Windows |
   | `zsh-autosuggestions` | Fish-style command suggestions |
   | `zsh-syntax-highlighting` | Syntax highlighting in the shell |
   | `zoxide` | Smarter `cd` |
   | `font-fira-code-nerd-font` | Nerd Font for file-type icons (the prompt itself needs none) |
   | `llvm` | C/C++ compiler toolchain |
   | `goenv` + Go | Go version manager |
   | `pyenv` + Python | Python version manager |
   | [NVM](https://github.com/nvm-sh/nvm) + Node.js | Node version manager |
   | [SDKMAN](https://sdkman.io) + Java | Java version manager |

4. Symlink every config file into the right place in your home folder
5. Prompt for your **name** and **email** for git — stored locally, never committed
6. Import the Terminal profile (font, colours)

---

## Setup — Windows

Requires **Windows 10 1809+ or Windows 11** with `winget` (ships as "App Installer"; install it from the Microsoft Store if `winget --version` fails).

**There is one command.** It clones the repo for you if it isn't there yet, so nothing needs setting up first — not even git.

Open a **normal PowerShell window** (not an Administrator one) and run:

```powershell
irm https://raw.githubusercontent.com/kevinksaji/dotfiles/main/setup.ps1 | iex
```

That's the whole install. If something needs Administrator rights, **the script asks for it itself** with a UAC prompt — accept it and it carries on. You never need to run a second command.

> **Don't run the whole script as Administrator.** PowerShell 7 and Windows Terminal ship as MSIX packages, and MSIX per-user installs fail from an elevated context. The script elevates only the individual steps that need it, which is why starting it elevated makes things worse rather than better.

The script will:

1. Clone or update the repo at `~\dotfiles`
2. Install or upgrade everything in the `Wingetfile` — PowerShell 7, Windows Terminal, Git, Starship, zoxide and fnm
3. Install the language toolchains natively (see below)
4. Install **FiraCode Nerd Font** per-user for the prompt icons
5. Install or update the `PSReadLine` and `Terminal-Icons` PowerShell modules
6. Prompt for your **name** and **email** for git — stored locally, never committed
7. Wire up every config file, backing up anything already there
8. Merge the font and colour scheme into Windows Terminal's `settings.json`

When it finishes, close the window and open a new Windows Terminal tab.

### Three rules the Windows script follows

**1. Native toolchains.** Windows gets the tools Windows actually uses, not Windows ports of the Unix version managers the macOS side runs:

| Language | Windows approach | Why not the macOS tool |
|---|---|---|
| Python | python.org installer + the **`py` launcher** (PEP 397) | `pyenv-win` is a third-party reimplementation whose shims shadow the interpreters the `py` launcher already manages |
| Java | **Temurin 21** + `JAVA_HOME`, switched by the `Use-Java` function in the profile | SDKMAN needs a POSIX shell and cannot run natively; Windows has no first-party version manager |
| Go | the official **Go MSI** | `goenv` is Unix-only. Go manages extra versions itself: `go install golang.org/dl/go1.22.5@latest` |
| C | **MSYS2 / mingw-w64**, updated via `pacman` | Standalone LLVM targets the MSVC ABI and cannot link without Visual Studio also installed. MSYS2's gcc is self-contained |
| Node | **fnm** | `nvm-windows` switches versions by rewriting a symlink under `Program Files`, so every `nvm use` needs elevation |

**2. Convergent.** A fresh machine and a machine last set up two years ago finish in the same state, on current versions. Every package step installs *or* upgrades — nothing assumes a clean slate, and nothing clobbers an install that is already correct. Re-running the script is the supported way to bring a machine up to date.

**3. Admin-free where possible.** There is no symlink step and no Developer Mode requirement. Each config is wired up with the tool's own include mechanism, and writing a small stub into your own home folder needs no privilege. The only UAC prompts come from installers that publish no user-scope package — Go and Temurin — and winget raises those itself.

### How the configs are wired

| Config | Mechanism |
|---|---|
| PowerShell profile | `$PROFILE` is a one-line stub that dot-sources the repo copy |
| `.gitconfig` | a stub using git's own `[include] path =` |
| `.ssh/config` | a stub using OpenSSH's `Include` (supported since 7.3; Windows ships 9.x) |
| `.gitignore_global` | no stub — `core.excludesfile` in `git/.gitconfig` points at the repo |
| Starship theme | no stub — the profile sets `STARSHIP_CONFIG` to the repo path |
| `claude/settings.json` | **copied** — Claude Code has no include mechanism |

Because the real content stays in the repo, editing a config file edits the same file the repo tracks, and changes can be committed and pushed like normal code. `claude/settings.json` is the one exception: it is a copy, so edit the repo copy and re-run the script.

### Windows notes

- **Every shell runs the literal same prompt.** `starship/.config/starship.toml` is one file, read directly by zsh, PowerShell, and Git Bash via `STARSHIP_CONFIG` — not several matching configs, the same one. It replaced Powerlevel10k and oh-my-posh, both of which needed a separate file kept in sync by hand.
- **Git Bash is a third managed shell on Windows, alongside PowerShell.** `gitbash/.bashrc` holds the same Starship wiring as the PowerShell profile; `~/.bashrc` and `~/.bash_profile` are stubs pointing at it, the same pattern as everything else in this section. The one wrinkle: the native `starship.exe` needs a Windows-style path, but bash thinks in POSIX ones, so `gitbash/.bashrc` runs it through `cygpath -w` first — that ships with both real Git for Windows and Cygwin, so it works regardless of which one is running.
- **The prompt is two lines, plain text, and has no right-hand side.** Path and git status on the first line, the `❯` you type after on the second, turning red when the last command failed. Git status uses Starship's own per-type symbols (`!` modified, `?` untracked, `+` staged, `✘` deleted, `»` renamed, `=` conflicted, `⇡`/`⇣`/`⇕` ahead/behind/diverged) with a file count appended to each via Starship's `$count` variable — its defaults show the bare symbol with no count, so this is one small, documented opt-in on top of them, not a reinvention. No Nerd Font glyphs anywhere in it, so it renders correctly even before the font is picked up.
- **Resizing the terminal can still misplace the cursor.** On Windows, PSReadLine tracks where your input begins as a buffer coordinate; resize a window while the prompt is wrapped and its idea of that position stops matching what's on screen. This is [PSReadLine #3637](https://github.com/PowerShell/PSReadLine/issues/3637), still open, with no setting that avoids it — **F5** is bound in the profile to `InvokePrompt()`, which redraws the prompt in place without wiping the scrollback the way Ctrl+L does. macOS has the same class of bug in zsh itself, documented in [Powerlevel10k's own FAQ](https://github.com/romkatv/powerlevel10k/blob/master/README.md) as "Horrific mess when resizing terminal window" — zsh redraws at a stale line offset after a resize reflows the prompt. Neither is a defect in this config or in Starship; both live below the prompt layer, in the shell's line editor and the terminal's own reflow racing each other. A short two-line prompt with no right-hand side narrows how often either triggers, but cannot prevent it. VS Code's own integrated terminal has a separate, unrelated resize bug: its renderer (xterm.js) can duplicate prompt lines when reflowing its scrollback buffer, most reliably when shrinking the window and then growing it back. That is a bug in xterm.js's buffer reflow, not in this config, this repo's shells, or VS Code's `settings.json` (which this repo does not manage); `clear`/`Ctrl+L` clears the duplicate without losing scrollback content.
- **Windows Terminal settings are merged, not replaced.** That file also holds machine-generated profile GUIDs, so overwriting it wholesale would break your profile list. Only `profiles.defaults`, the `kevinsaji` colour scheme, and `defaultProfile` are touched, and a `.dotfiles-backup` is written alongside.
- **If Windows Terminal has never been launched**, its settings file does not exist yet. Launch it once and re-run `setup.ps1`.
- **Older Python versions are kept.** `PY_PYTHON` is set so bare `py` runs the newest interpreter; `py -3.12`, `py -3.10` and any Anaconda install stay reachable. Run `py --list` to see them all.
- **Older JDKs are kept.** `JAVA_HOME` points at Temurin 21. Run `Use-Java` with no argument to list what is installed, or `Use-Java 17` to switch the current shell.
- **MSYS2 is detected before it is installed.** A hand-installed MSYS2 at `C:\msys64` is not registered with winget, so the script probes the filesystem first and updates that install in place rather than dropping a second copy over it.
- **`git-lfs` is not installed separately.** Git for Windows bundles it.
- **`UseKeychain` is macOS-only.** Windows OpenSSH aborts the whole connection on an unknown keyword, which is why `ssh-windows/` exists as a separate package.

### Pruning unmanaged runtimes

Convergence means one toolchain per language: whatever the script installs, and nothing else. A second Python or a stray JDK is not harmless — it shadows the managed one on PATH, which is exactly how you end up with `JAVA_HOME` pointing at one version while `java -version` reports another.

Every run **reports** what it would remove. Nothing is removed unless you pass `-Prune`:

```powershell
.\setup.ps1 -Prune
```

What counts as prunable:

| Language | Kept | Removed |
|---|---|---|
| Python | the newest `Python.Python.3.N` | every older interpreter, **and Anaconda/Miniconda** |
| Java | Temurin 21 | every other JDK or JRE, any vendor, winget-registered or not |
| Node | fnm | standalone Node.js installs and `nvm-windows` |
| Go | the official Go MSI | any other Go distribution |

> **Removing a runtime is irreversible.** Every virtualenv built against a removed interpreter stops working, and uninstalling Anaconda destroys all of its conda environments along with anything installed into them. Read the report before passing `-Prune`.

Three things keep this from going wrong:

- **A language is only pruned once its keeper is confirmed installed.** A failed install can never leave the machine with no Python at all.
- **The `py` launcher is never a candidate.** It is what makes the remaining interpreters reachable, and it is not itself an interpreter.
- **Removal goes through the vendor's uninstaller**, via winget or the registry. The single exception is a JDK unpacked by hand, which has no uninstaller — there the directory *is* the install, so it is deleted, but only after checking for `bin/java.exe`, `release` and `lib/modules` together. Anything not unmistakably a JDK is reported instead of touched.

Stale PATH entries are cleaned up in both user and machine scope as each runtime goes, so nothing is left shadowing the survivor. Leftover directories count too: uninstalling Python leaves its pip-installed packages behind, so a `PythonNNN` folder with no `python.exe` in it is pruned as dead weight.

Machine-scope removals — a Node.js MSI, a JDK under `Program Files` — need Administrator rights. The script raises a single UAC prompt and finishes them itself; accept it. That elevated step passes `-SkipPackages`, so it only removes things and never runs the MSIX installs that break under elevation.

Some uninstallers detach and finish after the script exits (Anaconda's does this), so a runtime can still look present for a minute or two afterwards.

### Script flags

| Flag | Effect |
|---|---|
| `-SkipPackages` | Config only — skip every installer. Fast way to re-apply config changes |
| `-SkipConfig` | Installers only — leave the config files alone |
| `-Prune` | Actually uninstall unmanaged runtimes. Without it, they are only reported |

---

## Existing machine

Any config file already on your machine that this repo manages will be replaced with the repo's version.

- **macOS:** `stow --adopt` pulls your existing files into the repo, and the script then reverts those specific files to the repo's versions. Uncommitted work you already had in `~/dotfiles` is left untouched — only files that stow actually adopted during this run are reverted.
- **Windows:** your old versions are moved aside to `<file>.dotfiles-backup` next to the original. Re-running the script never overwrites an existing backup.

> The two platforms differ here. Windows keeps a copy of whatever it replaced; macOS does not — an adopted file's previous contents are replaced by the repo's version and are not recoverable afterwards. On a Mac with configs you care about, copy them somewhere safe before the first run.

---

## Adding a new config file

**macOS:**

1. Create a folder in `~/dotfiles` named after the tool (e.g. `vim/`)
2. Mirror the path as it would appear under `$HOME` (e.g. `vim/.vimrc`)
3. Add the package name to the `TOPICS` list in `setup.sh`
4. Run `bash setup.sh`

**Windows:**

1. Create the folder and mirror the path as above
2. In the config phase of `setup.ps1`, add a `Write-Stub` call using whatever include mechanism the tool supports — or, if it supports none, copy the file as `claude/settings.json` is copied
3. Run `.\setup.ps1 -SkipPackages`

Windows does not mirror `$HOME` the way Stow does, because the targets do not all sit under it — `Documents` may be redirected to OneDrive, so the profile path is resolved at runtime.
