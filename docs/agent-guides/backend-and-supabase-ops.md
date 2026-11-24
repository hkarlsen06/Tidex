# Production server, Convex, and retained Supabase operations

Read this guide before accessing `one-s`, deploying Convex, touching dev Colima Convex, or making an authorized legacy Supabase/SQL change.

## Supabase Production Access

Agents may access production directly with `ssh one-s`. Always use that alias.
`~/.ssh/config` sets the user to `administrator` and sets
`HostKeyAlias 85.190.118.114`, which is the name the host key is stored under in
`known_hosts`. Connecting to the raw Tailscale IP (`100.109.207.90`) skips both
settings and fails with "Permission denied" or "Host key verification failed".
`administrator` is not in the `docker` group, so every `docker` command needs
`sudo` (passwordless).

The Tidex stack is at `/srv/tidex/tidex-sb`. Use `sudo docker compose` there to
inspect logs and services or make task-authorized service changes, and use
`sudo docker compose exec -T db psql -U postgres -d postgres` for direct
database inspection or task-authorized data mutations. Direct SSH is the normal
production access path, so do not block on Supabase MCP or the hosted dashboard.

After changing auth, its configuration, Caddy, or Compose, run
`ssh one-s sudo /srv/tidex/auth-smoke.sh`. This compatibility command runs
`/srv/tidex/healthcheck.py --legacy-refresh`, checking Convex, Clerk, calendar
routing and the retained GoTrue route. Success is silent. The source is
`backend/ops/healthcheck.py`; the wrapper is `supabase/ops/auth-smoke.sh`.
It needs root access to read the legacy API key.

The one-s watchdog runs every five minutes and emails failures. Its source is
`backend/ops/one-s-watchdog.sh`, deployed as `/srv/backup/watchdog.sh`.
It checks the three retained Supabase containers, both production Convex
backends, backup freshness and host capacity. Update its explicit service
checks when retiring the bridge. Keep Paeonia's checks intact.

one-s has 4 vCPU and 8 GB RAM. Tidex and Paeonia share the host with agent
sessions. The resolved Supabase Compose file puts retired services in the
`retired` profile with `restart: no`. Normal Compose startup keeps only
`db`, `auth` and `api-gw` running.

Tidex's production Convex deployment runs in `/srv/tidex/convex`
on one-s, with the Compose project name `tidex-convex`. Keep that name, because
Paeonia's stack is also in a folder called `convex`. The API is
`convex.tidex.no` on port 3220, HTTP actions are on `actions.tidex.no` on 3221,
and the dashboard is on the tailnet-only `convex-dashboard.tidex.no` on 6792.
`/srv/backup/tidex-convex-backup.sh` backs it up to `/srv/tidex/convex-backups`
and R2, and the watchdog checks it. Deploy from `backend/` on `main`
with `bun run deploy`, which reads the URL and admin key from the
gitignored `backend/.env.production`.

For hosted Convex runtime upgrades, allocator changes, or rollback, read
[the runtime upgrade procedure](../../backend/ops/convex-runtime/README.md). Production
uses the pinned November 12, 2026 release with packaged jemalloc. Keep its build
source and image manifest in recovery config archives.

The dev deployment runs on the Mac under colima, from `backend/dev/compose.yml`
on `127.0.0.1:3210` (dashboard on 6791). Start it with `colima start` and
`docker compose -f dev/compose.yml --env-file dev/.env up -d` from `backend/`.
The gitignored `backend/.env.local` points at it, so `bunx convex dev` never
touches production. It trusts the development Clerk instance. The development
Clerk secret key is in `Secrets/Tidex/clerk-dev.env` next to `asc.env`.
Convex publishes its images under `ghcr.io/convex/`. The old
`ghcr.io/get-convex/` path refuses pulls.

The HTTP routes are in `backend/convex/http.ts`: `/health`, message images
(`/attachments`), profile pictures (`/profile-picture`), the calendar feed
(`/calendar-feed/<token>.ics`) and the MCP server for AI agents (`/mcp`, see
[docs/mcp-server.md](../mcp-server.md)). The push and Live Activity
senders in `push.ts` and `liveActivities.ts` must stay in Convex's default
runtime, because APNs needs HTTP/2 and fetch in the Node runtime (`"use node"`)
can't speak it. Each deployment's environment holds `CLERK_JWT_ISSUER_DOMAIN`,
`CLERK_SECRET_KEY`, the `APNS_*` keys and `GOTRUE_JWKS`. Set them with
`bunx convex env set` and pipe secrets in on stdin, so they never reach the
shell history or the chat. `APNS_RECIPIENTS` decides who a deployment may push
to: `all`, or user IDs separated by commas. Unset sends nothing. Production uses
`all` after cutover, and Supabase's push cron stays disabled. Development must
stay unset or restricted to a test account because it holds copies of real
device tokens. APNs provider tokens persist in the internal-only
`apns_provider_tokens` table; action-local memory does not preserve them between
invocations.

`backend/scripts/migrate.ts` copies Supabase into a Convex deployment and a
Clerk instance. It reads one-s read-only and replaces every Convex table and
file, so never point it at production after cutover. The development Clerk
instance holds at most 100 users, so dev runs use `--clerk-only <uuids>` or
`--skip-clerk`.

On one-s, `.env` sets `COMPOSE_FILE=compose-migration.json`. That file is a
fully resolved config written during the move from `mdr`, with every value
from `.env`, `gotrue-extra.env` and `functions-secrets.env` copied in. Editing
those env files changes nothing until you make the same edit in
`compose-migration.json`. Back up the JSON file, edit the value there and in the
env file, run `sudo docker compose up -d <service>`, then confirm the live
value with `sudo docker compose exec -T auth env`.

Use migrations rather than ad hoc SQL for schema changes. Do not run remote
Supabase CLI database commands (`db push`, `db pull`, `migration repair`,
`--linked`, `--db-url`) against production. The production database has no
`supabase_migrations.schema_migrations` table, so `db push` would try to
replay every migration.

## Supabase Edge Functions

These functions are retained source only. Their production container is retired and all Supabase cron jobs stay disabled. Use the instructions below only for an explicitly authorized legacy restore.

**CRITICAL: Edit locally in `supabase/functions/`, then deploy to the self-hosted stack on `one-s`, NOT via Supabase's hosted deployment or MCP deploy tools**

- **Location**: `supabase/functions/<function-name>/index.ts`
- **Shared code**: `supabase/functions/_shared/`
- **Deployment**: Sync the function to `/srv/tidex/tidex-sb/volumes/functions/` on `one-s` and restart the `functions` service
- **Imports**: type-only imports from Node built-ins need the `node:` prefix (`"node:crypto"`, not `"crypto"`). The self-hosted edge runtime fails on the bare name.
- **Tests**: From `supabase/functions` run `bunx deno@2.9.6 test -A --frozen <file>`, and use `check` the same way. The older `deno-bin` runner cannot typecheck the current Apple SDK's Node crypto types.

**JWT enforcement:**

The router at `supabase/ops/edge-router/main/` (deployed as `volumes/functions/main/` on `one-s`) enforces JWTs. It ignores the `VERIFY_JWT` env var and `verify_jwt` in `supabase/config.toml`, which only matter for `supabase functions serve`. Keep both in sync with the router's `PUBLIC_FUNCTIONS` list.

- Public, no JWT check: `apple-server-notifications` (Apple signature), `before-user-created` (Standard Webhooks signature), `calendar-feed` (calendar token), `health` (retired monitoring endpoint), `wagey-chat-v2` (shutdown stub for old app versions). A new webhook or public function must be added to `PUBLIC_FUNCTIONS` in the router and to `config.toml` with `verify_jwt = false`.
- Uptime Kuma on depressed-louis now checks the Convex API, `actions.tidex.no/health`, Clerk and the website. The relay reads current iPhone registrations through the internal `monitoring:uptimeDevices` query. See [aftercare](../convex-aftercare.md) for source and deployment paths.
- Every other function needs a valid, unexpired JWT with role `authenticated` or `service_role`. The router accepts ES256/RS256 tokens signed with a key in `SUPABASE_JWKS` (what GoTrue issues) and HS256 tokens signed with `JWT_SECRET` (the legacy service role key that pg_cron sends from the vault). The router rejects the `sb_publishable_` key and the anon JWTs, so a signed-out call fails on protected functions.
- The router returns 404 for any first path segment that is not a directory under `volumes/functions/` with an `index.ts` (so `_shared`, `main` and `node_modules` are not routable).
- Functions still check the caller themselves, for example with `withSupabase({ auth: "user" })`. The router is the first check, not the only one.
- To deploy the router, copy `supabase/ops/edge-router/main/` to `/srv/tidex/tidex-sb/volumes/functions/main/` on `one-s`, back up the old files first, and restart the `functions` service. Run `ssh one-s sudo /srv/tidex/auth-smoke.sh`. Keep legacy push cron disabled while Convex sends production notifications.

## Supabase SQL Functions & Cron Jobs

**Locations:**

- SQL function source files: `supabase/sql/functions/<category>/*.sql`
- Cron job docs: `supabase/sql/cron/*.md`
- Migration files: `supabase/migrations/*.sql`

**CRITICAL:**

- Write migrations to `supabase/migrations/`.
- Do not treat `supabase/sql/migrations/` as the migration directory.
- Keep the SQL source files in `supabase/sql/functions/` in sync with the actual database definitions when making changes.

### Migration-only schema policy

Keep `[db.migrations].schema_paths = []`. Do not introduce `supabase/schemas/`, declarative sync, or a pg-delta gate until the documented prerequisites are met. The existing migration history cannot safely establish a clean baseline. Use exact read-only inventories for production-state comparison. Preserve hand-written transitions and never infer authorization for migration-history repair from ordinary schema work.

Before revisiting adoption or planning a history cutover, read [the decision and prerequisites](../supabase-declarative-schema-decision.md).

**Recommended workflow:**

1. Edit function/trigger source files in `supabase/sql/functions/` as needed.
2. Add or update the corresponding migration in `supabase/migrations/`.
3. Dry-run it on production by wrapping the file in `BEGIN;` and `ROLLBACK;` and piping it to `ssh one-s "cd /srv/tidex/tidex-sb && sudo docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1"`.
4. Apply it with the same command plus `--single-transaction`, reading the migration file on stdin, then verify the result with a read-only query.

**Retained Supabase cron jobs, all disabled after the Convex cutover:**

| Job Name                            | Schedule            | Description                            |
| ----------------------------------- | ------------------- | -------------------------------------- |
| `cleanup-shift-notification-events` | `0 4 * * 0`         | Clean retained notification outbox rows |
| `daily_purge_soft_deletes`          | `30 3 * * *`        | Purge expired soft-deleted records     |
| `process-pending-push-notifications` | `* * * * *`        | Drain queued push notifications        |
| `purge-messaging-sync-events-v2`    | `0 4 * * *`         | Purge expired messaging sync events    |
| `process-live-activities`           | `1,16,31,46 * * * *` | Process Live Activity updates          |
| `purge-auth-diagnostic-events`      | `45 4 * * 0`        | Purge auth diagnostics older than 90 days |
| `purge-app-activity-hours`          | `50 4 * * *`        | Purge hourly app activity older than 32 days |
| `purge-cron-run-details`            | `20 4 * * *`        | Purge pg_cron run history older than 10 days |

