#!/bin/bash
#
# End-to-end smoke test against a local restic file repository.
# No cloud, no Keychain (RESTIC_PASSWORD env bypasses it), no TCC.
# Exercises: init, backup, includes/excludes semantics (.env kept,
# node_modules dropped), restore round-trip, restore-test, retention,
# freshness guard, lock.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELICTA="$REPO_DIR/bin/relicta"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export RELICTA_CONFIG_DIR="$TMP/config"
export RELICTA_STATE_DIR="$TMP/state"
export RELICTA_LOG_DIR="$TMP/logs"
export RESTIC_PASSWORD="smoke-test-password"

fail() {
  echo "SMOKE FAIL: $*" >&2
  exit 1
}
pass() { echo "  ok: $*"; }

# --- fixture tree ----------------------------------------------------------
mkdir -p "$TMP/fixture/project/node_modules/junk" "$TMP/fixture/project/src"
echo "hello relicta" >"$TMP/fixture/file.txt"
echo "SECRET_KEY=hunter2" >"$TMP/fixture/project/.env"
echo "console.log('hi')" >"$TMP/fixture/project/src/index.js"
echo "junk" >"$TMP/fixture/project/node_modules/junk/pkg.json"

mkdir -p "$RELICTA_CONFIG_DIR"
cat >"$RELICTA_CONFIG_DIR/config" <<EOF
RELICTA_REPOSITORY="$TMP/repo"
RELICTA_HOST="smoke-host"
RELICTA_PRUNE_EVERY_DAYS=9999
RELICTA_MANIFESTS=false
EOF
echo "$TMP/fixture" >"$RELICTA_CONFIG_DIR/includes.txt"
echo "node_modules" >"$RELICTA_CONFIG_DIR/excludes.txt"

# --- init + backup ---------------------------------------------------------
"$RELICTA" run init >/dev/null
pass "restic repo initialized"

"$RELICTA" backup >/dev/null
pass "backup ran"

count="$("$RELICTA" run snapshots --json 2>/dev/null | tr ',' '\n' | grep -c '"short_id"')"
[ "$count" = "1" ] || fail "expected 1 snapshot, got $count"
pass "exactly one snapshot"

# --- include/exclude semantics ---------------------------------------------
listing="$("$RELICTA" run ls latest 2>/dev/null)"
echo "$listing" | grep -q "fixture/project/.env" || fail ".env file missing from snapshot (gitignored secrets must be backed up)"
pass ".env captured"
if echo "$listing" | grep -q "node_modules"; then
  fail "node_modules leaked into snapshot"
fi
pass "node_modules excluded"

# --- restore round-trip ----------------------------------------------------
"$RELICTA" run restore latest --target "$TMP/restore" >/dev/null 2>&1
diff "$TMP/fixture/file.txt" "$TMP/restore$TMP/fixture/file.txt" || fail "restored file differs"
pass "restore round-trip"

"$RELICTA" restore-test "$TMP/fixture/file.txt" >/dev/null || fail "restore-test subcommand failed"
pass "restore-test subcommand"

# --- freshness guard -------------------------------------------------------
out="$("$RELICTA" backup --scheduled)"
echo "$out" | grep -q "skip: last successful backup" || fail "freshness guard did not skip"
pass "freshness guard skips within 20h"

count="$("$RELICTA" run snapshots --json 2>/dev/null | tr ',' '\n' | grep -c '"short_id"')"
[ "$count" = "1" ] || fail "scheduled run should not have created a snapshot"
pass "no extra snapshot from guarded run"

# --- manual run always backs up; retention runs without deleting history -----
# restic fills unused keep-daily/-weekly/-monthly slots with the OLDEST
# snapshot, so early in a repo's life same-day snapshots are all retained
# (reasons: "daily snapshot" + "oldest daily snapshot").
echo "more" >>"$TMP/fixture/file.txt"
"$RELICTA" backup >/dev/null
count="$("$RELICTA" run snapshots --json 2>/dev/null | tr ',' '\n' | grep -c '"short_id"')"
[ "$count" = "2" ] || fail "expected 2 snapshots after manual re-run, got $count"
"$RELICTA" restore-test "$TMP/fixture/file.txt" >/dev/null || fail "latest snapshot does not have the updated file"
pass "manual backup ran; retention kept history; latest content verified"

# --- lock ------------------------------------------------------------------
mkdir -p "$RELICTA_STATE_DIR/lock.d"
echo "99999999" >"$RELICTA_STATE_DIR/lock.d/pid"
out="$("$RELICTA" backup)" # stale pid -> lock reclaimed, backup proceeds
echo "$out" | grep -q "removing stale lock" || fail "stale lock was not reclaimed"
pass "stale lock reclaimed"

echo "SMOKE OK"
