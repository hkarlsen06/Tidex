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

## iOS guidance

For native work, follow [ios/AGENTS.md](ios/AGENTS.md). Read [localization](ios/docs/AGENT_LOCALIZATION.md) when changing UI strings or catalogs and [verification](ios/docs/AGENT_VERIFICATION.md) when building or testing.

## App Store Connect / Fastlane Access

On Hjalmar's Mac, the existing Fastlane API configuration is saved in
`/Users/hkarlsen06/Lokalt/Secrets/Tidex/fastlane.env` (`ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_PATH`). `ios/fastlane/.env` is an ignored symlink
to that file, which Fastlane loads automatically. In a fresh checkout,
recreate the symlink or load the existing configuration before asking for
credentials. Keep the configuration and private key out of Git.

Use Homebrew Ruby at `/opt/homebrew/opt/ruby@3.4/bin`; the system Ruby is
too old for the installed bundle. From the repository root, bundled commands
use `BUNDLE_GEMFILE=ios/Gemfile BUNDLE_PATH=Vendor/bundle`.

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

### Migration-only schema policy

Keep `[db.migrations].schema_paths = []`. Do not introduce `supabase/schemas/`, declarative sync, or a pg-delta gate until the documented prerequisites are met. The existing migration history cannot safely establish a clean baseline. Use exact read-only inventories for production-state comparison. Preserve hand-written transitions and never infer authorization for migration-history repair from ordinary schema work.

Before revisiting adoption or planning a history cutover, read [the decision and prerequisites](docs/supabase-declarative-schema-decision.md).

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

# Bro keep going

Before you stop, ask yourself "is there a next step that the user would want me to do?" if so, keep going jobs not finished.
