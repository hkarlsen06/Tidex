# Tidex Route Caching Fix Plan

**Date**: 2025-11-14
**Based on**: CACHE_ANALYSIS.md comprehensive analysis
**Status**: Ready for implementation

---

## Context

### What the caching system should do

Tidex uses Next.js 16 caching features to improve performance:

1. **`'use cache: private'`** - Cache data access layer results across requests for each user
2. **`cacheTag()` + `updateTag()`** - Invalidate specific cached data when mutations occur
3. **React `cache()`** - Deduplicate requests within a single render
4. **Next.js route caching** - Reuse RSC payloads between navigations

When working correctly:
- Navigating Dashboard → Stats should reuse cached auth and settings data
- Navigating back to Dashboard should load instantly from cache
- After creating/editing a shift, only affected caches should invalidate
- Layout queries should cache and not re-run on every navigation

### What goes wrong today

**Zero cache reuse across route navigations.**

Every navigation triggers:
- Full SSR re-render
- All database queries run fresh (8-9 per page)
- No data reuse between routes

**Critical bug**: Cache invalidation is completely broken due to tag mismatch. Tags set during caching never match tags used for invalidation.

**Result**: 25+ database queries for Dashboard → Stats → Dashboard navigation loop instead of ~8-13.

---

## Fixes

### Fix 1: Cache Tag Mismatch (CRITICAL)

**Problem**: Tags set in DAL functions don't match tags invalidated in cache helpers.

**Evidence**:
- `data-access/cache.ts:10` invalidates `user-shifts-${userId}`
- `data-access/cache.ts:19` invalidates `user-stats-${userId}`
- `data-access/shifts.ts:65` sets tags `user-${userId}` + `user-shifts`
- `data-access/stats.ts:259` sets tags `user-${userId}` + `user-stats`
- **Tags never match** - invalidation never works

**Files to change**:
- `data-access/cache.ts`

**Line-by-line fix**:

```typescript
// data-access/cache.ts

// BEFORE (lines 9-11):
export function invalidateShiftsCache(userId: string): void {
  updateTag(`user-shifts-${userId}`);  // ❌ Wrong - tag never set
}

// AFTER:
export function invalidateShiftsCache(userId: string): void {
  updateTag(`user-${userId}`);  // ✅ Matches cacheTag in DAL
  updateTag('user-shifts');     // ✅ Matches cacheTag in DAL
}
```

```typescript
// BEFORE (lines 18-20):
export function invalidateStatsCache(userId: string): void {
  updateTag(`user-stats-${userId}`);  // ❌ Wrong - tag never set
}

// AFTER:
export function invalidateStatsCache(userId: string): void {
  updateTag(`user-${userId}`);  // ✅ Matches cacheTag in DAL
  updateTag('user-stats');      // ✅ Matches cacheTag in DAL
}
```

```typescript
// BEFORE (lines 26-29):
export function invalidateUserCache(userId: string): void {
  invalidateShiftsCache(userId);  // Calls both specific invalidators
  invalidateStatsCache(userId);
}

// AFTER:
export function invalidateUserCache(userId: string): void {
  // Invalidating user-${userId} invalidates ALL user data at once
  // More efficient than calling specific invalidators
  updateTag(`user-${userId}`);
}
```

**Expected behavior after fix**:
- `updateTag()` invalidates caches that were actually tagged
- After shift create/update/delete, cached shift data clears
- After settings update, cached settings data clears
- No stale data served to users

---

### Fix 2: Remove Excessive revalidatePath

**Problem**: Every mutation calls `revalidatePath("/", "layout")` which clears ALL route caches for ALL pages.

**Evidence**:
- `lib/revalidation/paths.ts:51` - `revalidatePath("/", "layout")`
- Called by 15+ server actions via `invalidateAndRevalidate(userId)`
- Creates a shift → clears stats cache too (over-invalidation)

**Files to change**:
- `lib/revalidation/paths.ts`

**Line-by-line fix**:

```typescript
// lib/revalidation/paths.ts

// BEFORE (lines 47-52):
export function invalidateAndRevalidate(userId: string) {
  invalidateUserCache(userId);
  // Use layout revalidation to ensure all localized routes are revalidated
  // This is more reliable than page-level revalidation for dynamic [locale] segments
  revalidatePath("/", "layout");  // ❌ Nukes entire app cache
}

// AFTER:
export function invalidateAndRevalidate(userId: string) {
  // Tag-based invalidation is sufficient with Next.js 16 'use cache' directive
  // updateTag() automatically revalidates only affected cached functions
  invalidateUserCache(userId);
  // Removed revalidatePath - tag invalidation handles cache clearing
}
```

**Expected behavior after fix**:
- Changing a shift only invalidates shift-related caches
- Stats cache survives shift mutations (until user navigates and cache refreshes naturally)
- Changing settings only invalidates settings-related caches
- Cache persists between navigations until explicitly invalidated by tags

---

### Fix 3: Cache Layout Settings Query

**Problem**: Layout fetches settings directly from Supabase on every navigation instead of using cached DAL function.

**Evidence**:
- `app/[locale]/(app)/layout.tsx:38-45` - Direct Supabase query every request
- `getUserSettings()` DAL function exists with `'use cache: private'` but not used
- Duplicate settings query: layout + each DAL function that needs settings

**Files to change**:
- `app/[locale]/(app)/layout.tsx`

**Line-by-line fix**:

```typescript
// app/[locale]/(app)/layout.tsx

// ADD at top (after line 5):
import { getUserSettings } from "@/data-access/settings";

// BEFORE (lines 38-45):
const [sessionRes, settingsRes] = await Promise.all([
  supabase.auth.getSession(),
  supabase
    .from("user_settings")
    .select("profile_picture_url,theme")
    .eq("user_id", user.id)
    .maybeSingle(),
]);

// AFTER:
const [sessionRes, settings] = await Promise.all([
  supabase.auth.getSession(),
  getUserSettings(user.id),  // ✅ Uses cached DAL function
]);

// BEFORE (lines 47-50):
const {
  data: { session },
} = sessionRes;

// AFTER (keep session extraction, update settings references):
const {
  data: { session },
} = sessionRes;

// BEFORE (lines 93-94):
const { data: settings } = settingsRes;
const profilePictureUrl = sanitizeUrl(settings?.profile_picture_url ?? null);

// AFTER (line 93-94 - settings is already the data object):
// Remove line 93: const { data: settings } = settingsRes;
const profilePictureUrl = sanitizeUrl(settings?.profile_picture_url ?? null);
```

**Expected behavior after fix**:
- First navigation: settings query runs once (in DAL), cached
- Subsequent navigations: settings loaded from cache (no query)
- Layout + DAL functions share the same cached settings
- Settings queries reduced by ~50%

---

### Fix 4: Consolidate connection() Calls (Optional Cleanup)

**Problem**: Every page calls `connection()` redundantly when it could be called once in layout.

**Evidence**:
- `app/[locale]/(app)/page.tsx:30` - `await connection();`
- `app/[locale]/(app)/stats/page.tsx:22` - `await connection();`
- `app/[locale]/(app)/shifts/page.tsx:28` - `await connection();`

**Note**: This doesn't enable caching by itself, but reduces redundancy.

**Files to change**:
- `app/[locale]/(app)/layout.tsx` (add)
- `app/[locale]/(app)/page.tsx` (remove)
- `app/[locale]/(app)/stats/page.tsx` (remove)
- `app/[locale]/(app)/shifts/page.tsx` (remove)

**Line-by-line fix**:

```typescript
// app/[locale]/(app)/layout.tsx

// ADD at top (after line 3):
import { connection } from "next/server";

// ADD at start of RootLayout function (after line 26):
export default async function RootLayout({
  children,
}: {
  children: ReactNode;
}) {
  await connection(); // ✅ Opt out of prerendering once for all protected pages

  const supabase = await createSupabaseServerClient();
  // ... rest of layout
}
```

```typescript
// app/[locale]/(app)/page.tsx

// REMOVE line 2:
// import { connection } from "next/server";

// REMOVE line 30:
export default async function Home({ params }: HomeProps) {
  // await connection(); // ❌ Remove - layout handles it now
  const { locale: _locale } = await params;
  // ... rest of function
}
```

```typescript
// app/[locale]/(app)/stats/page.tsx

// REMOVE line 3:
// import { connection } from "next/server";

// REMOVE line 22:
export default async function StatsPage({ params }: StatsPageProps) {
  // await connection(); // ❌ Remove - layout handles it now
  const { locale } = await params;
  // ... rest of function
}
```

```typescript
// app/[locale]/(app)/shifts/page.tsx

// REMOVE line 3:
// import { connection } from "next/server";

// REMOVE line 28:
export default async function ShiftsPage({ params }: ShiftsPageProps) {
  // await connection(); // ❌ Remove - layout handles it now
  const { locale: _locale } = await params;
  // ... rest of function
}
```

**Expected behavior after fix**:
- Same behavior (still dynamic rendering)
- Cleaner code (DRY principle)
- One less function call per page render

---

### Fix 5: Align Data Ranges (Optional Performance Optimization)

**Problem**: Dashboard loads 3 months, Stats loads full year. Different cache keys mean no data reuse.

**Evidence**:
- `app/[locale]/(app)/page.tsx:47-50` - 3 months (prev + current + next), limit 150
- `app/[locale]/(app)/shifts/page.tsx:39-42` - 3 months (prev + current + next), limit 150
- `data-access/stats.ts:127-128` - Full year (`getCurrentYearStart()` to `getCurrentYearEnd()`), limit 1000

**Trade-off**:
- **Pro**: Cache hit when Dashboard → Stats
- **Con**: Dashboard loads more data (slower initial load, more memory)

**Recommendation**: Implement ONLY if fixes 1-3 show insufficient improvement. Measure first.

**Files to change** (if implementing):
- `app/[locale]/(app)/page.tsx`
- `app/[locale]/(app)/shifts/page.tsx`

**Option A - Dashboard/Shifts load full year**:

```typescript
// app/[locale]/(app)/page.tsx

// ADD imports (after line 11):
import { getCurrentYearStart, getCurrentYearEnd } from "@/lib/date-utils";

// REPLACE lines 42-50:
// BEFORE:
const prevMonth = getPreviousYearMonth();
const nextMonth = getNextYearMonth();

const { shifts, settings } = await getComputedShifts(user.id, {
  startDate: getMonthStart(prevMonth.year, prevMonth.month),
  endDate: getMonthEnd(nextMonth.year, nextMonth.month),
  limit: 150
});

// AFTER:
const { shifts, settings } = await getComputedShifts(user.id, {
  startDate: getCurrentYearStart(),  // Full year like Stats
  endDate: getCurrentYearEnd(),
  limit: 1000  // Match Stats limit
});
```

**Expected behavior after fix** (if implemented):
- Dashboard → Stats: Settings + shifts loaded from cache (near-instant)
- Dashboard initial load: 200-400ms slower (loading full year)
- Memory usage: ~6x more shifts in memory (3 months → 12 months)

---

### Fix 6: Add Granular Cache Tags (Future Enhancement)

**Problem**: Invalidating `user-${userId}` clears ALL user data, even unrelated caches.

**Current**:
- Create a shift in November → invalidates December shifts cache too
- Change theme → invalidates shifts cache

**Enhancement** (not for initial fix):

```typescript
// data-access/shifts.ts:65

// BEFORE:
cacheTag(`user-${userId}`, 'user-shifts');

// FUTURE:
cacheTag(`user-${userId}`, 'user-shifts', `shifts-${year}-${month}`);

// Then in cache.ts:
export function invalidateShiftsForMonth(userId: string, year: number, month: number) {
  updateTag(`shifts-${year}-${month}`);  // Only invalidate specific month
}
```

**Skip this for now** - implement after validating fixes 1-3 work.

---

## Order of Work

### Phase 1: Critical Bug Fix (30 minutes)

**Do first - highest impact, lowest risk**:

1. **Fix cache tag mismatch** (Fix #1)
   - Edit `data-access/cache.ts`
   - Update all three functions: `invalidateShiftsCache`, `invalidateStatsCache`, `invalidateUserCache`
   - Test: Create a shift, verify cache invalidates

**Dependencies**: None - standalone fix
**Risk**: Very low - invalidation was broken anyway
**Impact**: Cache invalidation starts working

---

### Phase 2: Remove Over-Invalidation (15 minutes)

**Do second - enables cache persistence**:

2. **Remove excessive revalidatePath** (Fix #2)
   - Edit `lib/revalidation/paths.ts`
   - Remove `revalidatePath("/", "layout")` call
   - Test: Navigate Dashboard → Stats → Dashboard, verify cache persists

**Dependencies**: Requires Fix #1 (tag invalidation must work first)
**Risk**: Low - tag-based invalidation is sufficient
**Impact**: Cache survives mutations, 50-60% query reduction

---

### Phase 3: Optimize Layout (15 minutes)

**Do third - easy performance win**:

3. **Cache layout settings** (Fix #3)
   - Edit `app/[locale]/(app)/layout.tsx`
   - Import and use `getUserSettings()`
   - Test: Navigate between routes, verify settings not re-queried

**Dependencies**: None - standalone improvement
**Risk**: Very low - DAL function already exists and cached
**Impact**: ~2 fewer queries per navigation

---

### Phase 4: Code Cleanup (20 minutes)

**Do fourth - optional cleanup**:

4. **Consolidate connection() calls** (Fix #4)
   - Edit layout + 3 page files
   - Move `connection()` to layout
   - Test: Verify all pages still dynamic

**Dependencies**: None - pure refactor
**Risk**: Very low - same behavior, cleaner code
**Impact**: No performance change, better maintainability

---

### Phase 5: Data Range Alignment (SKIP INITIALLY)

**Do ONLY if Phases 1-3 show insufficient improvement**:

5. **Align data ranges** (Fix #5)
   - Measure current performance after Fixes 1-3
   - If cache hit rate < 60%, consider implementing
   - Edit Dashboard/Shifts to load full year
   - Test: Measure initial load time impact

**Dependencies**: Requires Fixes 1-3 complete
**Risk**: Medium - increases initial load time and memory
**Impact**: Higher cache hit rate, but slower initial loads

---

## Validation

### Test 1: Cache Tag Invalidation Works

**After Fix #1**:

1. Load Dashboard
2. Open DevTools → Network tab
3. Create a new shift
4. Navigate to Stats
5. **Expected**: Stats queries run fresh (cache was invalidated)
6. **Verify**: No stale data shown

**Success criteria**: Data refreshes after mutations

---

### Test 2: Cache Persists Between Navigations

**After Fixes #1 + #2**:

1. Clear browser cache
2. Load Dashboard → count Supabase queries (should be ~8)
3. Navigate to Stats → count Supabase queries
4. Navigate back to Dashboard → count Supabase queries
5. **Expected queries**:
   - Dashboard (first): 8 queries
   - Stats: 3-4 queries (auth + settings cached)
   - Dashboard (second): 0-1 queries (everything cached)

**Success criteria**: Second Dashboard load reuses cached data

**How to count queries**:
- Open DevTools → Network tab
- Filter: `supabase.co`
- Count POST requests to `/rest/v1/`

---

### Test 3: Layout Settings Cache

**After Fix #3**:

1. Load Dashboard → check Network tab
2. Navigate to Stats
3. Navigate to Shifts
4. **Expected**: `user_settings` query runs ONCE on first load
5. **Verify**: No duplicate settings queries in Network tab

**Success criteria**: Settings query count = 1 (not 3)

---

### Test 4: Cache Invalidation Scope

**After Fixes #1 + #2**:

1. Load Dashboard
2. Navigate to Stats (data should cache)
3. Go to Settings → change theme (unrelated to shifts)
4. Navigate to Dashboard
5. **Expected**: Shifts data still cached (not invalidated)
6. **Actual before fix**: All caches cleared by layout revalidation
7. **After fix**: Only settings cache invalidated

**Success criteria**: Unrelated caches survive unrelated mutations

---

### Test 5: Performance Benchmarks

**After all fixes**:

Run this navigation sequence 3 times, record average:

| Navigation | Queries (Before) | Queries (After) | Time (Before) | Time (After) |
|------------|-----------------|----------------|---------------|--------------|
| Dashboard load | 8 | 8 | ~500ms | ~500ms |
| → Stats | 9 | 3-4 | ~600ms | ~200ms |
| → Dashboard | 8 | 0-1 | ~500ms | ~50ms |
| **Total** | **25** | **11-13** | **1600ms** | **750ms** |

**Success criteria**:
- 50-60% reduction in queries
- 50-70% faster subsequent navigations

---

### Test 6: Browser Back/Forward

**After Fixes #1 + #2**:

1. Navigate Dashboard → Stats → Shifts
2. Use browser back button (Stats → Dashboard)
3. Use browser forward button (Dashboard → Stats)
4. **Expected**: Instant loads from cache
5. **Verify**: No loading spinners, no query flashes

**Success criteria**: Back/forward navigation reuses cache

---

### Automated Testing (Future)

Add cache hit logging to DAL functions:

```typescript
// data-access/shifts.ts:64
async function getComputedShiftsInternal(userId: string, options: ShiftLoadOptions = {}) {
  'use cache: private';
  cacheTag(`user-${userId}`, 'user-shifts');

  // Log cache hits/misses
  console.log(`[CACHE] getComputedShifts called - userId: ${userId.slice(0,8)}..., options:`, options);

  // ... rest of function
}
```

**Monitor logs**:
- If log appears on every navigation → cache miss
- If log appears only on first load → cache hit

---

## Migration Notes

### Cleanup Tasks

**After Fix #1**:

No cleanup needed - tags now match correctly.

**After Fix #2**:

1. Monitor server logs for any "stale data" user reports
2. If stale data occurs, add specific `revalidatePath()` calls for affected routes only
3. Example:
   ```typescript
   export function revalidateShiftData() {
     revalidatePath('/[locale]');       // Dashboard
     revalidatePath('/[locale]/shifts'); // Shifts page
     // NOT layout-level - too broad
   }
   ```

**After Fix #3**:

No cleanup needed - layout now uses DAL function.

**After Fix #4**:

Remove unused imports from page files:
- `import { connection } from "next/server";` deleted from 3 files

---

### Code Removal

**Remove after all fixes**:

No code to remove - all changes are refactors or fixes.

**Keep**:
- All `'use cache: private'` directives
- All `cacheTag()` calls
- All DAL internal functions
- React `cache()` wrappers

---

### Test Adjustments

**Update tests** (if tests exist for server actions):

1. **Cache invalidation tests**: Verify tags match between set and update
   ```typescript
   // Test that creating a shift invalidates correct tags
   expect(updateTag).toHaveBeenCalledWith('user-123');
   expect(updateTag).toHaveBeenCalledWith('user-shifts');
   ```

2. **DAL tests**: Verify `'use cache: private'` functions are called correctly
   ```typescript
   // Test that getUserSettings is cached
   await getUserSettings(userId);
   await getUserSettings(userId);
   // Should only query DB once
   expect(supabase.from).toHaveBeenCalledTimes(1);
   ```

3. **Integration tests**: Add navigation caching tests
   ```typescript
   // Test cache persistence across navigations
   await loadDashboard();
   const queriesBeforeStats = getQueryCount();
   await navigateToStats();
   const queriesAfterStats = getQueryCount();
   expect(queriesAfterStats - queriesBeforeStats).toBeLessThan(5);
   ```

---

### Logging Adjustments

**Add cache monitoring** (optional):

```typescript
// data-access/cache.ts

export function invalidateUserCache(userId: string): void {
  console.log(`[CACHE] Invalidating all caches for user ${userId.slice(0, 8)}...`);
  updateTag(`user-${userId}`);
}
```

**Remove after validation** period (1-2 weeks in production):
- Cache hit/miss logs
- Tag invalidation logs
- Query count logs

---

### Database Considerations

**No database changes needed** - all fixes are application-level.

**Monitor** (after deployment):
- Database query count reduction (should see 50-60% drop)
- Database CPU usage (should decrease)
- Connection pool usage (fewer simultaneous queries)

---

### Rollback Plan

**If issues occur after deployment**:

**Fix #1 rollback** (cache invalidation):
```bash
git revert <commit-hash>
```
Risk: Very low - invalidation was broken anyway

**Fix #2 rollback** (revalidatePath removal):
```typescript
// Restore lib/revalidation/paths.ts:51
export function invalidateAndRevalidate(userId: string) {
  invalidateUserCache(userId);
  revalidatePath("/", "layout"); // Restore over-invalidation
}
```
Risk: Low - restores over-invalidation (slower but safe)

**Fix #3 rollback** (layout settings):
```typescript
// Restore direct Supabase query in layout
const [sessionRes, settingsRes] = await Promise.all([
  supabase.auth.getSession(),
  supabase.from("user_settings").select("profile_picture_url,theme")
    .eq("user_id", user.id).maybeSingle(),
]);
```
Risk: Very low - just removes caching benefit

---

### Performance Monitoring

**Metrics to track** (post-deployment):

1. **Cache hit rate**: % of navigations using cached data
2. **Average queries per navigation**: Should drop from 8-9 to 0-4
3. **Page load time**: Should improve 50-70% for cached routes
4. **Database CPU**: Should decrease proportionally
5. **User-reported issues**: Monitor for stale data complaints

**Alerting thresholds**:
- Cache hit rate < 40% → investigate cache configuration
- Stale data reports > 1% → check tag invalidation logic
- Query count > baseline → check for cache bypass bugs

---

## Expected Outcomes

### Before Fixes

| Metric | Value |
|--------|-------|
| Queries per navigation | 8-9 |
| Dashboard → Stats → Dashboard queries | 25 |
| Cache hit rate | 0% |
| Cache invalidation | Broken (tags mismatch) |
| Layout settings queries | 3 per navigation |

### After Fixes (Phase 1-3)

| Metric | Value |
|--------|-------|
| Queries per navigation | 0-8 (first) → 0-4 (subsequent) |
| Dashboard → Stats → Dashboard queries | 11-13 |
| Cache hit rate | 60-70% |
| Cache invalidation | Working (tags match) |
| Layout settings queries | 1 per session |

**Improvement**: ~50-60% reduction in database queries, ~53% faster navigation time

### After Optional Fix #5 (Data Range Alignment)

| Metric | Value |
|--------|-------|
| Queries per navigation | 8 (first) → 0-1 (subsequent) |
| Dashboard → Stats → Dashboard queries | 8-9 |
| Cache hit rate | 75-85% |
| Dashboard initial load time | +200-400ms (slower) |

**Trade-off**: Higher cache hit rate but slower initial Dashboard load

---

## Summary

**Three critical fixes**:
1. Match cache tags (30 min) - enables invalidation
2. Remove layout revalidation (15 min) - enables persistence
3. Cache layout settings (15 min) - reduces queries

**Total implementation time**: ~1 hour
**Expected impact**: 50-60% fewer database queries, 53% faster navigation
**Risk level**: Low - fixes are isolated and reversible

**Next steps**:
1. Implement Fix #1 (tag mismatch)
2. Test invalidation works
3. Implement Fix #2 (remove revalidatePath)
4. Test cache persistence
5. Implement Fix #3 (layout settings)
6. Run full validation suite
7. Deploy and monitor

---

**End of Fix Plan**
