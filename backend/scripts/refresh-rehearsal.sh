#!/usr/bin/env bash
# Replaces the isolated Convex/Clerk rehearsal. Never run after the App Store cutover.
set -euo pipefail

if [ "$#" -ne 2 ] || [ "$1" != "--replace-rehearsal" ]; then
  echo "Usage: $0 --replace-rehearsal <file containing production CLERK_SECRET_KEY>" >&2
  exit 2
fi
CLERK_ENV="$2"
[ -f "$CLERK_ENV" ] || { echo "Clerk environment file not found" >&2; exit 2; }
cd "$(dirname "$0")/.."
python3 - .env.production <<'PY'
import pathlib, sys
values = dict(line.split('=', 1) for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if '=' in line and not line.startswith('#'))
if values.get('CONVEX_SELF_HOSTED_URL', '').strip('"\'') != 'https://convex.tidex.no':
    raise SystemExit('Expected the isolated production rehearsal deployment')
PY
curl -fsS --max-time 20 https://tidex.no/app-config.json | python3 -c '
import json, sys
gate = json.load(sys.stdin)
version = tuple(map(int, gate["minimumVersion"].split(".")))
if version >= (3, 1, 0) or gate["maintenance"]:
    raise SystemExit("Refusing rehearsal replacement during or after cutover")
'
ENVIRONMENT="$(bunx convex env list --env-file .env.production)"
if printf '%s\n' "$ENVIRONMENT" | cut -d= -f1 | grep -qx APNS_RECIPIENTS; then
  echo "Refusing to replace a deployment with push recipients enabled" >&2
  exit 1
fi
umask 077
WORK="$(mktemp -d /tmp/tidex-rehearsal.XXXXXX)"
echo "Rehearsal backup and logs: $WORK"
bunx convex export --include-file-storage --path "$WORK/before.zip" --env-file .env.production

# The old schema rejects the new profile shape. Empty the rehearsal, deploy the new
# schema, then remove tables that the new schema no longer declares.
bunx convex import --table profiles --replace-all --format jsonLines /dev/null -y --env-file .env.production
bun run deploy
bunx convex import --table profiles --replace-all --format jsonLines /dev/null -y --env-file .env.production
bun scripts/migrate.ts --env-file .env.production --clerk-env "$CLERK_ENV" >"$WORK/migration.log" 2>&1 || {
  echo "Migration failed. Inspect $WORK/migration.log; backup is $WORK/before.zip" >&2
  exit 1
}
bunx convex data --env-file .env.production >"$WORK/tables.txt"
if grep -Ex 'subscriptions|app_account_tokens|apple_notifications|apple_orphan_notifications|paywall_config' "$WORK/tables.txt"; then
  echo "Retired purchase tables survived the rehearsal refresh" >&2
  exit 1
fi
tail -n 4 "$WORK/migration.log"
echo "Rehearsal refreshed. Sign out and back in on rehearsal TestFlight phones to reset sync cursors."
