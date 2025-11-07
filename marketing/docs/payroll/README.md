# Payroll Calculation System

This document describes Tidex's payroll calculation system, which provides accurate wage calculations with historical accuracy, supplement rules, and flexible break deduction policies.

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Wage Snapshot System](#wage-snapshot-system)
- [Calculation Flow](#calculation-flow)
- [Supplement Rules](#supplement-rules)
- [Break Deduction System](#break-deduction-system)
- [Precision & Accuracy](#precision--accuracy)
- [Usage Examples](#usage-examples)
- [API Reference](#api-reference)

## Overview

The payroll system is built as a **pure, deterministic calculation engine** that computes wages for work shifts. All calculations happen server-side in the Data Access Layer, ensuring consistency and preventing client-side manipulation.

### Core Principles

1. **Pure functions**: All payroll logic is deterministic with no side effects
2. **Zero I/O**: Calculations never access the database or system clock
3. **Historical accuracy**: Wage snapshots preserve wage rates at the time shifts were worked
4. **Server-side only**: Computations happen once during data fetch, clients receive precomputed results
5. **High precision**: 3 decimal places for hours, 2 for currency

## Key Features

- ✅ **Tariff-based wages**: Support for Norwegian tariff levels (-2, -1, 1-6) with preset rates
- ✅ **Custom wages**: Users can set their own hourly rates
- ✅ **Time-based supplements**: Automatic evening, night, weekend, and holiday supplements
- ✅ **Flexible break deductions**: Multiple strategies (proportional, base-only, end-of-shift)
- ✅ **Cross-midnight shifts**: Handles shifts spanning midnight correctly
- ✅ **Historical accuracy**: Wage snapshots ensure past shifts remain accurate after wage changes
- ✅ **Mid-month wage changes**: Users can record wage changes at any date
- ✅ **Series shift support**: Ghost shifts from recurring series use appropriate snapshots

## Architecture

### Component Structure

```
lib/payroll/
├── calc.ts           # Main computation engine (computeShift)
├── periods.ts        # Wage period splitting and supplement application
├── breaks.ts         # Break deduction policies
├── presets.ts        # Norwegian tariff rules and supplement definitions
├── snapshot.ts       # Snapshot preparation utilities
└── types.ts          # TypeScript type definitions

data-access/
├── wage-snapshots.ts # Wage snapshot queries (CRUD operations)
└── shifts.ts         # Shift queries with payroll computations
```

### Data Flow

```
User creates shift
    ↓
Server action captures current wage settings → Creates wage snapshot
    ↓
Shift stored in database with snapshot reference
    ↓
Data Access Layer fetches shift + resolves snapshot
    ↓
Payroll engine computes wages (computeShift)
    ↓
Client receives fully computed shift data
```

## Wage Snapshot System

Wage snapshots solve the problem of maintaining accurate historical payroll data when wage rates change over time.

### Concept

Instead of storing wage data per shift (wasteful) or only storing current wage settings (inaccurate for past shifts), we use **time-based wage snapshots**:

- **Baseline snapshot**: One snapshot with `from_date = NULL` that serves as the default
- **Dated snapshots**: Additional snapshots marking when wage changes occurred (e.g., "2025-03-01")
- **Automatic resolution**: For any shift, find the most recent snapshot where `from_date <= shift_date`

### Snapshot Contents

Each snapshot captures:

```typescript
{
  id: string;
  user_id: string;
  from_date: string | null;      // NULL for baseline, ISO date otherwise
  hourly_wage: number;            // Resolved base rate (NOK/hour)
  wage_level: number | null;      // NULL = custom, -2 to 6 = tariff level
  supplements: {                   // Supplement rules active at this time
    rules: SupplementRule[]
  };
  created_at: string;
}
```

### Database Schema

```sql
create table wage_snapshots (
  id uuid primary key,
  user_id uuid references auth.users(id),
  from_date date,                  -- NULL for baseline
  hourly_wage numeric(10,2),
  wage_level integer,
  supplements jsonb,

  -- Constraints
  unique index on (user_id) where from_date is null,  -- One baseline per user
  unique index on (user_id, from_date) where from_date is not null
);
```

### Resolution Algorithm

```typescript
function getSnapshotForDate(shiftDate: string): WageSnapshot | null {
  const snapshots = getUserWageSnapshots(); // Ordered by from_date DESC

  // 1. Find most recent dated snapshot where from_date <= shiftDate
  const dated = snapshots.find(s => s.from_date !== null && s.from_date <= shiftDate);
  if (dated) return dated;

  // 2. Fall back to baseline snapshot (from_date = NULL)
  return snapshots.find(s => s.from_date === null) ?? null;
}
```

### Benefits

- **Minimal storage**: Only store when wages change
- **Historical accuracy**: Past shifts remain correct even after wage changes
- **Mid-month changes**: Users can record raises that take effect on specific dates
- **Retroactive corrections**: Users can add snapshots to fix historical data
- **Works with series**: Recurring shifts automatically use the correct snapshot for their date

## Calculation Flow

### Entry Point

The main computation function is `computeShift()`:

```typescript
function computeShift(
  shift: ShiftRow,
  settings: UserSettings,
  presetRules: SupplementRule[],
  snapshot: WageSnapshot | null = null
): ShiftComputed
```

### Step-by-Step Process

1. **Resolve base wage rate**
   - Priority 1: Use snapshot's hourly_wage (recommended)
   - Priority 2: Use shift's hourly_wage_snapshot (backward compatibility)
   - Priority 3: Fall back to PRESET_WAGE_RATES["1"] (safety net)

2. **Resolve supplement rules**
   - Priority 1: Use snapshot's supplements.rules (recommended)
   - Priority 2: Use shift's supplement_rules_snapshot (backward compatibility)
   - Priority 3: Fall back to preset rules (safety net)

3. **Build wage periods** (`buildWagePeriods`)
   - Split shift into time segments based on supplement boundaries
   - Apply highest matching supplement to each period
   - Handle cross-midnight shifts (add 24h to end time if end <= start)

4. **Apply break deduction** (`applyBreakDeduction`)
   - Check if shift duration exceeds threshold (e.g., 5.5 hours)
   - Apply deduction using selected method (proportional, base_only, end_of_shift)
   - Preserve original periods for display purposes

5. **Calculate pay**
   - For each wage period: hours × (baseRate + supplementRate)
   - Round to 3 decimals for hours, 2 decimals for currency
   - Sum to get total basePay, supplementPay, and gross

6. **Return computed data**
   ```typescript
   {
     id: string;
     durationHours: number;           // Before break deduction
     paidHours: number;               // After break deduction
     basePay: number;                 // Base wage (NOK)
     supplementPay: number;           // Supplement total (NOK)
     gross: number;                   // Total pay (NOK)
     wagePeriods: WagePeriod[];       // After break (for payroll)
     originalWagePeriods: WagePeriod[]; // Before break (for display)
     breakAudit: BreakAudit;          // Audit trail
   }
   ```

## Supplement Rules

Supplements are time-based bonuses applied to specific hours.

### Rule Structure

```typescript
type SupplementRule = {
  days: number[];      // 1-7 (Mon-Sun)
  from: "HH:mm";       // Start time (inclusive)
  to: "HH:mm";         // End time (inclusive)
  rate?: number;       // Fixed NOK/hour (e.g., 22, 45, 110)
  percent?: number;    // Percentage of base (e.g., 50 for 50%)
};
```

### Resolution Priority

1. **Fixed rate** (`rate`): Used if present (common in Norway)
2. **Percentage** (`percent`): Used if rate is not specified
3. **Zero**: If neither is specified

### Preset Tariff Rules

The app includes Norwegian tariff-based supplements:

```typescript
const PRESET_SUPPLEMENT_RULES = [
  // Weekday evenings
  { days: [1,2,3,4,5], from: "18:00", to: "21:00", rate: 22 },   // +22 NOK
  { days: [1,2,3,4,5], from: "21:00", to: "23:59", rate: 45 },   // +45 NOK

  // Saturdays
  { days: [6], from: "13:00", to: "15:00", rate: 45 },            // +45 NOK
  { days: [6], from: "15:00", to: "18:00", rate: 55 },            // +55 NOK
  { days: [6], from: "18:00", to: "23:59", rate: 110 },           // +110 NOK

  // Sundays (all day)
  { days: [7], from: "00:00", to: "23:59", rate: 115 },           // +115 NOK
];
```

### Supplement Application Logic

- **Overlapping rules**: Highest supplement wins for each time period
- **Cross-midnight rules**: Rules like `{ from: "22:00", to: "06:00" }` work correctly
- **Minute-level precision**: Supplements apply to exact minute boundaries

### Example Calculation

Shift: Monday 17:00-22:00 @ 185 NOK/hour

```
Period         Base    Supplement  Total    Hours   Pay
─────────────────────────────────────────────────────────
17:00-18:00    185     0           185      1.00    185.00
18:00-21:00    185     22          207      3.00    621.00
21:00-22:00    185     45          230      1.00    230.00
─────────────────────────────────────────────────────────
TOTAL                                       5.00    1036.00
```

## Break Deduction System

Automatic break deductions are policy-based (no manual per-shift pauses).

### Configuration

```typescript
type UserSettings = {
  pause_deduction_enabled: boolean;    // Master switch
  pause_deduction_method: BreakMethod; // How to deduct
  pause_threshold_hours: number;       // Minimum shift duration
  pause_deduction_minutes: number;     // Amount to deduct
};
```

### Deduction Methods

#### 1. Proportional (Default)

Deducts proportionally across all wage periods based on their duration.

**Formula**: `deduction_for_period = (period_duration / total_duration) × total_deduction`

**Example**: 5-hour shift with 30-min break
- Period A (2h): Deduct 12 minutes (40% of break)
- Period B (3h): Deduct 18 minutes (60% of break)

**Use case**: Fair distribution across all work periods

#### 2. Base Only

Deducts from periods with lowest supplements first.

**Algorithm**:
1. Sort periods by supplement rate (ascending)
2. Remove time from lowest-supplement periods first
3. If period is fully consumed, move to next

**Example**: 6-hour shift (3h base @ 185, 2h @ +22, 1h @ +45), 30-min break
1. Deduct 30 min from base period (3h → 2.5h)
2. Supplemented periods untouched

**Use case**: Minimize deduction from high-earning periods

#### 3. End of Shift

Removes break time from the end of the shift.

**Algorithm**: Subtract minutes from the last wage period, moving backward if needed.

**Example**: 5-hour shift ending at 22:00, 30-min break
- Shift effectively ends at 21:30
- Last 30 minutes unpaid

**Use case**: Simulates taking a break at the end

#### 4. None

No automatic deduction. Break time is paid.

### Threshold Logic

```typescript
if (totalHours > thresholdHours) {
  applyBreakDeduction(deductionMinutes);
}
```

**Example**: Threshold = 5.5 hours, Deduction = 30 min
- 5-hour shift: No break applied (under threshold)
- 6-hour shift: 30-minute break applied

### Audit Trail

Every break deduction produces an audit object:

```typescript
type BreakAudit = {
  method: BreakMethod;
  thresholdHours: number;
  deductedHours: number;     // Actual deduction applied (0 if under threshold)
  notes?: string[];          // Human-readable explanation
};
```

## Precision & Accuracy

### Rounding Strategy

```typescript
const HOUR_DECIMAL_PRECISION = 1000;  // 3 decimal places (0.001h = ~3.6s)
const CURRENCY_PRECISION = 100;       // 2 decimal places (cents)
```

### Calculation Steps

1. **Period hours**: Round to 3 decimals
   ```typescript
   hours = Math.round((minutes / 60) * 1000) / 1000
   ```

2. **Period pay**: Round to 2 decimals
   ```typescript
   pay = Math.round(hours × rate × 100) / 100
   ```

3. **Total pay**: Sum rounded period amounts, then round final total
   ```typescript
   gross = +(basePay + supplementPay).toFixed(2)
   ```

### Why High Precision?

- **Avoid compounding errors**: Small rounding errors accumulate over many shifts
- **Tax accuracy**: Payroll taxes require accurate totals
- **User trust**: Transparent, reproducible calculations

## Usage Examples

### Example 1: Basic Shift Computation

```typescript
import { computeShift } from '@/lib/payroll/calc';
import { PRESET_SUPPLEMENT_RULES } from '@/lib/payroll/presets';

const shift = {
  id: '123',
  user_id: 'user-456',
  shift_date: '2025-01-15',
  start_time: '09:00',
  end_time: '17:00',
};

const settings = {
  pause_deduction_enabled: true,
  pause_deduction_method: 'proportional',
  pause_threshold_hours: 5.5,
  pause_deduction_minutes: 30,
};

const snapshot = {
  hourly_wage: 185.38,
  supplements: { rules: PRESET_SUPPLEMENT_RULES },
};

const result = computeShift(shift, settings, PRESET_SUPPLEMENT_RULES, snapshot);

console.log(result);
// {
//   id: '123',
//   durationHours: 8.00,
//   paidHours: 7.50,        // 8h - 0.5h break
//   basePay: 1390.35,
//   supplementPay: 0,       // No supplements during 09:00-17:00
//   gross: 1390.35,
//   wagePeriods: [...],
//   originalWagePeriods: [...],
//   breakAudit: { ... }
// }
```

### Example 2: Evening Shift with Supplements

```typescript
const shift = {
  id: '124',
  shift_date: '2025-01-15',  // Wednesday
  start_time: '17:00',
  end_time: '23:00',
};

const snapshot = {
  hourly_wage: 185.00,
  supplements: { rules: PRESET_SUPPLEMENT_RULES },
};

const result = computeShift(shift, settings, PRESET_SUPPLEMENT_RULES, snapshot);

// Breakdown:
// 17:00-18:00: 1h × 185 = 185.00
// 18:00-21:00: 3h × (185 + 22) = 621.00
// 21:00-23:00: 2h × (185 + 45) = 460.00
// Total (before break): 1266.00
// Break (30 min proportional): ~18 NOK deducted
// Gross: ~1248.00
```

### Example 3: Cross-Midnight Shift

```typescript
const shift = {
  id: '125',
  shift_date: '2025-01-18',  // Saturday
  start_time: '22:00',
  end_time: '06:00',         // Next day (Sunday)
};

const snapshot = {
  hourly_wage: 185.00,
  supplements: { rules: PRESET_SUPPLEMENT_RULES },
};

const result = computeShift(shift, settings, PRESET_SUPPLEMENT_RULES, snapshot);

// The system correctly treats this as:
// 22:00-23:59 (Saturday): High Saturday evening supplement (+110)
// 00:00-06:00 (Sunday): Full Sunday supplement (+115)
```

### Example 4: Batch Shift Loading with Snapshots

```typescript
import { getComputedShifts } from '@/data-access/shifts';

// In a Server Component or Server Action
const data = await getComputedShifts({
  startDate: '2025-01-01',
  endDate: '2025-01-31',
});

// Returns fully computed shifts with snapshots automatically resolved
data.shifts.forEach(shift => {
  console.log(`${shift.shift_date}: ${shift.computed.gross} NOK`);
});
```

## API Reference

### Core Functions

#### `computeShift()`

Main payroll computation function.

```typescript
function computeShift(
  shift: ShiftRow,
  settings: UserSettings,
  presetRules: SupplementRule[],
  snapshot: WageSnapshot | null = null
): ShiftComputed
```

**Parameters:**
- `shift`: Shift data (date, times, user_id)
- `settings`: User's break deduction preferences
- `presetRules`: Fallback supplement rules if snapshot not available
- `snapshot`: Wage snapshot for historical accuracy (recommended)

**Returns:** Complete computed payroll data including hours, pay breakdown, and audit trail

#### `buildWagePeriods()`

Splits shift into wage periods based on supplement boundaries.

```typescript
function buildWagePeriods(
  startHHMM: string,
  endHHMM: string,
  weekday: number,
  baseRate: number,
  rules: SupplementRule[]
): WagePeriod[]
```

#### `applyBreakDeduction()`

Applies break deduction policy to wage periods.

```typescript
function applyBreakDeduction(
  periods: WagePeriod[],
  method: BreakMethod,
  thresholdHours: number,
  deductionHours: number
): { periods: WagePeriod[]; audit: BreakAudit }
```

### Data Access Layer

#### `getComputedShifts()`

Fetches shifts with payroll computations (cached).

```typescript
async function getComputedShifts(options?: {
  startDate?: string;
  endDate?: string;
  limit?: number;
}): Promise<{
  shifts: ShiftWithComputations[];
  defaultView: string;
  settings: UserSettings;
  aggregates: ShiftsAggregates;
}>
```

#### `getUserWageSnapshots()`

Gets all wage snapshots for authenticated user (cached).

```typescript
async function getUserWageSnapshots(): Promise<WageSnapshot[]>
```

#### `getSnapshotForDate()`

Resolves the applicable snapshot for a specific shift date.

```typescript
async function getSnapshotForDate(shiftDate: string): Promise<WageSnapshot | null>
```

#### `getSnapshotsForDates()`

Batch version for multiple shift dates (optimized).

```typescript
async function getSnapshotsForDates(
  shiftDates: string[]
): Promise<Map<string, WageSnapshot>>
```

### Type Definitions

#### `ShiftRow`

```typescript
type ShiftRow = {
  id: string;
  user_id: string;
  shift_date: string;        // ISO date (YYYY-MM-DD)
  start_time: string;        // HH:mm
  end_time: string;          // HH:mm
  series_id?: string;        // For recurring shifts
};
```

#### `ShiftComputed`

```typescript
type ShiftComputed = {
  id: string;
  durationHours: number;           // Before break
  paidHours: number;               // After break
  basePay: number;                 // NOK
  supplementPay: number;           // NOK
  gross: number;                   // Total NOK
  wagePeriods: WagePeriod[];       // After break
  originalWagePeriods: WagePeriod[]; // Before break
  breakAudit: BreakAudit;
};
```

#### `WagePeriod`

```typescript
type WagePeriod = {
  fromMin: number;           // Minutes from midnight
  toMin: number;             // Minutes from midnight (exclusive)
  baseRate: number;          // NOK/hour
  supplementRate: number;    // NOK/hour
  totalRate: number;         // baseRate + supplementRate
};
```

#### `BreakAudit`

```typescript
type BreakAudit = {
  method: BreakMethod;
  thresholdHours: number;
  deductedHours: number;
  notes?: string[];
};
```

#### `WageSnapshot`

```typescript
type WageSnapshot = {
  id: string;
  user_id: string;
  from_date: string | null;  // NULL for baseline
  hourly_wage: number;       // NOK/hour
  wage_level: number | null; // NULL = custom, -2 to 6 = tariff
  supplements: {
    rules: SupplementRule[];
  };
  created_at?: string;
};
```

## Constants

### Preset Wage Rates

Norwegian tariff levels (as of 2025):

```typescript
const PRESET_WAGE_RATES = {
  "-2": 132.90,  // Under 16 years
  "-1": 129.91,  // 16 years
  "1": 184.54,   // Level 1
  "2": 185.38,   // Level 2
  "3": 187.46,   // Level 3
  "4": 193.05,   // Level 4
  "5": 210.81,   // Level 5
  "6": 256.14,   // Level 6
};
```

---

**Last Updated**: 2025-01-07
**Version**: 2.0 (Wage Snapshots)
