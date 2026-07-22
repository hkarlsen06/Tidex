- [ ] Refactor remaining authenticated `SECURITY DEFINER` Supabase RPCs out of the exposed `public` API surface, or convert safe candidates to `SECURITY INVOKER`, so the remaining `authenticated_security_definer_function_executable` advisor warnings can be resolved without breaking iOS/admin flows.
- [x] Remove legacy Friends tab bootstrap RPCs once unsupported iOS clients are retired: `get_my_sharers`, `get_sharing_friends_api`, and `get_my_sharer_preview_payloads`. Migration SQL: `DROP FUNCTION IF EXISTS public.get_my_sharer_preview_payloads(uuid[], date, date); DROP FUNCTION IF EXISTS public.get_my_sharers(); DROP FUNCTION IF EXISTS public.get_sharing_friends_api();`

## iOS 27 foreground-auth lifecycle false positive

Observed on 2026-07-21 with Tidex 2.6.1 (`20260721.0003`) on iOS 27.0: the main app refreshed an existing Supabase session and emitted `session_fetch_failed` plus `foreground_session_failed` while the user was actively using another app. The same resident Tidex process had not relaunched. Treat `UIApplication.didBecomeActiveNotification` and `UIApplication.shared.applicationState == .active` as insufficient evidence that a Tidex scene is genuinely foreground-active.

- [ ] Gate `AppCoordinator.handleAppForeground()` on a real `UIScene.ActivationState.foregroundActive` scene, not only the process-level `UIApplication.didBecomeActiveNotification`.
- [ ] Debounce activation briefly and re-check scene state before starting authentication, synchronization, APNs registration, badge refresh, or Watch updates. This should ignore the extra `didBecomeActive` transition reported during locking/backgrounding on iOS 26 and later.
- [ ] Keep a reference to the foreground task and cancel it from both `handleWillResignActive()` and `handleDidEnterBackground()`; add cancellation checks before session access and before emitting foreground diagnostics.
- [ ] Record lifecycle provenance: transition name, previous/current application and scene states, foreground-task start time, completion time, cancellation state, and whether execution followed a URL, notification response, silent push, widget deep link, or ordinary activation.
- [ ] Distinguish Supabase SDK automatic token refreshes from explicit foreground `getSession()` calls in diagnostics.
- [ ] Suppress or deduplicate admin warning pushes when `session_fetch_failed` and `foreground_session_failed` describe the same operation, especially when a successful `tokenRefreshed` event has already restored an authenticated session.
- [ ] Confirm whether the unused `fetch` entry can be removed from `UIBackgroundModes`; the app currently declares background fetch without implementing `application(_:performFetchWithCompletionHandler:)`.
- [ ] Add device tests for lock/unlock, rapid app switching, Control Centre and Notification Centre, system sheets, silent notification prefetch, widget timeline refresh, widget tap, suspension/resumption, and successful refresh racing the 20-second session timeout on iOS 26 and iOS 27.
- [ ] Verify that automatic widget timeline refreshes remain isolated to the widget extension and only consume the shared keychain access token; they must not activate the containing app or refresh the Supabase session.

Reference: [Apple Developer Forums report of unexpected `didBecomeActive` callbacks during locking/backgrounding on iOS 26+](https://developer.apple.com/forums/tags/uikit?page=7).

## Evaluate Supabase declarative schemas with pg-delta

Research and, if the current Supabase workflow proves safe for Tidex, adopt declarative schema files as the readable source of truth while retaining versioned migrations as the deployment and transition history.

- [ ] Verify the currently supported Supabase CLI version, commands, configuration, and directory convention from the official documentation; do not rely on the original public-alpha `db schema declarative sync` interface if it has been superseded.
- [ ] Inventory the existing `supabase/migrations/` and `supabase/sql/` schema surface: tables, types, constraints, indexes, RLS policies, functions, triggers, views, grants, extensions, cron jobs, publications, Storage configuration, and any schema-adjacent data.
- [ ] Document which objects pg-delta cannot safely or completely represent. Keep DML/data transforms, extension-managed state, and unsupported objects in explicit hand-written migrations.
- [ ] Generate an initial `supabase/schemas/` baseline from the migration-reconstructed local database, then compare it with the linked Tidex project and explain every difference before accepting it.
- [ ] Decide how existing canonical files under `supabase/sql/` map into the declarative structure so functions and policies do not acquire two competing sources of truth.
- [ ] Trial the edit -> `supabase db diff -f <name>` -> review -> `supabase migration up` workflow on a disposable branch/local database. Never rewrite already-applied migrations.
- [ ] Test additive, rename, type-change, function, trigger, view, grant, and RLS-policy changes. Confirm generated migrations preserve data and do not introduce unexpected drops, locks, privilege changes, or RLS regressions.
- [ ] Prove reproducibility with a clean local reset and representative seed data, then run Supabase security and performance advisors against the result.
- [ ] If adopted, update `AGENTS.md` and contributor commands, add a CI drift/diff check where practical, and require declarative files plus reviewed generated migrations in the same change.

References: [Supabase declarative database schemas](https://supabase.com/docs/guides/local-development/declarative-database-schemas) and [pg-delta public-alpha announcement](https://github.com/orgs/supabase/discussions/44938).
