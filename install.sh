#!/bin/bash
#
# relicta installer — interactive first-run setup; everything after is
# unattended. Safe to re-run: it never clobbers an existing config.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
RELICTA_BIN="$REPO_DIR/bin/relicta"
CONFIG_DIR="${RELICTA_CONFIG_DIR:-$HOME/.config/relicta}"
LOG_DIR="$HOME/Library/Logs/relicta"
PLIST_LABEL="com.relicta.backup"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

step() { printf '\n==> %s\n' "$*"; }

[ "$(uname)" = "Darwin" ] || {
  echo "relicta targets macOS (launchd + Keychain)." >&2
  exit 1
}

step "Checking prerequisites"
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh" >&2
  exit 1
fi
if ! command -v restic >/dev/null 2>&1; then
  echo "Installing restic..."
  brew install restic
fi
restic_minor="$(restic version | sed -E 's/^restic 0\.([0-9]+).*/\1/')"
if [ "${restic_minor:-0}" -lt 16 ] 2>/dev/null; then
  echo "restic >= 0.16 required (found: $(restic version)). brew upgrade restic" >&2
  exit 1
fi
echo "restic: $(restic version | head -1)"

step "Linking relicta into ~/.local/bin"
mkdir -p "$HOME/.local/bin"
ln -sf "$RELICTA_BIN" "$HOME/.local/bin/relicta"

step "Scaffolding config in $CONFIG_DIR (existing files are never overwritten)"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
for pair in "includes.example.txt:includes.txt" "excludes.example.txt:excludes.txt"; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  if [ ! -f "$CONFIG_DIR/$dst" ]; then
    cp "$REPO_DIR/templates/$src" "$CONFIG_DIR/$dst"
    echo "created $CONFIG_DIR/$dst"
  else
    echo "kept existing $CONFIG_DIR/$dst"
  fi
done

if [ ! -f "$CONFIG_DIR/config" ]; then
  step "Interactive setup (backend, credentials, repository password)"
  "$RELICTA_BIN" init
else
  echo "kept existing $CONFIG_DIR/config — run 'relicta init' to reconfigure"
fi

step "Curate your backup set"
echo "Review what will (and won't) be backed up:"
echo "    \$EDITOR $CONFIG_DIR/includes.txt"
echo "    \$EDITOR $CONFIG_DIR/excludes.txt"
printf 'Press return when ready to run the first backup... '
read -r _

step "First backup (foreground — inherits your terminal's disk access)"
"$RELICTA_BIN" backup

step "Installing launchd agent ($PLIST_LABEL)"
mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
sed -e "s|__RELICTA_BIN__|$RELICTA_BIN|g" -e "s|__HOME__|$HOME|g" \
  "$REPO_DIR/templates/com.relicta.backup.plist.template" >"$PLIST_PATH"
launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
echo "loaded: $PLIST_PATH (fires 10:30 + 15:30 + on load; ~one real backup/day)"

step "Notification check"
osascript -e 'display notification "relicta is installed. This is what a backup alert looks like." with title "relicta"' >/dev/null 2>&1 || true
echo "You should have just seen a macOS notification. If not, allow"
echo "notifications from Script Editor in System Settings."

step "REQUIRED: grant Full Disk Access for unattended backups"
cat <<'EOF'
Interactive backups inherit your terminal's disk access, but launchd runs
do not: without this grant, scheduled backups of ~/Desktop, ~/Documents
etc. silently skip those files (partial backups + a warning notification).

  1. System Settings -> Privacy & Security -> Full Disk Access
  2. Click "+", press Cmd+Shift+G, and add:
       /opt/homebrew/opt/restic/bin/restic
  3. Re-grant after every `brew upgrade restic` (the new binary loses the
     grant); `relicta doctor` detects when this has happened.

Full details: docs/FULL-DISK-ACCESS.md
EOF
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true

printf '\nDone. Useful commands: relicta snapshots | relicta doctor | relicta restore-test\n'
