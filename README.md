# relicta

Curated, encrypted, unattended laptop backup for macOS — a thin, auditable
wrapper around [restic](https://restic.net) that backs up the stuff you can't
re-download (dotfiles, tool configs, `.env` files, documents, repos with
uncommitted work) to any S3-compatible storage: AWS S3, Cloudflare R2,
Backblaze B2, MinIO.

*relicta* (Latin): *the things left behind.*

## Why

- **Curated, not full-disk.** A dev machine is mostly re-installable. relicta
  backs up an explicit include list (typically 10–30 GB) and captures the
  re-installable world as text manifests (Brewfile, editor extensions, tool
  versions). Storage cost: well under $1/month.
- **One auditable file.** The whole tool is a single bash script
  ([`bin/relicta`](bin/relicta)) that any engineer can read end-to-end before
  trusting it with their secrets. No runtime beyond restic and stock macOS.
- **Actually unattended.** launchd schedule with sleep/shutdown catch-up,
  secrets in the macOS Keychain (never on disk), macOS notifications on
  failure, and a `doctor` command that diagnoses the classic silent killers
  (revoked Full Disk Access, locked keychain, unreachable bucket).
- **Encrypted client-side.** restic encrypts everything before upload; the
  storage provider sees ciphertext.

## Quickstart

```sh
git clone https://github.com/swarajban/relicta.git
cd relicta
./install.sh
```

The installer walks you through: backend + credentials (stored in the
Keychain), a generated repository password (**escrow it in your password
manager — this is enforced**), curating your include/exclude lists, a
foreground first backup, the launchd schedule, and the one manual macOS
settings step (Full Disk Access for restic).

## Day-to-day

```sh
relicta snapshots          # list snapshots
relicta doctor             # is the unattended path healthy?
relicta restore-test       # verify a file in the latest snapshot matches disk
relicta backup             # manual backup right now
relicta run <restic args>  # any restic command with relicta's env, e.g.
relicta run stats          #   repo size
relicta run mount /tmp/r   #   browse snapshots as a filesystem (needs macFUSE)
```

## Configuration

Everything lives in `~/.config/relicta/`:

| File | Purpose |
|---|---|
| `config` | repository URL, machine ID, retention knobs ([reference](templates/config.example)) |
| `includes.txt` | one path per line — this IS your backup |
| `excludes.txt` | restic exclude patterns (`node_modules`, venvs, build dirs) |

Two rules of thumb encoded in the defaults:

1. **Excludes are an explicit list, not gitignore.** restic never reads
   `.gitignore`, so gitignored-but-precious files (`.env`, local configs)
   are backed up while `node_modules`/`dist`/venvs are excluded by pattern.
2. **Back up repos even if they're on GitHub.** Uncommitted work, local
   branches, and `.env` files aren't on GitHub.

## Backends

One restic `s3:` code path covers all of them; only the URL differs:

| Backend | `RELICTA_REPOSITORY` | Region |
|---|---|---|
| AWS S3 | `s3:s3.us-west-2.amazonaws.com/bucket/yourname-mbp` | real region |
| Cloudflare R2 | `s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/bucket/yourname-mbp` | `auto` |
| Backblaze B2 | `s3:https://s3.us-west-004.backblazeb2.com/bucket/yourname-mbp` | `auto` |
| MinIO | `s3:https://minio.example.com/bucket/yourname-mbp` | `auto` |

Notes: use **S3 Standard** storage class — restic must randomly read pack
files for prune/check/restore, so Glacier breaks and IA's retrieval fees
bite. R2 has zero egress fees, which makes full integrity checks and
disaster-restore drills free; R2 buckets must be created in the dashboard
first, with an API token scoped to the bucket.

## Scheduling model

launchd fires the agent at 10:30, 15:30, and on load; the script skips any
run within 20h of the last success. StartCalendarInterval events missed
during sleep coalesce into one run at wake; events missed while shut down
are skipped — which the on-load run + freshness guard covers. Net effect:
~one backup per day, self-healing after days off.

Retention: 7 daily / 4 weekly / 6 monthly (configurable). `forget` runs every
backup (cheap); `prune` + `check --read-data-subset=5%` run weekly.

## Team adoption

One shared bucket, one restic repo per machine under a per-user prefix, one
scoped IAM policy per engineer. Isolated encryption per person, no lock
contention, offboarding = revoke one key. See [docs/COMPANY.md](docs/COMPANY.md).

## Restoring

From "I deleted a file" to "the laptop is at the bottom of a lake":
[docs/RESTORE.md](docs/RESTORE.md). The short version of the lake scenario —
on any Mac: `brew install restic`, export the repo URL + storage keys + repo
password *from your password manager*, `restic restore latest --target ~/x`.

## The one manual step: Full Disk Access

macOS TCC blocks launchd jobs from reading ~/Desktop, ~/Documents & co.
regardless of Unix permissions. Grant Full Disk Access to the restic binary
once (the installer opens the right settings pane), and re-grant after
`brew upgrade restic`. Partial backups caused by a lost grant are detected
and surfaced by notification and `relicta doctor`.
Details: [docs/FULL-DISK-ACCESS.md](docs/FULL-DISK-ACCESS.md).

## Threat model, briefly

Protects against: disk death, laptop loss/theft, fat-fingered `rm`, ransomware
that hasn't stolen your Keychain, a nosy storage provider (client-side
encryption). Does NOT protect against: an attacker with your repo password
*and* storage keys, or storage-credential compromise deleting the bucket
(restic needs delete permission for pruning; for append-only guarantees see
`restic rest-server --append-only`, out of scope here).

## License

MIT
