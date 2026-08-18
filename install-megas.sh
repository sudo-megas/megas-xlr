#!/bin/bash
# install-megas.sh
# Adds/removes the "megas-xlr" pacman repo (the Megas app-family repo)
# to/from /etc/pacman.conf, and handles trusting/untrusting its signing key.
#
# Usage:
#   sudo ./install-megas.sh --install
#   sudo ./install-megas.sh --remove
#   ./install-megas.sh --help

set -e

# ---- REPO ----------------
REPO_NAME="megas-xlr"
REPO_URL="https://github.com/sudo-megas/megas-xlr/releases/download/repo"
KEY_URL="https://raw.githubusercontent.com/sudo-megas/megas-xlr/main/sudo-megas-pubkey.asc"
KEY_ID="62328913D18D8EC3"
# ------------------------------------------------------------------------

PACMAN_CONF="/etc/pacman.conf"
SYNC_DIR="/var/lib/pacman/sync"

if [[ "$1" == "--help" || -z "$1" ]]; then
  cat <<EOF
Usage: install-megas.sh [option]
Options:
  --install   Add the $REPO_NAME repo to pacman.conf and trust its signing key
  --remove    Remove the $REPO_NAME repo from pacman.conf and untrust its key
  --help      Show this help
EOF
  exit 0
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run this with sudo."
  exit 1
fi

if [[ ! -f "$PACMAN_CONF" ]]; then
  echo "pacman.conf not found at $PACMAN_CONF"
  exit 1
fi

repo_exists() {
  grep -q "^\[$REPO_NAME\]" "$PACMAN_CONF"
}

# Drop any cached sync database/signature for this repo, so pacman always
# fetches a fresh copy. Prevents a stale db signature (e.g. left over from an
# older, signed database) from being validated against a new unsigned one.
clear_sync_cache() {
  echo "Clearing cached database for [$REPO_NAME]..."
  rm -f "$SYNC_DIR/$REPO_NAME.db" \
        "$SYNC_DIR/$REPO_NAME.db.sig" \
        "$SYNC_DIR/$REPO_NAME.files" \
        "$SYNC_DIR/$REPO_NAME.files.sig"
}

install_repo() {
  if repo_exists; then
    echo "[$REPO_NAME] is already in pacman.conf — nothing to do."
    return
  fi

  if [[ "$KEY_ID" == "REPLACE_WITH_YOUR_GPG_KEY_ID" ]]; then
    echo "KEY_ID is still a placeholder — edit the script and set it to your real GPG key ID first."
    exit 1
  fi

  echo "Backing up pacman.conf -> ${PACMAN_CONF}.bak"
  cp "$PACMAN_CONF" "${PACMAN_CONF}.bak"

  echo "Fetching and trusting the megas-xlr signing key..."
  curl -fsSL "$KEY_URL" -o /tmp/megas-xlr-pubkey.asc
  pacman-key --add /tmp/megas-xlr-pubkey.asc
  pacman-key --lsign-key "$KEY_ID"
  rm -f /tmp/megas-xlr-pubkey.asc

  echo "Adding [$REPO_NAME] to pacman.conf..."
  {
    echo ""
    echo "[$REPO_NAME]"
    echo "Server = $REPO_URL"
    echo "SigLevel = Required DatabaseOptional"
  } >> "$PACMAN_CONF"

  clear_sync_cache

  echo "Syncing package databases..."
  pacman -Sy

  echo "Done. Install the whole family with: pacman -S $REPO_NAME"
}

remove_repo() {
  if ! repo_exists; then
    echo "[$REPO_NAME] isn't in pacman.conf — nothing to do."
    return
  fi

  echo "Backing up pacman.conf -> ${PACMAN_CONF}.bak"
  cp "$PACMAN_CONF" "${PACMAN_CONF}.bak"

  echo "Removing [$REPO_NAME] block from pacman.conf..."
  # deletes the [megas-xlr] header line plus the 2 lines we added under it
  sed -i "/^\[$REPO_NAME\]\$/,+2d" "$PACMAN_CONF"

  if [[ "$KEY_ID" != "REPLACE_WITH_YOUR_GPG_KEY_ID" ]]; then
    echo "Untrusting the signing key..."
    pacman-key --delete "$KEY_ID" 2>/dev/null || true
  fi

  clear_sync_cache

  echo "Syncing package databases..."
  pacman -Sy

  echo "$REPO_NAME repo removed."
}

case "$1" in
  --install) install_repo ;;
  --remove)  remove_repo ;;
  *)
    echo "Unknown option: $1 (use --install, --remove, or --help)"
    exit 1
    ;;
esac
