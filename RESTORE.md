# Restoring

You need: the restic password, the e2 access key, and this repo's `.env` (or its values from your password manager).

All commands run from this repo with `.env` loaded:

```bash
cd ~/docker/backups && set -a && . ./.env && set +a
restic snapshots                    # pick a snapshot ID, or use "latest"
```

Restore into a scratch folder first, then put things back. Snapshot paths are absolute, so files land under `/tmp/restore/<original path>`.

```bash
restic restore latest --target /tmp/restore
```

## base-website database

```bash
cd /deploy
docker stop ps-client-portal ps-cms ps-photo-site     # nothing writing during restore
docker exec ps-postgres dropdb -U postgres app
docker exec ps-postgres createdb -U postgres app
gunzip -c /tmp/restore/deploy/backups/latest/postgres.sql.gz \
  | docker exec -i ps-postgres psql -U postgres -d app -v ON_ERROR_STOP=1
just deploy
```

(Use the `POSTGRES_USER` / `POSTGRES_DB` values from `/deploy/.env` if you changed them.)

## base-website photos (Garage)

Copies the restored files back into the bucket. Existing objects with the same name are overwritten; nothing else is deleted.

```bash
set -a; . /deploy/.env; set +a
docker run --rm --network ps_app \
  -e RCLONE_S3_ACCESS_KEY_ID="$S3_ACCESS_KEY" -e RCLONE_S3_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
  -e RCLONE_CONFIG=/tmp/rclone.conf \
  -v /tmp/restore/deploy/backups/latest/photos:/restore:ro \
  rclone/rclone:1 copy /restore ":s3:${S3_BUCKET:-photos}" \
  --s3-provider Other --s3-endpoint http://garage:3900 --s3-region us-east-1
```

## Paperless

The importer needs an **empty** Paperless of the **same version** as the export (check `manifest.json` / `metadata.json`).

```bash
cd ~/docker/paperless
docker compose down -v                               # ⚠ wipes current Paperless data
docker compose up -d
rsync -a --delete /tmp/restore/home/*/docker/paperless/export/ ./export/
docker compose exec -T webserver document_importer ../export
```

## .env files

They're in the snapshot at their original paths, e.g. `/tmp/restore/deploy/.env`. Copy back only what you need.

## Whole server lost

1. Install Debian, Docker, `just`, `restic`.
2. Clone `base-website` to `/deploy`, `edge-proxy` to `~/docker/proxy`, this repo to `~/docker/backups`. Recreate `~/docker/paperless` from its compose file.
3. Recreate this repo's `.env` and `restic-password` from your password manager, then `restic restore latest --target /tmp/restore`.
4. Copy each `.env` back from `/tmp/restore`.
5. `docker network create proxy`, start base-website (`just deploy`), then restore the database and photos as above.
6. Start the edge proxy (`just up`) and Paperless, then import Paperless.
7. `just install` here to resume nightly backups.

## Cleanup

```bash
rm -rf /tmp/restore
```
