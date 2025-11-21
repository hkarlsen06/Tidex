# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Next.js 16 application for tracking work shifts and calculating wages with Supabase authentication. Supports internationalization (i18n) with Norwegian and English locales. Uses Tailwind CSS for styling with a custom design system and supports both light and dark modes.

## CRITICAL: Cache Invalidation in Route Handlers vs Server Actions (Next.js 16)

**NEVER use `updateTag()` - ALWAYS use `revalidateTag()` with second argument**

- `updateTag()` only works in Server Actions (throws runtime error in Route Handlers)
- `revalidateTag()` works in both Server Actions AND Route Handlers
- **Next.js 16 requires second argument**: `revalidateTag(tag, "max")` to immediately expire cache
- All cache invalidation functions in `data-access/cache.ts` use `revalidateTag()` for compatibility
- When calling Server Actions from Route Handlers (e.g., Wagey chat executor), the actions MUST use `revalidateTag()` for cache invalidation

**Example of the error if you use updateTag in a Route Handler:**
```
Error: updateTag can only be called from within a Server Action.
To invalidate cache tags in Route Handlers or other contexts, use revalidateTag instead.
```

**Example of deprecation warning if you omit second argument:**
```
"revalidateTag" without the second argument is now deprecated, add second argument of "max" or use "updateTag".
```

**Correct usage (Next.js 16):**
```typescript
// ✅ CORRECT - Works everywhere and includes required second argument
import { revalidateTag } from "next/cache";
revalidateTag(`user-shifts-${userId}`, "max");

// ❌ WRONG - Missing second argument (deprecated in Next.js 16)
revalidateTag(`user-shifts-${userId}`);

// ❌ WRONG - Only works in Server Actions
import { updateTag } from "next/cache";
updateTag(`user-shifts-${userId}`); // Throws error in Route Handlers
```

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

- **Entry point (pure)**: `computeShift(shift, settings, presetRules)` from `lib/payroll/calc.ts`
- **Entry point (Effect)**: `computeShift` from `lib/payroll/effect.ts` with validation and typed errors
- **Zero I/O**: All inputs explicit, no dates from system clock
- **Server-side only**: Compute once per fetch in Data Access Layer via services
- **Client receives precomputed data**: UI renders `gross`, `paidHours`, etc. without recalculation

**Effect Integration:**
- Services use Effect-wrapped `computeShift` for type-safe validation
- Schema validation ensures valid shift inputs (dates, times, wages)
- Tagged errors (`ValidationError`, `ComputationError`) for failures
- Property-based tests verify computation invariants

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
- **Effect-based services**: All DAL functions use Effect internally via `lib/services/` for type-safe operations
- **Caching**: Uses React `cache()` for request deduplication and Effect Cache for persistent caching
- **Computation**: Server-side payroll calculations via Effect-wrapped `computeShift()`
- **Type safety**: Returns fully typed, enriched data with typed errors
- **Promise boundaries**: DAL exports Promise-based APIs for Next.js compatibility

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
- **Validation**:
  - `lib/validation/schemas.ts` - Effect Schema validation with branded types
  - `lib/validation/shift-validators.ts` - Legacy validators (isISODate, isHHMM) for backward compatibility
- **Error messages**: `lib/errors/messages.ts` (ERRORS constants for user-facing Norwegian messages)
- **Tagged errors**: `lib/errors/tagged.ts` (typed error classes for Effect pipelines)
- **Revalidation**: `lib/revalidation/paths.ts` (Effect-wrapped cache invalidation)
- **Snapshots**: `data-access/snapshots.ts` (Effect-based snapshot preparation)

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

## Effect-TS Integration

**Status:** Phase 6 complete - Migration finished ✅

This project uses Effect-TS for improved type safety, error handling, and testability across all DAL and services. See `EFFECT_MIGRATION.md` for the complete migration plan and `docs/error-handling-audit.md` for error handling patterns.

### Architecture

- **Effect in Core**: All DAL and services use Effect internally for type-safe operations
- **Promises at Boundaries**: Pages and Server Actions remain Promise-based for Next.js compatibility
- **Services Layer**: `lib/services/` contains Effect-based services (all services migrated)
- **Tagged Errors**: All errors use typed classes from `lib/errors/tagged.ts`
- **Layer Composition**: `lib/layers/app.ts` provides all services via dependency injection

### Available Services

All services are in `lib/services/` and accessed via Context.Tag:

- **AppConfig**: Environment configuration with validation
- **SupabaseService**: Database operations with retry and caching
- **AuthService**: Authentication and session management
- **SettingsService**: User settings and profile data
- **SnapshotsService**: Wage snapshot management
- **ShiftsService**: Shift data with payroll computations
- **StatsService**: Statistics and analytics
- **SubscriptionService**: Subscription and profile management

### Service Usage Examples

**Using SupabaseService**:
```typescript
import { SupabaseService } from "@/lib/services/supabase"
import { SupabaseLive } from "@/lib/layers/app"

const program = Effect.gen(function* () {
  const supabase = yield* SupabaseService

  const result = yield* supabase.query(
    async (client) => await client.from("shifts").select("*"),
    { retries: 2 }
  )

  return result
}).pipe(Effect.provide(SupabaseLive), Effect.scoped)

const data = await Effect.runPromise(program)
```

**Using ShiftsService**:
```typescript
import { ShiftsService } from "@/lib/services/shifts"
import { ShiftsLive } from "@/lib/layers/app"

const program = Effect.gen(function* () {
  const shifts = yield* ShiftsService

  const data = yield* shifts.getShiftsWithComputations({
    userId: "user-id",
    year: 2025,
    month: 1
  })

  return data
}).pipe(Effect.provide(ShiftsLive), Effect.scoped)

const shifts = await Effect.runPromise(program)
```

**Using Multiple Services**:
```typescript
import { AuthService, SettingsService } from "@/lib/services"
import { AuthSettingsLive } from "@/lib/layers/app"

const program = Effect.gen(function* () {
  const auth = yield* AuthService
  const settings = yield* SettingsService

  const session = yield* auth.getSession()
  const userSettings = yield* settings.getUserSettings(session.user.id)

  return { session, userSettings }
}).pipe(Effect.provide(AuthSettingsLive), Effect.scoped)

const data = await Effect.runPromise(program)
```

**Validation with Schema**:
```typescript
import { validateShiftInput } from "@/lib/validation/schemas"
import { ValidationError } from "@/lib/errors/tagged"

const program = validateShiftInput(data).pipe(
  Effect.mapError((error) => new ValidationError({
    field: "shift",
    message: "Invalid shift data"
  }))
)

const validShift = await Effect.runPromise(program)
```

### Effect Patterns

**1. Creating a Service**:
```typescript
import { Context, Effect, Layer } from "effect"
import { SupabaseService } from "./supabase"

export class MyService extends Context.Tag("MyService")<
  MyService,
  {
    readonly getData: (id: string) => Effect.Effect<Data, DatabaseError, never>
  }
>() {}

export const MyServiceLive = Layer.effect(
  MyService,
  Effect.gen(function* () {
    const supabase = yield* SupabaseService

    const getData = (id: string) =>
      Effect.gen(function* () {
        const result = yield* supabase.query(
          async (client) => await client.from("data").select("*").eq("id", id).single(),
          { retries: 2 }
        )
        return result
      })

    return { getData }
  })
)
```

**2. Composing Layers**:
```typescript
import { Layer } from "effect"
import { SupabaseLive } from "./supabase"
import { MyServiceLive } from "./my-service"

// Provide dependencies automatically
export const MyServiceWithDeps = Layer.provideMerge(MyServiceLive, SupabaseLive)
```

**3. Error Handling with catchTag**:
```typescript
import { NotFoundError, DatabaseError } from "@/lib/errors/tagged"

const program = Effect.gen(function* () {
  const data = yield* supabase.query(...)
  if (!data) {
    yield* Effect.fail(new NotFoundError({ resource: "User", id: "123" }))
  }
  return data
}).pipe(
  Effect.catchTag("NotFoundError", () => Effect.succeed(null)),
  Effect.catchTag("DatabaseError", (error) => {
    if (error.code === "NO_DATA") {
      return Effect.succeed(null)
    }
    logger.error("Database error:", error)
    return Effect.fail(error)
  })
)
```

**4. Parallel Execution**:
```typescript
const program = Effect.gen(function* () {
  // Execute queries in parallel
  const [shifts, settings, profile] = yield* Effect.all(
    [
      shiftsService.getShifts(userId),
      settingsService.getUserSettings(userId),
      subscription.getUserProfile(userId),
    ],
    { concurrency: 3 }
  )

  return { shifts, settings, profile }
})
```

**5. Branded Types for Validation**:
```typescript
import { Schema } from "effect"

// Define branded type
export const ISODateString = Schema.String.pipe(
  Schema.pattern(/^\d{4}-\d{2}-\d{2}$/),
  Schema.brand("ISODateString")
)

export type ISODateString = typeof ISODateString.Type

// Use in validation
const program = Schema.decodeUnknown(ISODateString)("2025-01-15")
const date = await Effect.runPromise(program) // Type: ISODateString
```

**6. Caching with Effect.Cache**:
```typescript
import { Cache, Duration } from "effect"

const cache = yield* Cache.make({
  capacity: 100,
  timeToLive: Duration.minutes(10),
  lookup: (key: string) =>
    Effect.gen(function* () {
      const supabase = yield* SupabaseService
      const data = yield* supabase.query(...)
      return data
    })
})

// Automatic deduplication and caching
const data = yield* cache.get("user-123")
```

**7. Wrapping Side Effects**:
```typescript
import { Effect } from "effect"

// Wrap Next.js cache operations
export const invalidateCacheEffect = (userId: string) =>
  Effect.sync(() => {
    updateTag(`user-${userId}`)
    revalidatePath("/", "layout")
  })

// Use in Effect pipeline
yield* invalidateCacheEffect(userId)
```

**8. Promise Wrappers for Next.js**:
```typescript
// Effect-based internal implementation
async function getUserDataInternal(userId: string): Promise<Data> {
  const program = Effect.gen(function* () {
    const service = yield* MyService
    const data = yield* service.getData(userId)
    return data
  }).pipe(Effect.provide(MyServiceLive), Effect.scoped)

  try {
    return await Effect.runPromise(program)
  } catch (error) {
    logger.error("Failed to get user data:", error)
    return null
  }
}

// Export Promise-based API for Next.js
export const getUserData = cache(getUserDataInternal)
```

### Testing with Effect

**Unit Tests with Effect.runPromise**:
```typescript
import { Effect } from "effect"
import { computeShift } from "@/lib/payroll/effect"

it("should compute shift correctly", async () => {
  const program = computeShift(shift, settings, rules)
  const result = await Effect.runPromise(program)

  expect(result.gross).toBeGreaterThan(0)
})

it("should handle validation errors", async () => {
  const program = computeShift(invalidShift, settings, rules)
  const result = await Effect.runPromise(Effect.either(program))

  expect(result._tag).toBe("Left")
  if (result._tag === "Left") {
    expect(result.left._tag).toBe("ValidationError")
  }
})
```

**Property-Based Tests with fast-check**:
```typescript
import { fc } from "@fast-check/vitest"

it("should never have paid hours exceed duration hours", () => {
  fc.assert(
    fc.property(shiftArbitrary, async (shift) => {
      const program = computeShift(shift, settings, [])
      const result = await Effect.runPromise(program)

      expect(result.paidHours).toBeLessThanOrEqual(result.durationHours)
    })
  )
})
```

### Migration Status

**✅ Completed:**
- **Phase 1**: Foundation (Effect setup, tagged errors, config, payroll)
- **Phase 2**: Database & Simple DAL (Supabase, Auth, Settings services)
- **Phase 3**: Complex DAL - Shifts (ShiftsService, SnapshotsService, parallel execution)
- **Phase 4**: Complex DAL - Stats (StatsService with aggregations)
- **Phase 5**: Remaining & Utilities (Subscription, validation, cache, revalidation)
- **Phase 6**: Testing & Documentation (property-based tests, error handling audit, documentation)

**All DAL and services are now Effect-based** ✅

See `EFFECT_MIGRATION.md` for detailed migration plan.
See `docs/error-handling-audit.md` for comprehensive error handling audit.

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
10. **Use Effect for all DAL/service code** - All DAL functions and services use Effect-TS internally with Promise wrappers at boundaries (see Effect-TS Integration section)

## Claude Code Behavior Guidelines

**IMPORTANT: Do NOT create unnecessary files or documentation:**

- **NO summary documents** (e.g., SUMMARY.md, CHANGES.md, REPORT.md) - waste of tokens
- **NO audit reports** unless explicitly requested for security/compliance
- **NO markdown files** unless they serve a critical project purpose (like this CLAUDE.md)
- **NO README files** unless user explicitly asks
- **Focus on code changes only** - communicate findings verbally in chat, not in files
- When asked to investigate or analyze, report findings in chat responses, not new files
