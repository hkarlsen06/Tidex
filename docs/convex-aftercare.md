# Convex aftercare

Completed after the public 3.1.0 release on 2026-10-29. Hjalmar chose to retain automatic sign-in for users who update later.

## Live state

- On one-s, the unused Supabase analytics, functions, imgproxy, meta, realtime, REST, storage, Studio and Vector containers were stopped and removed at 22:09 UTC. Source data, media and backups were preserved.
- Postgres, GoTrue and Envoy remain healthy for the temporary session refresh bridge. Supabase business writes remain blocked and all eight cron jobs remain disabled. GoTrue still writes session state, so the database is not globally read-only.
- The resolved Compose file puts retired services in the `retired` profile with `restart: no`. Normal startup selects only `db`, `auth` and `api-gw`. Envoy depends on auth instead of the retired Studio service.
- The one-s watchdog checks current Convex and Clerk endpoints, calendar routing, the retained bridge, backup freshness and host capacity. Paeonia checks are preserved. The watchdog and all Tidex backup timers are active.
- Uptime Kuma on depressed-louis has ten healthy checks. Tidex has four, covering its website, Convex API, HTTP action and database execution, and Clerk configuration. Existing monitor IDs and history remain intact.
- The alert relay reads only Hjalmar's current iPhone registrations through the fixed internal Convex query. Its restricted SSH key cannot select another user or query. A successful empty source clears recipients; a failed source read preserves the last successful snapshot.
- The actual monitor 8 recovery at 22:04:29 UTC was accepted by APNs on its first attempt. Its APNs ID is `d0431f01-9f75-4b72-ba52-a8b260b0abbd`. The relay has one active device and no pending or failed deliveries.
- Both obsolete App Store Server Notifications URLs are cleared. The API rejected null and empty URL updates, so they were cleared through App Store Connect. A fresh API read at 22:19:37 UTC confirmed both are null.
- Saved calendar routes still reach Convex on both legacy hostnames. The public app gate remains `minimumVersion: 3.1.0`, `maintenance: false`.

The monitors check reachability and known responses, not complete authenticated app journeys. The bridge probe confirms that a deliberately invalid refresh token reaches GoTrue; it does not use a real session. Current phone checks remain in the [cutover record](convex-cutover-checklist.md). This aftercare verified APNs acceptance without another phone display check. The home-hosted monitor cannot independently detect its own complete power or internet failure.

## Retained resources and retirement

Keep GoTrue, Postgres and Envoy until nearly all active users have upgraded, or 2026-11-29. The old `record_app_activity` RPC is blocked after cutover, so use current Convex activity and session-exchange evidence when assessing adoption. Users updating after bridge shutdown must sign in again with Clerk.

Before retiring the bridge, take and verify a final database archive, check that calendar routing continues directly to Convex, and update the watchdog's explicit bridge and legacy-backup checks. Preserve the cold archives. Removing source data or its volumes requires Hjalmar's approval. The existing stopped validation containers and Docker images were left intact with the source recovery state; they consume disk but run no services. No global Docker prune was run.

## Recovery records

Private aftercare artifacts are in:

- Mac: `/Users/hkarlsen06/Library/Application Support/Tidex/aftercare/20261029T214358Z`
- one-s: `/srv/tidex/aftercare/20261029T214358Z`
- depressed-louis: `/srv/uptime/aftercare/20261029T214358Z`

The one-s archive contains a fresh `pg_dumpall` of databases and roles, plus file storage, configuration, functions and the Postgres configuration volume. The database data directory itself is excluded from the file archive because the logical dump is the database backup. Both gzip archives passed integrity checks. `legacy-SHA256SUMS` records their hashes. The three files were copied to `r2:tidex-supabase-backups/tidex-retirement/20261029T214358Z`; `rclone check --download --one-way` confirmed three matching files and zero differences at 22:06:41 UTC. This prefix is outside the ordinary rolling-backup deletion prefix.

The old resolved Compose config, Caddy config, watchdog, auth check and device exporter are saved privately. The monitoring snapshot includes consistent SQLite backups and its previous source/configuration. Earlier cutover archives remain available. Restoring the old full production stack would restore obsolete writers and push paths, so a production rollback needs a separate plan. Do not rerun the migration importer.

## Source and verification

Tidex owns `backend/convex/monitoring.ts`, the public health route in `backend/convex/http.ts`, `backend/ops/healthcheck.py`, and `backend/ops/one-s-watchdog.sh`. The deployed health script is `/srv/tidex/healthcheck.py`; the watchdog is `/srv/backup/watchdog.sh`. The retained `/srv/tidex/auth-smoke.sh` command calls the new health script with `--legacy-refresh`.

The monitoring source repository is `/Users/hkarlsen06/.t3/scratch/2026-10-27-build-an-uptime-checking-service-b5b3400f`, deployed at `/srv/uptime` on depressed-louis. Its `docs/verification.md` records the current checks and APNs evidence. The exporter is root-owned at `/usr/local/libexec/uptime-export-tidex-devices` on one-s. It uses the local Convex admin API through a fixed query. Fresh provisioning also reads APNs credentials from Convex.

Verification completed:

- Three real local Convex integration checks, including private recipient access and the public database health action. Run from `backend/` with `bun test --env-file=.env.local ./scripts/monitoring.integration.ts`.
- `bun run typecheck` in `backend/` and production Convex deployment.
- Nine relay behavior tests, including unknown APNs environment resolution, source failure caching, empty-source revocation and rejection of old Supabase snapshots.
- Three health-check failure tests, shell syntax checks, and live health probes from the Mac and one-s.
- Kuma and relay image builds, provisioning and fresh passing observations for all ten live checks. Public administration routes remain refused on all three domains.
- The actual forced-command SSH refresh from the deployed relay, with the returned token set matching its active registration. No tokens were printed.
- Healthy retained containers, the default three-service Compose selection, zero active legacy crons, active backup timers, passing watchdog, calendar routing and the unchanged public gate.

Logs include `monitoring-backend-deploy.log`, `uptime-build.log`, `uptime-live-verification.log`, `legacy-archive.log`, `retire-services.log`, `final-watchdog.log` and `asc-aftercare-verification.json` in the private Mac artifact directory. The [decision trail](convex-aftercare-decisions.tsv) records the operational choices. No iOS source changed, so no new app build or phone installation was needed.

The runbooks were corrected where they disagreed with live behavior: UptimeRobot had been replaced by Kuma, the relay and health checks still described Supabase, and the migration plan raised the update gate before App Store availability. The current instructions reflect Convex monitoring and the verified release sequence.

## Independent review

gpt-6.1-sol checked the changes, decision trail, transcript and private evidence against the gpt-6-astra implementation. Model diversity was limited to GPT variants. No material correctness, privacy or retirement-safety defect was found. The review caught two stale instructions, the adoption RPC and the integration-test command, and both were corrected. Remaining attention is the bridge retirement deadline, the distinction between APNs acceptance and phone display, and the monitor's home-host outage limitation.
