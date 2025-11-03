# Use Data Access Layer (DAL)

Guide for using the Data Access Layer in tidex to load data in Server Components.

## When to use this skill

- Creating a new page that needs data
- Loading shifts, settings, statistics, or user profile
- Any server-side data fetching
- Replacing direct Supabase calls in pages

## Important Context

**All database queries must go through the Data Access Layer** (`data-access/` directory).

Benefits of using DAL:
- **Authentication**: Automatic session verification
- **Caching**: Request deduplication and persistent caching
- **Computation**: Server-side payroll calculations
- **Type safety**: Fully typed, enriched data
- **Single source of truth**: Consistent data loading patterns

**Critical rule**: Pages should NEVER call Supabase directly. Always use DAL functions.

## Available DAL Functions

### Authentication (data-access/auth.ts)

```tsx
// Returns authenticated user or redirects to login
export async function verifySession()
```

### Settings (data-access/settings.ts)

```tsx
// Get user's pay/display settings
export async function getUserSettings()

// Get user profile data
export async function getUserProfile()
```

### Shifts (data-access/shifts.ts)

```tsx
// Get shifts with payroll computations
export async function getComputedShifts(options?: {
  startDate?: string;
  endDate?: string;
  limit?: number;
})
```

### Statistics (data-access/stats.ts)

```tsx
// Get aggregated statistics
export async function getStatsData()

// Get chart data for stats page
export async function getChartsData()
```

### Subscription (data-access/subscription.ts)

```tsx
// Get subscription status
export async function getUserSubscriptionData()
```

### Snapshots (data-access/snapshots.ts)

```tsx
// Get current wage/supplement snapshots for shift creation
export async function getCurrentSnapshots()
```

## Standard Page Pattern

### Step 1: Opt out of prerendering

At the top of your page component, import and call `connection()`:

```tsx
import { connection } from "next/server";

export default async function MyPage() {
  await connection(); // Opt out of prerendering

  // Rest of page logic
}
```

**Why?** Protected pages must be dynamically rendered since they require authentication.

### Step 2: Import DAL functions

```tsx
import { getComputedShifts } from "@/data-access/shifts";
import { getUserSettings } from "@/data-access/settings";
import { getStatsData } from "@/data-access/stats";
// etc.
```

### Step 3: Call DAL functions

DAL functions handle authentication internally, so just call them:

```tsx
// No need to verify session - DAL does this
const { shifts, settings } = await getComputedShifts();
```

### Step 4: Render with data

```tsx
return <ShiftsList shifts={shifts} />;
```

## Complete Example: Shifts Page

```tsx
// app/[locale]/(app)/shifts/page.tsx
import { connection } from "next/server";
import { getComputedShifts } from "@/data-access/shifts";
import { ShiftsList } from "@/components/app/ShiftsList";

export default async function ShiftsPage() {
  // 1. Opt out of prerendering
  await connection();

  // 2. Load data via DAL
  const { shifts, settings } = await getComputedShifts({
    startDate: "2025-01-01",
    endDate: "2025-01-31"
  });

  // 3. Render with precomputed data
  return (
    <div>
      <h1>My Shifts</h1>
      <ShiftsList shifts={shifts} />
    </div>
  );
}
```

## Usage Patterns

### Loading shifts with filters

```tsx
// All shifts
const { shifts } = await getComputedShifts();

// Date range
const { shifts } = await getComputedShifts({
  startDate: "2025-01-01",
  endDate: "2025-01-31"
});

// Limited results
const { shifts } = await getComputedShifts({
  limit: 10
});
```

### Loading multiple data sources

```tsx
// Load in parallel
const [
  { shifts, settings },
  profile,
  stats
] = await Promise.all([
  getComputedShifts(),
  getUserProfile(),
  getStatsData()
]);
```

### Loading settings

```tsx
const settings = await getUserSettings();
// Returns user's wage settings and display preferences
```

### Loading subscription data

```tsx
const subscription = await getUserSubscriptionData();
// Returns subscription tier, status, etc.
```

## What DAL Returns

### getComputedShifts()

Returns object with:
```tsx
{
  shifts: Array<{
    id: string;
    date: string;
    start: string;
    end: string;
    gross: number;        // Computed wage
    paidHours: number;    // Computed paid hours
    breakdown: {...};     // Detailed payroll breakdown
    // ... other shift fields
  }>,
  settings: {
    hourlyWage: number;
    supplementRules: [...];
    // ... other settings
  }
}
```

**Key point**: Shifts include **precomputed** payroll data. Client components render this data without recalculation.

### getUserSettings()

Returns user's settings:
```tsx
{
  hourlyWage: number;
  supplementRules: Array<{...}>;
  displayPreferences: {...};
  // ... other settings
}
```

### getStatsData()

Returns aggregated statistics:
```tsx
{
  totalGross: number;
  totalHours: number;
  averageHourlyRate: number;
  // ... other stats
}
```

## Important Notes

### Authentication is automatic

DAL functions call `verifySession()` internally. If the user is not authenticated, they're redirected to login.

**You do NOT need to verify session manually:**

```tsx
// ❌ DON'T DO THIS
const user = await verifySession();
const shifts = await getComputedShifts();

// ✅ DO THIS
const { shifts } = await getComputedShifts();
```

### Caching is built-in

DAL functions use React `cache()` and Next.js `unstable_cache()`:
- Multiple calls in the same request are deduplicated
- Results are cached for performance
- Cache is invalidated by server actions using `invalidateAndRevalidate()`

### Computations are server-side only

Wage calculations happen in DAL functions via `computeShift()` from `lib/payroll/calc.ts`:
- Pure, deterministic calculations
- No I/O, all inputs explicit
- High precision (3 decimals for hours, 2 for currency)

**Client components receive precomputed data and render it directly.**

### Never call Supabase directly in pages

```tsx
// ❌ DON'T DO THIS
const supabase = await createSupabaseServerClient();
const { data: shifts } = await supabase.from('shifts').select();

// ✅ DO THIS
const { shifts } = await getComputedShifts();
```

## Verification

- [ ] Page imports `connection` from "next/server"
- [ ] Page calls `await connection()` at the top
- [ ] Data loaded via DAL functions (no direct Supabase calls)
- [ ] No manual session verification (DAL handles it)
- [ ] Client components receive precomputed data

## Common Patterns

### Dashboard page

```tsx
import { connection } from "next/server";
import { getComputedShifts } from "@/data-access/shifts";
import { getStatsData } from "@/data-access/stats";

export default async function DashboardPage() {
  await connection();

  const [{ shifts }, stats] = await Promise.all([
    getComputedShifts({ limit: 5 }),
    getStatsData()
  ]);

  return (
    <div>
      <StatsCards stats={stats} />
      <RecentShifts shifts={shifts} />
    </div>
  );
}
```

### Settings page

```tsx
import { connection } from "next/server";
import { getUserSettings, getUserProfile } from "@/data-access/settings";

export default async function SettingsPage() {
  await connection();

  const [settings, profile] = await Promise.all([
    getUserSettings(),
    getUserProfile()
  ]);

  return <SettingsForm settings={settings} profile={profile} />;
}
```

### Stats page with charts

```tsx
import { connection } from "next/server";
import { getChartsData } from "@/data-access/stats";

export default async function StatsPage() {
  await connection();

  const chartData = await getChartsData();

  return <ChartsDisplay data={chartData} />;
}
```

## Migration from Direct Supabase Calls

If you're migrating existing code:

**Before:**
```tsx
export default async function Page() {
  const supabase = await createSupabaseServerClient();
  const user = await verifySession();

  const { data: shifts } = await supabase
    .from('shifts')
    .select()
    .eq('user_id', user.id);

  // Manual computation
  const computed = shifts.map(shift => computeShift(shift, settings));

  return <ShiftsList shifts={computed} />;
}
```

**After:**
```tsx
import { connection } from "next/server";
import { getComputedShifts } from "@/data-access/shifts";

export default async function Page() {
  await connection();

  const { shifts } = await getComputedShifts();

  return <ShiftsList shifts={shifts} />;
}
```

See `docs/dal-migration.md` for complete migration guide.
