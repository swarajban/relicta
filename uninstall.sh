#!/bin/bash
#
# relicta uninstaller. Removes the schedule and (optionally) local config
# and Keychain items. NEVER touches the remote repository — your snapshots
# stay in the bucket.

set -euo pipefail

CONFIG_DIR="${RELICTA_CONFIG_DIR:-$HOME/.config/relicta}"
PLIST_LABEL="com.relicta.backup"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
KC_PREFIX="relicta"

echo "Unloading launchd agent..."
launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
rm -f "$PLIST_PATH"
rm -f "$HOME/.local/bin/relicta"

printf 'Delete Keychain credentials (%s.*)? Keep them if you plan to restore later. [y/N] ' "$KC_PREFIX"
read -r answer
case "$answer" in
  y | Y)
    for item in restic-password s3-key-id s3-secret; do
      /usr/bin/security delete-generic-password -a "$USER" -s "$KC_PREFIX.$item" >/dev/null 2>&1 || true
    done
    echo "Keychain items deleted."
    ;;
  *) echo "Keychain items kept." ;;
esac

printf 'Remove local config at %s? [y/N] ' "$CONFIG_DIR"
read -r answer
case "$answer" in
  y | Y)
    rm -rf "$CONFIG_DIR"
    echo "Config removed."
    ;;
  *) echo "Config kept." ;;
esac

echo
echo "Uninstalled. Your snapshots remain in the bucket — data was NOT deleted."
echo "To restore later you need: the repository URL, storage credentials, and"
echo "the repository password (from your password manager)."
