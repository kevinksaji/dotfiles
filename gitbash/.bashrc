# Git Bash config - the third shell this repo's Windows side wires Starship
# into, alongside PowerShell. Nothing else is managed here: PATH, JAVA_HOME
# and the rest come from the user environment setup.ps1 already sets, which
# Git Bash inherits directly.

# Check the window size after each command and update LINES/COLUMNS if
# necessary, and append to the history file rather than overwriting it -
# standard interactive-bash practice, on by default in most Linux distros'
# bashrc but not in Git for Windows'.
shopt -s checkwinsize
shopt -s histappend

# Starship - the native starship.exe expects a Windows-style path, but bash
# thinks in POSIX ones; cygpath does the conversion. It ships with both real
# Git for Windows and Cygwin, so this works regardless of which one is running.
if command -v starship >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then
    export STARSHIP_CONFIG="$(cygpath -w "$HOME/dotfiles/starship/.config/starship.toml")"
  else
    export STARSHIP_CONFIG="$HOME/dotfiles/starship/.config/starship.toml"
  fi
  eval "$(starship init bash)"
fi
