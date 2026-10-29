# Cut over Tidex 3.1.0

Run this checklist only after Hjalmar approves the production cutover and App Store Connect shows 3.1.0 as Pending Developer Release. Preparing the App Review draft does not authorize this checklist. Do not release 3.1.0 before the final import.

Run local commands from the repository root. Keep the same terminal for the variables below. The source of truth stays in Supabase until the release step. Never run the migration script again after that step.

## Current checkpoint, 2026-10-29

Hjalmar authorized step 1, backups, maintenance, the API write freeze and cron drain. That step is complete. The final import, calendar and push switch, and App Store release have not run.

- App Store Connect confirms build `20261028.1856` is `PENDING_DEVELOPER_RELEASE` with manual release.
- The public gate is `minimumVersion: 3.0.0`, `maintenance: true`. Hjalmar confirmed the maintenance screen on his phone.
- Caddy installed the Supabase-calendar freeze at `20:03:38 UTC`. Live probes on both API hostnames confirm that refresh reaches GoTrue, calendar requests reach the existing endpoint, and the other tested API routes abort.
- All eight Supabase cron jobs were disabled at `20:05:52 UTC`. At `20:07:02 UTC`, active jobs, running jobs and queued HTTP requests were all zero.
- Convex push delivery remains disabled. The Clerk audit found 251 users, none without `external_id`, and one imported account with Apple or Google connections. No Clerk users were changed.

The original gate, Caddy configuration and cron states, a full Convex export with files, its environment, and validated Supabase database archives from before and after the freeze are saved on both machines. The database archive and Convex export checksums match across the copies. The files contain private data and credentials.

On the Mac, resume with this existing directory. Do not rerun the preparation commands and replace the original rollback state with the frozen state.

```bash
CUTOVER='/Users/hkarlsen06/Library/Application Support/Tidex/cutovers/20261029T195639Z'
```

The second copy is root-only at `/srv/tidex/cutovers/20261029T195639Z` on one-s. `clerk.env` is prepared for the final import. Wait for Hjalmar's authorization for that next step. The ordinary auth smoke check now reports the expected blocked settings and password-reset routes.

## Check Apple sign-in requirements

Apple users may have no email. Confirm that email stays optional and supplied addresses still require verification.

```bash
python3 - <<'PY'
import json, urllib.request
request = urllib.request.Request('https://clerk.tidex.no/v1/environment?_is_native=true', headers={'User-Agent': 'Tidex readiness verification'})
with urllib.request.urlopen(request, timeout=20) as response:
    settings = json.load(response)['user_settings']
email = settings['attributes']['email_address']
apple = settings['social']['oauth_apple']
assert email['enabled'] and not email['required'] and email['verify_at_sign_up']
assert apple['enabled'] and apple['authenticatable']
print('Clerk Apple sign-in is enabled and email is optional')
PY
```

## Prepare the rollback files

```bash
umask 077
CUTOVER="$(mktemp -d /tmp/tidex-cutover.XXXXXX)"
cp marketing/public/app-config.json "$CUTOVER/app-config.json"
ssh one-s sudo cat /etc/caddy/Caddyfile > "$CUTOVER/Caddyfile"
ssh one-s 'cd /srv/tidex/tidex-sb && sudo docker compose exec -T db psql -U postgres -d postgres -At -v ON_ERROR_STOP=1' > "$CUTOVER/cron.json" <<'SQL'
select coalesce(json_agg(json_build_object('jobid', jobid, 'active', active)), '[]') from cron.job;
SQL
scp supabase/ops/convex-cutover.py one-s:/tmp/tidex-convex-cutover.py
scp supabase/ops/convex-cutover.py supabase/ops/test-convex-cutover.py one-s:/tmp/
ssh one-s python3 /tmp/test-convex-cutover.py
scp "$CUTOVER/Caddyfile" one-s:/tmp/tidex-before-cutover.Caddyfile
```

Save the deployment and file-storage backup before replacing the rehearsal.

```bash
cd backend
bunx convex export --include-file-storage --path "$CUTOVER/convex-before.zip" --env-file .env.production
bunx convex env list --env-file .env.production | cut -d= -f1
cd ..
```

Confirm `APNS_RECIPIENTS` is absent. Obtain the existing production Clerk key without displaying it.

```bash
cd backend
printf 'CLERK_SECRET_KEY=' > "$CUTOVER/clerk.env"
bunx convex env get CLERK_SECRET_KEY --env-file .env.production >> "$CUTOVER/clerk.env"
cd ..
```

List Clerk users without `external_id` and imported users with an Apple or Google connection. Follow phase 3 of [the migration plan](convex-migration-plan.md) if rehearsal sign-ins left any aliases. Delete only confirmed rehearsal users without `external_id`. The 2026-10-28 audit found none. It found one imported developer account with Apple and Google connections.

## Enter maintenance and freeze writes

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path('marketing/public/app-config.json')
d = json.loads(p.read_text())
d['maintenance'] = True
p.write_text(json.dumps(d, indent=2) + '\n')
PY
bun run pages:deploy:marketing
curl -fsS https://tidex.no/app-config.json
```

Wait until Hjalmar's phone shows maintenance. Then make Caddy abort old API requests. Calendar subscriptions and GoTrue token refresh remain available. The ordered `route` prevents another handler from accepting writes.

```bash
ssh one-s 'python3 /tmp/tidex-convex-cutover.py --source /tmp/tidex-before-cutover.Caddyfile --output /tmp/tidex-freeze.Caddyfile --calendar supabase && sudo caddy adapt --config /tmp/tidex-freeze.Caddyfile --adapter caddyfile >/dev/null'
ssh one-s "sudo bash -c 'set -a; . /etc/caddy/cloudflare.env; caddy validate --config /tmp/tidex-freeze.Caddyfile --adapter caddyfile'"
ssh one-s 'sudo install -m 644 /tmp/tidex-freeze.Caddyfile /etc/caddy/Caddyfile && sudo systemctl reload caddy'
ssh one-s sudo /srv/tidex/auth-smoke.sh
```

The normal auth smoke check reports intentionally blocked login, REST, and function endpoints during maintenance. A refresh request must still reach GoTrue. Check the routing without using a real token.

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X POST 'https://api.tidex.no/auth/v1/token?grant_type=refresh_token' -H 'Content-Type: application/json' --data '{"refresh_token":"cutover-routing-probe"}'
curl --max-time 10 'https://api.tidex.no/rest/v1/profiles'
```

The refresh probe returns a GoTrue 4xx response. The REST probe gets a closed connection or a Cloudflare origin error. A Postgres permission error is not a freeze.

Disable cron before the copy, so scheduled work cannot change the source while tables are read.

```bash
ssh one-s 'cd /srv/tidex/tidex-sb && sudo docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1' <<'SQL'
select cron.alter_job(jobid, active := false) from cron.job where active;
select count(*) as running_jobs from cron.job_run_details where status = 'running';
select count(*) as queued_http_requests from net.http_request_queue;
SQL
```

Repeat the last two read-only queries until both counts are zero. Allow 30 seconds for HTTP work already dispatched to finish. Do not import while a write or push job remains active.

## Import the final data

The backend must already be deployed and the purchase tables removed by the rehearsal refresh. Do not use `refresh-rehearsal.sh` during maintenance, because it deliberately refuses a cutover in progress.

```bash
cd backend
bun scripts/migrate.ts --env-file .env.production --clerk-env "$CUTOVER/clerk.env" > "$CUTOVER/migration.log" 2>&1
tail -n 8 "$CUTOVER/migration.log"
cd ..
```

Stop if the command fails or does not end with `All counts match`. Keep maintenance on and fix the import or roll back. If Clerk refuses swapped email addresses or more than 20 stale users, inspect the identities before allowing any deletion.

Sign out and back in on every phone that used the rehearsal TestFlight build. Its old sync cursors refer to the replaced copy.

## Switch calendar feeds and push delivery

```bash
ssh one-s 'python3 /tmp/tidex-convex-cutover.py --source /tmp/tidex-before-cutover.Caddyfile --output /tmp/tidex-convex.Caddyfile --calendar convex && sudo caddy adapt --config /tmp/tidex-convex.Caddyfile --adapter caddyfile >/dev/null'
ssh one-s "sudo bash -c 'set -a; . /etc/caddy/cloudflare.env; caddy validate --config /tmp/tidex-convex.Caddyfile --adapter caddyfile'"
ssh one-s 'sudo install -m 644 /tmp/tidex-convex.Caddyfile /etc/caddy/Caddyfile && sudo systemctl reload caddy'
ssh one-s sudo /srv/tidex/auth-smoke.sh
cd backend
bunx convex env set APNS_RECIPIENTS all --env-file .env.production
cd ..
```

Leave the Supabase cron jobs disabled. With the final TestFlight build, check sign-in, shifts, pay, messaging, one push and a saved calendar subscription refresh. Keep any feed URL out of logs and chat because it contains its access token.

## Release 3.1.0

This is the point of no return. Confirm the smoke checks passed. In App Store Connect, release 3.1.0 manually with phased release disabled. Then run:

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path('marketing/public/app-config.json')
d = json.loads(p.read_text())
d.update(minimumVersion='3.1.0', maintenance=False)
p.write_text(json.dumps(d, indent=2) + '\n')
PY
bun run pages:deploy:marketing
curl -fsS https://tidex.no/app-config.json
```

Check the old app shows the update gate and the new app signs in. App Store propagation can leave some regions waiting for the update. Commit the gate change signed after verification. Do not push unless Hjalmar asks. Clear completed release checks only after the release ships.

Keep GoTrue refresh and the read-only Supabase data for the retirement period in the migration plan. Remove the obsolete App Store Server Notifications URL when retiring the old subscription receiver.

## Roll back before release

Run these commands only before releasing 3.1.0. Disable Convex push delivery before re-enabling Supabase cron, so both systems cannot send the same alerts.

```bash
cd backend
bunx convex env remove APNS_RECIPIENTS --env-file .env.production
cd ..
scp "$CUTOVER/Caddyfile" one-s:/tmp/tidex-rollback.Caddyfile
ssh one-s 'sudo install -m 644 /tmp/tidex-rollback.Caddyfile /etc/caddy/Caddyfile && sudo systemctl reload caddy'
python3 - "$CUTOVER/cron.json" <<'PY' | ssh one-s 'cd /srv/tidex/tidex-sb && sudo docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1'
import json, sys
for job in json.load(open(sys.argv[1])):
    print(f"select cron.alter_job({int(job['jobid'])}, active := {str(bool(job['active'])).lower()});")
PY
cp "$CUTOVER/app-config.json" marketing/public/app-config.json
bun run pages:deploy:marketing
ssh one-s sudo /srv/tidex/auth-smoke.sh
```

Verify the old app works before leaving maintenance. The Convex rehearsal can remain in place for another attempt. After release, fix forward. Do not run the import or rollback commands against user writes in Convex.
