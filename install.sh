#!/usr/bin/env bash
# Personal dotfiles bootstrap for Linux dev environments (devcontainers,
# Codespaces, fresh VMs). Idempotent — safe to re-run.
#
# Usage:
#   install.sh                                       # no git identity set
#   install.sh --name "..." --email "..."            # CLI flags
#   DOTFILES_GIT_USER_NAME=... DOTFILES_GIT_USER_EMAIL=... install.sh   # env vars
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Args ----------------------------------------------------------------------
GIT_USER_NAME=""
GIT_USER_EMAIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)  GIT_USER_NAME="$2"; shift 2 ;;
    --email) GIT_USER_EMAIL="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Env var fallback ----------------------------------------------------------
GIT_USER_NAME="${GIT_USER_NAME:-${DOTFILES_GIT_USER_NAME:-}}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-${DOTFILES_GIT_USER_EMAIL:-}}"

# 1. oh-my-zsh — unattended, preserves existing .zshrc -----------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
fi

# 2. Drop .alias into $HOME -------------------------------------------------
cp -f "$DIR/.alias" "$HOME/.alias"

# 3. Source .alias from .zshrc (idempotent via marker block) ----------------
MARKER="# >>> jack dotfiles >>>"
if ! grep -qF "$MARKER" "$HOME/.zshrc" 2>/dev/null; then
  cat "$DIR/zshrc.append" >> "$HOME/.zshrc"
fi

# 4. Git identity — only if both name and email were provided ---------------
if [ -n "$GIT_USER_NAME" ] && [ -n "$GIT_USER_EMAIL" ]; then
  git config --global user.name  "$GIT_USER_NAME"
  git config --global user.email "$GIT_USER_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase        false
  git config --global push.autoSetupRemote true
  echo "Git identity set to: $GIT_USER_NAME <$GIT_USER_EMAIL>"
else
  echo "Note: git identity not set — pass --name/--email or set DOTFILES_GIT_USER_NAME/EMAIL"
fi

# 5. Default shell → zsh where permissions allow ----------------------------
if command -v zsh >/dev/null 2>&1; then
  current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "")"
  zsh_path="$(command -v zsh)"
  if [ "$current_shell" != "$zsh_path" ]; then
    sudo chsh -s "$zsh_path" "$USER" 2>/dev/null || \
      echo "Note: couldn't chsh to zsh — set 'terminal.integrated.defaultProfile.linux' in VS Code instead."
  fi
fi

echo "Dotfiles bootstrap complete. Open a new zsh shell to pick up changes."
