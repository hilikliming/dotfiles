#!/usr/bin/env bash
# Personal dotfiles bootstrap for Linux dev environments (devcontainers,
# Codespaces, fresh VMs). Idempotent — safe to re-run.
#
# Usage:
#   install.sh
#   install.sh --name "..." --email "..."
#
# Env-var fallbacks: DOTFILES_GIT_USER_NAME, DOTFILES_GIT_USER_EMAIL
#
# Claude Code auth needs no flag: the "claude-work" Feature mounts the host's
# ~/.claude-work (which holds .credentials.json) and links it into place.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Activate mise if present, so mise-managed tools (node/npm/etc) are on PATH.
# install.sh runs as non-interactive bash, which doesn't source .zshrc/.bashrc,
# so we need to do this explicitly.
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash --shims)" 2>/dev/null || true
fi

# Liveness test, used instead of `command -v` for mise-managed tools.
# /mise-data is a persisted volume but ~/.config/mise/config.toml is not, so after
# a rebuild a shim is still on PATH while resolving no version: `command -v uv`
# succeeds and `uv --version` fails with "No version is set for shim". Guarding on
# existence would skip the reinstall and leave a tool that cannot run.
runs() { "$@" >/dev/null 2>&1; }

# Args -----------------------------------------------------------------------
NAME=""; EMAIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)             NAME="$2";         shift 2 ;;
    --email)            EMAIL="$2";        shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
NAME="${NAME:-${DOTFILES_GIT_USER_NAME:-}}"
EMAIL="${EMAIL:-${DOTFILES_GIT_USER_EMAIL:-}}"

# 1. oh-my-zsh (unattended; preserves existing .zshrc) -----------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
fi

# 2. Drop .alias into $HOME -------------------------------------------------
# Back up a differing existing file rather than silently clobbering it. The
# Mac's ~/.alias carries Claude work/personal profile aliases that are
# deliberately not in this repo (they are macOS-keychain specific).
if [ -f "$HOME/.alias" ] && ! cmp -s "$DIR/.alias" "$HOME/.alias"; then
  cp -p "$HOME/.alias" "$HOME/.alias.dotfiles-backup.$(date +%s)"
  echo "Backed up differing ~/.alias before overwriting."
fi
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

# 5. Claude Code -----------------------------------------------------------
# No token injection. Claude Code >= 2.1.197 keeps credentials per config dir,
# so the container authenticates from the .credentials.json inside the mounted
# work config dir. The "claude-work" Feature bind-mounts it and symlinks it to
# both $HOME/.claude-work and $HOME/.claude.
#
# Gate on the mount rather than the symlink: the mount exists from container
# start, whereas the symlink is created by the Feature's postCreateCommand,
# whose ordering against the VS Code dotfiles flow is not guaranteed.
if [ -d "/var/claude-work.mount" ] || [ -d "$HOME/.claude-work" ]; then
  if ! command -v claude >/dev/null 2>&1; then
    # If no npm and mise is present, install node globally via mise so npm is on
    # PATH regardless of cwd. Per-repo `.mise.toml` only activates inside that repo,
    # but install.sh typically runs from ~/dotfiles (e.g., VS Code dotfiles flow).
    if ! command -v npm >/dev/null 2>&1 && command -v mise >/dev/null 2>&1; then
      echo "Installing node@lts globally via mise (needed for claude-code)..."
      mise use -g node@lts >/dev/null 2>&1 || true
      eval "$(mise activate bash --shims)" 2>/dev/null || true
    fi

    if command -v npm >/dev/null 2>&1; then
      npm install -g @anthropic-ai/claude-code \
        || sudo -E env "PATH=$PATH" npm install -g @anthropic-ai/claude-code \
        || echo "Warning: claude install failed (try: 'mise use -g node@lts && npm i -g @anthropic-ai/claude-code')"
    else
      echo "Note: no npm available; install claude manually."
    fi
  fi

  # Skip first-run onboarding wizard. Marker is ~/.claude.json (top-level home
  # dir), not ~/.claude/.claude.json. Deliberately no 'mkdir -p $HOME/.claude'
  # here: that dir is a symlink to the mount, and creating it as a real dir
  # first would just force the Feature's helper to move it aside.
  [ -f "$HOME/.claude.json" ] || \
    echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"

  echo "Claude Code: auth from the mounted work config dir (no token injected)."
fi

# 6. GitHub CLI (`gh`): install via official apt repo ----------------------
# Used for GitHub API ops only (PRs, issues, CI status). SSH agent forward
# handles git push/pull transport, so we deliberately don't run
# `gh auth setup-git`. Team `setup.sh` does not install `gh`.
if ! command -v gh >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  echo "Installing GitHub CLI (gh) from the official apt repo..."
  if ! command -v wget >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y wget
  fi
  sudo mkdir -p -m 755 /etc/apt/keyrings
  KEYRING=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  if [ ! -s "$KEYRING" ]; then
    TMP_KEY="$(mktemp)"
    wget -nv -O "$TMP_KEY" https://cli.github.com/packages/githubcli-archive-keyring.gpg
    sudo install -m 644 "$TMP_KEY" "$KEYRING"
    rm -f "$TMP_KEY"
  fi
  sudo mkdir -p -m 755 /etc/apt/sources.list.d
  SOURCES_LIST=/etc/apt/sources.list.d/github-cli.list
  ARCH="$(dpkg --print-architecture)"
  echo "deb [arch=$ARCH signed-by=$KEYRING] https://cli.github.com/packages stable main" \
    | sudo tee "$SOURCES_LIST" >/dev/null
  sudo apt-get update -y && sudo apt-get install -y gh \
    || echo "Warning: gh apt install failed; install manually or retry later."
fi

# 7. `gh` auth: non-interactive login from token file ---------------------
# Fine-grained PATs may need org admin approval to access org repos; we keep
# going on failure so the rest of the bootstrap still runs.
if [ -s "$HOME/.github-work-token" ] && command -v gh >/dev/null 2>&1; then
  if ! gh auth status >/dev/null 2>&1; then
    if gh auth login --with-token < "$HOME/.github-work-token"; then
      echo "gh: authenticated from ~/.github-work-token"
    else
      echo "Warning: 'gh auth login --with-token' failed."
      echo "  Fine-grained PATs may need org admin approval before they work against org repos."
      echo "  See: https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/managing-requests-for-personal-access-tokens-in-your-organization"
    fi
  fi
fi

# 8. `gt` auth: Graphite CLI token login -----------------------------------
# Team `setup.sh` installs `gt` via mise before this script runs, so we just
# auth here. Skip silently if the token file isn't present.
#
# gt is supplied by the *project's* .mise.toml, so from ~/dotfiles its shim
# resolves no version ("mise ERROR No version is set for shim: gt") even though
# `command -v gt` succeeds. Guarding on existence therefore ran the auth against
# a shim that cannot execute, and gt was left unauthenticated with only a warning.
# Run it from inside the workspace, where mise can resolve the version.
if [ -s "$HOME/.graphite-work-token" ]; then
  GT_DIR="$PWD"
  runs gt --version || GT_DIR="$(find /workspaces -maxdepth 2 -name .mise.toml -exec dirname {} \; 2>/dev/null | head -1)"
  if [ -n "$GT_DIR" ] && (cd "$GT_DIR" && runs gt --version); then
    if (cd "$GT_DIR" && gt auth --token "$(cat "$HOME/.graphite-work-token")" >/dev/null 2>&1); then
      echo "gt: authenticated from ~/.graphite-work-token"
    else
      echo "Warning: 'gt auth --token' failed; regenerate the Graphite token if it has expired."
    fi
  else
    echo "Note: gt is not resolvable yet; run 'gt auth --token \"\$(cat ~/.graphite-work-token)\"' inside the repo."
  fi
fi

# 9. TKS CLI: install when a knowledge workspace is mounted ----------------
# TKS keeps nothing under ~/.claude, so the claude-work mount does not carry it.
# The CLI lives in the container filesystem and is reinstalled on each rebuild;
# only the workspace itself persists, via the tks-workspace Feature's bind mount.
# Gate on that mount so containers without a workspace stay lean.
#
# The official installer is primary: mise's github backend verifies GitHub
# artifact attestations, and a fine-grained PAT cannot read that API (403
# "Resource not accessible by personal access token"), so the mise path fails on
# every rebuild and buries a real failure in a scary error. mise stays as the
# fallback for images without gh. Both need a GitHub credential for the private
# release asset, which is why this runs after step 7.
#
# TKS_UPDATE_PROFILE=0: the installer chooses a profile from $SHELL, which is not
# zsh here, so it would write .bashrc/.profile and leave interactive zsh without
# the binary. zshrc.append puts ~/.tks/bin on PATH instead.
if [ -d "/var/tks-workspace.mount" ] || [ -d "$HOME/knowledge" ]; then
  export PATH="$HOME/.tks/bin:$PATH"

  if ! runs tks --version; then
    if command -v gh >/dev/null 2>&1; then
      echo "Installing tks via the official installer..."
      gh api repos/TribeAI/tks-cli/contents/scripts/install.sh \
        -H "Accept: application/vnd.github.raw" \
        | TKS_UPDATE_PROFILE=0 bash \
        || echo "Warning: tks installer failed; trying mise."
    fi

    if ! runs tks --version && command -v mise >/dev/null 2>&1; then
      echo "Falling back to mise for tks..."
      if [ -s "$HOME/.github-work-token" ]; then
        MISE_GITHUB_TOKEN="$(cat "$HOME/.github-work-token")" \
          mise use -g "github:TribeAI/tks-cli@latest" || true
      else
        mise use -g "github:TribeAI/tks-cli@latest" || true
      fi
      eval "$(mise activate bash --shims)" 2>/dev/null || true
    fi
  fi

  if runs tks --version; then
    echo "TKS: $(tks --version 2>/dev/null), workspace at ~/knowledge"
  else
    echo "Warning: workspace is mounted but tks is not installed; install it manually."
  fi
fi

# 10. deep-security scanner kit --------------------------------------------
# The /deep-security skill wants 8 scanners. A devcontainer supplies only trivy
# (from the project's mise config), and $HOME/.local/bin has no volume, so the
# rest are wiped on every rebuild and scans come back DEGRADED until someone
# remembers to reinstall them. The skill ships the Linux installer already; this
# just calls it, so the kit is present before the first scan rather than after.
#
# Prefer the mount over the symlink for the same reason step 5 does: the mount
# exists from container start, the symlink only after the Feature's postCreate.
SCANNER_INSTALL=""
for base in /var/claude-work.mount "$HOME/.claude-work"; do
  if [ -f "$base/skills/deep-security/scripts/ci_install_scanners.sh" ]; then
    SCANNER_INSTALL="$base/skills/deep-security/scripts/ci_install_scanners.sh"
    break
  fi
done
if [ -n "$SCANNER_INSTALL" ]; then
  # bandit and checkov install through `uv tool`. uv normally comes from a
  # project's .mise.toml, which does not apply here in ~/dotfiles, so provision
  # it globally first or those two silently drop out of the kit.
  if ! runs uv --version && command -v mise >/dev/null 2>&1; then
    echo "Installing uv globally via mise (needed for the scanner kit)..."
    mise use -g uv >/dev/null 2>&1 || true
    eval "$(mise activate bash --shims)" 2>/dev/null || true
  fi
  echo "Provisioning the deep-security scanner kit..."
  # Shipped mode 600, so run it through bash rather than executing it directly.
  bash "$SCANNER_INSTALL" full \
    || echo "Warning: scanner kit incomplete; run '/deep-security --setup' from Claude."
fi

# 11. herdr (agent multiplexer) + jq --------------------------------------
# Global via mise so both resolve outside a project; the herdr-dispatch skills need jq.
# No `herdr integration install claude`: its absolute hook path breaks the Mac's shared settings.json.
if command -v mise >/dev/null 2>&1; then
  runs herdr --version || mise use -g herdr@0.9.5 >/dev/null 2>&1 \
    || echo "Warning: herdr install failed; run 'mise use -g herdr@0.9.5' manually."
  runs jq --version || mise use -g jq >/dev/null 2>&1 \
    || echo "Warning: jq install failed; run 'mise use -g jq' manually."
  eval "$(mise activate bash --shims)" 2>/dev/null || true
fi

# 12. Default shell → zsh where permissions allow ---------------------------
if command -v zsh >/dev/null 2>&1; then
  current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "")"
  zsh_path="$(command -v zsh)"
  if [ "$current_shell" != "$zsh_path" ]; then
    sudo chsh -s "$zsh_path" "$USER" 2>/dev/null || \
      echo "Note: couldn't chsh to zsh — set 'terminal.integrated.defaultProfile.linux' in VS Code instead."
  fi
fi

echo "Dotfiles bootstrap complete. Open a new zsh shell to pick up changes."
