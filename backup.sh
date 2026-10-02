#!/usr/bin/env bash
# Nightly backup of this server to IDrive e2 with restic.
#
#   1. base-website: scripts/backup.sh → STAGING_DIR (postgres.sql.gz, photos/)
#   2. paperless:    document_exporter → PAPERLESS_DIR/export
#   3. restic backup of the above + every stack's .env
#   4. restic forget/prune per KEEP_* (plus a light integrity check on Sundays)
#   5. healthchecks.io ping: /start, success, or /fail with the log tail
#
# Runs as root from systemd (needs docker). Config comes from .env next to this
# script. Any failure stops the run and reports it; nothing fails silently.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

if [ ! -f .env ]; then
  echo "ERROR: $HERE/.env missing (cp .env.example .env)" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${RESTIC_REPOSITORY:?}" "${RESTIC_PASSWORD_FILE:?}"
: "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}"
: "${BASE_WEBSITE_DIR:?}" "${STAGING_DIR:?}"
PAPERLESS_DIR="${PAPERLESS_DIR:-}"
EDGE_PROXY_DIR="${EDGE_PROXY_DIR:-}"
FAIL_ON_SKIP="${FAIL_ON_SKIP:-true}"
HC_PING_URL="${HC_PING_URL:-}"

# One run at a time (a slow first upload must not overlap the next night).
exec 9>"/tmp/server-backups.lock"
if ! flock -n 9; then
  echo "ERROR: another backup run is still in progress" >&2
  exit 1
fi

LOG="$(mktemp)"
exec > >(tee -a "$LOG") 2>&1

ping_hc() { # $1 = "" | /start | /fail ; body from stdin
  if [ -z "$HC_PING_URL" ]; then cat >/dev/null; return 0; fi
  curl -fsS -m 10 --retry 3 --data-binary @- "${HC_PING_URL}$1" >/dev/null || true
}

finish() {
  local code=$?
  set +e
  if [ "$code" -eq 0 ]; then
    tail -c 10000 "$LOG" | ping_hc ""
  else
    echo "✗ Backup FAILED (exit $code)"
    tail -c 10000 "$LOG" | ping_hc /fail
  fi
  rm -f "$LOG"
  exit "$code"
}
trap finish EXIT

echo "" | ping_hc /start
echo "=== server-backups $(date -Is) ==="

# ── 1. base-website ──────────────────────────────────────────────────────────
echo "→ base-website: dumping Postgres + mirroring photos"
BW_OUT="$(BACKUP_DIR="$STAGING_DIR" bash "$BASE_WEBSITE_DIR/scripts/backup.sh" 2>&1)" || {
  echo "$BW_OUT"
  echo "ERROR: base-website backup failed" >&2
  exit 1
}
echo "$BW_OUT"
if [ "$FAIL_ON_SKIP" = "true" ] && grep -q "^SKIPPED:" <<<"$BW_OUT"; then
  echo "ERROR: base-website skipped a step (FAIL_ON_SKIP=true)" >&2
  exit 1
fi

# ── 2. paperless ─────────────────────────────────────────────────────────────
PATHS=("$STAGING_DIR")
if [ -n "$PAPERLESS_DIR" ]; then
  echo "→ paperless: exporting documents"
  docker compose -f "$PAPERLESS_DIR/docker-compose.yml" exec -T webserver \
    document_exporter ../export --delete
  if [ ! -f "$PAPERLESS_DIR/export/manifest.json" ]; then
    echo "ERROR: paperless export has no manifest.json" >&2
    exit 1
  fi
  PATHS+=("$PAPERLESS_DIR/export")
fi

# ── 3. restic backup ─────────────────────────────────────────────────────────
for f in "$BASE_WEBSITE_DIR/.env" "${PAPERLESS_DIR:+$PAPERLESS_DIR/.env}" \
         "${EDGE_PROXY_DIR:+$EDGE_PROXY_DIR/.env}" "$HERE/.env"; do
  [ -n "$f" ] && [ -f "$f" ] && PATHS+=("$f")
done

echo "→ restic: backing up ${#PATHS[@]} paths"
# Output goes through tee/journald, not a terminal, so restic would otherwise
# stay silent until done. Print a progress line every minute instead.
export RESTIC_PROGRESS_FPS="${RESTIC_PROGRESS_FPS:-0.0167}"
printf '   %s\n' "${PATHS[@]}"
restic backup --tag nightly --no-scan "${PATHS[@]}"

# ── 4. retention + integrity ─────────────────────────────────────────────────
echo "→ restic: applying retention"
restic forget --tag nightly \
  --keep-daily "${KEEP_DAILY:-7}" \
  --keep-weekly "${KEEP_WEEKLY:-4}" \
  --keep-monthly "${KEEP_MONTHLY:-12}" \
  --prune

if [ "$(date +%u)" = "7" ]; then
  echo "→ restic: weekly check (reads 2% of data)"
  restic check --read-data-subset=2%
fi

echo "✓ Backup complete $(date -Is)"
