#!/usr/bin/env bash
# Personal dotfiles bootstrap for Linux dev environments (devcontainers,
# Codespaces, fresh VMs). Idempotent — safe to re-run.
#
# Usage:
#   install.sh
#   install.sh --name "..." --email "..."
#   install.sh --name "..." --email "..." --anthropic-token "..."
#
# Env-var fallbacks: DOTFILES_GIT_USER_NAME, DOTFILES_GIT_USER_EMAIL,
#                    DOTFILES_ANTHROPIC_OAUTH_TOKEN
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Args -----------------------------------------------------------------------
NAME=""; EMAIL=""; CLAUDE_TOKEN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)             NAME="$2";         shift 2 ;;
    --email)            EMAIL="$2";        shift 2 ;;
    --anthropic-token)  CLAUDE_TOKEN="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
NAME="${NAME:-${DOTFILES_GIT_USER_NAME:-}}"
EMAIL="${EMAIL:-${DOTFILES_GIT_USER_EMAIL:-}}"
CLAUDE_TOKEN="${CLAUDE_TOKEN:-${DOTFILES_ANTHROPIC_OAUTH_TOKEN:-}}"

# 1. oh-my-zsh (unattended; preserves existing .zshrc) -----------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
fi

# 2. Drop .alias into $HOME -------------------------------------------------
cp -f "$DIR/.alias" "$HOME/.alias"

# 3. .zshrc marker block — rewrite each run so updates to zshrc.append apply -
START="# >>> jack dotfiles >>>"
END="# <<< jack dotfiles <<<"
if [ -f "$HOME/.zshrc" ] && grep -qF "$START" "$HOME/.zshrc"; then
  sed -i.bak "/$START/,/$END/d" "$HOME/.zshrc"
  rm -f "$HOME/.zshrc.bak"
fi
cat "$DIR/zshrc.append" >> "$HOME/.zshrc"

# 4. Git identity (only if provided) ----------------------------------------
if [ -n "$NAME" ] && [ -n "$EMAIL" ]; then
  git config --global user.name  "$NAME"
  git config --global user.email "$EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase         false
  git config --global push.autoSetupRemote true
  echo "Git identity: $NAME <$EMAIL>"
fi

# 5. Claude Code (only if token provided) -----------------------------------
if [ -n "$CLAUDE_TOKEN" ]; then
  # Token file at $HOME/.anthropic-work-key, 600 perms (matches host convention).
  # zshrc.append exports CLAUDE_CODE_OAUTH_TOKEN from this file on shell start.
  (umask 077; printf '%s\n' "$CLAUDE_TOKEN" > "$HOME/.anthropic-work-key")

  if ! command -v claude >/dev/null 2>&1; then
    if command -v npm >/dev/null 2>&1; then
      npm install -g @anthropic-ai/claude-code 2>/dev/null \
        || sudo npm install -g @anthropic-ai/claude-code \
        || echo "Warning: claude install failed (try manually: 'npm i -g @anthropic-ai/claude-code')"
    else
      echo "Note: npm not found — token saved to ~/.anthropic-work-key; install claude later."
    fi
  fi

  # Skip the first-run onboarding wizard so the OAuth token takes effect immediately
  mkdir -p "$HOME/.claude"
  [ -f "$HOME/.claude/.claude.json" ] || \
    echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude/.claude.json"

  echo "Claude Code: token written to ~/.anthropic-work-key (600), auto-exported via .zshrc"
fi

# 6. Default shell → zsh where permissions allow ----------------------------
if command -v zsh >/dev/null 2>&1; then
  current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "")"
  zsh_path="$(command -v zsh)"
  if [ "$current_shell" != "$zsh_path" ]; then
    sudo chsh -s "$zsh_path" "$USER" 2>/dev/null || \
      echo "Note: couldn't chsh to zsh — set 'terminal.integrated.defaultProfile.linux' in VS Code instead."
  fi
fi

echo "Dotfiles bootstrap complete. Open a new zsh shell to pick up changes."
