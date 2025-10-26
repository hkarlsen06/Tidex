# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Next.js 16 application for tracking work shifts and calculating wages with Supabase authentication. Supports internationalization (i18n) with Norwegian and English locales. Uses Tailwind CSS for styling with a custom design system and supports both light and dark modes.

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

### Authentication Flow (Next.js 16)

Uses `@supabase/ssr` with cookie-based sessions following Next.js 16 best practices:

1. **Token refresh & locale routing**: `proxy.ts` middleware handles both Supabase token refresh and locale routing (~1-5ms, no auth logic)
2. **Authentication enforcement**: `app/[locale]/(app)/layout.tsx` calls `getUser()` and redirects to `/login` (single source of truth)
3. **Server-side**: Use `createSupabaseServerClient()` from `lib/supabase/server.ts` in Server Components and data loaders
4. **Client-side**: Import the shared `supabase` instance from `lib/supabase/browser.ts` in Client Components
5. **Session sync**: `app/supabase-listener.tsx` subscribes to auth changes via the shared client and calls `router.refresh()` to update server components

**Important**: Authentication happens in Server Components (data access layer), NOT in proxy.ts. All routes under `app/[locale]/(app)/` are protected by the layout. See `docs/auth.md` for detailed flow.

### Component System

**Critical: Two-tier component architecture**

- `components/ui/*` - Raw shadcn/ui components (generated, do not import directly)
- `components/app/*` - Wrapped components with app-specific logic and styling

**Always import from `components/app`, never from `components/ui`**

To add new shadcn components:

```bash
npm dlx shadcn@latest add <component-name>
```

Then create a wrapper in `components/app/` following existing patterns in that directory.

### Import Aliases

Defined in `tsconfig.json`:

- `@/*` - Project root
- `@components/*` - `components/`
- `@ui/*` - `components/ui/`
- `@appui/*` - `components/app/`

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
- Brand: `bg-brand-gradientStart`, etc.

**Never use hardcoded colors** (e.g., `bg-slate-900`, `text-gray-400`). Always use semantic tokens so components respond to theme changes.

The root `<body>` must have `bg-background text-foreground` classes for proper theming.

See `docs/THEME.md` for color token management.

### Payroll Calculation System

Pure, deterministic wage calculations live in `lib/payroll/`:

- **Entry point**: `computeShift(shift, settings, presetRules)` from `lib/payroll/calc.ts`
- **Zero I/O**: All inputs explicit, no dates from system clock
- **Server-side only**: Compute once per fetch in data loaders (e.g., `app/(app)/shifts/_data/getShifts.ts`)
- **Client receives precomputed data**: UI renders `gross`, `paidHours`, etc. without recalculation

Key concepts:

- Base rate resolved from snapshot, preset table, or custom wage
- Time split into wage periods with supplement overlays
- Break deductions applied via configurable policies (fixed, proportional, etc.)
- [Removed] No per-shift manual pause; policy-based only
- Cross-midnight shifts supported (when `end <= start`, treat as next day)
- High precision calculations: 3 decimal places for hours, 2 for currency

### Data Loading Pattern

Server Components fetch and compute data:

```tsx
// app/(app)/shifts/_data/getShifts.ts
export async function getComputedShifts(userId: string) {
  const supabase = await createSupabaseServerClient();
  // 1. Load user settings
  // 2. Load raw shifts
  // 3. Compute each shift with computeShift()
  // 4. Return enriched shifts with derived fields
}
```

Pages import and await these loaders, never calling Supabase directly.

## Configuration Files

Configuration files are in the project root:

- `tailwind.config.js` - Tailwind theme and semantic colors
- `postcss.config.cjs` - PostCSS with Tailwind plugin
- `tsconfig.json` - TypeScript configuration with path aliases
- `next.config.js` - Next.js configuration with PWA settings

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
3. **Centralize Supabase access** - use helpers in `lib/supabase`, never instantiate clients elsewhere
4. **Compute wages server-side** - `lib/payroll` functions are pure and called in data loaders
5. **Theme-aware components** - all UI must respond to light/dark mode via CSS variables
6. **Server-first auth checks** - redirect before render to avoid unauthenticated UI flashes
7. **Respect locale routing** - all user-facing URLs should include `[locale]` parameter
8. **Use translation dictionaries** - import from `lib/i18n/dictionaries/` for user-facing text
