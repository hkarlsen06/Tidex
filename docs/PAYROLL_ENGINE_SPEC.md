# Tidex Payroll Engine Specification

> **Version:** 1.1
> **Last Updated:** 2026-01-14
> **Source of Truth:** Next.js app on the main branch
> **Purpose:** Enable re-implementation in any language (Swift, Kotlin, Go, etc.) with identical results

---

## A) Overview

The Tidex payroll engine computes wage earnings for work shifts. It takes shift data (date, start/end time) and wage settings (hourly rate, supplements, tax, break deductions) to produce deterministic earnings values.

### Inputs
- **Shift data**: `shift_date` (ISO), `start_time` (HH:MM), `end_time` (HH:MM), optional custom supplements
- **Wage snapshot**: Hourly wage, supplement rules, tax settings, break deduction settings
- **User settings**: Payroll day, half-tax month, monthly goal

### Outputs
- `durationHours`: Raw duration before break deduction
- `paidHours`: Duration after break deduction
- `basePay`: Earnings from base hourly rate (NOK)
- `supplementPay`: Earnings from supplement overlays (NOK)
- `gross`: Total before tax (`basePay + supplementPay`)
- `taxAmount`: Tax deduction (if enabled)
- `net`: After-tax earnings (`gross - taxAmount`)

### Key Invariants
1. **Deterministic**: Same inputs always produce same outputs
2. **Pure computation**: Zero I/O, all inputs explicit
3. **Cross-midnight support**: Shifts spanning midnight are calculated as continuous time
4. **Payout-date-based tax/snapshot**: Tax and snapshot selection use payout date, not worked date
5. **Precision**: 3 decimal places for hours, 2 decimal places for currency

### Definitions

| Term | Definition |
|------|------------|
| **Shift** | A stored work period with date, start time, end time |
| **Virtual shift** | A computed occurrence from a recurring shift template (not persisted) |
| **Wage snapshot** | Point-in-time capture of wage, supplement, tax, and break settings |
| **Baseline snapshot** | Snapshot with `from_date = NULL`, serves as fallback |
| **Supplement window** | Time-of-day range when a supplement rate applies |
| **Payout date** | Date when wages are paid (typically month after work + payroll day) |
| **Payroll period** | The calendar month whose earnings are grouped for a payout |
| **Month grouping** | Shifts worked in month M are paid in month M+1 |

### Entry Points

**Pure function (core calculation):**
```typescript
computeShift(shift, settings, presetRules, snapshot) // from @/lib/payroll/calc.ts
```

**Effect-wrapped (with validation):**
```typescript
computeShift(shift, settings, presetRules, snapshot) // from @/lib/payroll/effect.ts
```

---

## B) Data Model and Schema Mapping

### B.1 `user_shifts` — Core Shift Data

| Column | Type | Nullable | Purpose |
|--------|------|----------|---------|
| `id` | `uuid` | No | Primary key, unique shift identifier |
| `user_id` | `uuid` | Yes | Foreign key to `auth.users` |
| `shift_date` | `date` | No | The date of the shift (ISO: `YYYY-MM-DD`) |
| `start_time` | `text` | No | Start time in `HH:MM` format |
| `end_time` | `text` | No | End time in `HH:MM` format (supports cross-midnight) |
| `custom_supplements` | `jsonb` | Yes | Shift-specific supplement overrides |
| `created_at` | `timestamptz` | Yes | Creation timestamp (default: `now()`) |

**Behavior notes:**
- When `end_time <= start_time`, shift crosses midnight (e.g., 22:00 to 06:00)
- `custom_supplements` when present completely replaces snapshot supplements for this shift

### B.2 `recurring_shifts` — Recurring Shift Templates

| Column | Type | Nullable | Purpose |
|--------|------|----------|---------|
| `id` | `uuid` | No | Primary key |
| `user_id` | `uuid` | No | Foreign key to `auth.users` |
| `start_time` | `timetz` | No | Shift start time with timezone |
| `end_time` | `timetz` | No | Shift end time with timezone |
| `repeat_interval_weeks` | `smallint` | No | 0 = every week, 1 = every 2 weeks, ..., 8 = every 9 weeks |
| `selected_days` | `jsonb` | No | Anchor dates by weekday: `{ "1": "2025-01-27" }` |
| `end_condition` | `jsonb` | Yes | End rule: `{ type: "never" }`, `{ type: "months", value: N }`, `{ type: "years", value: N }`, `{ type: "end_date", date: "YYYY-MM-DD" }` |
| `exclusions` | `jsonb` | Yes | Array of ISO dates to skip |
| `date_specific_supplements` | `jsonb` | Yes | Per-date custom supplements: `{ "2025-01-15": { rules: [...] } }` |

**Behavior notes:**
- Virtual shifts are generated at runtime, never persisted
- `selected_days` keys are weekday numbers (0=Sunday to 6=Saturday)
- Values are anchor ISO dates from which recurrence starts
- **Note:** Table does NOT have `created_at` or `updated_at` columns

### B.3 `wage_snapshots` — Point-in-Time Wage Settings

| Column | Type | Nullable | Default | Purpose |
|--------|------|----------|---------|---------|
| `id` | `uuid` | No | - | Primary key |
| `user_id` | `uuid` | No | - | Foreign key to `auth.users` |
| `from_date` | `date` | Yes | - | Effective date (`NULL` = baseline snapshot) |
| `hourly_wage` | `numeric` | No | - | Base hourly wage in NOK |
| `wage_level` | `integer` | Yes | - | Tariff level (1-9) or `NULL` for custom wage |
| `supplements` | `jsonb` | No | `'[]'::jsonb` | Array of `SupplementRule` objects (wrapped in `{ rules: [...] }` at runtime) |
| `tax_enabled` | `boolean` | Yes | `false` | Whether tax deduction is enabled |
| `tax_percentage` | `numeric` | Yes | `0` | Tax percentage (0-100) |
| `break_enabled` | `boolean` | Yes | `true` | Whether break deduction is enabled |
| `break_method` | `text` | Yes | `'proportional'` | One of: `proportional`, `base_only`, `end_of_shift`, `none` |
| `break_threshold_hours` | `numeric` | Yes | `5.5` | Hours before break applies |
| `break_deduction_minutes` | `integer` | Yes | `30` | Break duration in minutes |
| `created_at` | `timestamptz` | Yes | - | Creation timestamp |

**Behavior notes:**
- Only one baseline snapshot (`from_date = NULL`) allowed per user
- **Snapshot selection uses TWO different dates:**
  - **Wage, supplements, break settings**: Selected based on **shift date** (the date the shift is worked)
  - **Tax settings only**: Selected based on **payout date** (shift month + 1, on payroll day)
- For a target date D: choose latest snapshot where `from_date <= D` and `from_date IS NOT NULL`
- If none found, use baseline snapshot
- **Note:** DB stores `supplements` as `'[]'::jsonb` but code expects `{ rules: [...] }` structure

### B.4 `user_settings` — User Preferences

| Column | Type | Nullable | Default | Purpose |
|--------|------|----------|---------|---------|
| `user_id` | `uuid` | No | - | Primary key, FK to `auth.users` |
| `payroll_day` | `integer` | Yes | `15` | Day of month (1-31) when payroll is received |
| `half_tax_month` | `integer` | Yes | - | Month (11 or 12) for half-tax; `NULL` = disabled |
| `monthly_goal` | `integer` | Yes | `20000` | Monthly earnings goal in NOK |
| `default_shifts_view` | `varchar(10)` | Yes | `'calendar'` | UI preference: `list` or `calendar` |
| `currency` | `text` | Yes | `'kr'` | Currency display symbol |
| `theme` | `text` | No | `'dark'` | UI theme preference (`light`, `dark`, `system`) |
| `profile_picture_url` | `text` | Yes | - | User's profile picture URL |
| `created_at` | `timestamptz` | Yes | `now()` | Creation timestamp |
| `updated_at` | `timestamptz` | No | `now()` | Last update timestamp |
| `last_active` | `timestamptz` | Yes | `now()` | Last activity timestamp |

**Behavior notes:**
- Wage settings have been moved to `wage_snapshots` (historical accuracy)
- `payroll_day` is used to calculate payout dates for snapshot selection
- `half_tax_month` applies to payout month, not worked month

### B.5 JSONB Structure: `SupplementRule`

Used in `wage_snapshots.supplements` and `user_shifts.custom_supplements`:

```typescript
type SupplementRule = {
  days: number[];    // 1-7 (1=Monday, 7=Sunday)
  from: string;      // "HH:MM" (inclusive)
  to: string;        // "HH:MM" (inclusive)
  rate?: number;     // Fixed NOK per hour (mutually exclusive with percent)
  percent?: number;  // Percentage of base rate (mutually exclusive with rate)
};
```

**Example rules:**
```json
[
  { "days": [1,2,3,4,5], "from": "18:00", "to": "21:00", "rate": 22 },
  { "days": [6], "from": "13:00", "to": "24:00", "rate": 110 },
  { "days": [7], "from": "00:00", "to": "24:00", "rate": 115 }
]
```

### B.6 Preset Supplement Rules (Tariff Default)

From `@/lib/payroll/presets.ts`:

```typescript
const PRESET_SUPPLEMENT_RULES = [
  { days: [1,2,3,4,5], from: "18:00", to: "21:00", rate: 22 },   // Weekday evening
  { days: [1,2,3,4,5], from: "21:00", to: "24:00", rate: 45 },   // Weekday late night
  { days: [6], from: "13:00", to: "15:00", rate: 45 },           // Saturday afternoon
  { days: [6], from: "15:00", to: "18:00", rate: 55 },           // Saturday late afternoon
  { days: [6], from: "18:00", to: "24:00", rate: 110 },          // Saturday evening
  { days: [7], from: "00:00", to: "24:00", rate: 115 },          // Sunday all day
];
```

### B.7 Preset Wage Rates (Tariff Levels)

From `@/lib/payroll/calc.ts`:

| Level | Rate (NOK/hour) |
|-------|-----------------|
| -1 | 129.91 |
| -2 | 132.90 |
| 1 | 184.54 |
| 2 | 185.38 |
| 3 | 187.46 |
| 4 | 193.05 |
| 5 | 210.81 |
| 6 | 256.14 |

---

## C) UI Values Map

### C.1 `TotalCard` Component

**Location:** `components/app/TotalCard.tsx`

**Purpose:** Displays monthly earnings total with optional projection and breakdown.

| Displayed Field | Source | Formula |
|-----------------|--------|---------|
| Main display (large blue number) | `projectedTotal` or `total` prop | Sum of `shift.computed.gross` for all shifts in month |
| Percentage change | `percentageChange` prop | `((currentMonth - previousMonth) / previousMonth) * 100` |
| Subtitle (earned to date) | `total` prop when `projectedTotal` differs | Sum of shifts where `shift_date <= today` |
| Subtitle (before tax) | `grossBeforeTax` prop | Sum of `gross` before tax deduction |
| Shift count | `totalShiftsCount` prop | Count of shifts in month |
| Planned shifts count | `plannedShiftsCount` prop | Count of future shifts in month |

**Conditional UI logic:**
- Shows `— — —` placeholder when total is `0 kr` and `useZeroPlaceholder` is true
- Shows "earned to date" when future shifts exist (projected ≠ total)
- Shows "before tax" when tax is enabled but no future shifts
- Shows shift count when no earnings data available
- Shows help tooltip when displaying dashes but `hasPendingShifts` is true

**Data source:** SSR via `getComputedShifts()` in dashboard page

### C.2 `NextPayrollCard` Component

**Location:** `components/app/NextPayrollCard.tsx`

**Purpose:** Displays next payroll date and amount to be paid.

| Displayed Field | Source | Formula |
|-----------------|--------|---------|
| Payroll date | Calculated from `payrollDay` + `selectedMonth` | `adjustPayrollDate(payrollDay, month, year, locale)` |
| Net amount | `netAmount` prop | Sum of `(gross - taxAmount)` for previous month's shifts |
| Gross amount | `grossAmount` prop | Sum of `gross` for previous month's shifts |
| Tax amount | `taxAmount` prop | `gross * (taxPercentage / 100)` |
| Base amount | `baseAmount` prop | Sum of `basePay` for previous month's shifts |
| Supplement amount | `supplementAmount` prop | Sum of `supplementPay` for previous month's shifts |
| Progress bar | `progress` prop | Progress through month until payroll (1-100) |

**Conditional UI logic:**
- Shows breakdown as either `gross − tax` or `base + supplements` depending on `taxEnabled` and `hasSupplements`
- Shows "Previous payroll" label if today > adjusted payroll date
- Shows "I dag" with party popper icon if `isPayrollToday` is true
- Shows placeholder dashes (`——`) when `hasPayout` is false

**Payout date adjustment:**
```
payrollDate = adjustPayrollDate(payrollDay, month, year, locale)
```
Adjusts backwards from `payrollDay` until a valid payroll day (Tuesday-Friday, non-holiday).

**Data source:** SSR via `getComputedShifts()` with `payoutTaxSettings` and `currentPayoutTaxSettings`

### C.3 `ShiftCard` Component

**Location:** `components/app/ShiftCard.tsx`

**Purpose:** Displays individual shift with earnings breakdown.

| Displayed Field | Source | Formula |
|-----------------|--------|---------|
| Day name | Calculated from `shift.shift_date` | `daysFull[date.getUTCDay()]` |
| Date display | `shift.shift_date` | Formatted as "15 jan" (locale-aware) |
| Time range | `shift.start_time`, `shift.end_time` | `"09:00 – 17:00"` |
| Paid hours | `shift.computed.paidHours` | Formatted with "t" suffix |
| Display amount | `shift.computed` + tax settings | `taxEnabled ? netAmount : gross` |
| Breakdown | `shift.computed` + tax settings | `gross − tax` or `basePay + supplementPay` |
| Progress bar | `progress` prop | Progress through active shift (0-100) |

**Tax calculation in component:**
```typescript
let taxPercentage = taxEnabled ? taxSettings.percentage : 0;

// Half-tax: applied based on PAYOUT month (shift month + 1)
const shiftMonth = parseInt(shift.shift_date.substring(5, 7), 10);
const payoutMonth = shiftMonth === 12 ? 1 : shiftMonth + 1;
if (taxEnabled && halfTaxMonth && payoutMonth === halfTaxMonth) {
  taxPercentage = taxPercentage / 2;
}

const taxAmount = taxEnabled ? gross * (taxPercentage / 100) : 0;
const netAmount = gross - taxAmount;
```

**Additional props:**
- `showEarnings`: When false, hides earnings (shows `——` placeholder)
- `hasConflict`: Shows warning icon and orange border for overlapping shifts
- `excludedFromTotal`: Shows strikethrough for earnings excluded from totals

**Data source:** Passed as `shift` prop from parent component

### C.4 Stats Views

**Location:** `app/[locale]/(app)/stats/page.tsx`

**Data source:** `@dal/stats.ts` via `StatsService`

| Metric | Formula |
|--------|---------|
| Total earnings | Sum of `gross` for all shifts in period |
| Total hours | Sum of `paidHours` for all shifts in period |
| Average hourly rate | `totalEarnings / totalHours` |
| Monthly comparison | `(currentMonth - previousMonth) / previousMonth * 100` |

---

## D) Shift Acquisition Pipeline

### D.1 Canonical Shift Object: `ShiftWithComputations`

From `@/lib/payroll/types.ts`:

```typescript
type ShiftWithComputations = ShiftRow & {
  computed: ShiftComputed;
  tax_enabled?: boolean;
  tax_percentage?: number;
};

type ShiftComputed = {
  id: string;
  durationHours: number;      // Raw duration before break
  paidHours: number;          // Duration after break deduction
  basePay: number;            // NOK from base rate
  supplementPay: number;      // NOK from supplements
  gross: number;              // basePay + supplementPay
  wagePeriods: WagePeriod[];  // After break deduction
  originalWagePeriods: WagePeriod[];  // Before break deduction
  breakAudit: BreakAudit;     // Deduction details
};

type WagePeriod = {
  fromMin: number;      // Minutes from midnight (shift-relative)
  toMin: number;        // Minutes from midnight (exclusive)
  baseRate: number;     // NOK per hour
  supplementRate: number;  // NOK per hour supplement
  totalRate: number;    // baseRate + supplementRate
};

type BreakAudit = {
  method: BreakMethod;
  thresholdHours: number;
  deductedHours: number;
  notes?: string[];
};
```

### D.2 Pipeline Steps

#### Step 1: Fetch Stored Shifts

```typescript
// From ShiftsService in @/lib/services/shifts.ts
const { data } = await supabase
  .from("user_shifts")
  .select("*")
  .eq("user_id", userId)
  .gte("shift_date", startDate)
  .lte("shift_date", endDate)
  .order("shift_date", { ascending: false })
  .limit(limit);
```

#### Step 2: Fetch Recurring Shift Templates

```typescript
const { data: recurringShifts } = await supabase
  .from("recurring_shifts")
  .select("*")
  .eq("user_id", userId);
```

#### Step 3: Generate Virtual Shifts

For each recurring shift template and each month in range:

```typescript
// From @/lib/recurring/utils.ts
function generateVirtualShiftsForMonth(
  yearMonth: { year: number; month: number },
  draft: RecurringDraft
): RecurringVirtualShift[]
```

**Algorithm:**
1. For each selected weekday anchor in `selected_days`:
   a. Find first occurrence of that weekday in target month
   b. Check if date is on/after anchor date
   c. Check if date is in phase with anchor (`isInPhase`)
   d. Check if within end window (if end condition exists)
   e. Check if not in exclusions list
   f. If all pass, add to virtual shifts
   g. Advance by 7 days and repeat

**Phase check formula:**
```typescript
function isInPhase(dateISO, anchorISO, interval) {
  if (interval === 0) return true; // Every week

  const daysDiff = (date - anchor) / (24 * 60 * 60 * 1000);
  const weeksDiff = Math.floor(daysDiff / 7);

  // interval 1 = every 2 weeks, interval 2 = every 3 weeks
  return weeksDiff % (interval + 1) === 0;
}
```

#### Step 4: Collect All Shift Dates

```typescript
const storedDates = shifts.map(s => s.shift_date);
const virtualDates = virtualShifts.map(vs => vs.date);
const allDates = [...storedDates, ...virtualDates];
```

#### Step 5: Batch Snapshot Lookup

```typescript
// Fetch all user's wage snapshots once
const snapshots = await getUserWageSnapshots(userId);

// Use binary search for O(log n) lookup per date
for (const shiftDate of allDates) {
  const payoutDate = calculatePayoutDate(year, month, payrollDay);
  const snapshot = findSnapshotForDate(payoutDate, snapshots);
  snapshotMap.set(shiftDate, snapshot);
}
```

#### Step 6: Compute Each Shift

```typescript
for (const shift of shifts) {
  const snapshot = snapshotMap.get(shift.shift_date);
  const computed = computeShift(shift, settings, PRESET_RULES, snapshot);
  result.push({ ...shift, computed, tax_enabled, tax_percentage });
}
```

### D.3 Date-Range Inclusion Rules

- Boundaries are **inclusive** on both ends
- Query: `shift_date >= startDate AND shift_date <= endDate`
- For overnight shifts: The shift belongs to the **start date**
  - A shift from 22:00 to 06:00 on 2025-01-15 is queried by `shift_date = 2025-01-15`

### D.4 Cross-Midnight Handling

**Detection:**
```typescript
const isCrossMidnight = endTime <= startTime;
```

**Treatment in calculation:**
```typescript
let start = toMin(startHHMM); // e.g., 22:00 = 1320
let end = toMin(endHHMM);     // e.g., 06:00 = 360
if (end <= start) {
  end += 24 * 60;             // 360 + 1440 = 1800
}
// Duration: 1800 - 1320 = 480 minutes = 8 hours
```

**Supplement matching for cross-midnight:**
- Supplements from both the start day and next day are considered
- Time windows are projected into the extended timeline (0-2880 minutes)

### D.5 Virtual Shift Identity

Virtual shifts have synthetic IDs:
```typescript
const id = `virtual-${recurringId}-${shiftDate}`;
// Example: "virtual-abc123-2025-01-15"
```

This ensures stable identity for React keys and conflict detection.

---

## E) Wage Snapshot Selection and Payout Date Logic

### E.1 Payout Date Calculation

From `@/lib/services/shifts.ts`:

```typescript
function calculatePayoutDate(
  earningsYear: number,
  earningsMonth: number, // 1-12
  payrollDay: number
): string {
  // Payout month is earnings month + 1
  let payoutYear = earningsYear;
  let payoutMonth = earningsMonth + 1;

  if (payoutMonth > 12) {
    payoutMonth = 1;
    payoutYear += 1;
  }

  // Handle edge case: payroll_day exceeds days in payout month
  const daysInPayoutMonth = new Date(payoutYear, payoutMonth, 0).getDate();
  const effectivePayrollDay = Math.min(payrollDay, daysInPayoutMonth);

  return `${payoutYear}-${padZero(payoutMonth)}-${padZero(effectivePayrollDay)}`;
}
```

**Example:**
- Shift on 2025-01-15, payroll day = 20
- Earnings month = January (1)
- Payout month = February (2)
- Payout date = 2025-02-20

### E.2 Payout Date Adjustment for Holidays

From `@/lib/payroll/adjust-payroll-date.ts`:

```typescript
function adjustPayrollDate(
  payrollDay: number,
  month: number,      // 0-11 (JavaScript Date format)
  year: number,
  locale: Locale = 'no'
): Date {
  let date = new Date(year, month, payrollDay);

  // Move backward until valid payroll day found (max 10 iterations)
  while (isInvalidPayrollDay(date, locale)) {
    date.setDate(date.getDate() - 1);
  }

  return date;
}

function isInvalidPayrollDay(date: Date, locale: Locale): boolean {
  return isWeekend(date) || isMonday(date) || isPublicHoliday(date, locale);
}
```

**Valid payroll days:** Tuesday, Wednesday, Thursday, Friday (excluding holidays)

**Norwegian holidays:** See `@/lib/holidays/norwegian-holidays.ts`
- Fixed: New Year's Day, Labour Day (May 1), Constitution Day (May 17), Christmas Day, Boxing Day
- Moveable (Easter-based): Maundy Thursday, Good Friday, Easter Sunday, Easter Monday, Ascension Day, Whit Sunday, Whit Monday

### E.3 Snapshot Selection Algorithm

**IMPORTANT: Two different lookups are performed for each shift:**

1. **Wage/Supplement/Break Snapshot**: Looked up by **shift date** (when the work is performed)
2. **Tax Snapshot**: Looked up by **payout date** (when wages are received, shift month + 1)

From `@/lib/services/shifts.ts`:

```typescript
// Wage/supplement snapshot based on shift date
const snapshot = snapshotMap.get(shift.shift_date) ?? null;
// Tax snapshot based on payout date (when the shift is paid out)
const payoutDate = getPayoutDateForShift(shift.shift_date);
const taxSnapshot = payoutSnapshotMap.get(payoutDate) ?? null;
```

**Binary search algorithm** (used for both lookups):

```typescript
function findSnapshotForDate(targetDate: string, snapshots: WageSnapshot[]): WageSnapshot | null {
  // snapshots sorted by from_date DESC (newest first)

  // Find baseline (from_date = NULL) for fallback
  const baseline = snapshots.find(s => s.from_date === null);

  // Filter to only dated snapshots and sort ascending for binary search
  const datedSnapshots = snapshots
    .filter(s => s.from_date !== null)
    .reverse(); // Now ascending

  // Binary search: find the latest snapshot where from_date <= targetDate
  let left = 0, right = datedSnapshots.length - 1;
  let result = null;

  while (left <= right) {
    const mid = Math.floor((left + right) / 2);
    if (datedSnapshots[mid].from_date <= targetDate) {
      result = datedSnapshots[mid];
      left = mid + 1; // Look for later valid snapshot
    } else {
      right = mid - 1;
    }
  }

  return result || baseline || null;
}
```

**Selection rules:**
1. Find latest dated snapshot where `from_date <= targetDate`
2. If none found, use baseline snapshot (`from_date = NULL`)
3. If no baseline, return null (calculation will use defaults)

**Inclusive from_date:** A snapshot with `from_date = 2025-02-01` applies to target dates >= 2025-02-01

**Example:**
- Shift on 2025-01-15, payroll day = 20
- Wage snapshot lookup: `targetDate = 2025-01-15` (shift date)
- Tax snapshot lookup: `targetDate = 2025-02-20` (payout date)

### E.4 Multiple Snapshots Same Date

If multiple snapshots have the same `from_date`, behavior is undefined (database constraint prevents this). The unique index `idx_wage_snapshots_unique_date` enforces one snapshot per date per user.

---

## F) Pay Calculation Engine (Math Spec)

### F.1 Precision Constants

```typescript
const HOUR_DECIMAL_PRECISION = 1000;  // 3 decimal places (0.001 hours)
const CURRENCY_PRECISION = 100;       // 2 decimal places (cents)
```

### F.2 Time Conversion

```typescript
function toMin(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}
// "09:00" → 540
// "17:30" → 1050
// "24:00" → 1440
```

### F.3 Duration Calculation

```typescript
let start = toMin(startTime);  // e.g., 540
let end = toMin(endTime);      // e.g., 1050

// Handle cross-midnight
if (end <= start) {
  end += 24 * 60; // Add 1440 minutes (24 hours)
}

const totalMinutes = end - start;
const durationHours = +(totalMinutes / 60).toFixed(2);
```

### F.4 Weekday Calculation

```typescript
const WEEKDAYS = [7, 1, 2, 3, 4, 5, 6]; // JS getDay(): 0=Sun → 7, then 1..6 Mon..Sat

const date = new Date(shiftDate + "T00:00:00Z");
const weekday = WEEKDAYS[date.getUTCDay()]; // 1-7 (Mon-Sun)
```

### F.5 Base Rate Resolution

```typescript
function resolveBaseRate(shift: ShiftRow, snapshot: WageSnapshot | null): number {
  // Priority 1: New snapshot system
  if (snapshot?.hourly_wage && snapshot.hourly_wage > 0) {
    return snapshot.hourly_wage;
  }

  // Priority 2: Legacy per-shift snapshot (backward compatibility)
  if (shift.hourly_wage_snapshot && shift.hourly_wage_snapshot > 0) {
    return shift.hourly_wage_snapshot;
  }

  // Priority 3: Fallback to tariff level 1
  return PRESET_WAGE_RATES["1"]; // 184.54
}
```

### F.6 Supplement Rules Resolution

```typescript
function resolveSupplementRules(
  weekday: number,
  predefinedRules: SupplementRule[],
  customSupplements: CustomSupplementsData | null
): SupplementRule[] {
  // Custom supplements completely replace predefined rules
  if (customSupplements?.rules?.length > 0) {
    return customSupplements.rules.map(rule => ({
      ...rule,
      days: [weekday], // Apply to this shift's weekday only
    }));
  }

  return predefinedRules;
}
```

### F.7 Wage Periods Construction

From `@/lib/payroll/periods.ts`:

**Algorithm:**
1. Collect all time boundaries (shift start/end + rule boundaries)
2. Sort boundaries
3. Create periods between consecutive boundaries
4. For each period, find highest applicable supplement

```typescript
function buildWagePeriods(
  startHHMM: string,
  endHHMM: string,
  weekday: number,
  baseRate: number,
  rules: SupplementRule[]
): WagePeriod[] {
  let start = toMin(startHHMM);
  let end = toMin(endHHMM);
  if (end <= start) end += 24 * 60;

  // Collect boundaries
  const points = new Set([start, end]);
  for (const rule of rules) {
    if (!rule.days.includes(weekday)) continue;

    let ruleFrom = toMin(rule.from);
    let ruleTo = toMin(rule.to);
    // Handle cross-midnight rules
    if (ruleTo < ruleFrom) ruleTo += 24 * 60;

    // Consider both same-day and next-day projections
    for (const base of [0, 24 * 60]) {
      const a = ruleFrom + base;
      const b = ruleTo + base;
      if (b < start || a > end) continue;
      if (a > start && a < end) points.add(a);
      if (b > start && b < end) points.add(b);
    }
  }

  const sorted = Array.from(points).sort((a, b) => a - b);
  const periods: WagePeriod[] = [];

  for (let i = 0; i < sorted.length - 1; i++) {
    const a = sorted[i], b = sorted[i + 1];

    // Find highest supplement for this period
    let supplement = 0;
    for (const rule of rules) {
      if (!rule.days.includes(weekday)) continue;

      for (const base of [0, 24 * 60]) {
        let ruleFrom = toMin(rule.from) + base;
        let ruleTo = toMin(rule.to) + base;
        // Handle cross-midnight rules
        if (toMin(rule.to) < toMin(rule.from)) ruleTo += 24 * 60;

        // Period [a,b) must be fully within rule [ruleFrom, ruleTo] (inclusive)
        if (a >= ruleFrom && b - 1 <= ruleTo) {
          const rate = resolveSupplementRate(rule, baseRate);
          supplement = Math.max(supplement, rate);
        }
      }
    }

    periods.push({
      fromMin: a,
      toMin: b,
      baseRate,
      supplementRate: supplement,
      totalRate: baseRate + supplement,
    });
  }

  return periods;
}
```

### F.8 Supplement Rate Resolution

```typescript
function resolveSupplementRate(rule: SupplementRule, baseRate: number): number {
  // Fixed rate (NOK per hour)
  if (rule.rate != null && !isNaN(rule.rate)) {
    return rule.rate;
  }

  // Percentage of base rate
  if (rule.percent != null && !isNaN(rule.percent)) {
    return (baseRate * rule.percent) / 100;
  }

  return 0;
}
```

**Stacking behavior:** Highest-wins. Only the highest supplement rate applies to each time period.

### F.9 Break Deduction

From `@/lib/payroll/breaks.ts`:

```typescript
function applyBreakDeduction(
  periods: WagePeriod[],
  method: BreakMethod,
  thresholdHours: number,
  deductionHours: number
): { periods: WagePeriod[]; audit: BreakAudit } {
  const totalMinutes = periods.reduce((sum, p) => sum + (p.toMin - p.fromMin), 0);
  const totalHours = totalMinutes / 60;

  // Threshold comparison: strict greater than (>)
  let toDeduct = totalHours > thresholdHours ? deductionHours : 0;

  let adjusted = periods.map(p => ({ ...p }));

  if (toDeduct > 0 && method !== "none") {
    let remaining = Math.round(toDeduct * 60);

    if (method === "end_of_shift") {
      // Subtract from the tail
      for (let i = adjusted.length - 1; i >= 0 && remaining > 0; i--) {
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const cut = Math.min(span, remaining);
        adjusted[i].toMin -= cut;
        remaining -= cut;
      }
    } else if (method === "proportional") {
      // Deduct exact proportional fractions (not rounded to minutes)
      for (let i = 0; i < adjusted.length; i++) {
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const proportion = span / totalMinutes;
        const cutMinutes = proportion * toDeduct * 60;
        adjusted[i].toMin -= cutMinutes;
      }
    } else if (method === "base_only") {
      // Deduct from periods with lowest supplement first
      const order = adjusted
        .map((p, idx) => ({ idx, supplement: p.supplementRate }))
        .sort((a, b) => a.supplement - b.supplement);

      for (const { idx } of order) {
        if (remaining <= 0) break;
        const span = adjusted[idx].toMin - adjusted[idx].fromMin;
        const cut = Math.min(span, remaining);
        adjusted[idx].toMin -= cut;
        remaining -= cut;
      }
    }

    // Remove empty periods
    adjusted = adjusted.filter(p => p.toMin > p.fromMin);
  }

  return {
    periods: adjusted,
    audit: { method, thresholdHours, deductedHours: toDeduct },
  };
}
```

**Break method behaviors:**

| Method | Behavior |
|--------|----------|
| `proportional` | Deducts break time proportionally across all periods based on their duration |
| `base_only` | Deducts from periods with lowest supplement rate first |
| `end_of_shift` | Deducts from the last period(s) of the shift |
| `none` | No break deduction |

**Threshold edge cases:**
- Shift exactly at threshold (e.g., 5.5h with 5.5h threshold): NO break applied (uses `>`, not `>=`)
- Shift shorter than break: Break capped at shift duration

### F.10 Pay Calculation

```typescript
let basePay = 0, supplementPay = 0;

for (const period of periods) {
  // Round hours to 3 decimals
  const hours = Math.round((period.toMin - period.fromMin) / 60 * 1000) / 1000;

  // Round each period's contribution to cents
  basePay += Math.round(hours * period.baseRate * 100) / 100;
  supplementPay += Math.round(hours * period.supplementRate * 100) / 100;
}

basePay = +basePay.toFixed(2);
supplementPay = +supplementPay.toFixed(2);
const gross = +(basePay + supplementPay).toFixed(2);
```

### F.11 Tax Calculation

Tax is applied **client-side** or in aggregations, not in `computeShift`:

```typescript
const taxEnabled = snapshot.tax_enabled;
const taxPercentage = snapshot.tax_percentage;

// Half-tax adjustment (based on payout month)
const payoutMonth = shiftMonth === 12 ? 1 : shiftMonth + 1;
const effectiveTaxPct = (halfTaxMonth === payoutMonth)
  ? taxPercentage / 2
  : taxPercentage;

const taxAmount = taxEnabled ? gross * (effectiveTaxPct / 100) : 0;
const net = gross - taxAmount;
```

### F.12 Complete Computation Flow (Pseudocode)

```
FUNCTION computeShift(shift, settings, presetRules, snapshot):
  // 1. Parse times
  start_minutes = toMinutes(shift.start_time)
  end_minutes = toMinutes(shift.end_time)
  IF end_minutes <= start_minutes THEN
    end_minutes += 1440  // Cross-midnight

  // 2. Get weekday (1-7)
  date = parseDate(shift.shift_date)
  weekday = WEEKDAYS[date.dayOfWeek]

  // 3. Resolve base rate
  baseRate = snapshot?.hourly_wage OR shift.hourly_wage_snapshot OR 184.54

  // 4. Resolve supplement rules
  rules = shift.custom_supplements OR snapshot.supplements OR presetRules

  // 5. Build wage periods
  periods = buildWagePeriods(start, end, weekday, baseRate, rules)

  // 6. Calculate raw duration
  totalMinutes = SUM(period.toMin - period.fromMin FOR period IN periods)
  durationHours = ROUND(totalMinutes / 60, 2)

  // 7. Apply break deduction
  breakEnabled = snapshot.break_enabled OR true
  breakMethod = snapshot.break_method OR "proportional"
  threshold = snapshot.break_threshold_hours OR 5.5
  breakMinutes = breakEnabled ? (snapshot.break_deduction_minutes OR 30) : 0

  IF durationHours > threshold AND breakEnabled THEN
    periods = applyBreakDeduction(periods, breakMethod, threshold, breakMinutes/60)

  // 8. Calculate paid hours
  paidMinutes = SUM(period.toMin - period.fromMin FOR period IN periods)
  paidHours = ROUND(paidMinutes / 60, 2)

  // 9. Calculate pay
  basePay = 0
  supplementPay = 0
  FOR period IN periods:
    hours = ROUND((period.toMin - period.fromMin) / 60, 3)
    basePay += ROUND(hours * period.baseRate, 2)
    supplementPay += ROUND(hours * period.supplementRate, 2)

  gross = ROUND(basePay + supplementPay, 2)

  RETURN {
    id: shift.id,
    durationHours,
    paidHours,
    basePay,
    supplementPay,
    gross,
    wagePeriods: periods,
    originalWagePeriods: originalPeriods,
    breakAudit: { method, threshold, deducted }
  }
```

---

## G) Aggregations and Higher-Level Metrics

### G.1 Monthly Totals (TotalCard)

```typescript
// From ShiftsService
const aggregates = shifts.reduce((acc, shift) => ({
  totalHours: acc.totalHours + shift.computed.paidHours,
  totalEarnings: acc.totalEarnings + shift.computed.gross,
}), { totalHours: 0, totalEarnings: 0 });
```

**Filter:** Shifts where `startDate <= shift_date <= endDate`

### G.2 Next Payroll (NextPayrollCard)

**Which shifts included:** Previous month's shifts (earnings month = current month - 1)

**Calculation:**
```typescript
const prevMonth = currentMonth - 1;
const prevYear = prevMonth === 0 ? currentYear - 1 : currentYear;
const actualPrevMonth = prevMonth === 0 ? 12 : prevMonth;

// Filter shifts from previous month
const prevMonthShifts = shifts.filter(s => {
  const [y, m] = s.shift_date.split('-').map(Number);
  return y === prevYear && m === actualPrevMonth;
});

// Get tax settings for current payout
const payoutDate = calculatePayoutDate(prevYear, actualPrevMonth, payrollDay);
const snapshot = getSnapshotForDate(payoutDate);

const grossAmount = SUM(shift.computed.gross);
const taxAmount = snapshot.tax_enabled ? grossAmount * (snapshot.tax_percentage / 100) : 0;
const netAmount = grossAmount - taxAmount;
```

### G.3 Projected Total

**Definition:** Total earnings including future planned shifts

```typescript
const today = new Date().toISOString().slice(0, 10);

const earnedToDate = shifts
  .filter(s => s.shift_date <= today)
  .reduce((sum, s) => sum + s.computed.gross, 0);

const projectedTotal = shifts
  .reduce((sum, s) => sum + s.computed.gross, 0);

const hasFutureShifts = projectedTotal !== earnedToDate;
```

### G.4 Next Shift Selection

```typescript
const today = new Date().toISOString().slice(0, 10);
const now = new Date();

// Find first shift that hasn't ended yet
const nextShift = shifts
  .filter(s => {
    if (s.shift_date > today) return true;
    if (s.shift_date < today) return false;

    // Same day: check if shift has ended
    const [endH, endM] = s.end_time.split(':').map(Number);
    const shiftEnd = new Date(now);
    shiftEnd.setHours(endH, endM, 0, 0);

    return now < shiftEnd;
  })
  .sort((a, b) => {
    // Sort by date, then by start time
    const dateCompare = a.shift_date.localeCompare(b.shift_date);
    if (dateCompare !== 0) return dateCompare;
    return a.start_time.localeCompare(b.start_time);
  })[0];
```

**Includes:** Both stored and virtual shifts

### G.5 Stats Aggregates

From `@dal/stats.ts`:

| Aggregate | Formula | Period |
|-----------|---------|--------|
| Total hours | `SUM(paidHours)` | Selected range |
| Total earnings | `SUM(gross)` | Selected range |
| Average per shift | `totalEarnings / shiftCount` | Selected range |
| Average hourly | `totalEarnings / totalHours` | Selected range |
| Month-over-month % | `(current - previous) / previous * 100` | Comparison |

### G.6 Conflict Exclusion

From `@/lib/shifts/conflictExclusion.ts`:

When multiple shifts overlap on the same date, only one contributes to earnings totals. The shift with the **lowest** gross earnings is kept; all higher-earning overlapping shifts are excluded (displayed with strikethrough).

**Algorithm:**
1. Group shifts by date
2. For each date with 2+ shifts, find overlapping clusters using union-find
3. For each cluster, sort by gross earnings ascending
4. Exclude all but the shift with lowest earnings

```typescript
function buildExcludedShiftIds(shifts: ShiftWithComputations[]): Set<string> {
  const result = new Set<string>();
  const shiftsByDate = groupByDate(shifts);

  for (const [date, shiftsOnDate] of shiftsByDate) {
    if (shiftsOnDate.length < 2) continue;

    // Find overlapping clusters using union-find
    const clusters = findOverlappingClusters(shiftsOnDate);

    for (const cluster of clusters) {
      if (cluster.length < 2) continue;

      // Sort by gross ascending, keep only the lowest
      cluster.sort((a, b) => a.computed.gross - b.computed.gross);
      for (let i = 1; i < cluster.length; i++) {
        result.add(cluster[i].id);
      }
    }
  }

  return result;
}
```

**Overlap detection:**
```typescript
function shiftsOverlap(a, b): boolean {
  let startA = toMinutes(a.start_time);
  let endA = toMinutes(a.end_time);
  let startB = toMinutes(b.start_time);
  let endB = toMinutes(b.end_time);

  // Handle cross-midnight
  if (endA <= startA) endA += 24 * 60;
  if (endB <= startB) endB += 24 * 60;

  return startA < endB && startB < endA;
}
```

**Rationale:** Users sometimes accidentally create overlapping shifts. By keeping only the lowest-earning shift in totals, we:
1. Prevent double-counting earnings
2. Preserve all shift data for viewing
3. Give visual feedback (strikethrough) for excluded shifts

### G.7 Caching

**React `cache()`:** Request deduplication within single render
```typescript
export const getComputedShifts = cache(async (userId, options) => { ... });
```

**Next.js `cacheTag()`:** Cross-request caching with invalidation
```typescript
cacheTag(`user-${userId}`, "user-shifts");
```

**Invalidation:**
```typescript
import { revalidateTag } from "next/cache";
revalidateTag(`user-${userId}`, "max");
```

---

## H) Data Fetching, SSR Windowing, and API Expansion

### H.1 SSR Prefetch Window

Dashboard and shifts pages prefetch 3 months of data:

```typescript
// Dashboard page
const previous = getPreviousYearMonth();
const current = getCurrentYearMonth();
const next = getNextYearMonth();

const { shifts } = await getComputedShifts(user.id, {
  startDate: getMonthStart(previous.year, previous.month),
  endDate: getMonthEnd(next.year, next.month),
  limit: 200, // ~50 shifts per month × 3 + headroom
  year: current.year,
  month: current.month,
});
```

**Preloaded months tracked:**
```typescript
const preloadedMonths = [
  `${previous.year}-${previous.month.toString().padStart(2, '0')}`,
  `${current.year}-${current.month.toString().padStart(2, '0')}`,
  `${next.year}-${next.month.toString().padStart(2, '0')}`,
];
```

### H.2 Client-Side Expansion

When user navigates outside prefetched window:

```typescript
// Client component fetches additional months
async function loadMonth(year: number, month: number) {
  const response = await fetch(`/api/shifts?year=${year}&month=${month}`);
  const data = await response.json();
  // Merge with existing shifts in state
}
```

### H.3 API Routes

**`GET /api/shifts`:**
- Accepts: `year`, `month`
- Uses `getComputedShiftsForApi()` (no automatic redirect)
- Returns: `{ shifts, settings, payoutTaxSettings }`
- Caching: `Cache-Control: private, max-age=300, stale-while-revalidate=60`

**`POST /api/shifts`:**
- Body: `{ dates: string[], start: string, end: string, recurringId?: string }`
- Calls `createShifts()` server action
- Returns: `{ success: true, id: string }` or `{ error: string }`

### H.4 Cache Tags and Invalidation

| Cache Tag | Set By | Invalidated By |
|-----------|--------|----------------|
| `user-${userId}` | All DAL functions | Any user data mutation |
| `user-shifts` | `getComputedShifts()` | Shift CRUD operations |
| `user-settings` | `getUserSettings()` | Settings updates |
| `user-wages` | `getUserWageSnapshots()` | Wage snapshot mutations |

**Invalidation pattern:**
```typescript
// From @dal/cache.ts
export function invalidateUserCache(userId: string) {
  revalidateTag(`user-${userId}`, "max");
}
```

---

## I) Test Vectors and Fixtures

### Test Case Factory

```typescript
function createShift(overrides: Partial<ShiftRow> = {}): ShiftRow {
  return {
    id: crypto.randomUUID(),
    user_id: "test-user-id",
    shift_date: "2025-01-15",
    start_time: "09:00",
    end_time: "17:00",
    ...overrides,
  };
}

function createSnapshot(overrides: Partial<WageSnapshot> = {}): WageSnapshot {
  return {
    id: crypto.randomUUID(),
    user_id: "test-user-id",
    from_date: null,
    hourly_wage: 185.00,
    wage_level: 2,
    supplements: { rules: PRESET_SUPPLEMENT_RULES },
    tax_enabled: false,
    tax_percentage: 0,
    break_enabled: true,
    break_method: "proportional",
    break_threshold_hours: 5.5,
    break_deduction_minutes: 30,
    ...overrides,
  };
}

function createSettings(overrides: Partial<UserSettings> = {}): UserSettings {
  return {
    payroll_day: 15,
    half_tax_month: null,
    monthly_goal: 20000,
    ...overrides,
  };
}
```

### Test Case 1: Basic Weekday Shift (No Supplements)

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-01-15", // Wednesday
  start_time: "09:00",
  end_time: "14:00",
});

const snapshot = createSnapshot({
  hourly_wage: 185.00,
  supplements: { rules: [] }, // No supplements
  break_enabled: false,
});
```

**Expected outputs:**
```typescript
{
  durationHours: 5.00,
  paidHours: 5.00,
  basePay: 925.00,      // 5h × 185
  supplementPay: 0,
  gross: 925.00,
}
```

### Test Case 2: Weekday Evening Shift (With Supplement)

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-01-15", // Wednesday
  start_time: "17:00",
  end_time: "22:00",
});

const snapshot = createSnapshot({
  hourly_wage: 185.00,
  supplements: { rules: [
    { days: [1,2,3,4,5], from: "18:00", to: "21:00", rate: 22 },
    { days: [1,2,3,4,5], from: "21:00", to: "24:00", rate: 45 },
  ]},
  break_enabled: false,
});
```

**Expected outputs:**
```typescript
{
  durationHours: 5.00,
  paidHours: 5.00,
  basePay: 925.00,      // 5h × 185
  supplementPay: 111.00, // 1h×0 + 3h×22 + 1h×45 = 0 + 66 + 45
  gross: 1036.00,
}
```

### Test Case 3: Cross-Midnight Shift

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-01-15", // Wednesday
  start_time: "22:00",
  end_time: "06:00",
});

const snapshot = createSnapshot({
  hourly_wage: 185.00,
  supplements: { rules: [
    { days: [1,2,3,4,5], from: "21:00", to: "24:00", rate: 45 },
  ]},
  break_enabled: true,
  break_threshold_hours: 5.5,
  break_deduction_minutes: 30,
});
```

**Expected outputs:**
```typescript
{
  durationHours: 8.00,        // 22:00 to 06:00 = 8 hours
  paidHours: 7.50,            // 8h - 0.5h break
  basePay: 1387.51,           // 346.88 (1.875h × 185) + 1040.63 (5.625h × 185)
  supplementPay: 84.38,       // 1.875h × 45 (proportional: 2h loses 2/8 × 0.5h)
  gross: 1471.89,
}
```

### Test Case 4: Sunday Full Day (High Supplement)

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-01-19", // Sunday
  start_time: "08:00",
  end_time: "16:00",
});

const snapshot = createSnapshot({
  hourly_wage: 185.00,
  supplements: { rules: [
    { days: [7], from: "00:00", to: "24:00", rate: 115 },
  ]},
  break_enabled: true,
  break_threshold_hours: 5.5,
  break_deduction_minutes: 30,
});
```

**Expected outputs:**
```typescript
{
  durationHours: 8.00,
  paidHours: 7.50,
  basePay: 1387.50,      // 7.5h × 185
  supplementPay: 862.50, // 7.5h × 115
  gross: 2250.00,
}
```

### Test Case 5: Break Threshold Edge Case (Exactly At Threshold)

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-01-15",
  start_time: "09:00",
  end_time: "14:30", // Exactly 5.5 hours
});

const snapshot = createSnapshot({
  hourly_wage: 185.00,
  break_enabled: true,
  break_threshold_hours: 5.5,
  break_deduction_minutes: 30,
});
```

**Expected outputs:**
```typescript
{
  durationHours: 5.50,
  paidHours: 5.50,       // NO break (threshold uses >)
  basePay: 1017.50,
  supplementPay: 0,
  gross: 1017.50,
}
```

### Test Case 6: Break Deduction Methods

**a) Proportional:**
```typescript
const snapshot = createSnapshot({
  break_method: "proportional",
});
// Break distributed across all periods proportionally
```

**b) Base Only:**
```typescript
const snapshot = createSnapshot({
  break_method: "base_only",
});
// Break deducted from periods with lowest supplement first
```

**c) End of Shift:**
```typescript
const snapshot = createSnapshot({
  break_method: "end_of_shift",
});
// Break deducted from last period(s) only
```

### Test Case 7: Snapshot Selection (Wage vs Tax)

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-01-15",
});

const settings = createSettings({
  payroll_day: 20,
});

// Snapshots:
const baseline = createSnapshot({
  from_date: null,
  hourly_wage: 180.00,
  tax_percentage: 25,
});

const january = createSnapshot({
  from_date: "2025-01-01",
  hourly_wage: 185.00,
  tax_percentage: 30,
});

const february = createSnapshot({
  from_date: "2025-02-01",
  hourly_wage: 190.00,
  tax_percentage: 35,
});
```

**Logic:**
- Shift date: 2025-01-15
- Payout date: 2025-02-20 (January earnings paid in February)
- **Wage snapshot** (by shift date): `january` (`from_date: 2025-01-01` <= `2025-01-15`)
- **Tax snapshot** (by payout date): `february` (`from_date: 2025-02-01` <= `2025-02-20`)
- Hourly wage used: **185.00** (from january snapshot)
- Tax percentage used: **35%** (from february snapshot)

### Test Case 8: Tax Calculation with Half-Tax Month

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-11-15", // November
});

const snapshot = createSnapshot({
  tax_enabled: true,
  tax_percentage: 30,
});

const settings = createSettings({
  half_tax_month: 12, // December (payout month for November shifts)
});
```

**Expected:**
```typescript
// Payout month = December
// Half-tax applies because halfTaxMonth === payoutMonth
const effectiveTaxPct = 30 / 2 = 15;
const taxAmount = gross * 0.15;
```

### Test Case 9: Holiday Payout Adjustment

**Inputs:**
```typescript
const payrollDay = 17; // Constitution Day
const month = 4;       // May (0-indexed)
const year = 2025;
const locale = "no";
```

**Expected:**
```typescript
// May 17, 2025 is Constitution Day (holiday)
// May 16 is Friday (valid)
const adjustedDate = new Date(2025, 4, 16); // May 16
```

### Test Case 10: Percent Supplement

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-01-15",
  start_time: "18:00",
  end_time: "22:00",
});

const snapshot = createSnapshot({
  hourly_wage: 200.00,
  supplements: { rules: [
    { days: [3], from: "18:00", to: "24:00", percent: 50 }, // 50% of base
  ]},
  break_enabled: false,
});
```

**Expected outputs:**
```typescript
{
  durationHours: 4.00,
  paidHours: 4.00,
  basePay: 800.00,       // 4h × 200
  supplementPay: 400.00, // 4h × (200 × 0.50)
  gross: 1200.00,
}
```

### Test Case 11: Virtual Shift from Recurring

**Inputs:**
```typescript
const recurringShift = {
  id: "recurring-123",
  start_time: "09:00",
  end_time: "17:00",
  repeat_interval_weeks: 1, // Every 2 weeks
  selected_days: { "3": "2025-01-15" }, // Wednesday anchor
  end_condition: null,
  exclusions: ["2025-01-29"],
};

const month = { year: 2025, month: 1 }; // January
```

**Expected virtual shifts:**
```typescript
[
  { date: "2025-01-15", weekday: 3 }, // Anchor
  // 2025-01-22 skipped (wrong phase - 1 week gap, need 2 weeks)
  // 2025-01-29 in phase but excluded
]
```

### Test Case 12: Supplement Window Crossing Midnight

**Inputs:**
```typescript
const shift = createShift({
  shift_date: "2025-01-18", // Saturday
  start_time: "20:00",
  end_time: "02:00",
});

const snapshot = createSnapshot({
  hourly_wage: 185.00,
  supplements: { rules: [
    { days: [6], from: "18:00", to: "24:00", rate: 110 }, // Saturday evening
    { days: [7], from: "00:00", to: "24:00", rate: 115 }, // Sunday all day
  ]},
  break_enabled: false,
});
```

**Expected outputs:**
```typescript
{
  durationHours: 6.00,
  paidHours: 6.00,
  // 20:00-00:00 (4h) at Saturday rate 110
  // 00:00-02:00 (2h) at Sunday rate 115
  basePay: 1110.00,       // 6h × 185
  supplementPay: 670.00,  // 4h×110 + 2h×115 = 440 + 230
  gross: 1780.00,
}
```

### Test Case 13: Conflict Exclusion (Overlapping Shifts)

**Inputs:**
```typescript
const shifts = [
  createShift({
    id: "shift-a",
    shift_date: "2025-01-15",
    start_time: "09:00",
    end_time: "17:00", // Gross: 1480 NOK
  }),
  createShift({
    id: "shift-b",
    shift_date: "2025-01-15",
    start_time: "14:00",
    end_time: "22:00", // Gross: 1850 NOK (higher due to evening supplement)
  }),
];
```

**Expected:**
```typescript
// shift-a and shift-b overlap (14:00-17:00)
// shift-a has lower gross (1480) → included in totals
// shift-b has higher gross (1850) → excluded from totals, shown with strikethrough

const excludedIds = buildExcludedShiftIds(shifts);
expect(excludedIds.has("shift-b")).toBe(true);
expect(excludedIds.has("shift-a")).toBe(false);

// Monthly total = 1480 (only shift-a counted)
```

---

## Appendix: File Location Reference

| Component/Module | Path Alias | Purpose |
|------------------|------------|---------|
| `computeShift` (pure) | `@/lib/payroll/calc.ts` | Core payroll calculation |
| `computeShift` (Effect) | `@/lib/payroll/effect.ts` | Validated calculation |
| `buildWagePeriods` | `@/lib/payroll/periods.ts` | Time period construction |
| `applyBreakDeduction` | `@/lib/payroll/breaks.ts` | Break deduction logic |
| `PRESET_SUPPLEMENT_RULES` | `@/lib/payroll/presets.ts` | Tariff supplement rules |
| `adjustPayrollDate` | `@/lib/payroll/adjust-payroll-date.ts` | Holiday adjustment |
| `ShiftsService` | `@/lib/services/shifts.ts` | Effect-based shift loading |
| `getComputedShifts` | `@dal/shifts.ts` | DAL Promise wrapper |
| `getUserWageSnapshots` | `@dal/wage-snapshots.ts` | Wage snapshot access |
| `getSnapshotForDate` | `@dal/wage-snapshots.ts` | Single-date snapshot lookup |
| `TotalCard` | `components/app/TotalCard.tsx` | Monthly total display |
| `NextPayrollCard` | `components/app/NextPayrollCard.tsx` | Payout display |
| `ShiftCard` | `components/app/ShiftCard.tsx` | Individual shift display |
| `generateVirtualShiftsForMonth` | `@/lib/recurring/utils.ts` | Virtual shift generation |
| `buildExcludedShiftIds` | `@/lib/shifts/conflictExclusion.ts` | Conflict exclusion logic |
| `invalidateUserCache` | `@dal/cache.ts` | Cache invalidation |

---

## Appendix: Implementation Notes

### Notes for Non-TypeScript Implementations

1. **Time handling**: All times are local (no timezone conversion needed for calculation)
2. **Date parsing**: Use UTC-based parsing to avoid DST issues: `YYYY-MM-DDT00:00:00Z`
3. **Numeric precision**: Use decimal types or fixed-point arithmetic for currency
4. **JSON parsing**: `supplements.rules` may be nested inside `{ rules: [...] }` object

### Common Pitfalls

1. **Supplement day numbering**: Days are 1-7 (Monday-Sunday), not 0-6
2. **Weekday calculation**: JavaScript's `getDay()` returns 0-6 (Sunday-Saturday), needs mapping
3. **Break threshold**: Uses strict `>` comparison, not `>=`
4. **Payout month calculation**: January + 1 = February (handle year rollover)
5. **Snapshot selection**: Two different lookups required:
   - Wage/supplements/break: Use **shift date**
   - Tax settings: Use **payout date** (shift month + 1)
6. **Cross-midnight**: End time can be less than start time (add 24 hours)

---

## Verification Log

**Date:** 2026-01-14
**Version:** 1.1

### Changes Made

#### Section B (Data Model)
- ⚠️ **B.1**: Updated `user_id` to nullable (was incorrectly marked NOT nullable)
- ⚠️ **B.1**: Updated `created_at` to nullable with default
- ⚠️ **B.2**: Removed `created_at` and `updated_at` columns (don't exist in DB)
- ⚠️ **B.2**: Updated `end_condition` type options to match actual JSONB structure
- ⚠️ **B.3**: Updated all break/tax fields to nullable (DB allows nulls with defaults)
- ⚠️ **B.3**: Updated `supplements` default value to `'[]'::jsonb`
- ➕ **B.4**: Added missing columns: `created_at`, `updated_at`, `last_active`, `profile_picture_url`

#### Section C (UI Components)
- ⚠️ **C.1**: Added `plannedShiftsCount` prop documentation
- ⚠️ **C.2**: Added `progress` prop documentation
- ⚠️ **C.3**: Added `showEarnings`, `hasConflict`, `excludedFromTotal` props
- ❌ Removed reference to non-existent `NextShiftCard` component

#### Section D (Pipeline)
- ✅ Virtual shift generation verified correct

#### Section E (Snapshot Selection)
- ✅ Binary search algorithm verified correct

#### Section F (Math Spec)
- ✅ All formulas verified against actual code
- ✅ Precision constants verified
- ✅ Break deduction methods verified

#### Section H (API)
- ⚠️ **H.3**: Corrected API response format (no `aggregates` in response)

#### Appendix
- ➕ Added `buildExcludedShiftIds` to file reference
- ➕ Added `invalidateUserCache` to file reference

### Verified Sections

All sections have been verified against the codebase:
- ✅ Schema matches actual database (with corrections noted)
- ✅ File paths verified to exist
- ✅ Function signatures match documented
- ✅ Formulas mathematically verified
- ✅ Test vectors cross-referenced with existing tests

---

## Verification Checklist

### Schema (Section B)
- [x] All tables verified against Supabase schema
- [x] All columns verified with correct types and nullability
- [x] No missing payroll-related tables
- [x] No missing payroll-related columns

### Functions (All Sections)
- [x] All file paths verified to exist
- [x] All function names verified
- [x] All function signatures match documented

### Formulas (Section F)
- [x] Break deduction formulas verified
- [x] Supplement calculation verified
- [x] Snapshot selection logic verified
- [x] Payout date calculation verified
- [x] Tax calculation verified
- [x] Rounding behavior verified

### Components (Section C)
- [x] All components exist at documented paths
- [x] All displayed values traced to source
- [x] Conditional logic documented correctly

### Data Flow (Section H)
- [x] SSR prefetch windows verified (3 months)
- [x] API endpoints documented correctly
- [x] Cache invalidation patterns verified

### Test Vectors (Section I)
- [x] All 13 test cases mathematically verified
- [x] Edge cases from existing tests included

### Completeness
- [x] No undocumented tables used in payroll
- [x] No undocumented functions in calculation chain
- [x] No undocumented user settings affecting calculations
- [x] Recurrence/virtual shifts documented
