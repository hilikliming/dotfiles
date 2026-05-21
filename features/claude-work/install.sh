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
# Symlinks $HOME/.claude-work to the bind-mounted host directory so Claude
# Code in the container shares config, memories, and conversation history
# with the host's claude-work install.
#
# Runs as the container's remoteUser via postCreateCommand.
set -euo pipefail

SRC="/var/claude-work.mount"
DST="$HOME/.claude-work"

if [ ! -d "$SRC" ]; then
  echo "[claude-work] No mount at $SRC (host ~/.claude-work missing?). Skipping." >&2
  exit 0
fi

# If $HOME/.claude-work already exists as something other than a symlink to SRC,
# move it aside rather than clobber.
if [ -e "$DST" ] && [ ! -L "$DST" ]; then
  mv "$DST" "$DST.pre-mount-backup.$(date +%s)"
  echo "[claude-work] Pre-existing $DST moved aside as $DST.pre-mount-backup.*"
fi

# Replace stale symlinks pointing elsewhere.
if [ -L "$DST" ] && [ "$(readlink "$DST")" != "$SRC" ]; then
  rm "$DST"
fi

if [ ! -e "$DST" ]; then
  ln -s "$SRC" "$DST"
  echo "[claude-work] Symlinked $DST -> $SRC"
else
  echo "[claude-work] Symlink already in place at $DST"
fi
HELPER

chmod +x "$DST"
echo "[claude-work] Helper installed at $DST; symlink runs at postCreate."
