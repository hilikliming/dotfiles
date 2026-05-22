#!/usr/bin/env bash
# Build-time setup for the github-token Feature.
#
# The bind-mount declared in devcontainer-feature.json's `mounts` is only
# attached at container *run* time, not at *build* time, so we can't copy
# from the mount here. Instead, install a small helper script that the
# Feature's postCreateCommand invokes once the container is up. The helper
# only stages the file; `gh auth login --with-token` happens later from
# the repo-root install.sh, since `gh` may not be on PATH at Feature time.
set -euo pipefail

DST_DIR="/usr/local/share/github-token"
DST="$DST_DIR/install-token.sh"

mkdir -p "$DST_DIR"
cat > "$DST" <<'HELPER'
#!/usr/bin/env bash
# Copies the bind-mounted host token to $HOME/.github-work-token
# (mode 600, owned by the container user). Runs as the container's
# remoteUser via postCreateCommand. Does NOT run `gh auth login` here:
# `gh` may not be installed at Feature postCreate time.
set -euo pipefail

SRC="/var/github-work-token.mount"
DST="$HOME/.github-work-token"
TARGET_USER="${_REMOTE_USER:-${USER:-$(id -un)}}"

if [ ! -f "$SRC" ] || [ ! -s "$SRC" ]; then
  echo "[github-token] No token at $SRC (host ~/.github-work-token missing/empty?). Skipping." >&2
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
  echo "[github-token] WARNING: expected mode 600 owned by $TARGET_USER, got mode $ACT_MODE owned by $ACT_OWNER at $DST" >&2
fi
echo "[github-token] Installed token at $DST (mode $ACT_MODE, owner $ACT_OWNER)."
HELPER

chmod +x "$DST"
echo "[github-token] Helper installed at $DST; copy runs at postCreate."
