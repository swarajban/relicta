# relicta — notes for coding agents

Single-file bash tool wrapping restic for curated macOS backups. The design
constraint that explains everything else: **`bin/relicta` must stay one
auditable file** an engineer can read end-to-end before trusting it with
their secrets. Resist splitting it into a lib/ tree.

## Hard constraints

- **bash 3.2 compatible** (macOS stock `/bin/bash`). Forbidden: `mapfile`,
  associative arrays, `${var,,}`, `&>>`, `local -n`. Watch out: empty-array
  expansion under `set -u` needs the `${arr[@]+"${arr[@]}"}` guard.
- No runtime deps beyond restic + stock macOS (`security`, `launchctl`,
  `osascript`, `pmset`). Nothing from brew except restic itself.
- restic >= 0.16 (for `--retry-lock`; CI installs latest via brew).

## Gates (all must pass before pushing; CI runs the same)

```sh
shellcheck -s bash bin/relicta install.sh uninstall.sh tests/smoke.sh
shfmt -d -i 2 -ci bin/relicta install.sh uninstall.sh tests/smoke.sh
./tests/smoke.sh   # e2e against a local restic repo; no cloud, no Keychain
```

The smoke test bypasses the Keychain via `RESTIC_PASSWORD` env and uses
`RELICTA_CONFIG_DIR`/`RELICTA_STATE_DIR`/`RELICTA_LOG_DIR` overrides — keep
those escape hatches working.

## Non-obvious behavior (learned the hard way)

- **restic exit 3 is PARTIAL, not failure**: a snapshot WAS saved but some
  files were unreadable. On macOS that almost always means the restic
  binary lost its Full Disk Access grant (TCC) — which `brew upgrade
  restic` silently causes. Never `set -e`-die on exit 3.
- TCC denials appear in logs as **"operation not permitted"**, not
  "permission denied" — doctor greps for both.
- FDA is granted to the **restic binary**, never to bash or "relicta"
  (users look for "relicta" in the FDA list; it will never be there).
- restic `forget --keep-*` fills unused slots with the *oldest* snapshot,
  so young repos retain same-day snapshots (the smoke test encodes this).
- restic does NOT expand `~` in `--files-from`/`--exclude-file`;
  `expand_pathfile()` does it. Excludes are restic patterns, not gitignore —
  no `!` negation, bare names match anywhere. `.env` files must never be
  excluded (that's a core product decision, tested in smoke).
- Scheduling is launchd `StartCalendarInterval` x2 + `RunAtLoad` + a 20h
  freshness guard in the script — sleep coalesces missed fires, shutdown
  skips them, the guard makes the union behave like anacron. Locking is
  mkdir-based (macOS has no flock(1)).

## Machine-local state (not in this repo)

Per-machine config: `~/.config/relicta/{config,includes.txt,excludes.txt}`;
secrets in the macOS Keychain as `relicta.restic-password` /
`relicta.s3-key-id` / `relicta.s3-secret`; state stamps in
`~/.local/state/relicta/`; logs in `~/Library/Logs/relicta/`.
