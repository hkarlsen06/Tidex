# Architecture

**Analysis Date:** 2026-01-13

## Pattern Overview

**Overall:** Full-Stack Layered Architecture with Effect-TS Services

**Key Characteristics:**
- Next.js 16 App Router with locale-based routing
- Effect-TS for type-safe services and error handling
- Centralized Data Access Layer (DAL) with Promise boundaries
- Supabase for database, auth, and edge functions
- Capacitor for iOS native bridge

## Layers

**Proxy Layer (`proxy.ts`):**
- Purpose: Network boundary operations only
- Contains: Token refresh, locale routing, cookie management
- Depends on: Supabase client
- Used by: All incoming requests

**Presentation Layer (`app/[locale]/`, `components/`):**
- Purpose: UI rendering and user interaction
- Contains: Pages, layouts, React components
- Depends on: Data Access Layer, components
- Used by: End users via browser/iOS app

**Data Access Layer (`data-access/`):**
- Purpose: Data loading with authentication enforcement
- Contains: `auth.ts`, `shifts.ts`, `settings.ts`, `stats.ts`, `subscription.ts`, `wagey.ts`, `sharing.ts`
- Depends on: Effect-based Services
- Used by: Pages, Server Actions, API Routes

**Service Layer (`lib/services/`):**
- Purpose: Business logic with Effect-TS type safety
- Contains: `supabase.ts`, `auth.ts`, `shifts.ts`, `stats.ts`, `claude.ts`, `wagey.ts`, `sharing.ts`
- Depends on: SupabaseService, AppConfig
- Used by: Data Access Layer (via Effect.runPromise)

**Payroll Computation (`lib/payroll/`):**
- Purpose: Pure, deterministic wage calculations
- Contains: `calc.ts`, `effect.ts`, `periods.ts`, `breaks.ts`, `presets.ts`
- Depends on: None (pure functions)
- Used by: ShiftsService for shift computations

**Utility Layer (`lib/`):**
- Purpose: Shared utilities and abstractions
- Contains: Validation, formatters, date utils, error types
- Depends on: Effect, Zod
- Used by: All other layers

## Data Flow

**Authenticated Request Lifecycle:**

1. Request arrives at `proxy.ts`
2. Proxy refreshes Supabase tokens (if needed)
3. Proxy routes to locale-prefixed path
4. Page component calls DAL function (e.g., `getComputedShifts`)
5. DAL calls `verifySession()` internally
6. DAL invokes Effect-based Service
7. Service queries Supabase, computes payroll
8. Result returned as Promise to page
9. Page renders with data

**State Management:**
- Server-side: React `cache()` for request deduplication
- Client-side: React state, no global store
- Cache: `cacheTag`/`revalidateTag` for user-scoped invalidation

## Key Abstractions

**Effect Service:**
- Purpose: Type-safe service with dependency injection
- Examples: `ShiftsService`, `SupabaseService`, `AuthService`
- Pattern: `Context.Tag` with `Layer.effect` implementation

**Tagged Error:**
- Purpose: Type-safe error handling with `Effect.catchTag`
- Examples: `DatabaseError`, `ValidationError`, `NotFoundError`, `AuthError`
- Pattern: `Data.TaggedError` with `_tag` discriminant

**DAL Function:**
- Purpose: Promise-based API for Next.js compatibility
- Examples: `getComputedShifts`, `getUserSettings`, `verifySession`
- Pattern: Wraps Effect in `Effect.runPromise` with error handling

**Server Action:**
- Purpose: Form submissions and mutations
- Examples: `createShift`, `updateShift`, `deleteShift`
- Pattern: `"use server"` function calling DAL with revalidation

## Entry Points

**Root Layout (`app/layout.tsx`):**
- Triggers: All page loads
- Responsibilities: Theme initialization, fonts, metadata, PWA manifest

**Proxy (`proxy.ts`):**
- Triggers: All HTTP requests
- Responsibilities: Token refresh, locale detection, routing

**Locale Layout (`app/[locale]/layout.tsx`):**
- Triggers: Locale-prefixed routes
- Responsibilities: i18n provider, dictionary loading

**Auth Callback (`app/auth/callback/route.ts`):**
- Triggers: OAuth redirects, magic links
- Responsibilities: Exchange code for session, redirect to app

## Error Handling

**Strategy:** Tagged errors bubble up, caught at DAL/page boundaries

**Patterns:**
- Services throw `DatabaseError`, `ValidationError`, `NotFoundError`
- DAL catches with `Effect.catchTag` or `Effect.match`
- Pages redirect on `AuthError`, show error UI on others
- Server Actions return `{ error: string }` for form errors

**Error Types (`lib/errors/tagged.ts`):**
- `DatabaseError` - Supabase query failures
- `ValidationError` - Input validation failures
- `NotFoundError` - Resource not found
- `AuthError` - Authentication failures
- `ConfigError` - Missing configuration
- `ComputationError` - Payroll calculation failures

## Cross-Cutting Concerns

**Logging:**
- `lib/logger.ts` wrapper over console
- Structured logging in production (stdout for Vercel)

**Validation:**
- `lib/validation/schemas.ts` - Effect Schema with branded types
- `lib/validation/shift-validators.ts` - Legacy validators (isISODate, isHHMM)
- Zod schemas for runtime validation

**Authentication:**
- `data-access/auth.ts` - `verifySession()` single source of truth
- All DAL functions call `verifySession()` internally
- No direct Supabase calls in pages

**Caching:**
- React `cache()` for request deduplication
- `cacheTag()` for user-scoped cache tags
- `revalidateTag(tag, "max")` for immediate invalidation (Next.js 16)

**Internationalization:**
- `lib/i18n/` - Locale detection, dictionary loading
- Namespace-based filtering for bundle optimization
- `getAppDictionary(locale, namespaces)` pattern

## Service Composition

**Layer Hierarchy (`lib/layers/app.ts`):**

```
AppLive
├── AppConfigLive (environment variables)
├── SupabaseLive (database operations)
├── AuthServiceLive (depends on: Supabase)
├── SettingsServiceLive (depends on: Supabase, Auth)
├── SnapshotsServiceLive (depends on: Supabase)
├── ShiftsServiceLive (depends on: Settings, Snapshots)
├── StatsServiceLive (depends on: Supabase)
├── SubscriptionServiceLive (depends on: Supabase)
├── ClaudeServiceLive (depends on: AppConfig)
├── WageyServiceLive (depends on: Claude, Subscription)
└── SharingServiceLive (depends on: Supabase, Subscription)
```

---

*Architecture analysis: 2026-01-13*
*Update when major patterns change*
