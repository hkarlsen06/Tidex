# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Next.js 16 application for tracking work shifts and calculating wages with Supabase authentication. Supports internationalization (i18n) with Norwegian and English locales. Uses Tailwind CSS for styling with a custom design system and supports both light and dark modes.

## Next.js 16 Critical Updates

**IMPORTANT: This project uses Next.js 16. Key breaking changes:**

### Proxy (formerly Middleware)

- **File name**: `proxy.ts` (NOT `middleware.ts` - that name is deprecated)
- **Export name**: `proxy` (NOT `middleware`)
- **Runtime**: Node.js only (Edge runtime NOT supported)
- **Purpose**: Network boundary operations ONLY (routing, redirects, cookie management, token refresh)
- **NOT for**: Heavy logic, database queries, or complex operations (those belong in Server Components/Actions)
- **Confusion warning**: "Middleware" was renamed to "proxy" because developers confused it with Express.js middleware and did inappropriate heavy operations

### Async Request APIs (Breaking Change)

All these APIs are now **fully asynchronous** and must be awaited:
- `cookies()` → `await cookies()`
- `headers()` → `await headers()`
- `draftMode()` → `await draftMode()`
- `params` in pages/layouts → `const params = await props.params`
- `searchParams` in pages → `const searchParams = await props.searchParams`

### Other Breaking Changes

- **Node.js 20.9+** required (Node 18 dropped)
- **Turbopack** is now default (webpack requires explicit `--webpack` flag)
- **Parallel routes** require explicit `default.js` files or build fails
- **React 19** is supported (was React 18 before)
- **AMP support removed** completely
- **`next lint`** command removed (use ESLint/Biome directly)

## Development Commands

```bash
npm run dev         # Start HTTPS dev server via server.mjs (https://localhost:3000)
npm run dev:http    # Start HTTP dev server (http://localhost:3000)
npm run dev:turbo   # Start dev server with Turbo mode
npm run build       # Production build
npm start           # Run production server
npm run lint        # Run ESLint
```

## Architecture

### Route Structure

The application uses locale-based routing with dynamic `[locale]` segments for internationalization:

- `app/[locale]/(app)/*` - Protected routes requiring authentication (home, shifts, stats, settings)
- `app/[locale]/(auth)/*` - Public authentication routes (login, signup, verify-email, reset-password)
- `app/auth/callback/` - OAuth/magic link callback handler (unlocalized)

Each route group has its own layout:

- `app/[locale]/(app)/layout.tsx` - Authentication enforcement, renders TopHeader, wraps authenticated pages
- `app/[locale]/(auth)/layout.tsx` - Minimal layout for auth pages
- `app/[locale]/layout.tsx` - Locale wrapper with i18n providers
- `app/layout.tsx` - Root layout with theme initialization script, fonts, and metadata

**Key routes:**
- `/{locale}/` - Home/dashboard (protected)
- `/{locale}/shifts` - View and manage shifts (protected)
- `/{locale}/stats` - Statistics and analytics (protected)
- `/{locale}/settings` - Settings hub with nested routes (protected)
- `/{locale}/login` - Login page (public)
- `/{locale}/signup` - Sign up page (public)

### Internationalization (i18n)

The app supports multiple locales (Norwegian and English) via:

- **Locale routing**: All user-facing routes are prefixed with `[locale]` (e.g., `/en/shifts`, `/no/shifts`)
- **Locale detection**: `proxy.ts` middleware detects locale from URL, cookie (`NEXT_LOCALE`), or `Accept-Language` header
- **Automatic redirects**: Requests to non-localized paths (e.g., `/shifts`) are redirected to the user's preferred locale
- **Configuration**: See `lib/i18n/config.ts` for supported locales and settings
- **Translations**: Dictionary files in `lib/i18n/dictionaries/` provide localized strings

**Dictionary Loading (Optimized):**

To minimize bundle size and improve performance, the i18n system uses namespace-based filtering:

- **`getDictionary(locale)`** - Loads the complete dictionary for a locale (use sparingly)
- **`getAppDictionary(locale, namespaces[])`** - Loads only app shell + specified namespaces (preferred for most pages)
- **`getAuthDictionary(locale)`** - Shorthand for auth pages (loads `pages.auth` namespace)
- **`getMarketingDictionary(locale)`** - Loads `marketing` and `legal` namespaces

**App shell** always includes: `common`, `dateTime`, `header`, `footer`, `userMenu`, `navigation`, `components`

**When to use each:**
- Auth pages that use `LegalModal` must use `getDictionary()` to include the `legal` namespace
- Protected pages should use `getAppDictionary(locale, ['pages.home'])` with specific namespaces
- Only load namespaces actually used by the page to reduce serialization overhead

### Authentication Flow (Next.js 16)

Uses `@supabase/ssr` with cookie-based sessions following Next.js 16 best practices:

1. **Token refresh & locale routing**: `proxy.ts` handles both Supabase token refresh and locale routing (~1-5ms, no auth logic)
2. **Authentication enforcement**: Centralized in Data Access Layer via `verifySession()` from `data-access/auth.ts` (single source of truth)
3. **Prerender opt-out**: Protected pages call `connection()` from "next/server" to ensure dynamic rendering
4. **Server-side**: Use `createSupabaseServerClient()` from `lib/supabase/server.ts` in Server Components and data loaders
5. **Client-side**: Import the shared `supabase` instance from `lib/supabase/browser.ts` in Client Components
6. **Session sync**: `app/supabase-listener.tsx` subscribes to auth changes via the shared client and calls `router.refresh()` to update server components

**Important**: Authentication happens in the Data Access Layer via `verifySession()`, NOT in pages or layouts. All DAL functions verify authentication before data access. See `docs/auth.md` and `docs/dal-migration.md` for detailed flow.

#### Cookie Configuration (CRITICAL)

**See skill:** Use the `troubleshoot-supabase-cookies` skill if you encounter "Refresh Token Not Found" errors.

All Supabase clients MUST use consistent cookie configuration from `lib/auth/cookie-config.ts`. The three clients (proxy, server, browser) each have dedicated builder functions that ensure matching cookie settings. Never create cookie configurations inline.

### Component System

**See skill:** Use the `add-shadcn-component` skill for detailed instructions on adding UI components.

The project uses a two-tier component architecture: `components/ui/*` contains raw shadcn/ui components (never import directly), and `components/app/*` contains wrapped components with app-specific logic. Always import from `components/app`.

### Import Aliases

Defined in `tsconfig.json`:

- `@/*` - Project root (use `@/components/app/*` for app-specific components)
- `@components/*` - `components/`
- `@ui/*` - `components/ui/` (never import directly; shadcn/ui raw components)
- `@dal/*` - `data-access/` (Data Access Layer)

**Component imports:** Always use `@/components/app/*` (e.g., `import { Button } from '@/components/app/Button'`). Never import from `@ui/*` directly.

### Theming & Styling

**Dark mode is class-based**: The `dark` class on `<html>` toggles between themes.

Theme management:

- `ThemeToggle` component controls theme (in `components/app/ThemeToggle.tsx`)
- Theme state synced to localStorage
- Initial theme set via inline script in `app/layout.tsx` (prevents flash)
- Tailwind configured with `darkMode: ["class"]` in `tailwind.config.js`

**Color system**: CSS variables in `app/globals.css` define semantic tokens for light and dark modes:

- Surface: `bg-surface-primary`, `bg-surface-secondary`
- Text: `text-text-primary`, `text-text-secondary`, `text-text-muted`
- Background: `bg-background`, `bg-background-secondary`
- Borders: `border-border`, `border-border-subtle`
- Brand: `bg-brand-gradient-start`, etc.

**Never use hardcoded colors** (e.g., `bg-slate-900`, `text-gray-400`). Always use semantic tokens so components respond to theme changes.

The root `<body>` must have `bg-background text-foreground` classes for proper theming.

See `docs/THEME.md` for color token management.

### Payroll Calculation System

Pure, deterministic wage calculations live in `lib/payroll/`:

- **Entry point**: `computeShift(shift, settings, presetRules)` from `lib/payroll/calc.ts`
- **Zero I/O**: All inputs explicit, no dates from system clock
- **Server-side only**: Compute once per fetch in Data Access Layer (e.g., `data-access/shifts.ts`)
- **Client receives precomputed data**: UI renders `gross`, `paidHours`, etc. without recalculation

Key concepts:

- Base rate resolved from snapshot, preset table, or custom wage
- Time split into wage periods with supplement overlays
- Break deductions applied via configurable policies (fixed, proportional, etc.)
- [Removed] No per-shift manual pause; policy-based only
- Cross-midnight shifts supported (when `end <= start`, treat as next day)
- High precision calculations: 3 decimal places for hours, 2 for currency

### Data Access Layer (DAL)

**Centralized data loading in `data-access/` directory**

All database queries go through the DAL, which provides:

- **Authentication**: All DAL functions call `verifySession()` to ensure user is authenticated
- **Caching**: Uses React `cache()` for request deduplication and Next.js `unstable_cache()` for persistent caching
- **Computation**: Server-side payroll calculations via `computeShift()`
- **Type safety**: Returns fully typed, enriched data to pages

**Available DAL functions:**

```tsx
// data-access/auth.ts
export async function verifySession() // Returns authenticated user or redirects

// data-access/settings.ts
export async function getUserSettings() // Get user's pay/display settings
export async function getUserProfile()  // Get user profile data

// data-access/shifts.ts
export async function getComputedShifts(options) // Get shifts with payroll computations

// data-access/stats.ts
export async function getStatsData()    // Get aggregated statistics
export async function getChartsData()   // Get chart data for stats page

// data-access/subscription.ts
export async function getUserSubscriptionData() // Get subscription status
```

**See skill:** Use the `use-data-access-layer` skill for complete DAL usage patterns and examples.

Pages should NEVER call Supabase directly. Always use DAL functions which handle authentication, caching, and computations automatically.

### Server Actions & Utilities

**See skill:** Use the `create-server-action` skill for complete server action implementation patterns.

Server actions use centralized utilities from `lib/` for consistency:
- **Validation**: `lib/validation/shift-validators.ts` (isISODate, isHHMM)
- **Error messages**: `lib/errors/messages.ts` (ERRORS constants)
- **Revalidation**: `lib/revalidation/paths.ts` (invalidateAndRevalidate, revalidateShiftData)
- **Snapshots**: `data-access/snapshots.ts` (getCurrentSnapshots)

## Configuration Files

Configuration files are in the project root:

- `tailwind.config.js` - Tailwind theme and semantic colors
- `postcss.config.cjs` - PostCSS with Tailwind plugin
- `tsconfig.json` - TypeScript configuration with path aliases
- `next.config.js` - Next.js configuration with PWA settings and `cacheComponents: true`

## Dependency Management

**CRITICAL: Next.js Build-Time Dependencies**

Some packages must be in `dependencies` (not `devDependencies`) because they're required during production builds on Vercel:

**Required in `dependencies`:**
- `@next/bundle-analyzer` - Used by `next.config.js` at build time when wrapping the config
- `babel-plugin-react-compiler` - Required by Next.js React Compiler feature at build time
- Any package imported in `next.config.js` or used by Next.js plugins

**Why this matters:**
- Vercel's production builds install only `dependencies`, not `devDependencies`
- If Next.js imports a package at build time (via `next.config.js`), it must be in `dependencies`
- Build errors like `Cannot find package '@next/bundle-analyzer'` indicate a misplaced dependency

**General rule:** If a package is:
- Used only in tests → `devDependencies`
- Used only during local development → `devDependencies`
- Imported in `next.config.js` or required at build time → `dependencies`
- Used at runtime (imported in app code) → `dependencies`

## Environment Variables

Required in `.env.local`:

**Supabase (Authentication & Database):**
- `NEXT_PUBLIC_SUPABASE_URL` - Supabase project URL
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` - Supabase anon/public key

**Stripe (Subscriptions):**
- `NEXT_PUBLIC_PRO_PRICE_ID` - Stripe price ID for Pro tier
- `NEXT_PUBLIC_MAX_PRICE_ID` - Stripe price ID for Max tier

**Security:**
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY` - Cloudflare Turnstile site key for bot protection

**Optional:**
- `NEXT_PUBLIC_SITE_URL` - Full site URL (used for secure cookie determination)

Environment variables are validated at module load in `lib/env.ts` (throws errors if missing).

## Key Principles

1. **Never import from `components/ui` directly** - always wrap and import from `components/app`
2. **Use semantic color tokens** - avoid hardcoded Tailwind colors like `slate-*` or `gray-*`
3. **Use the Data Access Layer** - all database queries go through `data-access/`, never call Supabase directly in pages
4. **Opt out of prerendering** - protected pages must call `connection()` from "next/server" at the top
5. **Compute wages server-side** - `lib/payroll` functions are pure and called in DAL functions
6. **Theme-aware components** - all UI must respond to light/dark mode via CSS variables
7. **Respect locale routing** - all user-facing URLs should include `[locale]` parameter
8. **Use translation dictionaries** - import from `lib/i18n/dictionaries/` for user-facing text
9. **Use centralized utilities in server actions** - use validators, error messages, revalidation helpers, and snapshot preparation from `lib/` and `data-access/` for consistency

## Claude Code Behavior Guidelines

**IMPORTANT: Do NOT create unnecessary files or documentation:**

- **NO summary documents** (e.g., SUMMARY.md, CHANGES.md, REPORT.md) - waste of tokens
- **NO audit reports** unless explicitly requested for security/compliance
- **NO markdown files** unless they serve a critical project purpose (like this CLAUDE.md)
- **NO README files** unless user explicitly asks
- **Focus on code changes only** - communicate findings verbally in chat, not in files
- When asked to investigate or analyze, report findings in chat responses, not new files
