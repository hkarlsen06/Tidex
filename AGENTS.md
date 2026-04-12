```

```

# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Project Overview

A monorepo for the Tidex iOS app and its supporting infrastructure.

Tidex is now an iOS-only product. The repository still includes supporting public/legal web surfaces, the legacy compatibility host for `app.tidex.no`, and the shared backend.

- **marketing/** - Next.js 16 public website for `tidex.no`
- **app-compat/** - Static Cloudflare Pages compatibility site for `app.tidex.no`
- **dev-site/** - Developer portfolio static site
- **ios/** - Native iOS application

The supporting web surfaces and iOS app share a common Supabase backend (edge functions, migrations, database schema) located in `supabase/`.

## Repository Structure

```
tidex/
├── marketing/      # Marketing static site (tidex.no)
├── app-compat/     # Compatibility redirects + Apple association files (app.tidex.no)
├── dev-site/       # Developer portfolio static site (kkarlsen.dev)
├── ios/            # Native iOS application (see ios/AGENTS.md)
├── supabase/       # Shared backend (edge functions, migrations)
└── docs/           # Shared documentation
```

## Developer Info

- **Primary developer user ID**: `032d8c2a-9af6-4777-99f0-24e2c4058bf3` (Hjalmar's account for testing/debugging)

## Available Skills

Use these skills for specialized tasks:

- `ios` - Start iOS development mode for working on the native Tidex iOS app
- `troubleshoot-supabase-cookies` - For "Refresh Token Not Found" errors
- `add-shadcn-component` - For adding UI components
- `motion-react` - For adding animations
- `use-data-access-layer` - For DAL usage patterns
- `create-server-action` - For server action patterns

## iOS Localization Scripts

Located in `ios/Scripts/`. Use `pnpm` commands from repo root as the default interface.

**Commands:**

```bash
pnpm ios:l10n:add -- --key "feature.key" --en "English" --nb "Norwegian"
pnpm ios:l10n:delete -- --key "feature.key"
pnpm ios:l10n:search -- "query"
pnpm ios:l10n:audit
pnpm ios:l10n:validate
```

## Local Chat Package Workflow

The Exyte `Chat` dependency is forked at `TidexHQ/Chat` and is also cloned locally at `../Chat` for day-to-day development.

- Default local development workflow: compile Tidex against the sibling `../Chat` clone.
- Switch package source with:

```bash
./scripts/set-chat-package-source.sh local
./scripts/set-chat-package-source.sh remote
```

- `local` mode points Xcode at `../../Chat` as a local Swift package.
- `remote` mode points Xcode back at `https://github.com/TidexHQ/Chat.git` for a portable committed state.
- When editing the package, make code changes in the sibling `../Chat` repo and commit them there, not inside `tidex`.
- Treat this as a hard rule: do not edit a resolved SwiftPM package checkout, build artifact, or any `Chat` source copy that lives under `tidex`.
- If a change should persist, it must land in `../Chat`, because that is the sustained fork repo and the source of truth for local package development.

**Release / shipping reminder:**

- If the user asks for work that implies a release or shared portable state, treat that as a reminder to check the `Chat` fork workflow.
- Examples: release, ship, App Store submission, TestFlight build, tagging a version, cutting a release, handing work off, or preparing CI-safe commits.
- Before those steps, if `../Chat` has relevant changes, remember to commit, tag, and push the `TidexHQ/Chat` fork.
- Before committing release-oriented Tidex project changes, run `./scripts/set-chat-package-source.sh remote`.
- After release work, switch back with `./scripts/set-chat-package-source.sh local` if continuing local package development.

## Supabase Edge Functions

**CRITICAL: Edit locally in `supabase/functions/`, deploy via CLI, NOT via MCP deploy tool**

- **Location**: `supabase/functions/<function-name>/index.ts`
- **Shared code**: `supabase/functions/_shared/`
- **Deployment**: `supabase functions deploy <name> --no-verify-jwt`
- **CLI rule**: Always include `--no-verify-jwt` when deploying edge functions with the Supabase CLI

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
- Use `supabase db pull` only when intentionally baselining or capturing remote-first schema changes back into `supabase/migrations/`.
- Do not treat `supabase/sql/migrations/` as the CLI-applied migration directory.
- Keep the SQL source files in `supabase/sql/functions/` in sync with the actual database definitions when making changes.

**Recommended workflow:**

1. Edit function/trigger source files in `supabase/sql/functions/` as needed.
2. Add or update the corresponding migration in `supabase/migrations/`.
3. Apply it with `supabase db push`.
4. If the remote database was changed outside the CLI workflow, reconcile with `supabase db pull` before continuing.

**Current Cron Jobs:**

| Job Name                              | Schedule      | Description               |
| ------------------------------------- | ------------- | ------------------------- |
| `cleanup-shift-notification-events` | `0 4 * * *` | Clean sent outbox entries |

## Agent Behavior Guidelines

**Do NOT create unnecessary files:**

- NO summary documents, audit reports, or markdown files unless explicitly requested
- Focus on code changes only - communicate findings in chat

**NEVER push to git automatically** - commit when requested, but wait for user approval before pushing.

Run commands from the repository root unless explicitly stated otherwise.

**iOS Builds:**
- To check for Swift errors, run `swiftlint` (fast, catches common issues)
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
