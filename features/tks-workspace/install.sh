#!/usr/bin/env bash
# Build-time setup for the tks-workspace Feature.
#
# Mounts apply at container run time, not build time, so we drop a helper
# script that the Feature's postCreateCommand invokes once the container
# is up and the bind mount is live.
set -euo pipefail

DST_DIR="/usr/local/share/tks-workspace"
DST="$DST_DIR/install-tks-workspace.sh"

mkdir -p "$DST_DIR"
cat > "$DST" <<'HELPER'
#!/usr/bin/env bash
# Symlinks the bind-mounted host TKS workspace to $HOME/knowledge, so the
# container's tks and the host's Obsidian operate on the same brains.
#
# One link is enough here, unlike the claude-work Feature: tks finds a workspace
# by walking up from cwd looking for _workspace/manifest.yaml, so nothing
# depends on a fixed $HOME path. The link is convenience, not plumbing.
#
# Runs as the container's remoteUser via postCreateCommand.
set -euo pipefail

SRC="/var/tks-workspace.mount"
LINK="$HOME/knowledge"

if [ ! -d "$SRC" ]; then
  echo "[tks-workspace] No mount at $SRC (host workspace missing?). Skipping." >&2
  exit 0
fi

# Anything that is not already a symlink gets moved aside rather than clobbered.
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  mv "$LINK" "$LINK.pre-mount-backup.$(date +%s)"
  echo "[tks-workspace] Pre-existing $LINK moved aside as $LINK.pre-mount-backup.*"
fi

# Replace stale symlinks pointing elsewhere.
if [ -L "$LINK" ] && [ "$(readlink "$LINK")" != "$SRC" ]; then
  rm "$LINK"
fi

if [ ! -e "$LINK" ]; then
  ln -s "$SRC" "$LINK"
  echo "[tks-workspace] Symlinked $LINK -> $SRC"
else
  echo "[tks-workspace] Symlink already in place at $LINK"
fi
HELPER

chmod +x "$DST"
echo "[tks-workspace] Helper installed at $DST; symlink runs at postCreate."
