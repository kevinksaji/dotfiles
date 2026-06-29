#!/usr/bin/env bash

# setting instructions
# -e flag exits immediately if any command fails
# -u treats unset variables as errors to prevent silent bugs
# -o pipefail causes whole pipeline to fail on failure of one command
set -euo pipefail

# setting variables (paths used throughout script)
DOTFILES="$HOME/dotfiles"
REPO="https://github.com/kevinksaji/dotfiles.git"

echo "==> Installing Xcode Command Line Tools (if missing)"
# no git installation means not installed, if so macOS install is triggered
if ! command -v git &>/dev/null; then
  xcode-select --install
  echo "    Complete the installation dialog, then press Enter to continue..."
  read -r
fi

echo "==> Cloning or updating dotfiles repo"
# if doesnt exist, clones fresh repo
# if exists but not git repo, wipes existing and clones fresh
# else git pull
if [ ! -d "$DOTFILES/.git" ]; then
  rm -rf "$DOTFILES"
  git clone "$REPO" "$DOTFILES"
else
  git -C "$DOTFILES" pull
fi

echo "==> Installing Homebrew (if missing)"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> Installing packages from Brewfile"
brew bundle --file="$DOTFILES/Brewfile"

echo "==> Installing Go via goenv"
export GOENV_ROOT="$HOME/.goenv"
export PATH="$GOENV_ROOT/bin:$GOENV_ROOT/shims:$PATH"
GO_LATEST=$(goenv install --list | grep -E '^\s+[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 | tr -d ' ')
goenv install --skip-existing "$GO_LATEST"
goenv use "$GO_LATEST" --global

echo "==> Installing Python via pyenv"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
PYTHON_LATEST=$(pyenv install --list | grep -E '^\s+3\.[0-9]+\.[0-9]+$' | tail -1 | tr -d ' ')
pyenv install --skip-existing "$PYTHON_LATEST"
pyenv global "$PYTHON_LATEST"

echo "==> Installing NVM"
if [ ! -d "$HOME/.nvm" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts

echo "==> Installing SDKMAN and Java"
if [ ! -d "$HOME/.sdkman" ]; then
  curl -s "https://get.sdkman.io" | zsh
fi
zsh -c '
  export SDKMAN_DIR="$HOME/.sdkman"
  [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
  sdk install java
'

echo "==> Git identity"
read -rp "    Name:  " git_name
read -rp "    Email: " git_email

echo "==> Stowing dotfiles"
TOPICS=(zsh git p10k ssh claude)
for topic in "${TOPICS[@]}"; do
  if [ -d "$DOTFILES/$topic" ]; then
    # --adopt moves any pre-existing real files into the dotfiles repo before symlinking
    stow --dir="$DOTFILES" --target="$HOME" --adopt --restow "$topic"
    echo "  stowed: $topic"
  fi
done

echo "==> Restoring repo versions (overriding any adopted local changes)"
git -C "$DOTFILES" checkout -- .

echo "==> Configuring git identity"
git config -f ~/.gitconfig.local user.name  "$git_name"
git config -f ~/.gitconfig.local user.email "$git_email"

echo "==> Importing Terminal profile"
# Register the profile straight into Terminal's prefs via cfprefsd instead of `open`-ing
# the .terminal file. `open` always spawns a new window (and switches you to Terminal.app
# even when run from the VS Code terminal); merging the dict here does neither.
PROFILE_XML="$(plutil -convert xml1 -o - "$DOTFILES/terminal/kevinsaji.terminal")"
defaults write com.apple.Terminal "Window Settings" -dict-add "kevinsaji" "$PROFILE_XML"
defaults write com.apple.Terminal "Default Window Settings" -string "kevinsaji"
defaults write com.apple.Terminal "Startup Window Settings" -string "kevinsaji"

echo ""
echo "Done. Close this window and open a new Terminal window to use the kevinsaji profile."
exit
