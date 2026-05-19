#!/usr/bin/env bash
# Installs the bind-mounted host token at $HOME/.anthropic-work-key (mode 600).
# Runs as root with $_REMOTE_USER and $_REMOTE_USER_HOME set by the dev container CLI.
set -euo pipefail

: "${_REMOTE_USER:=root}"
: "${_REMOTE_USER_HOME:=/root}"

SRC="/tmp/anthropic-work-key.mount"
DST="${_REMOTE_USER_HOME}/.anthropic-work-key"

if [ ! -f "$SRC" ] || [ ! -s "$SRC" ]; then
  echo "[anthropic-token] No token at $SRC (host ~/.anthropic-work-key missing/empty?). Skipping." >&2
  exit 0
fi

install -m 600 "$SRC" "$DST"
chown "${_REMOTE_USER}:" "$DST"
echo "[anthropic-token] Installed token at $DST (mode 600, owner ${_REMOTE_USER})."
