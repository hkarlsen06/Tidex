- [ ] Refactor remaining authenticated `SECURITY DEFINER` Supabase RPCs out of the exposed `public` API surface, or convert safe candidates to `SECURITY INVOKER`, so the remaining `authenticated_security_definer_function_executable` advisor warnings can be resolved without breaking iOS/admin flows.
- [x] Remove legacy Friends tab bootstrap RPCs once unsupported iOS clients are retired: `get_my_sharers`, `get_sharing_friends_api`, and `get_my_sharer_preview_payloads`. Migration SQL: `DROP FUNCTION IF EXISTS public.get_my_sharer_preview_payloads(uuid[], date, date); DROP FUNCTION IF EXISTS public.get_my_sharers(); DROP FUNCTION IF EXISTS public.get_sharing_friends_api();`
- [ ] Remove retired monthly-goal persistence after old app versions no longer need it: drop the Supabase goal columns/defaults/function plumbing in a forward migration, then remove the matching iOS local/sync/sharing compatibility.
- [ ] Drop `user_settings.ai_data_sharing_enabled` and `user_settings.wagey_showcase_seen` once iOS 2.7.1 and older are retired. Those builds still write both columns when they push settings, so dropping them earlier breaks their settings sync. The app stopped using them in the release after 2.7.1.
- [ ] Remove the server paywall plumbing once pre-3.0.0 iOS builds are retired: `get_my_entitlement`, `user_entitlements`, `get_paywall_config` + `internal.paywall_config`, `profiles.before_paywall`, and (after 2026-10-18) `apple-server-notifications` with `_shared/deno-signed-data-verifier.ts`, `@apple/app-store-server-library`, `get_or_create_app_account_token`, `internal.app_account_tokens`, `internal.apple_notifications` and `internal.apple_orphan_notifications`.

## iOS 27 foreground-auth lifecycle false positive

Observed on 2026-07-21 with Tidex 2.6.1 (`20260721.0003`) on iOS 27.0: the main app refreshed an existing Supabase session and emitted `session_fetch_failed` plus `foreground_session_failed` while the user was actively using another app. The same resident Tidex process had not relaunched. Treat `UIApplication.didBecomeActiveNotification` and `UIApplication.shared.applicationState == .active` as insufficient evidence that a Tidex scene is genuinely foreground-active.

- [x] Gate `AppCoordinator.handleAppForeground()` on a real `UIScene.ActivationState.foregroundActive` scene, not only the process-level `UIApplication.didBecomeActiveNotification`.
- [x] Debounce activation briefly and re-check scene state before starting authentication, synchronization, APNs registration, or badge refresh. This should ignore the extra `didBecomeActive` transition reported during locking/backgrounding on iOS 26 and later.
- [x] Keep a reference to the foreground task and cancel it from both `handleWillResignActive()` and `handleDidEnterBackground()`; add cancellation checks before session access and before emitting foreground diagnostics.
- [ ] Record lifecycle provenance: transition name, previous/current application and scene states, foreground-task start time, completion time, cancellation state, and whether execution followed a URL, notification response, silent push, widget deep link, or ordinary activation.
- [ ] Distinguish Supabase SDK automatic token refreshes from explicit foreground `getSession()` calls in diagnostics.
- [ ] Suppress or deduplicate admin warning pushes when `session_fetch_failed` and `foreground_session_failed` describe the same operation, especially when a successful `tokenRefreshed` event has already restored an authenticated session.
- [x] Confirm whether the unused `fetch` entry can be removed from `UIBackgroundModes`; the app currently declares background fetch without implementing `application(_:performFetchWithCompletionHandler:)`. Removed; `remote-notification` still covers silent prefetch pushes.
- [ ] Add device tests for lock/unlock, rapid app switching, Control Centre and Notification Centre, system sheets, silent notification prefetch, widget timeline refresh, widget tap, suspension/resumption, and successful refresh racing the 20-second session timeout on iOS 26 and iOS 27.
- [ ] Verify that automatic widget timeline refreshes remain isolated to the widget extension and only consume the shared keychain access token; they must not activate the containing app or refresh the Supabase session.

Reference: [Apple Developer Forums report of unexpected `didBecomeActive` callbacks during locking/backgrounding on iOS 26+](https://developer.apple.com/forums/tags/uikit?page=7).

## Supabase declarative schema adoption deferred

Decision confirmed 2026-07-24: do not adopt declarative schemas yet. Tidex
remains migration-only because the committed history cannot reconstruct the
foundational database and the required three-state round trip is not proven.

- [x] Verified Supabase CLI 2.109.1 and the current
  `db diff`/`schema_paths` workflow; pg-delta is the documented default and the
  installed CLI supports `--use-pg-delta`. The still-exposed public-alpha sync
  command is not the current documented workflow.
- [x] Inventoried the original 90 migrations, 144 SQL function files, views,
  policies, triggers, Auth/Storage dependencies, cron, seed DDL, and CI
  coverage.
- [x] Confirmed the migration set is not clean-room reproducible:
  `20260311193000_schema_baseline.sql` assumes foundational tables that no
  committed migration creates.
- [x] Reconciled migration-proven retired sharing RPC and legacy
  notification-queue trigger sources with the linked project.
- [x] Inventoried linked managed integrations read-only: Auth/event triggers,
  three Storage buckets, 15 policies, six cron jobs, four Realtime publication
  tables, seven required extensions, the `stripe_sync_work` PGMQ queue, Vault
  secret names, and `postgres` default ACLs. Nine Storage policies are legacy
  avatar aliases.
- [x] Compared all SQL function and view bodies with the linked catalog.
  Established the committed source as intentional for `edit_message`,
  `record_auth_diagnostic_event`, and `admin_log_action`, and added a
  forward-only reconciliation migration. Intentional future-state calendar
  sources remain outside the active migration lane.
- [x] Tested the recovered historical migration chain in a disposable local
  stack. It is not directly reusable: foundational objects/columns are missing,
  two migrations share `20260130120000`, and the current baseline references
  `monthly_goals_by_month` before creating it.
- [x] Dumped linked `public,internal` read-only and proved the snapshot plus
  explicit prerequisites for `pg_cron`, `pg_net`, `moddatetime`, `pgcrypto`,
  `pgmq`, `supabase_vault`, and `uuid-ossp` through startup, clean reset, lint,
  exact catalog comparison, and disposable replay. A snapshot guard rejected
  replay over existing user tables and still passed a clean reset.
- [x] Proved disposable hand-written fixtures for the `auth.users` trigger,
  three Storage buckets, six canonical Storage policies, six cron jobs, and
  four `supabase_realtime` publication tables. Stable catalog hashes matched
  the linked project after excluding the nine policies selected for retirement.
- [x] Reconciled `supabase/seed.sql` with the canonical `profile-pictures`
  bucket/policies and added a forward-only migration to drop the nine legacy
  avatar policy aliases. Both SQL files execute successfully in the disposable
  stack; neither was applied to the linked project.
- [x] Exported the 11 previously remote-only functions/views and added active
  CREATE history for all 45 functions and two views that were absent from the
  migration chain. Disposable definitions, ACLs, comments, and view options
  match the linked catalog by exact aggregate hashes.
- [x] Added hand-written migration coverage for the Auth/event triggers,
  required extensions, `profile-pictures` bucket/four canonical policies, and
  `stripe_sync_work` queue existence. Proved idempotent replay, Auth profile
  bootstrap behavior, and automatic RLS enablement in rolled-back tests.
- [x] Proved the CLI 2.109.1 `--from linked --to <Postgres URL>` pg-delta path
  is not valid evidence here: it returned empty output with a deliberate extra
  table. The supported linked-to-local form is currently blocked by the
  project's legacy IPv6 connection metadata. Keep exact catalog comparison as
  a required companion gate.
- [x] Built an ordered temporary declarative candidate using the extension
  prerequisite, current `public,internal` snapshot, explicit negative
  privileges, and event-trigger source. A second disposable stack replayed it
  to a byte-for-byte identical dump (SHA-256
  `21134dc08b0c94c4897b98153303c52e1580bc028c76c64e82d696da7602d08e`);
  managed catalog hashes, lint, Auth bootstrap, and automatic-RLS probes also
  passed.
- [x] Isolated the remaining diff-engine blocker: with identical migration and
  declarative inputs, pg-delta proposed destructive rebuilds of six messaging
  tables plus related functions/indexes, while migra returned no changes. Do
  not generate or apply that migration. Related dependency over-replacement is
  open in `supabase/pg-toolbelt#280`; the clean-room breaking-alpha rewrite is
  still open in PR `#299`.
- [x] Proved Vault provisioning separately with rolled-back placeholder
  `supabase_url` and `service_role_key` secrets; no placeholder or linked
  secret values were retained.
- [x] Documented the deferral and permanent hand-written migration lane in
  `AGENTS.md`; left `schema_paths = []` and did not add a misleading drift gate.

Prerequisites before reevaluation:

- [x] Design and prove the coordinated migration-history repair: with Supabase
  Git deployment paused, generate a fresh snapshot version, add a generic
  fail-closed nonempty-database guard and explicit negative privileges, archive
  the old applied SQL files byte-for-byte, mark the old versions reverted and
  the snapshot applied with migration repair, verify tracking read-only, then
  reenable deployment. Migration repair changes tracking only; never execute
  the snapshot SQL on populated production.
- [ ] Review and deploy the four new forward migrations through the normal
  migration workflow. Until then, the linked project intentionally differs in
  three function bodies and still contains the nine retired Storage policies;
  the other two migrations establish no-op history for linked definitions and
  managed integrations.
- [x] Preserve the linked project's current default ACL behavior during the
  history-only cutover so it remains a semantic no-op. Preserve explicit
  negative ACLs such as `user_entitlements`; move any transition to Supabase's
  explicit-grant model into a separate reviewed forward migration.
- [ ] Perform the coordinated production history cutover only after pg-delta
  can compare the identical Tidex states without destructive false positives.
  Keep Storage rows, Auth/event triggers, PGMQ, Vault requirements, cron,
  publications, privileges, and extension setup in permanent hand-written
  lanes.
- [ ] Provision the required Vault entries (`supabase_url` and
  `service_role_key`) through environment-managed secrets in every disposable
  or replacement environment. Never commit or copy linked secret values or
  PGMQ runtime messages.
- [ ] Establish zero unexplained drift between a clean migration build,
  declarative build, and the linked Tidex project using both pg-delta and exact
  catalog inventories. The exact inventories and migra already converge; the
  identical-input pg-delta destructive plan must disappear before enablement.
- [ ] Repeat generated migration, reset, lint, test, advisor, and CI trials
  after pg-delta's current rewrite stabilizes.

References: [Supabase declarative database schemas](https://supabase.com/docs/guides/local-development/declarative-database-schemas), [pg-delta public-alpha announcement](https://github.com/orgs/supabase/discussions/44938), [destructive dependency replacement issue](https://github.com/supabase/pg-toolbelt/issues/280), and [clean-room pg-delta rewrite](https://github.com/supabase/pg-toolbelt/pull/299).
