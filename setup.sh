#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"

echo "==> Installing Homebrew (if missing)"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> Installing GNU Stow"
brew install stow

echo "==> Stowing dotfiles"
TOPICS=(zsh git p10k ssh claude)
for topic in "${TOPICS[@]}"; do
  if [ -d "$DOTFILES/$topic" ]; then
    stow --target="$HOME" --restow "$topic"
    echo "  stowed: $topic"
  fi
done

echo ""
echo "Done. Restart your terminal."
