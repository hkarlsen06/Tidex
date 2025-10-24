# Performance Optimization Plan

## Executive Summary

This document outlines a comprehensive plan to improve Core Web Vitals metrics (FCP, LCP, TTFB) for the app routes: dashboard, shifts, and stats pages.

### Target Metrics

- **TTFB (Time to First Byte)**: < 800ms (currently ~1000ms+)
- **FCP (First Contentful Paint)**: < 1.8s (currently ~2-3s)
- **LCP (Largest Contentful Paint)**: < 2.5s (currently ~3-4s)

---

## Current Performance Issues

### TTFB Bottlenecks

1. **Duplicate Authentication Queries**
   - Both `app/(app)/layout.tsx` and individual pages call `getUser()`
   - No request deduplication with React `cache()`
   - Results in multiple identical Supabase queries per request

2. **Blocking Layout Queries**
   - Layout fetches shift count for onboarding hint (`app/(app)/layout.tsx:38-49`)
   - Non-critical data blocks entire app from rendering
   - All child routes wait for this query to complete

3. **Heavy Data Loading Without Pagination**
   - `getComputedShifts()` loads ALL shifts regardless of count
   - Query: `supabase.from("user_shifts").select("*")`
   - No pagination, no date range filtering
   - Users with 100+ shifts load entire history

4. **Expensive Server-Side Calculations**
   - `getStatsData()` performs 532 lines of computation on every request
   - Builds 11+ different data structures (monthly summaries, cumulative data, projections)
   - No caching, computation happens on every page load
   - Calls `getComputedShifts()` internally (duplicates work)

5. **No Caching Strategy**
   - No React `cache()` for deduplication
   - No Next.js Data Cache (`unstable_cache`)
   - No ISR (Incremental Static Regeneration)
   - Every request recomputes everything from scratch

### FCP Bottlenecks

1. **Large Data Payloads**
   - All shifts serialized in `__NEXT_DATA__` JSON
   - Stats page sends massive pre-computed datasets
   - Increases HTML size and parse time

2. **No Progressive Rendering**
   - No Suspense boundaries in page components
   - No streaming SSR enabled
   - Entire page blocks until all data is ready

3. **Heavy Client Components Load Synchronously**
   - All components in critical rendering path
   - Only calendar component uses dynamic import
   - Charts, stats, and heavy UI load before first paint

### LCP Bottlenecks

1. **Synchronous Chart Loading**
   - Stats page loads 7+ recharts components at once
   - All charts render simultaneously
   - ~100KB+ of charting library in initial bundle

2. **Client-Side Data Processing**
   - `HomeContent.tsx:132-144` builds shifts index in browser
   - Additional filtering and aggregations on client
   - Delays rendering of largest contentful element

3. **No Loading States**
   - No skeleton UI components
   - User sees blank screen until everything loads
   - No progressive enhancement

---

## Optimization Strategy

### Phase 1: Quick Wins (High Impact, Low Effort)

#### 1.1 Implement React cache() for Request Deduplication

**Problem**: Layout and pages both create Supabase clients and fetch user data independently.

**Solution**:
- Wrap `createSupabaseServerClient()` with React `cache()`
- Wrap `getComputedShifts()` with React `cache()`
- React will deduplicate identical calls within same request

**Files to modify**:
- `lib/supabase/server.ts`
- `app/(app)/shifts/_data/getShifts.ts`

**Implementation**:
```typescript
// lib/supabase/server.ts
import { cache } from 'react';

export const createSupabaseServerClient = cache(async () => {
  // existing implementation
});

// app/(app)/shifts/_data/getShifts.ts
import { cache } from 'react';

export const getComputedShifts = cache(async (userId: string) => {
  // existing implementation
});
```

**Expected Impact**: 30-50% reduction in TTFB by eliminating duplicate database queries

---

#### 1.2 Remove Blocking Shift Count from Layout

**Problem**: Layout queries shift count for onboarding hint, blocking entire app render.

**Solution**:
- Remove shift count query from `app/(app)/layout.tsx`
- Move onboarding hint logic to client component with deferred loading
- Or wrap in Suspense boundary with fallback

**Files to modify**:
- `app/(app)/layout.tsx` (lines 38-49, 101-102)
- `components/app/AppLayoutClient.tsx` (remove `showAddShiftHint` prop)

**Implementation Options**:

**Option A**: Client-side fetch
```typescript
// Remove from layout, fetch in client component
useEffect(() => {
  async function checkShiftCount() {
    // Fetch count only if needed
  }
}, []);
```

**Option B**: Suspense boundary
```typescript
// In layout
<Suspense fallback={null}>
  <OnboardingHintChecker userId={user.id} />
</Suspense>
```

**Expected Impact**: 50-100ms reduction in TTFB, faster initial render

---

#### 1.3 Add Suspense Boundaries with Skeleton UI

**Problem**: Entire page waits for all data before showing anything to user.

**Solution**:
- Wrap page components in Suspense boundaries
- Create skeleton components matching final UI
- Enable Next.js streaming SSR

**Files to modify**:
- `app/(app)/page.tsx`
- `app/(app)/shifts/page.tsx`
- `app/(app)/stats/page.tsx`
- Create new skeleton components

**Implementation**:
```typescript
// app/(app)/page.tsx
import { Suspense } from 'react';
import { HomeSkeleton } from '@/components/app/skeletons/HomeSkeleton';

export default async function Home() {
  return (
    <Suspense fallback={<HomeSkeleton />}>
      <HomeDataLoader />
    </Suspense>
  );
}

// Create separate async component for data loading
async function HomeDataLoader() {
  const { shifts, settings } = await getComputedShifts(user.id);
  return <HomeContent shifts={shifts} settings={settings} />;
}
```

**Expected Impact**: 40-60% improvement in FCP, better perceived performance

---

#### 1.4 Lazy Load All Chart Components

**Problem**: Stats page loads 7+ chart components synchronously, bloating initial bundle.

**Solution**:
- Dynamic import all recharts components
- Load below-fold charts only when visible (intersection observer)
- Progressive chart rendering

**Files to modify**:
- `components/app/StatsContent.tsx`

**Implementation**:
```typescript
// Lazy load chart components
const MonthlyCumulativeChart = dynamic(
  () => import('./charts/MonthlyCumulativeChart'),
  { loading: () => <ChartSkeleton /> }
);

const SupplementBreakdownChart = dynamic(
  () => import('./charts/SupplementBreakdownChart'),
  { loading: () => <ChartSkeleton /> }
);

// Or load when visible
const [isVisible, setIsVisible] = useState(false);
const ref = useRef();

useEffect(() => {
  const observer = new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) {
      setIsVisible(true);
    }
  });
  if (ref.current) observer.observe(ref.current);
}, []);
```

**Expected Impact**: 40-60% reduction in initial bundle size, better FCP/LCP

---

### Phase 2: Data Layer Optimizations (High Impact, Medium Effort)

#### 2.1 Implement Shift Pagination

**Problem**: Loading all shifts regardless of count causes slow queries and large payloads.

**Solution**:
- Modify `getComputedShifts()` to accept date range parameters
- Default to last 6 months of shifts
- Add "Load older shifts" functionality for historical data

**Files to modify**:
- `app/(app)/shifts/_data/getShifts.ts`
- Update all callers of `getComputedShifts()`

**Implementation**:
```typescript
export async function getComputedShifts(
  userId: string,
  options: {
    startDate?: string;
    endDate?: string;
    limit?: number;
  } = {}
) {
  const {
    startDate = getMonthsAgo(6), // Default: last 6 months
    endDate = getCurrentDate(),
    limit = 500
  } = options;

  const { data: shifts } = await supabase
    .from("user_shifts")
    .select("*")
    .eq("user_id", userId)
    .gte("shift_date", startDate)
    .lte("shift_date", endDate)
    .order("shift_date", { ascending: false })
    .limit(limit);

  // rest of implementation
}
```

**Expected Impact**: 50-70% reduction in data loading time and payload size

---

#### 2.2 Add Data Caching Layer

**Problem**: Every request recomputes all shift calculations from scratch.

**Solution**:
- Use Next.js `unstable_cache()` to cache computed results
- Set appropriate TTL (5-15 minutes)
- Implement cache invalidation on mutations (add/edit/delete shift)

**Files to modify**:
- `app/(app)/shifts/_data/getShifts.ts`
- `app/(app)/stats/_data/getStatsData.ts`
- Create cache invalidation utility

**Implementation**:
```typescript
import { unstable_cache } from 'next/cache';
import { revalidateTag } from 'next/cache';

export const getComputedShifts = unstable_cache(
  async (userId: string) => {
    // existing implementation
  },
  ['computed-shifts'],
  {
    tags: (userId) => [`user-shifts-${userId}`],
    revalidate: 300 // 5 minutes
  }
);

// When shift is mutated
export async function invalidateShiftsCache(userId: string) {
  revalidateTag(`user-shifts-${userId}`);
}
```

**Expected Impact**: 70-90% reduction in TTFB on cache hits

---

#### 2.3 Optimize Stats Calculations

**Problem**: `getStatsData()` performs extensive calculations on every request (532 lines).

**Solution**:
- Move aggregations to database level where possible
- Pre-compute monthly summaries in database
- Cache stats calculations aggressively
- Consider materialized views for complex queries

**Files to modify**:
- `app/(app)/stats/_data/getStatsData.ts`
- Database migration for views/indexes

**Implementation**:

**Database View** (create in Supabase):
```sql
CREATE OR REPLACE VIEW user_monthly_stats AS
SELECT
  user_id,
  DATE_TRUNC('month', shift_date) as month,
  SUM(computed_gross) as total_earnings,
  SUM(computed_hours) as total_hours,
  COUNT(*) as shift_count
FROM user_shifts
GROUP BY user_id, DATE_TRUNC('month', shift_date);
```

**TypeScript**:
```typescript
// Query pre-computed view instead of computing in code
const { data: monthlySummaries } = await supabase
  .from('user_monthly_stats')
  .select('*')
  .eq('user_id', userId)
  .order('month', { ascending: false })
  .limit(12);
```

**Expected Impact**: 50-70% reduction in stats page TTFB

---

#### 2.4 Database Optimization

**Problem**: Queries may be slow due to missing indexes.

**Solution**:
- Verify and add indexes on frequently queried columns
- Add composite indexes for common query patterns
- Analyze query performance with EXPLAIN

**Database Changes**:
```sql
-- Verify these indexes exist
CREATE INDEX IF NOT EXISTS idx_user_shifts_user_id
  ON user_shifts(user_id);

CREATE INDEX IF NOT EXISTS idx_user_shifts_shift_date
  ON user_shifts(shift_date);

-- Composite index for common query pattern
CREATE INDEX IF NOT EXISTS idx_user_shifts_user_date
  ON user_shifts(user_id, shift_date DESC);

-- For settings lookups
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id
  ON user_settings(user_id);
```

**Expected Impact**: 30-50% faster database queries

---

### Phase 3: Advanced Optimizations (Medium Impact, Higher Effort)

#### 3.1 Progressive Data Loading on Stats Page

**Problem**: Stats page loads all chart data at once before rendering.

**Solution**:
- Load critical stats first (current month summary)
- Defer chart data loading with client-side API calls
- Show progressive UI updates as data arrives

**Files to modify**:
- `app/(app)/stats/page.tsx`
- `components/app/StatsContent.tsx`
- `app/api/stats/route.ts` (already exists, expand it)

**Implementation**:
```typescript
// Load minimal data server-side
export default async function StatsPage() {
  const criticalData = await getCriticalStatsData(user.id); // Current month only
  return <StatsContent initialData={criticalData} userId={user.id} />;
}

// Client component loads additional data
function StatsContent({ initialData, userId }) {
  const [chartData, setChartData] = useState(null);

  useEffect(() => {
    // Defer chart data loading
    fetch(`/api/stats/charts?userId=${userId}`)
      .then(res => res.json())
      .then(setChartData);
  }, [userId]);

  return (
    <>
      <HeroSection data={initialData} />
      {chartData ? <Charts data={chartData} /> : <ChartSkeletons />}
    </>
  );
}
```

**Expected Impact**: Much faster initial render, better perceived performance

---

#### 3.2 Route-Level Code Splitting Optimization

**Problem**: Verify routes aren't loading each other's code unnecessarily.

**Solution**:
- Audit bundle analyzer output
- Ensure stats/shifts components are properly split
- Extract common vendor chunks efficiently

**Files to modify**:
- `next.config.js`

**Implementation**:
```javascript
// next.config.js
experimental: {
  optimizePackageImports: ['@tabler/icons-react', 'recharts', 'lucide-react'],
},
```

**Tools to use**:
```bash
# Analyze bundle
npm run build
# Use @next/bundle-analyzer or similar
```

**Expected Impact**: 20-30% smaller route-specific bundles

---

#### 3.3 Add Resource Hints and Preloading

**Problem**: Critical resources load late in waterfall.

**Solution**:
- Preconnect to Supabase domain
- Preload critical fonts and assets
- Add priority hints for LCP elements

**Files to modify**:
- `app/layout.tsx`
- Individual page metadata

**Implementation**:
```typescript
// app/layout.tsx
export default function RootLayout({ children }) {
  return (
    <html>
      <head>
        <link rel="preconnect" href={process.env.NEXT_PUBLIC_SUPABASE_URL} />
        <link rel="dns-prefetch" href={process.env.NEXT_PUBLIC_SUPABASE_URL} />
      </head>
      <body>{children}</body>
    </html>
  );
}

// For images that are LCP candidates
import Image from 'next/image';
<Image
  src="..."
  priority // Marks as high priority
  alt="..."
/>
```

**Expected Impact**: 10-20% improvement in LCP timing

---

## Implementation Checklist

### Phase 1: Quick Wins
- [ ] 1.1 - Implement React cache() for deduplication
- [ ] 1.2 - Remove blocking shift count from layout
- [ ] 1.3 - Add Suspense boundaries with skeleton UI
- [ ] 1.4 - Lazy load all chart components

### Phase 2: Data Layer
- [ ] 2.1 - Implement shift pagination
- [ ] 2.2 - Add data caching layer
- [ ] 2.3 - Optimize stats calculations
- [ ] 2.4 - Database optimization (indexes)

### Phase 3: Advanced
- [ ] 3.1 - Progressive data loading on stats page
- [ ] 3.2 - Route-level code splitting optimization
- [ ] 3.3 - Add resource hints and preloading

---

## Expected Results

### After Phase 1
- **TTFB**: ~1000ms → ~600-700ms (30-40% improvement)
- **FCP**: ~2-3s → ~1.2-1.8s (40% improvement)
- **LCP**: ~3-4s → ~2.0-2.8s (30% improvement)

### After Phase 1 + 2
- **TTFB**: ~1000ms → ~300-500ms (50-70% improvement)
- **FCP**: ~2-3s → ~1.0-1.5s (40-50% improvement)
- **LCP**: ~3-4s → ~1.8-2.3s (30-40% improvement)

### After All Phases
- **TTFB**: < 400ms ✅ (within good range)
- **FCP**: < 1.5s ✅ (within good range)
- **LCP**: < 2.5s ✅ (within good range)

---

## Monitoring and Validation

### Tools to Use
1. **Vercel Speed Insights** (already installed)
   - Monitor real-user metrics
   - Track improvements over time

2. **Lighthouse CI**
   - Run before/after each phase
   - Document improvements

3. **Chrome DevTools**
   - Performance tab recordings
   - Network waterfall analysis

### Success Criteria
- All three metrics (TTFB, FCP, LCP) consistently in "good" range
- 95th percentile scores meet targets
- Real user metrics from Vercel Speed Insights show improvement

---

## Notes

- Implement phases sequentially for easier debugging
- Measure before/after each phase
- Each optimization is independent and can be rolled back if needed
- Focus on Phase 1 first for immediate wins
- Phase 2 provides the most dramatic improvements
- Phase 3 is polish and incremental gains
