set dotenv-load := true
set export := true

# List recipes
default:
    @just --list

# Create the encrypted restic repository in the e2 bucket (once)
init:
    @test -n "${AWS_ACCESS_KEY_ID:-}" || { echo "AWS_ACCESS_KEY_ID is empty: fill in .env first"; exit 1; }
    @test -s "${RESTIC_PASSWORD_FILE}" || { echo "No password file at '${RESTIC_PASSWORD_FILE}' (RESTIC_PASSWORD_FILE in .env)"; exit 1; }
    restic init

# Install + enable the nightly systemd timer (needs sudo)
install:
    sed "s#@REPO@#{{ justfile_directory() }}#" systemd/server-backups.service | sudo tee /etc/systemd/system/server-backups.service >/dev/null
    sudo cp systemd/server-backups.timer /etc/systemd/system/server-backups.timer
    sudo systemctl daemon-reload
    sudo systemctl enable --now server-backups.timer
    systemctl list-timers server-backups.timer

# Run a backup now, the same way the timer does (follow with `just logs`)
run:
    sudo systemctl start --no-block server-backups.service
    @echo "Started. Follow with: just logs"

# Run a backup in the foreground (use inside tmux for the first, long upload)
run-foreground:
    sudo ./backup.sh

# Follow backup logs
logs:
    journalctl -u server-backups.service -f -n 100

# List snapshots
snapshots:
    restic snapshots

# Repository size and stats
stats:
    restic stats --mode raw-data

# Full integrity check (reads metadata; add --read-data to download everything)
check *args:
    restic check {{ args }}

# Restore the latest snapshot to a temp folder and sanity-check it
restore-test:
    bash scripts/restore-test.sh

# Remove a stale lock left by a killed run
unlock:
    restic unlock
