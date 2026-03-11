```

```

# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Project Overview

A monorepo containing two applications for tracking work shifts and calculating wages:

- **next/** - Next.js 16 web application with Supabase authentication
- **ios/** - Native iOS application

Both apps share a common Supabase backend (edge functions, migrations, database schema) located in `supabase/`.

## Repository Structure

```
tidex/
├── next/           # Next.js web application (see next/AGENTS.md)
├── marketing/      # Marketing static site (tidex.no)
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

## Supabase Edge Functions

**CRITICAL: Edit locally in `supabase/functions/`, deploy via CLI, NOT via MCP deploy tool**

- **Location**: `supabase/functions/<function-name>/index.ts`
- **Shared code**: `supabase/functions/_shared/`
- **Deployment**: `supabase functions deploy <name> --no-verify-jwt`

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
