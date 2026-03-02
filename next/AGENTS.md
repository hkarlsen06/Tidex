# Next.js AGENTS.md

Next.js-specific development guidance for the Tidex web application.

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

**Status:** Migration complete

All DAL and services use Effect-TS internally with Promise wrappers at boundaries for Next.js compatibility.

### Architecture

- **Effect in Core**: DAL and services use Effect for type-safe operations
- **Promises at Boundaries**: Pages/Server Actions remain Promise-based
- **Services**: `lib/services/` (AppConfig, SupabaseService, AuthService, SettingsService, SnapshotsService, ShiftsService, StatsService, SubscriptionService, ClaudeService, WageyService, SharingService)
- **Tagged Errors**: `lib/errors/tagged.ts`
- **Layers**: `lib/layers/app.ts`

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
