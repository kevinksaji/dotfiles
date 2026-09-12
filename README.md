# dotfiles

Personal machine configuration for **macOS** and **Windows**. One script per platform sets up a new machine or syncs an existing one.

The two platforms are deliberately kept separate — macOS uses zsh, Homebrew and GNU Stow; Windows uses PowerShell 7, winget and symlinks. Only the genuinely portable configs (`git`, `claude`) are shared between them.

| | macOS | Windows |
|---|---|---|
| Setup script | `setup.sh` | `setup.ps1` |
| Package list | `Brewfile` | `Wingetfile` |
| Shell | zsh (`zsh/`) | PowerShell 7 (`powershell/`) |
| Prompt | Powerlevel10k (`p10k/`) | oh-my-posh (`ohmyposh/`) |
| Terminal | Terminal.app (`terminal/`) | Windows Terminal (`windows-terminal/`) |
| SSH | `ssh/` | `ssh-windows/` |
| Linking | GNU Stow | symlinks (explicit table in `setup.ps1`) |

## What gets configured

| Package | Platform | Files | What it does |
|---|---|---|---|
| `zsh` | macOS | `.zshrc`, `.zprofile` | Shell config — PATH, version managers, plugins, prompt |
| `p10k` | macOS | `.p10k.zsh` | Powerlevel10k prompt theme — colours, icons, git status display |
| `terminal` | macOS | `kevinsaji.terminal` | Terminal.app profile — font, colours |
| `ssh` | macOS | `.ssh/config` | SSH settings with macOS Keychain integration |
| `powershell` | Windows | `Microsoft.PowerShell_profile.ps1` | Shell config — PATH, version managers, PSReadLine, prompt |
| `ohmyposh` | Windows | `kevinsaji.omp.json` | Prompt theme, matching the Powerlevel10k layout |
| `windows-terminal` | Windows | `settings.partial.json` | Font and colour scheme, **merged** into Windows Terminal's settings |
| `ssh-windows` | Windows | `.ssh/config` | SSH settings without the Apple-only `UseKeychain` keyword |
| `git` | both | `.gitconfig`, `.gitignore_global` | Git settings and global ignore rules. Identity is set per-machine and never stored in the repo |
| `claude` | both | `.claude/settings.json` | Claude Code model and effort settings |

---

## Setup — macOS

You need **Xcode Command Line Tools** to use `git`. If you have never set up a Mac for development before, open Terminal and run:

```sh
xcode-select --install
```

A dialog will appear. Click **Install** and wait for it to finish (a few minutes).

> **Important:** the repo must be cloned to `~/dotfiles` exactly. The setup script expects it there.

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/kevinksaji/dotfiles/main/setup.sh)
```

This clones the repo to `~/dotfiles` (or pulls the latest if it's already there) and configures everything in one shot. The script will:

1. Clone or update the repo at `~/dotfiles`
2. Install [Homebrew](https://brew.sh) if not already installed
3. Install all tools and languages from the `Brewfile`:

   | Tool | Description |
   |---|---|
   | `powerlevel10k` | Shell prompt theme |
   | `zsh-autosuggestions` | Fish-style command suggestions |
   | `zsh-syntax-highlighting` | Syntax highlighting in the shell |
   | `zoxide` | Smarter `cd` |
   | `font-fira-code-nerd-font` | Nerd Font required for prompt icons |
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

> **Run this from a normal PowerShell window, not an Administrator one.** PowerShell 7 and Windows Terminal ship as MSIX packages, and MSIX per-user installs fail from an elevated context — running the whole script as admin breaks those two installs.
>
> Creating symlinks *does* need privilege, so the script handles that itself: if it can't create one, it pops a single **UAC prompt** and elevates only the linking step. Accept it. (To skip the prompt entirely, turn on **Developer Mode** under Settings → System → For developers beforehand. If you decline it, the script falls back to copying your configs — they still work, but edits no longer flow back into the repo.)

> **Important:** the repo must end up at `%USERPROFILE%\dotfiles` exactly. The setup script puts it there.

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/kevinksaji/dotfiles/main/setup.ps1 | iex
```

The script will:

1. Clone or update the repo at `~\dotfiles`
2. Install everything in the `Wingetfile` via winget:

   | Tool | Description |
   |---|---|
   | `Microsoft.PowerShell` | PowerShell 7 — the shell this repo configures |
   | `Microsoft.WindowsTerminal` | Terminal emulator |
   | `Git.Git` + `GitHub.GitLFS` | Git and Git LFS |
   | `JanDeDobbeleer.OhMyPosh` | Prompt theme engine |
   | `ajeetdsouza.zoxide` | Smarter `cd` |
   | `LLVM.LLVM` | C/C++ compiler toolchain |
   | `GoLang.Go` | Go |
   | `CoreyButler.NVMforWindows` + Node.js | Node version manager |
   | `EclipseAdoptium.Temurin.21.JDK` | Java 21 |

3. Install **FiraCode Nerd Font** per-user (no admin needed) for the prompt icons
4. Install the `PSReadLine` and `Terminal-Icons` PowerShell modules
5. Install [pyenv-win](https://github.com/pyenv-win/pyenv-win) and the latest Python 3
6. Prompt for your **name** and **email** for git — stored locally, never committed
7. Symlink every config file into place, backing up anything already there (elevating via UAC for this step only, if needed)
8. Merge the font and colour scheme into Windows Terminal's `settings.json`

When it finishes, close the window and open a new Windows Terminal tab.

### Windows notes

- **Version managers differ from macOS.** `goenv` and SDKMAN have no native Windows support, so Go and Java are installed directly at a pinned version. Python uses `pyenv-win` and Node uses `nvm-windows`, both close equivalents to their macOS counterparts.
- **Windows Terminal settings are merged, not replaced.** That file also holds machine-generated profile GUIDs, so overwriting it wholesale would break your profile list. Only `profiles.defaults`, the `kevinsaji` colour scheme, and `defaultProfile` are touched, and a `.dotfiles-backup` is written alongside.
- **If Windows Terminal has never been launched**, its settings file does not exist yet. Launch it once and re-run `setup.ps1`.
- **`UseKeychain` is macOS-only.** Windows OpenSSH aborts the whole connection on an unknown keyword, which is why `ssh-windows/` exists as a separate package.
- **Don't run the script elevated to "fix" symlinks.** It elevates the linking step on its own via `setup.ps1 -LinkOnly`; elevating the whole run breaks the MSIX installs instead.

---

## Existing machine

Any config file already on your machine that this repo manages will be replaced with the repo's version.

- **macOS:** your old versions are adopted into the repo by `stow --adopt` and show up as local changes in `git diff` after the script runs.
- **Windows:** your old versions are moved aside to `<file>.dotfiles-backup` next to the original. Re-running the script never overwrites an existing backup.

Either way, nothing is permanently lost — check the backups or `git diff` and copy across anything you want to keep.

---

## Adding a new config file

**macOS:**

1. Create a folder in `~/dotfiles` named after the tool (e.g. `vim/`)
2. Mirror the path as it would appear under `$HOME` (e.g. `vim/.vimrc`)
3. Add the package name to the `TOPICS` list in `setup.sh`
4. Run `bash setup.sh`

**Windows:**

1. Create the folder and mirror the path as above
2. Add an entry to the `$links` table in `setup.ps1` with its `Source` and `Target`
3. Run `.\setup.ps1`

Windows uses an explicit table rather than Stow-style path mirroring because GNU Stow has no Windows equivalent, and the targets do not all sit under `$HOME` — `Documents` may be redirected to OneDrive, so the profile path is resolved at runtime.

## How it works

Both platforms create symlinks from your home folder into this repo. For example:

```
macOS     ~/.zshrc   ->  ~/dotfiles/zsh/.zshrc
Windows   ~\.gitconfig  ->  ~\dotfiles\git\.gitconfig
```

This means editing a config file anywhere — in `~/dotfiles` or via its symlink — edits the same file, and changes can be committed and pushed like normal code.
