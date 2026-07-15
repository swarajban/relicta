# Restoring

Read this **before** you need it. Better: run the disaster drill at the
bottom once, today.

## What you need

Three things, none of which should live only on the laptop being restored:

1. **Repository URL** — e.g. `s3:s3.us-west-2.amazonaws.com/bucket/yourname-mbp`
2. **Storage credentials** — the access key ID + secret for the bucket
3. **Repository password** — from your password manager / team vault

If you have the laptop, all three are recoverable: URL from
`~/.config/relicta/config`, secrets from Keychain Access (search "relicta").
If you don't have the laptop, that's exactly why the installer made you
escrow the password.

## Scenario 1: I deleted / clobbered a file

```sh
# What snapshots exist?
relicta snapshots

# Find the file
relicta run find 'partial-name*'

# Print a single file to stdout
relicta run dump latest ~/path/to/file > /tmp/recovered

# Or restore a subtree into a scratch dir (never restore over $HOME blindly)
relicta run restore latest --target /tmp/restored --include ~/path/to/dir
```

Browsing interactively beats guessing paths (requires macFUSE):

```sh
mkdir -p /tmp/snapshots && relicta run mount /tmp/snapshots
# poke around /tmp/snapshots/snapshots/…, copy what you need, then Ctrl-C
```

## Scenario 2: new / wiped machine

On any Mac:

```sh
brew install restic

export RESTIC_REPOSITORY='s3:…your repo URL…'
export AWS_ACCESS_KEY_ID='…'
export AWS_SECRET_ACCESS_KEY='…'
export AWS_DEFAULT_REGION='auto'        # or your AWS region
export RESTIC_PASSWORD='…from your password manager…'

restic snapshots                        # sanity: the history is all there
restic restore latest --target ~/restored
```

Then rebuild the machine **from the restore, not onto it**:

1. `~/restored/…/.config/relicta/manifests/Brewfile` →
   `brew bundle install --file=Brewfile` reinstalls every app and CLI tool.
2. Editor extensions: `manifests/vscode-extensions.txt` et al. →
   `cat vscode-extensions.txt | xargs -L1 code --install-extension`
3. Move dotfiles/configs into place selectively. Restore `~/.ssh`, `~/.aws`,
   `~/.gnupg` with their permissions: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/*`.
4. Repos and documents: copy back wholesale.
5. Re-run relicta's `install.sh` on the new machine so backups resume —
   reuse the same repository URL but a **new prefix** if you want to keep the
   old machine's history separate, or the same prefix to continue it.

## The cfprefsd gotcha (restoring `~/Library/Preferences`)

macOS caches plists in `cfprefsd`; files you restore into
`~/Library/Preferences` while logged in get silently overwritten by the
cached versions. After copying restored plists in:

```sh
killall cfprefsd
```

…then restart the affected apps (or log out/in). Restore preferences
app-by-app as you notice missing settings rather than wholesale.

## Older snapshots

`latest` is a convenience alias. Time-travel:

```sh
relicta snapshots                       # pick an ID
relicta run restore a1b2c3d4 --target /tmp/last-tuesday
relicta run diff a1b2c3d4 latest        # what changed since?
```

## Disaster drill (do this once, ~10 minutes)

On your machine, pretending the laptop is gone:

```sh
mkdir -p /tmp/drill && cd /tmp/drill
# Use ONLY credentials from your password manager — that's the point.
export RESTIC_REPOSITORY='…' AWS_ACCESS_KEY_ID='…' AWS_SECRET_ACCESS_KEY='…' \
       AWS_DEFAULT_REGION='…' RESTIC_PASSWORD='…'
restic restore latest --target . --include "$HOME/.gitconfig"
diff "$HOME/.gitconfig" "./$HOME/.gitconfig" && echo "DRILL PASSED"
```

If any step surprised you, fix the surprise now — not during a real disaster.
