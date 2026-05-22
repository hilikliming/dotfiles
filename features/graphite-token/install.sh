#!/usr/bin/env bash
# Build-time setup for the graphite-token Feature.
#
# The bind-mount declared in devcontainer-feature.json's `mounts` is only
# attached at container *run* time, not at *build* time, so we can't copy
# from the mount here. Instead, install a small helper script that the
# Feature's postCreateCommand invokes once the container is up.
set -euo pipefail

DST_DIR="/usr/local/share/graphite-token"
DST="$DST_DIR/install-token.sh"

mkdir -p "$DST_DIR"
cat > "$DST" <<'HELPER'
#!/usr/bin/env bash
# Copies the bind-mounted host token to $HOME/.graphite-work-token
# (mode 600, owned by the container user). Runs as the container's
# remoteUser via postCreateCommand.
set -euo pipefail

SRC="/var/graphite-work-token.mount"
DST="$HOME/.graphite-work-token"
TARGET_USER="${_REMOTE_USER:-${USER:-$(id -un)}}"

if [ ! -f "$SRC" ] || [ ! -s "$SRC" ]; then
  echo "[graphite-token] No token at $SRC (host ~/.graphite-work-token missing/empty?). Skipping." >&2
  exit 0
fi

cp "$SRC" "$DST"
chmod 600 "$DST"
# Belt-and-suspenders: helper runs as the remote user, so `cp` already
# produces a file owned by them, but make the ownership guarantee explicit
# (and tolerate failure in restricted environments where chown is blocked).
chown "$TARGET_USER" "$DST" 2>/dev/null || true

ACT_MODE="$(stat -c '%a' "$DST" 2>/dev/null || stat -f '%Lp' "$DST" 2>/dev/null || echo 'unknown')"
ACT_OWNER="$(stat -c '%U' "$DST" 2>/dev/null || stat -f '%Su' "$DST" 2>/dev/null || echo 'unknown')"
if [ "$ACT_MODE" != "600" ] || [ "$ACT_OWNER" != "$TARGET_USER" ]; then
  echo "[graphite-token] WARNING: expected mode 600 owned by $TARGET_USER, got mode $ACT_MODE owned by $ACT_OWNER at $DST" >&2
fi
echo "[graphite-token] Installed token at $DST (mode $ACT_MODE, owner $ACT_OWNER)."
HELPER

chmod +x "$DST"
echo "[graphite-token] Helper installed at $DST; copy runs at postCreate."
