# Full Disk Access: the one manual step

## Why this exists

macOS TCC (Transparency, Consent & Control) gates access to ~/Desktop,
~/Documents, ~/Downloads, and more — *per application*, on top of Unix
permissions. When you run a backup from your terminal, restic inherits the
terminal's grant and everything works. Under launchd there is no terminal:
the process that actually opens your files — **the restic binary itself** —
needs its own Full Disk Access grant, and in a background context macOS
doesn't prompt; reads just fail with `permission denied`.

The failure mode is quiet by design: restic still commits a snapshot of
everything it *could* read and exits with code 3. relicta treats exit 3 as
PARTIAL — you get a macOS notification, and `relicta doctor` pinpoints it.

## Granting

1. Open **System Settings → Privacy & Security → Full Disk Access**
   (the installer opens this pane for you).
2. Click **+**. In the file picker press **⌘⇧G** and enter:
   ```
   /opt/homebrew/opt/restic/bin/restic
   ```
   This is Homebrew's stable "opt" path for the *current* restic — prefer it
   over a `Cellar/restic/<version>/` path, which dies on every upgrade.
   (Intel Macs: `/usr/local/opt/restic/bin/restic`.)
3. Toggle it on.

Grant FDA to **restic**, not to `/bin/bash`: a grant on bash would extend to
every bash script on the machine — a far worse security posture, and the
kind of thing that fails an open-source security review.

## The upgrade trap

`brew upgrade restic` installs a new binary with a new code signature, and
macOS **silently invalidates the old grant**. Nothing tells you. Your next
scheduled backup goes PARTIAL and relicta notifies you; re-do the grant
(remove the stale entry, add it again).

Ways to notice it early:

- `relicta doctor` — flags permission-denied reads in the latest run log.
- The PARTIAL notification after the first post-upgrade scheduled backup.
- `relicta run ls latest | grep -c Desktop` dropping to zero.

## Verifying the grant works under launchd

Don't trust a terminal run — it tests the wrong context. Force a real
scheduled run:

```sh
rm -f ~/.local/state/relicta/last-success   # disarm the freshness guard
launchctl kickstart gui/$(id -u)/com.relicta.backup
sleep 5 && tail -f ~/Library/Logs/relicta/backup-*.log
```

Success looks like `backup ok` (exit 0). A TCC problem looks like
`backup PARTIAL` plus `permission denied` lines for ~/Desktop or
~/Documents paths.
