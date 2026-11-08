# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Builds and tests (read this first)

Every agent, subagents included, builds and runs the app and its tests itself to prove its change works. Reading the code is not proof. Never hand the user a check you could run yourself.

- Use the wrappers only, never raw `xcodebuild`. They share one machine-wide lock, `/tmp/xcode-agent.lock`, across Tidex, Paeonia, Kvil and Notex, so parallel agents queue instead of colliding. The test wrapper holds it only while it builds, then tests under a simulator's lock, so another agent compiles while your tests run. If a run prints `waiting for another agent's xcodebuild` or `[lock] waiting.`, wait. Do not kill the other run or set `XCODE_AGENT_NO_LOCK=1`.
- Run a wrapper in the foreground with a 600000 ms timeout. That is how you wait for a long run, so do not write `sleep` loops to poll one. The wrapper's last line is a summary such as `SUMMARY: SUCCESS queued=312s compiled=95s tested=140s simulator="Shared iPhone 2"`, where `queued` is the time it waited for other agents and for a simulator to boot.
- Run the smallest set of tests that proves the change, filtered with `-only-testing:<Target>/<Class>` where possible. The test wrapper builds the app itself, so do not run the build wrapper first.
- Run UI tests (`TidexAppUITests`) when the change alters a journey they walk. Unfiltered runs skip them, so name the class with `-only-testing:TidexAppUITests/<Class>`.
- UI journeys using the `app-store-screenshots` fixture require a shared simulator because the fixture is disabled on physical devices. Run them separately from device unit tests with `XCODE_TEST_AGENT_DESTINATION` unset.
- Run on a connected device, or on a shared simulator when none is connected. [Devices and simulators](#devices-and-simulators) below says how. Do not open Simulator.app.
- The lock does not see the Xcode app. If a run fails with `build.db: database is locked`, Hjalmar is probably building in Xcode. Wait a minute and retry.
- `XCODE_AGENT_NICE` and `XCODE_AGENT_JOBS` are for the user to set, not you.
- Write a test only when [Tests](#tests) calls for one, and run it.
- **Handoff.** Name the builds and tests you ran and their results. List only the checks you could not run, such as a feature the simulator lacks, and say why.

### Devices and simulators

Agents in several repos share this Mac, and simulators created by agents once filled its disk. Whenever the app or tests run:

- Use a connected device first. `xcrun xctrace list devices` lists them. Pick an iPhone or iPad under `== Devices ==`, not the Mac and not one under `== Devices Offline ==`, and pass it as `platform=iOS,id=<UDID>`, for example `XCODE_TEST_AGENT_DESTINATION="platform=iOS,id=<UDID>" ./scripts/xcode-test-agent.sh`. If the device is locked, use a shared simulator and say so in the handoff.
- If no device is connected, leave `XCODE_TEST_AGENT_DESTINATION` unset. The test wrapper then tests on a free shared simulator, or on the one your worktree holds.
- Use the three shared simulators, `Shared iPhone`, `Shared iPhone 2` and `Shared iPhone 3`. Agents in every worktree and every repo on this Mac take them through `scripts/lock`. They are the three booted simulators this Mac allows, so use them instead of creating your own. They stay booted between tasks. To clear the app's data, uninstall it instead of erasing the simulator.
- Use `Shared iPhone SE` only for checking layouts on a small screen, and shut it down when you're done.
- Before every run on a simulator, the wrapper uninstalls Tidex there, on a shared simulator while it holds that simulator's lock. If a run fails with "test runner hung before establishing connection" or "failed to launch no.tidex.app", run it again through the wrapper.
- Before you drive a simulator by hand, take one with `SIM="$(scripts/lock acquire simulator)"`. It prints the name of a free shared simulator, boots it if needed, and waits while all three are busy. Start every simulator command with `SIM="$(scripts/lock acquire simulator)" &&` and use `"$SIM"` in it. While your worktree holds a simulator, the command returns that same one and counts as a use. A session nobody has used for 10 minutes goes stale, so a simulator you forget to release frees itself 10 minutes after your last command. When you're done, close your T3 Device panel session with `device_close` first, then release the simulator with `scripts/lock release simulator`. T3 keeps its own session on the simulator, and no other agent can open it in the Device panel until you close yours. Driving by hand covers the T3 Device panel (`device_open`), `agent-device`, `xcrun simctl install`, `launch` and `uninstall`, sign-in scripts and end-to-end play. The locks are machine-wide, so Paeonia agents share the same three simulators. `scripts/lock status` shows who holds each one. Never close or take over another agent's device session. Do not hold the xcodebuild lock to drive a simulator.
- On a physical device, the wrapper uninstalls nothing. If a run there fails that way, ask the user before uninstalling, because that deletes the app's data on the device.
- Do not download simulator runtimes or platforms, through `xcodebuild -downloadPlatform`, `xcrun simctl runtime add` or Xcode's Components settings. If a shared simulator is missing or no runtime is installed, report that in the handoff and finish the rest of the task.
- `./scripts/xcode-build-agent.sh` builds for the generic simulator destination. That needs no simulator or runtime, so these rules don't change it.

## Tests

Most of the test weight sits on end-to-end and integration tests that walk real user journeys and the backend contract. Unit tests are a thin layer for pure logic. Tests an agent writes for its own change mostly restate its own reading of the task, so they cost time and catch little.

**When to add a test.** Add or extend a test when the user asks for one, or when a change touches one of the unit-test areas listed below and no existing test would go red if the change were reverted. A bug fix in those areas gets a test that reproduces the bug. Every other change ships with the tests that already exist, and the handoff says so in one line.

**Which kind.** Pick the first kind that can see the behavior:

1. An end-to-end UI test in `ios/TidexAppUITests/` that walks a journey through the real app, such as `ShiftJourneyUITests`.
2. An integration test in `ios/TidexAppTests/` that drives real collaborators together: the in-memory `LocalStore`, repositories, the sync merge, view models with only the network edge faked. `SyncOfflineBehaviorTests` and `FriendsMessageOutboxTests` are examples.
3. A backend test next to the edge function in `supabase/functions/` for handlers and payload contracts, or a SQL script in `supabase/tests/` for RLS.
4. A unit test, for pure logic where a bug costs money, data or privacy and is hard to see on screen:
   - parsers and decoders for server, calendar (ICS) and file formats
   - date, time zone, pay period, cross-midnight and DST math
   - pay, overtime, tax, supplement and currency rules
   - security and authorization checks: who sees whose shifts, earnings and messages, user isolation, admin gating, auth routing
   - sync, merge, conflict, outbox and dedup logic

A test earns its place by checking an outcome a user would notice. Assertions on constants, enum raw values, mapping tables copied from the code, localized copy, mock call counts, layout, focus, gesture thresholds or animation restate the implementation, so leave those out.

**Failing tests.** A red test means the code or the test has a bug. Fix the code, or stop and report the failure with its output. Never delete, skip or loosen a failing test to get a green run, and never add `XCTSkip` or `XCTExpectFailure` for that purpose. Delete a test only when the user asks, or when the behavior it checks was removed on purpose.

## Project Overview

A monorepo for the Tidex iOS app and its supporting infrastructure.

Tidex is now an iOS-only product, and it has been free since 2026-09-28. The paywall and the Apple subscriptions are gone, so don't add purchase, entitlement or StoreKit code. The repository still includes supporting public/legal web surfaces and the shared backend. The `app.tidex.no` compatibility host was retired on 2026-11-08.

- **marketing/** - Next.js 16 public website for `tidex.no`
- **ios/** - Native iOS application

The iOS app uses Convex in `backend/` and Clerk authentication. The production cutover and manual release of 3.1.0 took place on 2026-10-29. Before migration or retirement work, read the [live cutover checkpoint](docs/convex-cutover-checklist.md#current-checkpoint-2026-10-29).

Supabase retains only Postgres, GoTrue and Envoy on `one-s` for source data and legacy session refresh. The other nine services were removed on 2026-10-29. Before changing that bridge, read [the aftercare record](docs/convex-aftercare.md). Public API writes and Supabase cron jobs are disabled. Caddy routes saved calendar URLs on `api.tidex.no` and `identity.tidex.no` to Convex. The former `mdr` host and hosted Supabase project are retired.

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
[the runtime upgrade procedure](backend/ops/convex-runtime/README.md). Production
uses the pinned November 6, 2026 release with packaged jemalloc. Keep its build
source and image manifest in recovery config archives.

The dev deployment runs on the Mac under colima, from `backend/dev/compose.yml`
on `127.0.0.1:3210` (dashboard on 6791). Start it with `colima start` and
`docker compose -f dev/compose.yml --env-file dev/.env up -d` from `backend/`.
The gitignored `backend/.env.local` points at it, so `bunx convex dev` never
touches production. It trusts the development Clerk instance. The development
Clerk secret key is in `Secrets/Tidex/clerk-dev.env` next to `asc.env`.
Convex publishes its images under `ghcr.io/convex/`. The old
`ghcr.io/get-convex/` path refuses pulls.

The HTTP routes are in `backend/convex/http.ts`: message images
(`/attachments`) and the calendar feed (`/calendar-feed/<token>.ics`). The push and Live Activity
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

## Repository Structure

```
tidex/
├── marketing/      # Marketing static site (tidex.no)
├── ios/            # Native iOS application (see ios/AGENTS.md)
├── backend/        # Production Convex backend
├── supabase/       # Retained source data and legacy GoTrue refresh
└── docs/           # Shared documentation
```

## Developer Info

- **Primary developer user ID**: `032d8c2a-9af6-4777-99f0-24e2c4058bf3` (Hjalmar's account for testing/debugging)

## Available Skills

Use these skills for specialized tasks:

- `ios-whats-new` - App Store release notes and metadata updates
- `supabase-postgres-best-practices` - Postgres performance and RLS guidance

## iOS guidance

For native work, follow [ios/AGENTS.md](ios/AGENTS.md). Read [localization](ios/docs/AGENT_LOCALIZATION.md) when changing UI strings or catalogs and [verification](ios/docs/AGENT_VERIFICATION.md) when building or testing.

## App Store Connect access

Tidex uses the pinned `asc` CLI for metadata, screenshot and creative-asset uploads.
Read [the workflow](ios/app-store/README.md) before changing or uploading App Store
assets. `bun run app-store` provides read-only plans by default. Apply with `--apply`
only when uploading is authorized. Native commands use `bun run asc <command>` and
accept `--read-only` for diagnostics. Build and test through the shared Xcode wrappers.

The ignored `ios/app-store/.env` symlink points to
`/Users/hkarlsen06/Documents/Privat/Utviklernøkler/Secrets/Tidex/asc.env`, with
`ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_PATH`. Recreate it or load the
existing credentials before asking for keys. Keep credentials outside Git.

Screenshot sets can all report `COMPLETE` while individual images are stuck.
Inspect image delivery states as well as set summaries before submitting.

## Local Chat Package Workflow

The Exyte `Chat` dependency is forked at `hkarlsen06/Chat` and is also cloned locally at `../Chat` for day-to-day development.

- The committed project is usually in `remote` mode. Check the current mode with `./scripts/check-chat-package-source.sh` before you rely on `../Chat`. Edits in `../Chat` only reach a Tidex build in `local` mode.
- Switch package source with:

```bash
./scripts/set-chat-package-source.sh local
./scripts/set-chat-package-source.sh remote
```

- `local` mode points Xcode at `../../Chat` as a local Swift package.
- `remote` mode points Xcode back at `https://github.com/hkarlsen06/Chat.git` for a portable committed state.
- When editing the package, make code changes in the sibling `../Chat` repo and commit them there, not inside `tidex`.
- Treat this as a hard rule: do not edit a resolved SwiftPM package checkout, build artifact, or any `Chat` source copy that lives under `tidex`.
- If a change should persist, it must land in `../Chat`, because that is the sustained fork repo and the source of truth for local package development.

**Release / shipping reminder:**

- If the user asks for work that implies a release or shared portable state, treat that as a reminder to check the `Chat` fork workflow.
- Examples: release, ship, App Store submission, TestFlight build, tagging a version, cutting a release, handing work off, or preparing CI-safe commits.
- Before those steps, if `../Chat` has relevant changes, remember to commit, tag, and push the `hkarlsen06/Chat` fork.
- Before committing release-oriented Tidex project changes, run `./scripts/set-chat-package-source.sh remote`.
- After release work, switch back with `./scripts/set-chat-package-source.sh local` if continuing local package development.

## Release checks

[RELEASE_CHECKS.md](RELEASE_CHECKS.md) lists things to try on a device before the next App Store or TestFlight release. When the user asks for release work (App Store submission, TestFlight build, version tag), show them the open items first and ask whether they have checked them. After the release ships, delete the items and keep the empty file. When a change needs a manual device check that the tests can't cover, add it there.

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
- Uptime Kuma on depressed-louis now checks the Convex API, `actions.tidex.no/health`, Clerk and the website. The relay reads current iPhone registrations through the internal `monitoring:uptimeDevices` query. See [aftercare](docs/convex-aftercare.md) for source and deployment paths.
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

Before revisiting adoption or planning a history cutover, read [the decision and prerequisites](docs/supabase-declarative-schema-decision.md).

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

## Agent Behavior Guidelines

**Parallel agent safety:**

- The developer often runs multiple agents in parallel in the same worktree.
- If you see unrelated changes, do not touch, revert, reformat, or "clean up" them.
- Treat unrelated diffs as owned by the user or another agent, even if they appeared after your work began.
- Only modify files and hunks required for your task. If unrelated changes block you, start a fresh worktree off `main` and do the task there.
- Never run `git stash`, `git reset`, `git checkout -- <path>` or `git clean` in the shared worktree. Other agents stage whole files, so check your own hunks with `git diff -- <file>` and `git diff --cached -- <file>`.
- A warning or compile error the user pastes may come from another agent's edit. Check `git diff` for the file before you fix it.

**Shell notes (macOS, zsh):**

- Always give `rg` a path (`rg pattern ios`). Without one it can wait on stdin until the 120 s timeout.
- Quote globs (`rg -g '*.swift'`). zsh fails an unmatched `--include=*.ts` with "no matches found".
- Tools are BSD: `sed -i ''`, no `cat -A`. `fd`, PIL and ImageMagick are not installed.
- On `one-s`, add `</dev/null` or `-T` when `docker compose exec` should not read your stdin, and don't `pkill -f` a pattern that also matches your own ssh command.

**Commits.** Commit on your own branch in your own worktree off `main`. Deploys wait until Hjalmar asks for them. A push to `main` is a deploy: the Cloudflare Pages project `tidex` builds `tidex.no` from committed `main` (root dir `marketing`) and overwrites any direct upload made with `bun run pages:deploy:marketing`. Keep the root `prepare` script as `husky || true`, because Pages runs its own `npm install` at the repo root and fails without husky.

**Old app builds.** Endpoints that regular users call must keep working for older iOS builds still in use. Admin functions and admin screens need no such compatibility, because the admins always run the latest build, so change or drop admin fields freely.

**App Review demo account.** The Apple App Review account has the jobs "Harbor Café" and "City Library" in `$` on a Norwegian device. That is demo data on purpose. Leave the account out of production data audits and cleanups, and change its data only when Hjalmar asks.

**Commits must always be signed** - never disable commit signing. If signing fails, stop and report the signing failure instead of creating an unsigned commit.

**Legal policy updates:**

- When changing the Terms of Service or Privacy Policy copy, always update the canonical client-facing version references in the same change.
- Bump the relevant dates/timestamps in:
  - `marketing/lib/i18n/dictionaries/legal.en.ts`
  - `marketing/lib/i18n/dictionaries/legal.no.ts`
  - `marketing/public/legal/version.json`
  - `marketing/public/en/version.json`
  - `marketing/public/no/version.json`
- Do not update `ios/TidexApp/App/TermsVersion.swift` fallback version reference as part of normal legal copy changes; it is only a placeholder for API failure scenarios and should not be treated as the canonical legal version.
- This is required so every client surface, including iOS re-acceptance checks and localized public pages, picks up the new legal version from the shared public manifests.
- A manifest bump makes every iOS user accept the policy again on next launch. For an edit that only discloses existing processing or follows a product change, ask Hjalmar whether to bump the manifests or only `lastUpdatedDate`. The Terms page date (2026-09-30) is newer than `termsVersionDate` (2026-05-30) on purpose, so leave that gap alone.

Run commands from the repository root unless explicitly stated otherwise.

When running verification or diagnostic commands, prefer flags that reduce non-actionable output and preserve useful diagnostics. Examples: use `swiftlint --quiet` for fast Swift checks, use `--json` on repository build/test wrappers when you need structured diagnostics, and use focused test filters where possible. Avoid verbose command modes unless the extra output is needed to debug the issue.

## Writing style

Cut AI tells from all prose you write or edit, including docs, comments, release notes, and user-facing copy. Scan for the patterns below, rewrite while preserving meaning and matching the intended tone, then self-audit with "What makes this obviously AI generated?" and fix what remains. If a direct quote or a file format requires the original wording, keep it correct and apply these rules to the rest. Rule numbers are stable ids. A removed rule leaves a gap.

### Content

3. **Superficial -ing phrases.** "highlighting...", "ensuring...", "reflecting...", "showcasing...", "fostering...". Delete or expand with real sources.
5. **Vague attributions.** "Experts believe", "Industry reports suggest", "Some critics argue". Name the source or delete.

### Language

7. **AI vocabulary.** Additionally, crucial, delve, enduring, enhance, fostering, garner, interplay, intricate, landscape (abstract), pivotal, showcase, tapestry (abstract), testament, underscore, vibrant. Replace with plain words.
8. **Fancy ways to say "is".** "serves as", "stands as", "boasts", "features". Just say "is" or "has".
9. **"Not just X, but Y."** State the point directly instead.
10. **Rule of three.** Forcing ideas into groups of three. Use the natural number.
11. **Synonym cycling.** Protagonist, main character, central figure, hero all in one paragraph. Pick one, repeat it.
12. **False ranges.** "from X to Y" where X and Y aren't on a meaningful scale. List topics directly.

### Style

13. **Em dash overuse.** Avoid em dashes entirely. Use periods or commas only (no parentheses, no en dashes, no hyphen-as-dash substitutes). If a thought needs separation, end the sentence or use a comma.
14. **Colon overuse.** Colons are fine before a list or example. Not as mid-sentence connectors. "If you're coming from traditional automation: instead of registering event handlers, you describe conditions" adds nothing with the colon. Rewrite to let the point stand on its own without comparison framing. "Describing when the scheduler should fire works best as plain English." Same meaning, no crutch punctuation.
15. **Boldface overuse.** Don't bold every proper noun or acronym.
16. **Inline-header lists.** The tell is a bold label and colon that restates the line: "**Performance:** Performance improved...". Convert those to prose. A bold lead-in that ends in a period, names the item, and is followed by genuinely new detail ("**Schema in TypeScript.** Tables live in one file.") is fine, not a tell.
17. **Title case headings.** Use sentence case.
18. **Decorative emojis.** Remove from headings and bullets.
19. **Curly quotes.** Replace with straight quotes.

### Communication artifacts

20. **Chatbot phrases.** "I hope this helps!", "Let me know if...", "Of course!", "Certainly!", "Found the smoking gun!" Remove.
22. **Sycophantic tone.** "Great question! You're absolutely right!" Respond directly.

### Filler

23. **Filler phrases.** "In order to" becomes "To". "Due to the fact that" becomes "Because". "It is important to note that" gets deleted.
24. **Excessive hedging.** "could potentially possibly be argued that it might" becomes "may".
25. **Generic conclusions.** "The future looks bright." State specific plans or facts.

### Jargon

26. **Abstract metaphor nouns.** Substrate, wedge, vector, locus, vantage, nexus, primitive (as noun), harness (as metaphor), surface (as in "API surface"), bedrock, scaffolding (as metaphor), modality, paradigm, gold-plating, ratchet (as metaphor), evacuate (for moving code), endgame, north star, flywheel. These read as technical but usually have a plainer concrete word. "Substrate" becomes "base". "Wedge in" becomes "add". "Vector" becomes "way" or "method". "Gold-plating" becomes "more than the job needs". "Ratchet" becomes the mechanism's real name or "a limit that only tightens". "Evacuate" becomes "move out". "Endgame" becomes "the last phase". Pick the concrete word.

### Plain speech

27. **Say what it does, not how it feels.** "the database stays close at hand", "SQL you can read", "types that follow your schema" name a feeling. The fix names the mechanism or a number: "`.toSQL()` returns the exact string sent to the database", "a column rename fails the build". Ask what the sentence tells the reader to do or know, then write that. If you can't restate it as a concrete instruction, fact, or number, cut it. One more check: if the sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.
28. **Shorten or split dense sentences.** If the reader has to backtrack to parse a sentence, break it in two or drop clauses. One idea per sentence.
29. **Active voice.** Prefer it. Catch "is/are/was/were + past participle" and name the actor: "queries are validated" becomes "the compiler validates queries", "the file is parsed by the loader" becomes "the loader parses the file". Passive is fine only when the actor is unknown or genuinely doesn't matter.
30. **Cut adverbs, or use a stronger verb.** "runs quickly" becomes "is fast" or the number. "significantly improves" becomes the measured delta. An adverb propping up a weak verb means the verb is wrong.
31. **Prefer the plain word.** "utilize" becomes "use", "leverage" becomes "use", "facilitate" becomes "help", "numerous" becomes "many", "in the event that" becomes "if". The fancier synonym is rarely clearer.
32. **Mannered prose.** Metaphor or flourish where a literal phrase exists: aphorisms ("wire it or delete it"), rhetorical fragments for effect, personified code ("the plan holds it"), figurative verbs ("rides along", "stands on"), stock framing phrases. "A dial worth turning" becomes "a parameter worth varying". Say what you mean. Rule 26 covers the metaphor nouns.
33. **Over-compression.** Dropped articles, verbless fragments, symbol-speak, and abbreviations that make the reader decode instead of read. "Parser rejects bad date → exit 2, no write" becomes "The parser rejects a bad date, exits with code 2, and writes nothing." Write whole sentences with their articles and verbs, and spell out arrows and abbreviations.
