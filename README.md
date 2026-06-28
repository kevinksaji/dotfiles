# dotfiles

Personal Mac configuration managed with [GNU Stow](https://www.gnu.org/software/stow/). One script sets up a new machine or syncs an existing one.

## What gets configured

| Package | Files | What it does |
|---|---|---|
| `zsh` | `.zshrc`, `.zprofile` | Shell configuration, PATH, tool initialisation |
| `git` | `.gitconfig`, `.gitignore_global` | Git identity and global ignore rules |
| `p10k` | `.p10k.zsh` | Terminal prompt theme (Powerlevel10k) |
| `ssh` | `.ssh/config` | SSH agent and key settings |
| `claude` | `.claude/settings.json` | Claude Code model settings |

## Prerequisites

You need **Xcode Command Line Tools** to use `git`. If you have never set up a Mac for development before, open Terminal and run:

```sh
xcode-select --install
```

A dialog will appear. Click **Install** and wait for it to finish (a few minutes).

---

## Setup

> **Important:** the repo must be cloned to `~/dotfiles` exactly. The setup script expects it there.

### Step 1 — Clone the repo

```sh
git clone https://github.com/kevinksaji/dotfiles.git ~/dotfiles
```

### Step 2 — Run the setup script

```sh
cd ~/dotfiles
bash setup.sh
```

The script will:
1. Install [Homebrew](https://brew.sh) (the Mac package manager) if it is not already installed
2. Install all packages listed in the `Brewfile` (git-lfs, zoxide, zsh plugins, etc.)
3. Symlink every config file into the right place in your home folder

### Step 3 — Restart your terminal

Close and reopen Terminal (or your terminal app of choice). Your shell, prompt, and tools will be active.

---

## Existing Mac

Any config files already on your machine that are managed by Stow will be overwritten with the versions from this repo.

Your old versions are not permanently lost — they will appear as local changes in `git diff` after the script runs. If you want to preserve anything, do a `git diff` and copy what you need into the relevant file before committing.

---

## Adding a new config file

1. Create a folder in `~/dotfiles` named after the tool (e.g. `vim/`)
2. Mirror the path as it would appear under `$HOME` (e.g. `vim/.vimrc`)
3. Add the package name to the `TOPICS` list in `setup.sh`
4. Run `bash setup.sh` to symlink it

## How it works

GNU Stow creates symlinks from your home folder into this repo. For example:

```
~/.zshrc  →  ~/dotfiles/zsh/.zshrc
~/.gitconfig  →  ~/dotfiles/git/.gitconfig
```

This means editing a config file anywhere (in `~/dotfiles` or via its symlink in `~`) edits the same file, and changes can be committed and pushed like normal code.
