#!/usr/bin/env bash
# Build-time setup for the claude-work Feature.
#
# Mounts apply at container run time, not build time, so we drop a helper
# script that the Feature's postCreateCommand invokes once the container
# is up and the bind mount is live.
set -euo pipefail

DST_DIR="/usr/local/share/claude-work"
DST="$DST_DIR/install-claude-work.sh"

mkdir -p "$DST_DIR"
cat > "$DST" <<'HELPER'
#!/usr/bin/env bash
# Symlinks the container's Claude Code config dirs to the bind-mounted host
# directory, so Claude Code in the container shares config, memories, and
# credentials with the host's claude-work install.
#
# Both paths point at the same mount, on purpose:
#   $HOME/.claude-work  matches CLAUDE_CONFIG_DIR, exported by zshrc.append.
#   $HOME/.claude       is the DEFAULT config dir, used by anything that never
#                       sources .zshrc: the VS Code Claude Code panel, tasks,
#                       non-login shells. Without this link those launchers
#                       find no credentials and prompt for /login every time.
#
# Runs as the container's remoteUser via postCreateCommand.
set -euo pipefail

SRC="/var/claude-work.mount"

if [ ! -d "$SRC" ]; then
  echo "[claude-work] No mount at $SRC (host ~/.claude-work missing?). Skipping." >&2
  exit 0
fi

link_to_mount() {
  dst="$1"

  # Anything that is not already a symlink gets moved aside rather than clobbered.
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.pre-mount-backup.$(date +%s)"
    echo "[claude-work] Pre-existing $dst moved aside as $dst.pre-mount-backup.*"
  fi

  # Replace stale symlinks pointing elsewhere.
  if [ -L "$dst" ] && [ "$(readlink "$dst")" != "$SRC" ]; then
    rm "$dst"
  fi

  if [ ! -e "$dst" ]; then
    ln -s "$SRC" "$dst"
    echo "[claude-work] Symlinked $dst -> $SRC"
  else
    echo "[claude-work] Symlink already in place at $dst"
  fi
}

link_to_mount "$HOME/.claude-work"
link_to_mount "$HOME/.claude"
HELPER

chmod +x "$DST"
echo "[claude-work] Helper installed at $DST; symlink runs at postCreate."
