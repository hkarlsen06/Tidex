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
| Function | `verify_jwt` | Reason |
|----------|-------------|--------|
| `stripe_webhook` | `false` | Webhook |
| `apple-server-notifications` | `false` | Webhook |
| `apple-verify-purchase` | `true` | User-called |
| `send-push-notifications` | `false` | pg_cron |
| `before-user-created` | `false` | Auth hook |

Use `verify_jwt: false` for pg_cron, webhooks, service role auth. Use `verify_jwt: true` only for direct user calls.

## Supabase SQL Functions & Cron Jobs

**Location:** `supabase/sql/functions/<category>/*.sql` and `supabase/sql/cron/*.md`

**CRITICAL:** Keep local files in sync with remote database when making changes.

**Current Cron Jobs:**
| Job Name | Schedule | Description |
|----------|----------|-------------|
| `cleanup-shift-notification-events` | `0 4 * * *` | Clean sent outbox entries |

## Agent Behavior Guidelines

**Do NOT create unnecessary files:**
- NO summary documents, audit reports, or markdown files unless explicitly requested
- Focus on code changes only - communicate findings in chat

**NEVER push to git automatically** - commit when requested, but wait for user approval before pushing.

**iOS Builds:**
- **NEVER run `xcodebuild` directly** - it is slow and often fails due to environment issues (watchOS SDK, derived data, etc.)
- To check for Swift errors, run `swiftlint` instead (fast, catches common issues)
- At the end of your turn, **ask the user to run a build in Xcode** to catch any remaining compilation errors
