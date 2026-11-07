#!/bin/bash
# Paeonia self-hosted Convex backup. Usage: paeonia-backup.sh [db-only]
#   paeonia-backup.sh          nightly: snapshot export with file storage, plus the
#                              config needed to rebuild the stack, copied offsite
#   paeonia-backup.sh db-only  hourly: snapshot export without files, local only
# Restore: fresh backend, `convex env set --from-file`, deploy main, then
# `convex import --replace-all <export.zip>`. See backend/AGENTS.md in the Paeonia repo.
set -euo pipefail
umask 077
MODE="${1:-full}"
source /srv/backup/paeonia.conf   # STACK_DIR, CLI_DIR, DEST, KEEP, KEEP_HOURLY, [OFFSITE_REMOTE, OFFSITE_KEEP_DAYS]

export CONVEX_SELF_HOSTED_URL=http://127.0.0.1:3210
CONVEX_SELF_HOSTED_ADMIN_KEY="$(cat "$STACK_DIR/admin-key")"
export CONVEX_SELF_HOSTED_ADMIN_KEY
convex() { (cd "$CLI_DIR" && ./node_modules/.bin/convex "$@"); }

TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DEST"

if [ "$MODE" = "db-only" ]; then
  OUT="$DEST/export-hourly-$TS.zip"
  convex export --path "$OUT" >/dev/null
  python3 -m zipfile -t "$OUT" >/dev/null
  ls -t "$DEST"/export-hourly-*.zip | tail -n +$((KEEP_HOURLY+1)) | xargs -r rm
  echo "OK paeonia hourly export=$(du -h "$OUT" | cut -f1)"
  exit 0
fi

# ponytail: every night downloads all files from R2. Sync the files bucket instead once media reaches several GB.
OUT="$DEST/export-$TS.zip"
convex export --include-file-storage --path "$OUT" >/dev/null
python3 -m zipfile -t "$OUT" >/dev/null

# The instance secret, admin key and Convex env vars are needed to bring the deployment back.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
convex env list > "$WORK/convex.env"
# Locally packaged runtime images need their pinned build inputs on recovery.
RUNTIME=()
if [ -d /srv/convex-runtime/source ]; then
  RUNTIME+=(srv/convex-runtime/source)
  while IFS= read -r manifest; do RUNTIME+=("${manifest#/}"); done < <(
    find /srv/convex-runtime/build -name images.json -type f -print
  )
fi
CONFIG_OUT="$DEST/config-$TS.tar.gz"
tar -czf "$CONFIG_OUT" -C "$WORK" convex.env -C / \
  "${STACK_DIR#/}/.env" "${STACK_DIR#/}/admin-key" "${STACK_DIR#/}/docker-compose.yml" \
  srv/backup/paeonia.conf srv/backup/paeonia-backup.sh "${RUNTIME[@]}"
gzip -t "$CONFIG_OUT"

ls -t "$DEST"/export-[0-9]*.zip | tail -n +$((KEEP+1)) | xargs -r rm
ls -t "$DEST"/config-*.tar.gz | tail -n +$((KEEP+1)) | xargs -r rm
if [ -n "${OFFSITE_REMOTE:-}" ]; then
  rclone copy "$OUT" "$OFFSITE_REMOTE/paeonia/" --s3-no-check-bucket
  rclone copy "$CONFIG_OUT" "$OFFSITE_REMOTE/paeonia/" --s3-no-check-bucket
  rclone delete "$OFFSITE_REMOTE/paeonia/" --min-age "${OFFSITE_KEEP_DAYS}d" 2>/dev/null || true
  echo "offsite: synced to $OFFSITE_REMOTE/paeonia/"
fi
echo "OK paeonia export=$(du -h "$OUT" | cut -f1) config=$(du -h "$CONFIG_OUT" | cut -f1)"
