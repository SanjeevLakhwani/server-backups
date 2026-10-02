# server-backups

Nightly encrypted backups of the home server to **IDrive e2** (bucket `sanjeev-server-backups`, Chicago) using [restic](https://restic.net).

```
03:00  systemd timer → backup.sh
  1. base-website  /deploy/scripts/backup.sh → /deploy/backups/latest (postgres.sql.gz, photos/)
  2. paperless     document_exporter         → ~/docker/paperless/export
  3. restic backup those + every stack's .env  → e2 (encrypted, deduplicated)
  4. restic forget/prune: 7 daily, 4 weekly, 12 monthly (+ 2% data check on Sundays)
  5. healthchecks.io ping: start / success / fail
```

Only clean dumps and exports are backed up, never live database files or Docker volumes.

## Setup

Requires Debian with Docker, `restic` and [`just`](https://github.com/casey/just).

```bash
sudo apt install restic just
git clone git@github.com:SanjeevLakhwani/server-backups.git ~/docker/backups
cd ~/docker/backups

cp .env.example .env && chmod 600 .env       # fill in keys and paths
openssl rand -base64 32 > restic-password && chmod 600 restic-password
#   → save the password AND the e2 keys in your password manager now

just init                                    # creates the encrypted repo in the bucket
tmux new -s backup 'just run-foreground'     # first run: uploads everything, can take hours
just restore-test                            # prove it can be restored
just install                                 # enable the nightly timer
```

For monitoring, create a check on [healthchecks.io](https://healthchecks.io) (period 1 day, grace 2 hours), and put its ping URL in `HC_PING_URL`.

### IDrive e2 bucket settings
- Default encryption: on (IDrive-managed key). restic encrypts client-side anyway.
- Versioning: off. Object lock: off (it breaks `restic prune`).
- Access key: limited to this bucket only.

## Commands

| Command | What it does |
| --- | --- |
| `just run` | Start a backup now via systemd (`just logs` to follow) |
| `just run-foreground` | Run in the terminal (use inside tmux) |
| `just logs` | Follow backup logs |
| `just snapshots` | List snapshots |
| `just stats` | Repository size |
| `just check` | Integrity check (`just check --read-data` downloads everything) |
| `just restore-test` | Restore latest to a temp folder and verify it |
| `just unlock` | Clear a stale lock after a killed run |
| `just install` | Install/refresh the systemd service + timer |

To restore, see [RESTORE.md](RESTORE.md).
