# server-backups

Nightly restic backups of this server to IDrive e2. See README.md (setup) and RESTORE.md.

## Layout on the server
- base-website: `/deploy` (its `scripts/backup.sh` writes `postgres.sql.gz` + `photos/` to `$STAGING_DIR`)
- paperless: `$PAPERLESS_DIR` (export written by `document_exporter` to `export/`)
- edge proxy: `$EDGE_PROXY_DIR`
- systemd: `server-backups.service` + `server-backups.timer` (03:00), installed by `just install`

## Rules
- Back up dumps/exports only. Never add live database dirs or Docker volume paths to restic.
- Never print, log or commit `.env`, `restic-password`, or the e2 keys.
- Never enable object lock or versioning on the bucket, and never run `restic forget`/`prune` with different flags without the user's say-so: it deletes snapshots.
- Never run a restore over live data (RESTORE.md steps that drop databases or `docker compose down -v`) without explicit user confirmation.
- A failing nightly run must fail loudly (non-zero exit + healthchecks /fail). Don't add `|| true` to backup steps.
- After changing backup.sh: `shellcheck backup.sh scripts/*.sh`, then `just run-foreground` and `just restore-test`.
