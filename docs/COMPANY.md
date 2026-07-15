# Team adoption: one bucket, many laptops

The tool needs no code changes for team use — it's a bucket-layout
convention plus scoped credentials.

## Layout

One shared bucket, **one restic repository per machine**, keyed by prefix:

```
s3://acme-laptop-backups/
  alice-mbp/     ← independent restic repo (own password, own encryption)
  bob-mbp/
  carol-air/
```

Why per-machine repos instead of one shared repo (which restic technically
supports):

- **Isolated encryption.** Each engineer's password decrypts only their
  repo. A shared repo shares a master key: anyone's password unlocks
  everyone's data, and offboarding means re-keying the world.
- **No lock contention.** restic locks are repo-wide; one person's weekly
  prune would block everyone's backups.
- **Trivial offboarding.** Revoke one IAM key, optionally delete one prefix.
- The cost — no cross-machine dedup — rounds to zero for curated sets.

## Bucket (once, by an admin)

```sh
aws s3api create-bucket \
  --bucket acme-laptop-backups \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2
aws s3api put-public-access-block \
  --bucket acme-laptop-backups \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Use **S3 Standard** (no lifecycle transition to Glacier/IA — restic must
randomly read pack files for prune/check/restore; archived objects break it).
Skip bucket versioning: restic snapshots already provide history, and
versioning doubles storage on every prune repack.

## Per-engineer credentials

One IAM user (or role) per engineer, scoped to their prefix:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::acme-laptop-backups",
      "Condition": { "StringLike": { "s3:prefix": "alice-mbp/*" } }
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::acme-laptop-backups/alice-mbp/*"
    }
  ]
}
```

Note restic **requires `s3:DeleteObject`** — it deletes lock files on every
run and pack files during prune. An append-only policy breaks it; if you
want ransomware-grade append-only guarantees, front the bucket with
`restic rest-server --append-only` on a small VM (out of scope here).

## Password escrow policy

Each engineer's repository password should be escrowed in the team vault
(1Password shared vault or equivalent) at install time. The installer
enforces *an* escrow acknowledgment; the team policy should say *where*.
A backup whose password lived only on the dead laptop is ciphertext-shaped
garbage.

## Onboarding an engineer

1. Admin: create IAM user `backup-alice` with the policy above
   (prefix `alice-mbp/*`), hand over the access key.
2. Engineer: `git clone … && ./install.sh` — choosing AWS S3, the shared
   bucket, and their prefix; escrow the generated repo password in the vault.
3. Engineer: curate `~/.config/relicta/includes.txt` (the example file is a
   sane engineer-Mac starting point) and grant restic Full Disk Access.
4. Verify: `relicta doctor` all green, `relicta restore-test` passes.
