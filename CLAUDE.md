# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Next.js 16 application for tracking work shifts and calculating wages with Supabase authentication. Supports internationalization (i18n) with Norwegian and English locales. Uses Tailwind CSS for styling with a custom design system and supports both light and dark modes.

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

## iOS Development Rules

**Current iOS version: iOS 26** (released September 2025). Apple changed version numbering at WWDC 2025 to align all operating systems. iOS 26 introduced the "Liquid Glass" design language.

**NEVER run Xcode builds automatically.** Prompt the user to build in Xcode themselves.

**ONLY create API routes when service role privileges are required.** Everything that can be done in the iOS binary using the user's JWT + RLS policies should stay there. Examples:
- ✅ API route needed: `/api/delete-account` (needs admin API), `/api/push-device` (needs `internal` schema)
- ❌ No API route: Subscription/entitlement data, settings, shifts - use Supabase client directly or RPC functions

### iOS Color System

**ALWAYS use semantic Tidex colors** from `Color+Tidex.swift`. Never use hardcoded colors or non-existent color names.

Available colors (all adapt to light/dark mode):
| Category | Colors |
|----------|--------|
| Background | `tidexBackground`, `tidexBackgroundSecondary`, `tidexLaunchBackground` |
| Surface | `tidexSurfacePrimary`, `tidexSurfaceSecondary` |
| Text | `tidexTextPrimary`, `tidexTextSecondary`, `tidexTextMuted`, `tidexTextInverse` |
| Brand | `tidexBlue`, `tidexBrandPrimary`, `tidexPurple` |
| Border | `tidexBorder`, `tidexBorderSubtle` |
| Status | `tidexError`, `tidexSuccess`, `tidexWarning`, `tidexInfo` |

Usage: `Color.tidexSurfacePrimary`, `Color.tidexTextSecondary`, etc.

## CRITICAL: Cache Invalidation (Next.js 16)

**ALWAYS use `revalidateTag(tag, "max")` - NEVER use `updateTag()`**

- `updateTag()` only works in Server Actions (throws runtime error in Route Handlers)
- Next.js 16 requires second argument: `revalidateTag(tag, "max")`
- Use `invalidateUserCache(userId)` from `data-access/cache.ts` for consistency
- DAL functions set tags using `cacheTag(`user-${userId}`, "category-name")` - invalidate with `revalidateTag(`user-${userId}`, "max")`

## Next.js 16 Critical Updates

### Proxy (formerly Middleware)

- **File name**: `proxy.ts` (NOT `middleware.ts`)
- **Export name**: `proxy` (NOT `middleware`)
- **Runtime**: Node.js only (Edge runtime NOT supported)
- **Purpose**: Network boundary operations ONLY (routing, redirects, cookie management, token refresh)

### Async Request APIs (Breaking Change)

All these APIs must be awaited:
- `cookies()` → `await cookies()`
- `headers()` → `await headers()`
- `params` in pages/layouts → `const params = await props.params`
- `searchParams` in pages → `const searchParams = await props.searchParams`

### Other Breaking Changes

- **Node.js 24+** required (see `.nvmrc`)
- **Turbopack** is now default
- **Parallel routes** require explicit `default.js` files
- **React 19** supported
- **`next lint`** removed (use ESLint/Biome directly)

## Development Commands

```bash
pnpm dev         # Start dev server (http://localhost:3000)
pnpm dev:https   # Start HTTPS dev server (https://localhost:3000)
pnpm build       # Production build
pnpm start       # Run production server
pnpm lint        # Run ESLint
```

## Architecture

### Route Structure

- `app/[locale]/(app)/*` - Protected routes (dashboard, shifts, stats, settings, wagey, sharing)
- `app/[locale]/(auth)/*` - Public auth routes (login, signup, verify-email, reset-password, mfa-verify, accept-terms)
- `app/auth/callback/` - OAuth/magic link callback handler (unlocalized)

### Internationalization (i18n)

- **Locale routing**: Routes prefixed with `[locale]` (e.g., `/en/shifts`, `/no/shifts`)
- **Configuration**: `lib/i18n/config.ts`
- **Translations**: `lib/i18n/dictionaries/`

**Dictionary Loading:**
- `getDictionary(locale)` - Complete dictionary (use sparingly)
- `getAppDictionary(locale, namespaces[])` - App shell + specified namespaces (preferred)
- `getAuthDictionary(locale)` - For auth pages
- `getMarketingDictionary(locale)` - For marketing pages

### Authentication Flow (Next.js 16)

Uses `@supabase/ssr` with cookie-based sessions:

1. `proxy.ts` handles token refresh and locale routing
2. Authentication enforced via `verifySession()` from `data-access/auth.ts`
3. Protected pages call `connection()` from "next/server" for dynamic rendering
4. Server-side: `createSupabaseServerClient()` from `lib/supabase/server.ts`
5. Client-side: `supabase` from `lib/supabase/browser.ts`

All Supabase clients MUST use cookie configuration from `lib/auth/cookie-config.ts`.

### API Routes for Native iOS App

**Only create API routes when the iOS app needs service role privileges.** Most operations should use the Supabase client directly in Swift with the user's JWT.

When an API route IS needed (`app/api/*`):

1. **Auth is automatic** - Both `getSession()` and `createSupabaseServerClient()` handle Bearer tokens (iOS) and cookies (web)
2. **Use DAL functions when available** - They work with Bearer auth automatically
3. **Use service client for internal schema** - `createSupabaseServiceClient()` for `internal` schema (when no DAL function exists)
4. **Return simple JSON responses** - Keep shapes flat and Swift-Codable friendly

**Current iOS API routes (all require service role):**
- `/api/delete-account` - Needs admin API to delete auth user
- `/api/push-device` - Needs access to `internal` schema
- `/api/profile-picture` - Needs storage operations with user context
- `/api/sharing/previews` - Uses DAL function with Bearer auth

### Component System

Two-tier architecture: `components/ui/*` (raw shadcn/ui - never import directly) and `components/app/*` (wrapped with app logic - always import from here).

**Skeleton components**: `@/components/app/skeletons`

### Import Aliases

- `@/*` - Project root
- `@components/*` - `components/`
- `@ui/*` - `components/ui/` (never import directly)
- `@dal/*` - `data-access/`

### Theming & Styling

**Dark mode is class-based** via `dark` class on `<html>`.

**Color system**: CSS variables in `app/globals.css` define semantic tokens. **Never use hardcoded colors** (e.g., `bg-slate-900`). Always use semantic tokens (`bg-surface-primary`, `text-text-primary`, etc.).

See `docs/THEME.md` for details.

### Animations

Uses **Motion for React** (import from `motion/react`, never `framer-motion`). For server components: `import * as motion from "motion/react-client"`.

### Payroll Calculation System

Pure, deterministic calculations in `lib/payroll/`:
- **Pure**: `computeShift(shift, settings, presetRules)` from `lib/payroll/calc.ts`
- **Effect**: `computeShift` from `lib/payroll/effect.ts` with validation
- **Server-side only**: Computed in DAL, client receives precomputed data

### Data Access Layer (DAL)

All database queries go through `data-access/`. Provides authentication, caching, computation, and type safety.

**Key functions:** `verifySession()`, `getSession()`, `getUserSettings()`, `getComputedShifts()`, `getStatsData()`, `getUserSubscriptionData()`, `getWageyAccess()`, `getSharingData()`, `getCurrentSnapshots()`, `getUserWageSnapshots()`

Pages should NEVER call Supabase directly.

### Server Actions & Utilities

- **Validation**: `lib/validation/schemas.ts` (Effect Schema), `lib/validation/shift-validators.ts` (legacy)
- **Error messages**: `lib/errors/messages.ts`
- **Tagged errors**: `lib/errors/tagged.ts`
- **Revalidation**: `lib/revalidation/paths.ts`

## Configuration Files

- `postcss.config.cjs` - PostCSS with Tailwind v4
- `tsconfig.json` - TypeScript with path aliases
- `next.config.js` - Next.js with PWA settings

**Note**: Tailwind v4 uses CSS-first config via `@theme` in `app/globals.css`.

## Dependency Management

**CRITICAL:** Packages required at build time must be in `dependencies` (not `devDependencies`):
- `@next/bundle-analyzer`
- `babel-plugin-react-compiler`
- Any package imported in `next.config.js`

## Environment Variables

Required in `.env.local`:
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_PRO_PRICE_ID`, `NEXT_PUBLIC_MAX_PRICE_ID`
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY`

Optional: `NEXT_PUBLIC_SITE_URL`

Validated at module load in `lib/env.ts`.

## Effect-TS Integration

**Status:** Migration complete ✅

All DAL and services use Effect-TS internally with Promise wrappers at boundaries for Next.js compatibility.

### Architecture

- **Effect in Core**: DAL and services use Effect for type-safe operations
- **Promises at Boundaries**: Pages/Server Actions remain Promise-based
- **Services**: `lib/services/` (AppConfig, SupabaseService, AuthService, SettingsService, SnapshotsService, ShiftsService, StatsService, SubscriptionService, ClaudeService, WageyService, SharingService)
- **Tagged Errors**: `lib/errors/tagged.ts`
- **Layers**: `lib/layers/app.ts`

**For detailed patterns and examples, see `docs/effect-patterns.md`**

See also: `EFFECT_MIGRATION.md`, `docs/error-handling-audit.md`

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

## Key Principles

1. **Never import from `components/ui` directly** - use `components/app`
2. **Use semantic color tokens** - no hardcoded colors
3. **Use the Data Access Layer** - never call Supabase in pages
4. **Opt out of prerendering** - call `connection()` in protected pages
5. **Compute wages server-side** - in DAL, not client
6. **Theme-aware components** - respond to light/dark mode
7. **Respect locale routing** - include `[locale]` in URLs
8. **Use translation dictionaries** - `lib/i18n/dictionaries/`
9. **Use centralized utilities** - validators, error messages, revalidation helpers
10. **Use Effect for DAL/service code** - with Promise wrappers at boundaries

## Claude Code Behavior Guidelines

**Do NOT create unnecessary files:**
- NO summary documents, audit reports, or markdown files unless explicitly requested
- Focus on code changes only - communicate findings in chat

**NEVER push to git automatically** - commit when requested, but wait for user approval before pushing.
