#!/usr/bin/env bash
# Restores the latest snapshot into a temp folder and checks that the pieces
# needed for a real restore are present and readable. Deletes the temp folder.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
. ./.env
set +a

DEST="$(mktemp -d)"
trap 'rm -rf "$DEST"' EXIT
fail=0

if [ "$(restic snapshots --json --latest 1 2>/dev/null | tr -d '[:space:]')" = "[]" ]; then
  echo "No snapshots yet: run a backup first (just run-foreground)."
  exit 1
fi

echo "→ Restoring latest snapshot to $DEST"
restic restore latest --target "$DEST" >/dev/null

check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }

DUMP="$DEST$STAGING_DIR/postgres.sql.gz"
check "postgres dump decompresses" "gzip -t '$DUMP' 2>/dev/null"
check "postgres dump contains CREATE TABLE" "gzip -dc '$DUMP' | grep -q 'CREATE TABLE'"
PHOTOS="$(find "$DEST$STAGING_DIR/photos" -type f 2>/dev/null | wc -l)"
check "photos present ($PHOTOS files)" "[ '$PHOTOS' -gt 0 ]"
if [ -n "${PAPERLESS_DIR:-}" ]; then
  check "paperless manifest.json present" "[ -s '$DEST$PAPERLESS_DIR/export/manifest.json' ]"
fi
check "base-website .env present" "[ -s '$DEST$BASE_WEBSITE_DIR/.env' ]"

if [ "$fail" -eq 0 ]; then echo "✓ Restore test passed"; else echo "✗ Restore test FAILED"; exit 1; fi
