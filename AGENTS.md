# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Project Overview

A monorepo for the Tidex iOS app and its supporting infrastructure.

Tidex is now an iOS-only product. The repository still includes supporting public/legal web surfaces, the legacy compatibility host for `app.tidex.no`, and the shared backend.

- **marketing/** - Next.js 16 public website for `tidex.no`
- **app-compat/** - Static Cloudflare Pages compatibility site for `app.tidex.no`
- **ios/** - Native iOS application

The supporting web surfaces and iOS app share a common Supabase backend (edge functions, migrations, database schema) located in `supabase/`. Production Supabase is self-hosted on the `mdr` server behind `api.tidex.no`; the old hosted Supabase project is retired.

## Supabase Production Access

Agents may access production directly with `ssh mdr`. The Tidex stack is at
`/srv/tidex/tidex-sb`; use `docker compose` there to inspect logs and services
or make task-authorized service changes, and use
`docker compose exec -T db psql -U postgres -d postgres` for direct database
inspection or task-authorized data mutations. Direct SSH is the normal
production access path, so do not block on Supabase MCP or the hosted dashboard.

Use migrations rather than ad hoc SQL for schema changes. When a Supabase CLI
operation is required, pass the explicit, percent-encoded MDR connection as
`--db-url "$TIDEX_MDR_DB_URL"`. Do not use bare remote CLI commands or
`--linked`; they target the retired hosted project unless explicitly
reconfigured and verified. Never commit the database URL or its credentials.

## Repository Structure

```
tidex/
├── marketing/      # Marketing static site (tidex.no)
├── app-compat/     # Compatibility redirects + Apple association files (app.tidex.no)
├── ios/            # Native iOS application (see ios/AGENTS.md)
├── supabase/       # Shared backend (edge functions, migrations)
└── docs/           # Shared documentation
```

## Developer Info

- **Primary developer user ID**: `032d8c2a-9af6-4777-99f0-24e2c4058bf3` (Hjalmar's account for testing/debugging)

## Available Skills

Use these skills for specialized tasks:

- `ios-whats-new` - App Store release notes and metadata updates
- `supabase-postgres-best-practices` - Postgres performance and RLS guidance

## iOS Localization Scripts

Use `./scripts/xcstrings-set` from the repo root for ordinary plain string catalog edits.

**Localization key usage:**

- Always use generated `LocalizedStringResource` symbols in Swift code, for example `Text(.settingsSaveButton)` or `String(localized: .settingsSaveButton)`.
- Never call localization APIs with raw string keys such as `String(localized: "settings.saveButton")`, `Text("settings.saveButton", tableName: "Localizable")`, `LocalizedStringResource("settings.saveButton", table: "Localizable")`, or `NSLocalizedString("settings.saveButton", ...)`.
- If a key has no generated symbol, add or rename the catalog entry to a dot-notation key that does generate one, then use the symbol.

**Commands:**

```bash
./scripts/xcstrings-set ios/Resources/Localization/App/Localizable.xcstrings feature.key \
  --comment "Translator context" \
  --en "English" \
  --nb "Norwegian"
bun run ios:l10n:delete -- --key "feature.key"
bun run ios:l10n:search -- "query"
bun run ios:l10n:audit
bun run ios:l10n:validate
```

- New keys must include English, Norwegian Bokmal, and a translator comment.
- The helper preserves existing catalog order by default to keep diffs focused. Pass `--sort-keys` only when intentionally normalizing a catalog.
- Use `--locale <code>=<value>` for additional languages if a specific non-generated locale edit is needed.
- Use Xcode's String Catalog editor or XLIFF export/import for pluralization, substitutions, device variants, or bulk translator workflows.
- After adding English/Norwegian copy, remind the user to run `bun ios/Scripts/translate-xcstrings.mjs` when other supported languages should be generated.

## Local Chat Package Workflow

The Exyte `Chat` dependency is forked at `hkarlsen06/Chat` and is also cloned locally at `../Chat` for day-to-day development.

- Default local development workflow: compile Tidex against the sibling `../Chat` clone.
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

## Supabase Edge Functions

**CRITICAL: Edit locally in `supabase/functions/`, then deploy to the self-hosted stack on `mdr`, NOT via Supabase's hosted deployment or MCP deploy tools**

- **Location**: `supabase/functions/<function-name>/index.ts`
- **Shared code**: `supabase/functions/_shared/`
- **Deployment**: Sync the function to `/srv/tidex/tidex-sb/volumes/functions/` on `mdr` and restart the `functions` service

**`verify_jwt` settings:**

| Function                       | `verify_jwt` | Reason      |
| ------------------------------ | -------------- | ----------- |
| `stripe_webhook`             | `false`      | Webhook     |
| `apple-server-notifications` | `false`      | Webhook     |
| `apple-verify-purchase`      | `true`       | User-called |
| `send-push-notifications`    | `false`      | pg_cron     |
| `before-user-created`        | `false`      | Auth hook   |

Use `verify_jwt: false` for pg_cron, webhooks, service role auth. Use `verify_jwt: true` only for direct user calls.

## Supabase SQL Functions & Cron Jobs

**Locations:**

- SQL function source files: `supabase/sql/functions/<category>/*.sql`
- Cron job docs: `supabase/sql/cron/*.md`
- CLI migration files: `supabase/migrations/*.sql`

**CRITICAL:**

- Write migrations that will be applied by the Supabase CLI to `supabase/migrations/`.
- Use `supabase db pull --db-url "$TIDEX_MDR_DB_URL"` only when intentionally baselining or capturing remote-first schema changes back into `supabase/migrations/`.
- Do not treat `supabase/sql/migrations/` as the CLI-applied migration directory.
- Keep the SQL source files in `supabase/sql/functions/` in sync with the actual database definitions when making changes.

### Declarative schema adoption is deferred

Tidex evaluated Supabase declarative schemas with CLI 2.109.1 on 2026-07-24
and must remain migration-only for now:

- Keep `[db.migrations].schema_paths = []`.
- Do not create or commit `supabase/schemas/`, enable schema paths, or add a
  pg-delta drift CI gate until the prerequisites below are complete.
- The committed migration history is not a reconstructable foundation.
  `20260311193000_schema_baseline.sql` starts from pre-existing core tables and
  is internally out of dependency order: it defines sharing functions that
  reference `user_settings.monthly_goals_by_month` before adding that column.
  A clean reset or shadow database therefore cannot establish a trustworthy
  declarative baseline.
- Do not add a naïve earlier-dated bootstrap migration. The self-hosted MDR
  database would treat it as unapplied during the next migration push.
- Git history contains a useful deleted `00000000000000_schema.sql` plus
  January 2026 migrations, but they are not safe to restore verbatim. The
  snapshot omits `feedback`, `notification_preferences`,
  `shift_shares.notification_frequency`, and
  `wage_snapshots.tariff_type_id`; two deleted migrations also share version
  `20260130120000`.
- A 2026-07-24 read-only dump of the then-hosted production `public,internal`
  schemas, advanced through the
  four pending forward migrations and preceded by explicit hand-written
  prerequisites for the seven required user-lane extensions, replays and
  resets cleanly in disposable stacks. An independent snapshot replay produced
  a byte-for-byte identical 485 KiB dump (SHA-256
  `21134dc08b0c94c4897b98153303c52e1580bc028c76c64e82d696da7602d08e`)
  after an explicit post-dump revoke preserved the intentional denial on
  `user_entitlements`. Auth, Storage, cron, Realtime, event-trigger, PGMQ,
  extension, and default-ACL inventories also match exactly. A fail-closed
  guard rejects replay over existing user tables and still allows a clean
  reset. This proves the current-state snapshot plus permanent hand-written
  lanes is a viable foundation candidate; it does not make the existing
  migration chain or production cutover safe.
- `supabase/sql/` has been reconciled for currently deployed function and view
  intent. Retired sharing and notification-queue sources were removed, the 11
  previously remote-only definitions were exported, and one forward migration
  captures all 45 functions and two views that lacked active CREATE history.
  Their definitions, ACLs, comments, and view options match the captured
  production catalog by exact hashes after disposable replay. A separate forward migration
  reconciles the three intentionally newer function definitions. Intentional
  future-state sources under `supabase/todo-migrations/` remain outside the
  active lane and differ from the captured production state by design.
- Read-only managed-schema inventory found `on_auth_user_created`,
  `ensure_rls`, three Storage buckets, 15 Storage policies, six cron jobs, four
  Realtime publication tables, the `stripe_sync_work` PGMQ queue, and Vault
  entries named `supabase_url` and `service_role_key`. Forward migrations now
  capture the Auth/event triggers, extension prerequisites, queue existence,
  canonical `profile-pictures` bucket/four policies, and removal of nine
  legacy avatar aliases. Queue messages and Vault values are runtime or secret
  data and must never be copied. The captured production `postgres` default
  ACLs grant broad privileges in `public` and `storage`; preserve them only in the reviewed
  privilege lane and revisit them against Supabase's explicit-grant rollout.
- The declarative pg-delta gate currently fails even for identical states. An
  ordered temporary schema build needed the extension prerequisite SQL plus
  explicit privilege/event-trigger inputs. With the exact same snapshot on the
  migration and declarative sides, `--use-pg-delta` still proposed destructive
  drop/recreate operations for six messaging tables, related indexes, and four
  functions. `--use-migra` returned no changes, and independent dumps were
  byte-identical, proving the pg-delta plan is a false positive. This is the
  active adoption blocker; related destructive dependency replacement is
  tracked in `supabase/pg-toolbelt#280`, and the clean-room breaking-alpha
  rewrite is still open in PR `#299`.
- Use exact read-only catalog/dump inventories for production-state comparison.
  Current declarative `db diff` documentation compares schema files with
  migrations, not the live database. CLI 2.109.1's explicit linked-to-URL form
  also returned an empty result with a deliberate probe table, while the
  linked-to-local form stalled behind legacy IPv6/link metadata; neither is
  valid live-drift evidence.
- The public-alpha `supabase db schema declarative sync` interface must not be
  used. CLI 2.109.1 still exposes it, but the current documented evaluation
  workflow is `supabase db diff` with `schema_paths`, followed by review and
  local migration application. pg-delta is the documented default; the
  installed CLI also confirms the explicit `--use-pg-delta` flag is supported.
- DML/backfills, Storage buckets, cron, extensions, publications, privileges,
  managed-schema objects, renames, and destructive/data-dependent transitions
  stay in reviewed hand-written migrations even after a future adoption.

Reconsider adoption only after all of these are true:

1. A production-safe, reconstructable foundational migration history exists.
2. `supabase/sql/` has been reconciled with current deployed intent.
3. Remote-only Auth and Storage objects have been exported and explained.
4. Migration-built, declarative-built, and production schemas round-trip with zero
   unexplained pg-delta output and matching exact catalog inventories.
5. Clean reset, lint, representative tests, advisors, and a disposable
   generated-migration trial pass.

Any eventual history cutover must be coordinated directly against the
self-hosted MDR database. First deploy all ordinary forward
migrations and regenerate the snapshot from that exact state. Create the new
snapshot with `supabase migration new`, add a generic fail-closed
nonempty-`public`/`internal` guard, and append the explicit privilege
reconciliation. Preserve current default-ACL behavior during the history
cutover; change privilege policy only in a separate reviewed migration.
Prove the snapshot from scratch, archive old applied migration files
byte-for-byte outside the active migration directory, then use
`supabase migration repair --db-url "$TIDEX_MDR_DB_URL"` to mark the old
versions reverted and the snapshot version applied. Migration repair changes tracking only, so the snapshot SQL
must never run on the populated MDR database. Verify tracking rows
read-only before the next explicit production migration push.
This is a future production operation and must not be inferred from routine
schema work.

**Recommended workflow:**

1. Edit function/trigger source files in `supabase/sql/functions/` as needed.
2. Add or update the corresponding migration in `supabase/migrations/`.
3. Preview and apply it explicitly to MDR with `supabase db push --db-url "$TIDEX_MDR_DB_URL" --dry-run`, then rerun without `--dry-run`.
4. If the remote database was changed outside the CLI workflow, reconcile with `supabase db pull --db-url "$TIDEX_MDR_DB_URL"` before continuing.

**Current Cron Jobs:**

| Job Name                            | Schedule            | Description                            |
| ----------------------------------- | ------------------- | -------------------------------------- |
| `cleanup-shift-notification-events` | `0 4 * * 0`         | Clean retained notification outbox rows |
| `daily_purge_soft_deletes`          | `30 3 * * *`        | Purge expired soft-deleted records     |
| `process-pending-push-notifications` | `* * * * *`        | Drain queued push notifications        |
| `purge-messaging-sync-events-v2`    | `0 4 * * *`         | Purge expired messaging sync events    |
| `queue-subscription-trial-reminders` | `15 * * * *`       | Queue subscription trial reminders     |
| `process-live-activities`           | `1,16,31,46 * * * *` | Process Live Activity updates          |

## Agent Behavior Guidelines

**Parallel agent safety:**

- The developer often runs multiple agents in parallel in the same worktree.
- If you see unrelated changes, do not touch, revert, reformat, or "clean up" them.
- Treat unrelated diffs as owned by the user or another agent, even if they appeared after your work began.
- Only modify files and hunks required for your task; if unrelated changes block you, stop and ask before proceeding.

**Do NOT create unnecessary files:**

- NO summary documents, audit reports, or markdown files unless explicitly requested
- Focus on code changes only - communicate findings in chat

**NEVER push to git automatically** - commit when requested, but wait for user approval before pushing.

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

Run commands from the repository root unless explicitly stated otherwise.

When running verification or diagnostic commands, prefer flags that reduce non-actionable output and preserve useful diagnostics. Examples: use `swiftlint --quiet` for fast Swift checks, use `--json` on repository build/test wrappers when you need structured diagnostics, and use focused test filters where possible. Avoid verbose command modes unless the extra output is needed to debug the issue.

**iOS Builds:**
- To check for Swift errors, run `swiftlint --quiet` (fast, catches common issues)
- Prefer not to run full iOS builds for small, focused changes. Use `swiftlint --quiet` and targeted inspection by default, then report when a build was intentionally skipped.
- Run the build wrapper when the user explicitly asks for a build, when the change is broad or risky enough that lint is insufficient, or when you know you are working autonomously on a longer task and should verify end-to-end before handing back.
- When building the iOS app, always run:

```bash
./scripts/xcode-build-agent.sh
```

- Do NOT run `xcodebuild` directly.
- JSON output is available with:

```bash
./scripts/xcode-build-agent.sh --json
```

- Interpretation rules:
  - Exit code `0` + `STATUS: SUCCESS` -> build succeeded
  - Non-zero exit code or `STATUS: FAILURE` -> build failed
  - If present, read the `WARNINGS` and `ERRORS` sections for diagnostics
- During active debugging sessions where the user is already rebuilding in Xcode or on device/simulator after each turn, do not auto-run the build wrapper for every small change.
- In that mode, skip build execution when the change is narrow and you are confident it does not introduce compile failures; report that you intentionally skipped the build so the user can validate in their normal loop.

**iOS Tests:**
- When running iOS tests from the terminal, always run:

```bash
./scripts/xcode-test-agent.sh
```

- Do NOT run `xcodebuild test` directly.
- JSON output is available with:

```bash
./scripts/xcode-test-agent.sh --json
```

- Pass focused test flags through to `xcodebuild test`, for example:

```bash
./scripts/xcode-test-agent.sh -- -only-testing:TidexAppTests/FriendsMessagesRepositoryTests
```

- Interpretation rules:
  - Exit code `0` + `STATUS: SUCCESS` -> tests passed
  - Non-zero exit code or `STATUS: FAILURE` -> tests failed
  - If present, read the `TESTS`, `WARNINGS`, `ERRORS`, and `test_failures` diagnostics
- During active debugging sessions where the user is already rebuilding/rerunning manually after each turn, do not auto-run tests for every small change.
- In that mode, skip test execution when the change is narrow and low-risk, and state that tests were intentionally skipped because the user is validating interactively.
