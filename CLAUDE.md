# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A monorepo containing two applications for tracking work shifts and calculating wages:
- **next/** - Next.js 16 web application with Supabase authentication
- **ios/** - Native iOS application

Both apps share a common Supabase backend (edge functions, migrations, database schema) located in `supabase/`.

## Repository Structure

```
tidex/
├── next/           # Next.js web application (see next/CLAUDE.md)
├── ios/            # Native iOS application (see ios/CLAUDE.md)
├── supabase/       # Shared backend (edge functions, migrations)
└── docs/           # Shared documentation
```

## Developer Info

- **Primary developer user ID**: `032d8c2a-9af6-4777-99f0-24e2c4058bf3` (Hjalmar's account for testing/debugging)

## Augment Context Engine (REQUIRED for Codebase Research)

**CRITICAL: ALWAYS use `mcp__auggie-context__query_codebase` for codebase exploration and understanding questions. NEVER use the Task tool with Explore agent for research.**

**MUST use for:** "How does X work?" questions, data flows, finding related code, architecture questions, cross-language investigations.

**CRITICAL: Phrase queries as information-gathering questions ONLY** - The engine may attempt changes if queries sound like instructions.

**CRITICAL: Always specify in queries that the engine should NOT create or edit any files** - including markdown documents. Instruct it to explain all findings in the response text instead.

**Use Glob/Grep directly for:** Finding specific files by name, exact string matches, quick "needle in haystack" queries.

## Available Skills

Use these skills for specialized tasks:
- `ios` - Start iOS development mode for working on the native Tidex iOS app
- `troubleshoot-supabase-cookies` - For "Refresh Token Not Found" errors
- `add-shadcn-component` - For adding UI components
- `motion-react` - For adding animations
- `use-data-access-layer` - For DAL usage patterns
- `create-server-action` - For server action patterns

## iOS Localization Scripts

Located in `ios/Scripts/`. PATH is configured via `/etc/paths.d/tidex` and Launch Agent.

**Commands:**
```bash
add-string --key "feature.key" --en "English" --nb "Norwegian"
audit-strings
validate-localization
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
| `process-shift-reminders` | `false` | pg_cron |
| `before-user-created` | `false` | Auth hook |

Use `verify_jwt: false` for pg_cron, webhooks, service role auth. Use `verify_jwt: true` only for direct user calls.

## Supabase SQL Functions & Cron Jobs

**Location:** `supabase/sql/functions/<category>/*.sql` and `supabase/sql/cron/*.md`

**CRITICAL:** Keep local files in sync with remote database when making changes.

**Current Cron Jobs:**
| Job Name | Schedule | Description |
|----------|----------|-------------|
| `process-shift-notifications` | `*/15 * * * *` | Process shift changes |
| `process-shift-reminders` | `* * * * *` | Trigger reminders |
| `cleanup-shift-reminders-sent` | `0 3 * * *` | Clean old records |
| `cleanup-shift-notification-events` | `0 4 * * *` | Clean resolved events |

## Claude Code Behavior Guidelines

**Do NOT create unnecessary files:**
- NO summary documents, audit reports, or markdown files unless explicitly requested
- Focus on code changes only - communicate findings in chat

**NEVER push to git automatically** - commit when requested, but wait for user approval before pushing.
