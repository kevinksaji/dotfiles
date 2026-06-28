#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"

echo "==> Installing Homebrew (if missing)"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> Installing packages from Brewfile"
brew bundle --file="$DOTFILES/Brewfile"

echo "==> Stowing dotfiles"
TOPICS=(zsh git p10k ssh claude)
for topic in "${TOPICS[@]}"; do
  if [ -d "$DOTFILES/$topic" ]; then
    # --adopt moves any pre-existing real files into the dotfiles repo before symlinking
    stow --target="$HOME" --adopt --restow "$topic"
    echo "  stowed: $topic"
  fi
done

echo "==> Restoring repo versions (overriding any adopted local changes)"
git -C "$DOTFILES" checkout -- .

echo ""
echo "Done. Restart your terminal."
