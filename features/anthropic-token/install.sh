#!/usr/bin/env bash
# Build-time setup for the anthropic-token Feature.
#
# The bind-mount declared in devcontainer-feature.json's `mounts` is only
# attached at container *run* time, not at *build* time — so we can't copy
# from the mount here. Instead, install a small helper script that the
# Feature's postCreateCommand invokes once the container is up.
set -euo pipefail

DST_DIR="/usr/local/share/anthropic-token"
DST="$DST_DIR/install-token.sh"

mkdir -p "$DST_DIR"
cat > "$DST" <<'HELPER'
#!/usr/bin/env bash
# Copies the bind-mounted host token to $HOME/.anthropic-work-key (mode 600).
# Runs as the container's remoteUser via postCreateCommand.
set -euo pipefail

SRC="/tmp/anthropic-work-key.mount"
DST="$HOME/.anthropic-work-key"

if [ ! -f "$SRC" ] || [ ! -s "$SRC" ]; then
  echo "[anthropic-token] No token at $SRC (host ~/.anthropic-work-key missing/empty?). Skipping." >&2
  exit 0
fi

install -m 600 "$SRC" "$DST"
echo "[anthropic-token] Installed token at $DST (mode 600)."
HELPER

chmod +x "$DST"
echo "[anthropic-token] Helper installed at $DST; copy runs at postCreate."
