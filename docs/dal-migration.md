# Data Access Layer (DAL) Migration

## Context

This document tracks the migration of our authentication and data access patterns to follow Next.js best practices for data security. Currently, our app duplicates authentication logic across ~14 files: every Server Action independently calls `supabase.auth.getUser()` with identical boilerplate, every page has redundant auth checks with comments saying "this should never happen", and data loaders accept `userId` as a trusted parameter. This violates the DRY principle and creates maintenance burden.

A **Data Access Layer (DAL)** is a centralized internal library that controls how and when data is fetched, ensuring consistent security practices across the application. By implementing a DAL, we create a single source of truth for authentication using a cached `verifySession()` helper, eliminate repetitive auth boilerplate, improve type safety (functions return `User` instead of `User | null`), and make it easier to add authorization logic later (e.g., checking if users can access specific resources).

This migration is purely a refactoring effort with no behavior changes - we're consolidating existing patterns into the recommended Next.js 15+ architecture. The work is divided into 5 incremental phases that can be completed independently, with clear success criteria and rollback options for each phase.

### Important: Folder Structure

**CRITICAL**: The `data-access/` folder MUST be created at the **project root**, at the same level as `app/`, `lib/`, and `components/`.

```
tidex/                    ← project root
├── app/
├── components/
├── lib/
├── data-access/          ← CREATE HERE (not in lib/ or app/)
│   ├── auth.ts
│   ├── shifts.ts
│   ├── stats.ts
│   └── settings.ts
├── docs/
└── ...
```

**Why root level?**
- `lib/` contains low-level utilities with no auth logic (Supabase factories, payroll calc, date utils)
- `data-access/` is a high-level architectural layer that handles authentication and authorization
- This separation follows Next.js best practices and creates clear boundaries

## Overview

Migrating from scattered authentication checks to centralized Data Access Layer following Next.js best practices.

**Reference**: https://nextjs.org/docs/app/guides/data-security#data-access-layer

## Migration Status

### Authentication Pattern Progress
- ✅ Layout enforces auth ([layout.tsx:27-35](../app/[locale]/(app)/layout.tsx#L27-L35)) - Kept as first line of defense
- ✅ Pages no longer duplicate auth checks - handled by DAL
- ✅ All Server Actions use centralized `verifySession()`
- ✅ Data loaders internally handle auth, no `userId` params

### File Inventory

**Server Actions migrated** (✅ All 12+ files):
- [x] `app/[locale]/(app)/shifts/add/_actions/createSeriesShift.ts`
- [x] `app/[locale]/(app)/settings/_actions/updateSettings.ts` (12 functions!)
- [x] `app/[locale]/(app)/settings/subscription/_actions/createCheckoutSession.ts`
- [x] `app/[locale]/(app)/settings/subscription/_actions/createPortalSession.ts`
- [x] `app/[locale]/(app)/shifts/add/_actions/deleteShiftsInOtherMonths.ts`
- [x] `app/[locale]/(app)/shifts/_actions/deleteShift.ts`
- [x] `app/[locale]/(app)/shifts/_actions/updateShift.ts`
- [x] `app/[locale]/(app)/shifts/_actions/deleteSeriesShift.ts`
- [x] `app/[locale]/(app)/shifts/_actions/moveSeriesShift.ts`
- [x] `app/[locale]/(app)/shifts/_actions/copyShifts.ts`
- [x] `app/[locale]/(app)/shifts/_actions/updateSeriesShift.ts`
- [x] `app/[locale]/(app)/shifts/_actions/convertSeriesShiftToStandalone.ts`
- [x] `app/[locale]/(app)/shifts/add/_checks/checkShiftLimit.ts`

**Data loaders migrated to DAL** (✅ All 5 modules):
- [x] `data-access/shifts.ts` (from `app/[locale]/(app)/shifts/_data/getShifts.ts`)
- [x] `data-access/stats.ts` (from `app/[locale]/(app)/_data/getMonthlyTotal.ts` + `stats/_data/getStatsData.ts`)
- [x] `data-access/settings.ts` (from `app/[locale]/(app)/settings/_data/getSettings.ts`)
- [x] `data-access/subscription.ts` (from `app/[locale]/(app)/settings/subscription/_data/getSubscription.ts`)

**Pages cleaned up** (✅ All 9 pages):
- [x] `app/[locale]/(app)/page.tsx`
- [x] `app/[locale]/(app)/shifts/page.tsx`
- [x] `app/[locale]/(app)/shifts/add/page.tsx`
- [x] `app/[locale]/(app)/stats/page.tsx`
- [x] `app/[locale]/(app)/settings/profile/page.tsx`
- [x] `app/[locale]/(app)/settings/pay/page.tsx`
- [x] `app/[locale]/(app)/settings/display/page.tsx`
- [x] `app/[locale]/(app)/settings/preferences/page.tsx`
- [x] `app/[locale]/(app)/settings/subscription/page.tsx`

## Migration Phases

### Phase 1: Foundation ✅

**Create DAL structure**:
- [x] Create `data-access/` folder **at project root** (NOT under `/lib` or `/app`)
- [x] Create `data-access/auth.ts` with `verifySession()` helper
  ```typescript
  import 'server-only'
  import { cache } from 'react'
  import { createSupabaseServerClient } from '@/lib/supabase/server'
  import { redirect } from 'next/navigation'

  export const verifySession = cache(async () => {
    const supabase = await createSupabaseServerClient()
    const { data: { user } } = await supabase.auth.getUser()

    if (!user) {
      redirect('/login')
    }

    return { user }
  })
  ```
- [x] Test with one Server Action (e.g., `updatePreferencesSettings`)

**Success criteria**: Server Action works, auth check happens once per request ✅

---

### Phase 2: Server Actions ✅

**Migrate all Server Actions to use `verifySession()`**:

Before:
```typescript
const supabase = await createSupabaseServerClient();
const { data: { user } } = await supabase.auth.getUser();
if (!user) throw new Error('Not authenticated');
```

After:
```typescript
const { user } = await verifySession();
const supabase = await createSupabaseServerClient(); // Still needed for DB operations
```

**Files updated**:
- [x] `createSeriesShift.ts`
- [x] `updateSettings.ts` (12 functions - all updated)
- [x] `createCheckoutSession.ts`
- [x] `createPortalSession.ts`
- [x] `deleteShiftsInOtherMonths.ts`
- [x] `deleteSeriesShift.ts`
- [x] `moveSeriesShift.ts`
- [x] `copyShifts.ts`
- [x] `updateSeriesShift.ts`
- [x] `deleteShift.ts`
- [x] `updateShift.ts`
- [x] `convertSeriesShiftToStandalone.ts`

**Success criteria**: No Server Actions call `auth.getUser()` directly ✅

---

### Phase 3: Data Loaders ✅

**Create DAL modules by domain**:

- [x] Create `data-access/shifts.ts`
  - Move `getComputedShifts` from `app/[locale]/(app)/shifts/_data/getShifts.ts`
  - Change signature: Remove `userId` param, call `verifySession()` internally

- [x] Create `data-access/stats.ts`
  - Move `getMonthlyTotal` from `app/[locale]/(app)/_data/getMonthlyTotal.ts`
  - Move `getStatsData` from `app/[locale]/(app)/stats/_data/getStatsData.ts`

- [x] Create `data-access/settings.ts`
  - Move `getUserSettings`, `getUserProfile` from `app/[locale]/(app)/settings/_data/getSettings.ts`

- [x] Create `data-access/subscription.ts`
  - Move `getSubscription` from `app/[locale]/(app)/settings/subscription/_data/getSubscription.ts`

**Pattern**:
```typescript
// Before (in _data/getShifts.ts)
export const getComputedShifts = cache(async (userId: string, options) => {
  const supabase = await createSupabaseServerClient();
  // ... fetch with userId
})

// After (in data-access/shifts.ts)
export const getComputedShifts = cache(async (options) => {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();
  // ... fetch with user.id
})
```

**Success criteria**: All data access centralized in `data-access/` ✅

---

### Phase 4: Update Pages ✅

**Remove redundant auth checks**:

Before:
```typescript
const supabase = await createSupabaseServerClient();
const { data: { user } } = await supabase.auth.getUser();
if (!user) redirect("/login"); // "This should never happen"

const { shifts } = await getComputedShifts(user.id, options);
```

After:
```typescript
const { shifts } = await getComputedShifts(options);
```

**Pages updated**:
- [x] `app/[locale]/(app)/page.tsx` - Removed auth boilerplate, updated imports, kept onboarding check
- [x] `app/[locale]/(app)/shifts/page.tsx` - Removed auth boilerplate, updated imports
- [x] `app/[locale]/(app)/shifts/add/page.tsx` - Uses `verifySession()`, updated PRESET_RULES import
- [x] `app/[locale]/(app)/stats/page.tsx` - Removed auth boilerplate, no more userId param
- [x] `app/[locale]/(app)/settings/profile/page.tsx` - Removed auth, calls `getUserProfile()` directly
- [x] `app/[locale]/(app)/settings/pay/page.tsx` - Removed auth, calls `getUserSettings()` directly
- [x] `app/[locale]/(app)/settings/display/page.tsx` - Removed auth, calls `getUserSettings()` directly
- [x] `app/[locale]/(app)/settings/preferences/page.tsx` - Removed auth, calls `getUserSettings()` directly
- [x] `app/[locale]/(app)/settings/subscription/page.tsx` - Removed auth, calls `getUserSubscriptionData()` directly

**Additional files updated**:
- [x] `app/[locale]/(app)/shifts/add/actions.ts` - Updated to use DAL subscription import
- [x] `app/[locale]/(app)/shifts/add/_checks/checkShiftLimit.ts` - Uses `verifySession()` + DAL
- [x] `app/[locale]/(app)/shifts/_actions/copyShifts.ts` - Updated subscription import

**Success criteria**: Pages are simpler, no auth boilerplate ✅
- Removed ~180 lines of redundant auth code across all pages
- All page imports now use `@/data-access/*` instead of `@/app/[locale]/(app)/*/_data/*`
- No more `userId` parameters passed to DAL functions

---

### Phase 5: Cleanup ✅

**Completed work**:
- [x] Update API routes to use DAL (special handling needed - can't use `redirect()`)
  - Created `getSession()` helper in `data-access/auth.ts` that returns `null` instead of redirecting
  - Created `*ForApi()` variants of DAL functions for API routes (`getStatsDataForApi`, `getComputedShiftsForApi`)
  - Updated `app/api/stats/route.ts` - Now uses `getSession()` + `getStatsDataForApi()`
  - Updated `app/api/stats/charts/route.ts` - Now uses `getSession()` + `getStatsDataForApi()`
  - Updated `app/api/shifts/route.ts` - Now uses `getSession()` + `getComputedShiftsForApi()`
- [x] Delete old `_data/` folders once API routes are updated
  - Deleted `app/[locale]/(app)/shifts/_data/`
  - Deleted `app/[locale]/(app)/_data/`
  - Deleted `app/[locale]/(app)/settings/_data/`
  - Deleted `app/[locale]/(app)/settings/subscription/_data/`
  - Deleted `app/[locale]/(app)/stats/_data/`
- [x] Move `invalidateUserCache` from `_data/cache.ts` to `data-access/cache.ts`
  - Created `data-access/cache.ts` with all cache invalidation utilities
  - Updated all imports in Server Actions to use new location
- [x] Update TypeScript path alias - Added `@dal/*` → `data-access/*`
- [x] Update all type imports in components to use DAL instead of `_data`

**Remaining work** (optional):
- [ ] Consider updating layout to use `verifySession()` for consistency (currently uses direct `getUser()` call)
- [ ] Update tests to mock `verifySession()` instead of Supabase (when tests are added)

**Implementation notes**:
- API routes use `getSession()` which returns `null` on auth failure (instead of redirecting)
- API-specific DAL functions (`*ForApi()`) don't call `verifySession()` - they rely on manual auth checks
- All cache invalidation utilities moved to `data-access/cache.ts` for better organization

---

## Benefits Achieved

- ✅ **Single source of truth for authentication** - `verifySession()` in `data-access/auth.ts`
- ✅ **Request-level caching** via React's `cache()` - auth check happens once per request
- ✅ **Eliminated ~180+ lines of duplicated auth code** across all pages and actions
- ✅ **Better type safety** - DAL functions return `User` instead of `User | null`, no guards needed
- ✅ **Cleaner page components** - No auth boilerplate, just data fetching and rendering
- ✅ **Simplified Server Actions** - No repetitive auth checks, just call `verifySession()` once
- ✅ **No userId parameters** - DAL handles authentication internally, can't be spoofed
- ✅ **Easier to add authorization** - Centralized place to add resource-level checks later
- ✅ **Follows Next.js 15+ best practices** - As documented in official Next.js security guide

**Code metrics**:
- 12+ Server Actions migrated
- 6 DAL modules created (`auth.ts`, `shifts.ts`, `stats.ts`, `settings.ts`, `subscription.ts`, `cache.ts`)
- 9 pages cleaned up
- 3 API routes migrated to use DAL
- ~180 lines of redundant code removed
- All old `_data/` folders deleted
- TypeScript path alias added for better DX
- 0 breaking changes (purely refactoring)

## Rollback Plan

If issues arise, each phase is independently reversible:
- ✅ All phases complete - migration is done!
- Use git to revert specific commits if needed:
  - `git revert <commit-hash>` for individual phase rollback
  - Old code patterns well-documented in this file for manual rollback
- All changes are backwards-compatible (no database migrations or breaking changes)
- If needed, old `_data/` files can be recovered from git history
