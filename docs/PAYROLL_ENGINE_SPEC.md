# Tidex Payroll Engine Specification

> **Version:** 3.4
> **Last Updated:** 2026-09-11
> **Source of Truth:** Shared payroll logic in the Tidex monorepo (`ios` and `supabase/functions/_shared/wagey`)
> **Purpose:** Enable re-implementation in any language (Swift, Kotlin, Go, etc.) with identical results

---

## A) Overview

The Tidex payroll engine computes wage earnings for work shifts. It takes shift data (date, start/end time) and wage settings (hourly rate, supplements, tax, break deductions) to produce deterministic earnings values.

### Inputs
- **Shift data**: `shift_date` (ISO), `start_time` (HH:MM), `end_time` (HH:MM), optional `note`, optional custom pause windows, optional custom supplements, `job_id`
- **Wage snapshot**: Hourly wage, supplement rules, tax settings, break deduction settings, `tariff_type_id`, `job_id`
- **Job**: Name, color, immutable `currency`, `payroll_day`, `half_tax_month`, `monthly_goal` (now the primary source; user settings mirrored for legacy clients)
- **Payroll adjustments**: Manual payout-level bonuses, retro pay, corrections, and other additions with payout date, job scope, amount, currency, and tax treatment
- **User settings**: Global preferences; `payroll_day`/`half_tax_month`/`monthly_goal` kept as fallback during compatibility window

### Outputs
- `durationHours`: Raw duration before break deduction
- `paidHours`: Duration after break deduction
- `basePay`: Earnings from base hourly rate (job currency)
- `supplementPay`: Earnings from supplement overlays (job currency)
- `gross`: Total before tax (`basePay + supplementPay`)
- `wagePeriods`: Post-deduction paid periods
- `originalWagePeriods`: Periods before break or pause deduction
- `breakAudit`: Deduction method, source, deducted hours, applied pause windows, and notes
- Downstream totals: `taxAmount`, `net`, completed gross/net, projection values, and payroll adjustment gross/net totals

### Key Invariants
1. **Deterministic**: Same inputs always produce same outputs
2. **Pure computation**: Zero I/O, all inputs explicit
3. **Cross-midnight support**: Shifts spanning midnight are calculated as continuous time
4. **Dual-date snapshot logic**: Wage/supplements/breaks use shift date; tax uses payout date
5. **Precision**: Exact minute-based hours; round each shift pay component once to 2 decimal places
6. **Job-scoped snapshots**: Each shift is matched to wage snapshots that belong to the same job; legacy (job-less) snapshots serve as fallback
7. **Job-scoped payroll day**: `payroll_day` is resolved from the shift's job first, then the default job, then `user_settings.payroll_day`

### Definitions

| Term | Definition |
|------|------------|
| **Shift** | A stored work period with date, start time, end time |
| **Virtual shift** | A computed occurrence from a recurring shift template (not persisted) |
| **Wage snapshot** | Point-in-time capture of wage, supplement, tax, and break settings — now scoped to a job |
| **Baseline snapshot** | Snapshot with `from_date = NULL`, serves as fallback within its job bucket |
| **Supplement window** | Time-of-day range when a supplement rate applies |
| **Pause window** | Exact unpaid interval clipped from wage periods before pay is calculated |
| **Payout date** | Date when wages are paid (typically month after work + payroll day) |
| **Payroll period** | The calendar month whose earnings are grouped for a payout |
| **Month grouping** | Shifts worked in month M are paid in month M+1 |
| **Payroll adjustment** | Manual payout-level bonus, retro pay, correction, or other non-shift amount included in payout totals |
| **Job** | An employer/workplace entity that groups shifts and wage snapshots; owns `payroll_day`, `half_tax_month`, `monthly_goal` |
| **Default job** | Each user has exactly one active default job; shifts without an explicit `job_id` are assigned here |
| **Legacy snapshot** | A local or historical `wage_snapshot` with `job_id = NULL`; used only as rollout fallback, primarily for the default job |

### Entry Points

**iOS month orchestration (active app):**
```swift
PayrollEngine.computeShiftsForMonth(request)
// ios/TidexApp/Services/Payroll/PayrollEngine.swift
```

**iOS per-shift calculator (active app):**
```swift
PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
// ios/TidexApp/Services/Payroll/PayrollCalculator.swift
```

**Shared TypeScript calculator (Wagey / server-side tools):**
```typescript
computeShift(shift, settings, presetRules, snapshot, job?)
// supabase/functions/_shared/wagey/payroll/calc.ts
```

The TypeScript `settings` and `job` parameters are compatibility arguments for older call sites. Payroll day, payout date, and tax snapshot selection are resolved upstream by the iOS `PayrollEngine` and by `supabase/functions/_shared/wagey/data.ts`.

---

## B) Data Model and Schema Mapping

### B.1 `user_shifts` — Core Shift Data

| Column | Type | Nullable | Purpose |
|--------|------|----------|---------|
| `id` | `uuid` | No | Primary key, unique shift identifier |
| `user_id` | `uuid` | Yes | Foreign key to `auth.users` |
| `job_id` | `uuid` | No | Foreign key to `public.jobs` (NOT NULL; assigned by DB trigger when client omits it) |
| `shift_date` | `date` | No | The date of the shift (ISO: `YYYY-MM-DD`) |
| `start_time` | `text` | No | Start time in `HH:MM` format |
| `end_time` | `text` | No | End time in `HH:MM` format (supports cross-midnight) |
| `note` | `text` | Yes | Private owner-only shift note; omitted from shared payloads |
| `custom_pause_windows` | `jsonb` | Yes | Exact per-shift pause windows: `{ windows: [{ start, end }] }` |
| `custom_supplements` | `jsonb` | Yes | Shift-specific supplement overrides |
| `created_at` | `timestamptz` | Yes | Creation timestamp (default: `now()`) |
| `updated_at` | `timestamptz` | Yes | Sync timestamp |
| `revision` | `bigint` | No | Local-first sync revision |
| `deleted_at` | `timestamptz` | Yes | Soft-delete marker |

**Behavior notes:**
- When `end_time <= start_time`, shift crosses midnight (e.g., 22:00 to 06:00)
- `custom_pause_windows` is normalized before persistence; empty or fully invalid payloads become `NULL`
- `custom_supplements` when present completely replaces snapshot supplements for this shift
- Legacy clients that do not send `job_id` are automatically assigned the user's default job by a DB trigger

### B.2 `recurring_shifts` — Recurring Shift Templates

| Column | Type | Nullable | Purpose |
|--------|------|----------|---------|
| `id` | `uuid` | No | Primary key |
| `user_id` | `uuid` | No | Foreign key to `auth.users` |
| `job_id` | `uuid` | No | Foreign key to `public.jobs` (NOT NULL; all generated virtual shifts inherit this job) |
| `start_time` | `timetz` | No | Shift start time with timezone |
| `end_time` | `timetz` | No | Shift end time with timezone |
| `repeat_interval_weeks` | `smallint` | No | 0 = every week, 1 = every 2 weeks, ..., 8 = every 9 weeks |
| `selected_days` | `jsonb` | No | Anchor dates by weekday: `{ "1": "2025-01-27" }` |
| `end_condition` | `jsonb` | Yes | End rule: `{ type: "never" }`, `{ type: "months", value: N }`, `{ type: "years", value: N }`, `{ type: "end_date", date: "YYYY-MM-DD" }` |
| `exclusions` | `jsonb` | Yes | Array of ISO dates to skip |
| `date_specific_pause_windows` | `jsonb` | Yes | Per-date pause overrides: `{ "2025-01-15": { windows: [...] } }` |
| `date_specific_supplements` | `jsonb` | Yes | Per-date custom supplements: `{ "2025-01-15": { rules: [...] } }` |
| `date_specific_notes` | `jsonb` | Yes | Per-date private notes keyed by ISO date |
| `updated_at` | `timestamptz` | Yes | Sync timestamp |
| `revision` | `bigint` | No | Local-first sync revision |
| `deleted_at` | `timestamptz` | Yes | Soft-delete marker |

**Behavior notes:**
- Virtual shifts are generated at runtime, never persisted
- `selected_days` keys are weekday numbers (0=Sunday to 6=Saturday)
- Values are anchor ISO dates from which recurrence starts
- A recurring pattern and all its generated virtual shifts belong to one job; there is no per-occurrence job override
- Generated virtual shifts inherit date-specific pause windows, supplements, and notes for their occurrence date

### B.3 `wage_snapshots` — Point-in-Time Wage Settings

| Column | Type | Nullable | Default | Purpose |
|--------|------|----------|---------|---------|
| `id` | `uuid` | No | - | Primary key |
| `user_id` | `uuid` | No | - | Foreign key to `auth.users` |
| `job_id` | `uuid` | No | - | Foreign key to `public.jobs` (NOT NULL; controls which job's wage history is used) |
| `from_date` | `date` | Yes | - | Effective date (`NULL` = baseline snapshot for this job) |
| `hourly_wage` | `numeric` | No | - | Base hourly wage in the job currency |
| `wage_level` | `integer` | Yes | - | Tariff level (1-9) or `NULL` for custom wage |
| `tariff_type_id` | `text` | Yes | - | Tariff type identifier such as `hk_retail`, or `NULL` for custom wage |
| `supplements` | `jsonb` | No | `{ "rules": [] }` | Object containing an array of `SupplementRule` objects |
| `tax_enabled` | `boolean` | Yes | `false` | Whether tax deduction is enabled |
| `tax_percentage` | `numeric` | Yes | `0` | Tax percentage (0-100) |
| `break_enabled` | `boolean` | Yes | `true` | Whether break deduction is enabled |
| `break_method` | `text` | Yes | `'proportional'` | One of: `proportional`, `base_only`, `end_of_shift`, `none` |
| `break_threshold_hours` | `numeric` | Yes | `5.5` | Hours before break applies |
| `break_deduction_minutes` | `integer` | Yes | `30` | Break duration in minutes |
| `created_at` | `timestamptz` | Yes | - | Creation timestamp |
| `updated_at` | `timestamptz` | Yes | - | Sync timestamp |
| `revision` | `bigint` | No | `1` | Local-first sync revision |
| `deleted_at` | `timestamptz` | Yes | `NULL` | Soft-delete marker |

**Unique constraints (updated for multi-job):**
- `UNIQUE (user_id, job_id) WHERE from_date IS NULL AND deleted_at IS NULL` — one baseline per (user, job)
- `UNIQUE (user_id, job_id, from_date) WHERE from_date IS NOT NULL AND deleted_at IS NULL` — one snapshot per (user, job, date)

**Behavior notes:**
- Snapshots are **job-scoped**: each bucket belongs to a specific `job_id`
- Only one baseline snapshot (`from_date = NULL`) allowed per (user, job) pair
- The live database backfilled snapshots to non-null `job_id`; `job_id = NULL` remains supported only as a rollout/local compatibility fallback
- **Snapshot selection uses TWO different dates:**
  - **Wage, supplements, break settings**: Selected based on **shift date** (the date the shift is worked)
  - **Tax settings only**: Selected based on **payout date** (shift month + 1, on job's payroll day)
- For a target date D inside a selected snapshot scope: choose the latest snapshot where `from_date <= D`; if none exists, use that scope's `from_date = NULL` baseline
- The active iOS payroll engine first chooses a scope: explicit job bucket when present → default-job bucket when present → legacy nil-job rows → all loaded snapshots. Once a non-empty scope is chosen, no later fallback bucket is searched for that target date.
- The shared Wagey TypeScript resolver remains bucket based for server-side tools: job-specific dated → legacy dated → job-specific baseline → legacy baseline → any baseline
- In the iOS local repository, nil-job snapshots are only included for the selected default job; non-default job reads do not borrow legacy nil-job snapshots
- The app expects `supplements` to decode as `{ rules: [...] }`

### B.4 `user_settings` — User Preferences

| Column | Type | Nullable | Default | Purpose |
|--------|------|----------|---------|---------|
| `user_id` | `uuid` | No | - | Primary key, FK to `auth.users` |
| `payroll_day` | `integer` | Yes | `15` | Day of month (1-31) when payroll is received |
| `half_tax_month` | `integer` | Yes | - | Month (11 or 12) for half-tax; `NULL` = disabled |
| `monthly_goal` | `integer` | Yes | `20000` | Monthly earnings goal in the active/default job currency |
| `monthly_goals_by_month` | `jsonb` | No | `{}` | Sparse `YYYY-MM` monthly goal overrides |
| `default_shifts_view` | `varchar(10)` | Yes | `'calendar'` | UI preference: `list` or `calendar` |
| `show_dashboard_clock_buttons` | `boolean` | No | `true` | Whether dashboard clock controls are visible |
| `default_startup_tab` | `text` | No | `'home'` | App tab opened at launch |
| `ai_data_sharing_enabled` | `boolean` | Yes | `NULL` | Wagey / AI data sharing preference |
| `currency` | `text` | Yes | `'kr'` | Currency display symbol |
| `theme` | `text` | No | `'dark'` | UI theme preference (`light`, `dark`, `system`) |
| `profile_picture_url` | `text` | Yes | - | User's profile picture URL |
| `created_at` | `timestamptz` | Yes | `now()` | Creation timestamp |
| `updated_at` | `timestamptz` | No | `now()` | Last update timestamp |
| `last_active` | `timestamptz` | Yes | `now()` | Last activity timestamp |

**Behavior notes:**
- Wage settings have been moved to `wage_snapshots` (historical accuracy)
- `payroll_day`, `half_tax_month`, `monthly_goal` are now primarily owned by the `jobs` table; `user_settings` keeps mirrored copies for legacy client compatibility during the transition window
- DB triggers keep `user_settings` and the default job in sync in both directions
- `payroll_day` is used to calculate payout dates for snapshot selection; resolution order: shift job's `payroll_day` → default job's `payroll_day` → `user_settings.payroll_day` → app fallback (`1`)
- `half_tax_month` applies to payout month, not worked month

### B.4.5 `jobs` — Employer/Workplace Entities

Each user has one or more jobs. New table added in the multi-job rollout.

| Column | Type | Nullable | Default | Purpose |
|--------|------|----------|---------|---------|
| `id` | `uuid` | No | `gen_random_uuid()` | Primary key |
| `user_id` | `uuid` | No | - | Foreign key to `auth.users` (ON DELETE CASCADE) |
| `name` | `text` | No | - | Display name (1-100 chars) |
| `color` | `text` | Yes | `NULL` | Hex color string (`#RRGGBB`) or NULL |
| `is_default` | `boolean` | No | `false` | Exactly one active default per user |
| `sort_order` | `smallint` | No | `0` | Display ordering |
| `payroll_day` | `integer` | Yes | `15` | Day of month (1-31) payroll is received for this job |
| `half_tax_month` | `integer` | Yes | `NULL` | Month (11 or 12) for half-tax; `NULL` = disabled |
| `monthly_goal` | `integer` | Yes | `20000` | Monthly earnings goal for this job |
| `currency` | `text` | No | `'kr'` | Immutable display currency for this job |
| `archived_at` | `timestamptz` | Yes | `NULL` | Set when archived; hides from Add Shift pickers |
| `deleted_at` | `timestamptz` | Yes | `NULL` | Soft-delete; retained for historical data |
| `created_at` | `timestamptz` | No | `now()` | Creation timestamp |
| `updated_at` | `timestamptz` | No | `now()` | Last update timestamp (maintained by trigger) |
| `revision` | `bigint` | No | `1` | Incremented on each update (for sync) |

**Unique constraints:**
- `UNIQUE (user_id) WHERE is_default = true AND deleted_at IS NULL AND archived_at IS NULL` — one active default per user

**Behavior notes:**
- Every user gets a default job ("Jobb") created automatically on sign-up
- A default job cannot be deleted; the user must designate another job as default first
- Archived jobs (`archived_at IS NOT NULL`) remain visible in historical shift views but are excluded from Add Shift pickers
- Soft-deleted jobs (`deleted_at IS NOT NULL`) are excluded from all active queries
- `payroll_day` resolution for payout date: shift job value → default job value → `user_settings.payroll_day` → `1`
- Job `currency` is captured at job creation and used for dashboard grouping, payout variants, and mixed-currency breakdowns

### B.4.6 `payroll_adjustments` — Manual Payout Corrections

Payroll adjustments are payout-level amounts that are not tied to a single shift. They cover retro pay, bonuses, corrections, and other additions that should appear on a payroll card without changing shift hours or shift-level wage periods.

| Column | Type | Nullable | Default | Purpose |
|--------|------|----------|---------|---------|
| `id` | `uuid` | No | `gen_random_uuid()` | Primary key |
| `user_id` | `uuid` | No | - | Foreign key to `auth.users` |
| `job_id` | `uuid` | Yes | `NULL` | Optional job scope; `NULL` resolves to the default job for display and tax lookup |
| `amount` | `numeric` | No | - | Adjustment amount in the row currency |
| `currency` | `text` | No | `'kr'` | Display currency |
| `category` | `text` | No | - | One of: `retro_pay`, `bonus`, `correction`, `other` |
| `tax_treatment` | `text` | No | `gross_taxable` | One of: `gross_taxable`, `net_manual`, `excluded_from_tax_estimate` |
| `description` | `text` | No | - | Short user-visible explanation |
| `note` | `text` | Yes | `NULL` | Private user note |
| `curated_note` | `text` | Yes | `NULL` | Optional Wagey-authored CTA text |
| `curated_description` | `text` | Yes | `NULL` | Optional longer curated explanation shown after tapping the CTA |
| `curated_link` | `text` | Yes | `NULL` | Optional source link for the curated explanation |
| `curated_link_title` | `text` | Yes | `NULL` | Optional user-visible title for the curated source link |
| `earned_from_date` | `date` | Yes | `NULL` | Optional earned-period start |
| `earned_to_date` | `date` | Yes | `NULL` | Optional earned-period end |
| `payout_date` | `date` | No | - | Payroll date whose totals include this adjustment |
| `created_at` | `timestamptz` | No | `now()` | Creation timestamp |
| `updated_at` | `timestamptz` | No | `now()` | Sync timestamp |
| `revision` | `bigint` | No | `1` | Local-first sync revision |
| `deleted_at` | `timestamptz` | Yes | `NULL` | Soft-delete marker |

**Behavior notes:**
- Explicit `job_id` values must belong to the same active, non-deleted, non-archived user-owned job
- Adjustments are filtered by `payout_date`; they are not allocated back into shift periods
- `gross_taxable` adjustments use payout-date tax settings for their job and the same half-tax rule as shifts
- `net_manual` and `excluded_from_tax_estimate` contribute their amount to both gross and net totals without estimated tax

### B.5 JSONB Structure: `SupplementRule`

Used in `wage_snapshots.supplements` and `user_shifts.custom_supplements`:

```typescript
type SupplementRule = {
  days: number[];    // 1-7 (1=Monday, 7=Sunday)
  from: string;      // "HH:MM" (inclusive)
  to: string;        // "HH:MM" (exclusive)
  rate?: number;     // Fixed amount per hour in the job currency (mutually exclusive with percent)
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

From `PayrollCalculator.presetSupplementRules` and `supabase/functions/_shared/wagey/payroll/presets.ts`:

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

From `PayrollCalculator.presetWageRates` and `supabase/functions/_shared/wagey/payroll/calc.ts`:

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

## C) Active App Values Map

The active product surface is the native iOS app. The historical Next.js app components (`components/app/TotalCard.tsx`, `NextPayrollCard`, `ShiftCard`, DAL cache tags, and SSR prefetch windows) are retired and are not part of the live payroll behavior.

### C.1 Dashboard Total Card

**Location:** `ios/TidexApp/Features/Dashboard/Components/TotalCard.swift`

**Purpose:** Displays the selected month's shift-derived earnings and projection for the primary currency bucket.

| Displayed Field | Source | Formula |
|-----------------|--------|---------|
| Main amount | `DashboardData.displayTotal` / projected total | Shift totals after conflict exclusion; net when tax is enabled, otherwise gross |
| Earned to date | Completed shift totals | Completed shifts are determined by `Date.hasShiftEnded(...)` |
| Before-tax amount | Gross total | Sum of included `shift.grossPay` |
| Shift count | Dashboard month shifts | Count of included visible shifts |
| Mixed-currency indicator | `JobCurrencyAggregateResolver` | Shown when the selected month has positive gross in more than one job currency |

Monthly totals remain shift-only. Payroll adjustments are shown in payout cards and details sheets so non-shift money does not distort hours, average hourly rate, or projection math.

### C.2 Payroll Card and Details Sheet

**Locations:**
- `ios/TidexApp/Features/Dashboard/Components/PayrollCard.swift`
- `ios/TidexApp/Features/Dashboard/Components/PayrollDetailsSheet.swift`

**Purpose:** Displays a payout date, payout gross/net/tax, shift breakdown, break/pause deductions, and payroll adjustments for the payout month.

| Displayed Field | Source | Formula |
|-----------------|--------|---------|
| Payout date | Job `payroll_day` + visible payout month | `adjustPayrollDate(...)` for display/countdown only |
| Shift gross | Previous earnings month shifts | Sum of included shift `grossPay` |
| Shift net | Previous earnings month shifts | Per-shift gross less payout-date tax with half-tax applied when configured |
| Adjustment gross/net | `payroll_adjustments` by `payout_date` | `PayrollAdjustmentCalculator.totals(...)` |
| Total payout | Shift totals + adjustment totals | Gross/net shown in the job/currency variant |
| Break details | `ShiftComputed.breakAudit` | Shows automatic break or exact pause-window deductions |

### C.3 Shift Cards and Shift Details

**Representative locations:**
- `ios/TidexApp/Features/Dashboard/Components/FeaturedShiftCard.swift`
- `ios/TidexApp/Features/Shifts/`
- `ios/TidexApp/Shared/Components/EarningsBreakdownCard.swift`

| Displayed Field | Source | Formula |
|-----------------|--------|---------|
| Paid hours | `shift.computed.paidHours` | Raw duration minus exact pause windows or automatic break |
| Display amount | `ShiftWithComputations` tax settings | Net when tax is enabled, otherwise gross |
| Breakdown | `basePay`, `supplementPay`, `breakAudit` | Base + supplements, plus pre/post deduction details |
| Conflict state | `ConflictExclusion` | Higher-gross overlaps are visible but excluded from totals |

### C.4 Stats Views

**Location:** `ios/TidexApp/Features/Stats/`

| Metric | Formula |
|--------|---------|
| Total earnings | Sum of included shift gross/net for the selected range |
| Total hours | Sum of included `paidHours` |
| Average per shift | `totalEarnings / shiftCount` |
| Average hourly rate | `totalEarnings / totalHours` |
| Month-over-month % | `(current - previous) / previous * 100`, scoped to the primary currency bucket when mixed currencies exist |

---

## D) Shift Acquisition Pipeline

### D.1 Canonical Shift Object: `ShiftWithComputations`

Mirrors `ios/TidexApp/Models/*` and `supabase/functions/_shared/wagey/payroll/types.ts`:

```typescript
// ShiftRow now includes job_id
type ShiftRow = {
  id: string;
  user_id: string;
  job_id?: string | null;   // Set to default job if omitted by legacy clients
  shift_date: string;
  start_time: string;
  end_time: string;
  hourly_wage_snapshot?: number | null;
  supplement_rules_snapshot?: { rules: SupplementRule[] } | null;
  custom_pause_windows?: { windows: PauseWindow[] } | null;
  custom_supplements?: CustomSupplementsData | null;
  recurring_id?: string;
  recurring_anchor_weekday?: number;
};

// WageSnapshot now includes job_id
type WageSnapshot = {
  id: string;
  user_id: string;
  job_id?: string | null;   // NULL for legacy/migrated snapshots (fallback bucket)
  from_date: string | null;
  hourly_wage: number;
  wage_level: number | null;
  tariff_type_id: string | null;
  supplements: { rules: SupplementRule[] };
  tax_enabled: boolean;
  tax_percentage: number;
  break_enabled: boolean;
  break_method: BreakMethod;
  break_threshold_hours: number;
  break_deduction_minutes: number;
  created_at?: string;
};

// New Job type
type Job = {
  id: string;
  user_id: string;
  name: string;
  color?: string | null;
  is_default: boolean;
  sort_order: number;
  payroll_day?: number | null;
  half_tax_month?: number | null;
  monthly_goal?: number | null;
  archived_at?: string | null;
  deleted_at?: string | null;
  created_at?: string;
  updated_at?: string;
};

// ShiftData now includes jobs array
type ShiftData = {
  shifts: readonly ShiftWithComputations[];
  defaultView: string;
  settings: UserSettings;
  jobs: readonly Job[];            // All active (non-deleted) jobs for the user
  aggregates: ShiftsAggregates;
  payoutTaxSettings: PayoutTaxSettings;
  currentPayoutTaxSettings: PayoutTaxSettings;
  breakDeductionEnabled: boolean;
};

type ShiftWithComputations = ShiftRow & {
  computed: ShiftComputed;
  tax_enabled?: boolean;
  tax_percentage?: number;
};

type ShiftComputed = {
  id: string;
  durationHours: number;      // Raw duration before break
  paidHours: number;          // Duration after break deduction
  basePay: number;            // Job currency from base rate
  supplementPay: number;      // Job currency from supplements
  gross: number;              // basePay + supplementPay
  wagePeriods: WagePeriod[];  // After break deduction
  originalWagePeriods: WagePeriod[];  // Before break deduction
  breakAudit: BreakAudit;     // Deduction details
};

type WagePeriod = {
  fromMin: number;      // Minutes from midnight (shift-relative)
  toMin: number;        // Minutes from midnight (exclusive)
  baseRate: number;     // Job currency per hour
  supplementRate: number;  // Job currency per hour supplement
  totalRate: number;    // baseRate + supplementRate
};

type BreakAudit = {
  method: BreakMethod;
  thresholdHours: number;
  deductedHours: number;
  source: "none" | "automatic_break" | "custom_pause_windows";
  appliedPauseWindows?: PauseWindow[];
  notes?: string[];
};
```

### D.2 Pipeline Steps

#### Step 1: Load Stored Shifts, Recurring Shifts, Jobs, and Snapshots

The active iOS app reads payroll input from the local SwiftData repositories, then sync fills those local stores from Supabase. The shared Wagey TypeScript path performs equivalent Supabase reads for server-side tools.

```typescript
// Representative Wagey/server-side read path.
// iOS equivalent: MonthlyPayrollReadService + local repositories.
const [shifts, recurringShifts, jobs, allSnapshots] = await Promise.all([
  supabase.from("user_shifts")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .eq("job_id", jobId)    // optional — only if filtering by job
    .gte("shift_date", startDate)
    .lte("shift_date", endDate)
    .limit(limit),

  supabase.from("recurring_shifts")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .eq("job_id", jobId),   // optional

  supabase.from("jobs")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("sort_order", { ascending: true }),

  supabase.from("wage_snapshots")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("from_date", { ascending: false, nullsFirst: false }),
]);
```

**Jobs post-processing:**
```typescript
const jobsById = new Map(jobs.map(j => [j.id, j]));
const defaultJob = jobs.find(j => j.is_default && j.archived_at == null)
                ?? jobs.find(j => j.is_default)
                ?? jobs[0]
                ?? null;
```

**Payroll day resolution:**
```typescript
const payrollDayForJob = (targetJobId?: string | null): number =>
  jobsById.get(targetJobId ?? "")?.payroll_day
  ?? defaultJob?.payroll_day
  ?? userSettings?.payroll_day
  ?? 1;  // hard fallback
```

#### Step 2: Build Snapshot Buckets

Snapshots are grouped into buckets keyed by `job_id` (or `"__legacy__"` for `job_id = NULL`):

```typescript
const buildSnapshotBuckets = (snapshots: WageSnapshot[]) => {
  const map = new Map<string, { dated: WageSnapshot[]; baseline: WageSnapshot | null }>();

  for (const snapshot of snapshots) {
    const key = snapshot.job_id ?? "__legacy__";
    const bucket = map.get(key) ?? { dated: [], baseline: null };

    if (snapshot.from_date === null) {
      bucket.baseline = snapshot;
    } else {
      bucket.dated.push(snapshot);
    }
    map.set(key, bucket);
  }

  for (const bucket of map.values()) {
    bucket.dated.sort((a, b) => b.from_date.localeCompare(a.from_date));
  }

  return map;
};
```

**Shared Wagey TypeScript snapshot resolution with job-scoped fallback chain:**
```typescript
const resolveSnapshotForDate = (buckets, snapshots, date, jobId?) => {
  const preferredKeys = [jobId ?? "__legacy__", "__legacy__"];

  // Try dated snapshots first
  for (const key of preferredKeys) {
    const dated = buckets.get(key)?.dated.find(s => s.from_date <= date);
    if (dated) return dated;
  }

  // Then baselines
  for (const key of preferredKeys) {
    const baseline = buckets.get(key)?.baseline;
    if (baseline) return baseline;
  }

  return snapshots.find(s => s.from_date === null) ?? null;
};
```

**Active iOS snapshot scope selection:**
```swift
let effectiveJobId = shift.job_id ?? defaultJobId
let scopedSnapshots = snapshotsForJob(
  jobId: effectiveJobId,
  allSnapshots: allSnapshots,
  snapshotsByJobId: snapshotsByJobId,
  legacyNilJobSnapshots: legacyNilJobSnapshots,
  defaultJobId: defaultJobId
)

let wageSnapshot = SnapshotsService.snapshotForDate(shift.shift_date, from: scopedSnapshots)
let taxSnapshot = SnapshotsService.snapshotForDate(payoutDate, from: scopedSnapshots)
```

Swift scope fallback is explicit job bucket when present, then default-job bucket when present, then legacy nil-job rows, then all loaded snapshots. `SnapshotsService.snapshotForDate` searches only the chosen scope: latest dated snapshot first, then that scope's baseline.

#### Step 3: Generate Virtual Shifts

For each recurring shift template and each month in range:

```typescript
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
   f. If all pass, add to virtual shifts, inheriting the recurring shift's `job_id`, date-specific pause windows, date-specific supplements, and date-specific notes
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

#### Step 4: Compute Stored Shifts (job-scoped snapshot lookup)

```typescript
for (const shift of shifts) {
  const shiftJobId = shift.job_id ?? defaultJobId;

  // Wage/supplement/break snapshot: use shift date, job-scoped
  const snapshot = resolveSnapshotForDate(snapshotBuckets, snapshots, shift.shift_date, shiftJobId);

  // Tax snapshot: use payout date for THIS shift's job
  const payoutDate = calculatePayoutDate(shift.shift_date, payrollDayForJob(shiftJobId));
  const taxSnapshot = resolveSnapshotForDate(snapshotBuckets, snapshots, payoutDate, shiftJobId);

  const computed = computeShift(
    shift, userSettings, PRESET_SUPPLEMENT_RULES, snapshot,
    shiftJobId ? jobsById.get(shiftJobId) ?? null : null
  );

  result.push({
    ...shift,
    job_id: shiftJobId,
    computed,
    tax_enabled: taxSnapshot?.tax_enabled ?? false,
    tax_percentage: taxSnapshot?.tax_percentage ?? 0,
  });
}
```

#### Step 5: Compute Virtual Shifts (same job-scoped logic)

Virtual shifts inherit `job_id` from their parent recurring shift template. Snapshot lookup and payroll day resolution follow identical logic to Step 4.

#### Step 6: Sort and Aggregate

```typescript
const allShifts = [...storedShifts, ...virtualShifts]
  .sort((a, b) => a.shift_date.localeCompare(b.shift_date));

const aggregates = allShifts.reduce(
  (acc, shift) => ({
    totalHours: acc.totalHours + shift.computed.paidHours,
    totalEarnings: acc.totalEarnings + shift.computed.gross,
  }),
  { totalHours: 0, totalEarnings: 0 }
);
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
- A rule's weekdays identify the days on which its window starts.
- Build windows for the previous, current and next day, including overnight rules carried from yesterday.
- Example: a Saturday 20:00-02:00 shift receives Saturday evening supplements until midnight and Sunday supplements after midnight. When windows overlap, only the highest rate applies.
- The shift-specific editor clips these windows to the occurrence before saving overrides, preserving the weekday-specific amounts.

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

Implemented in `PayrollEngine.calculatePayoutDate(...)` and `supabase/functions/_shared/wagey/data.ts`:

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

Implemented for display/countdown UX in `ios/TidexApp/Shared/Utilities/PayrollDateAdjuster.swift` and the marketing docs helper:

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

**Norwegian holidays:** Fixed and Easter-based Norwegian public holidays are excluded.
- Fixed: New Year's Day, Labour Day (May 1), Constitution Day (May 17), Christmas Day, Boxing Day
- Moveable (Easter-based): Maundy Thursday, Good Friday, Easter Sunday, Easter Monday, Ascension Day, Whit Sunday, Whit Monday

### E.3 Snapshot Selection Algorithm (Job-Scoped)

**IMPORTANT: Two different lookups are performed for each shift, both are job-scoped:**

1. **Wage/Supplement/Break Snapshot**: Looked up by **shift date** + **shift's job_id**
2. **Tax Snapshot**: Looked up by **payout date** + **shift's job_id** (payout date uses the job's payroll day)

**Active iOS scope chain for each lookup:**

```
1. Explicit shift job bucket, when that bucket has any snapshots
2. Default-job bucket, when present and the explicit job has no snapshots
3. Legacy nil-job snapshot rows
4. All loaded snapshots
5. null (calculation uses defaults)
```

Within the selected scope, `SnapshotsService.snapshotForDate` chooses the latest dated snapshot where `from_date <= targetDate`, then the scope baseline (`from_date = NULL`). It does not continue to the next fallback scope after choosing a non-empty scope.

**Shared Wagey TypeScript fallback chain:**

```
1. Job-specific bucket → dated snapshot where from_date <= targetDate
2. Legacy bucket ("__legacy__") → dated snapshot where from_date <= targetDate
3. Job-specific bucket → baseline snapshot (from_date = NULL)
4. Legacy bucket ("__legacy__") → baseline snapshot
5. Any snapshot with from_date = NULL
6. null (calculation uses defaults)
```

These chains preserve rollout compatibility for snapshots created before the multi-job backfill (`job_id = NULL`) while keeping the active iOS app job-scoped for normal local-first reads.

**Lookup algorithm** (linear scan within pre-sorted bucket, O(n) per shift):

```typescript
const resolveSnapshotForDate = (
  buckets: Map<string, SnapshotBucket>,
  snapshots: WageSnapshot[],
  date: string,
  jobId?: string | null
): WageSnapshot | null => {
  const preferredKeys = [jobId ?? "__legacy__", "__legacy__"];

  // Try dated snapshots first (bucket is sorted DESC by from_date)
  for (const key of preferredKeys) {
    const dated = buckets.get(key)?.dated.find(s => s.from_date <= date);
    if (dated) return dated;
  }

  // Then baselines
  for (const key of preferredKeys) {
    const baseline = buckets.get(key)?.baseline ?? null;
    if (baseline) return baseline;
  }

  return snapshots.find(s => s.from_date === null) ?? null;
};
```

**Selection rules:**
1. Select the job-specific snapshot scope for the runtime path (active Swift scope chain or shared TypeScript bucket chain)
2. Find the latest dated snapshot in that scope where `from_date <= targetDate`
3. If none, use that scope's baseline snapshot (`from_date = NULL`)
4. If still none after the runtime path's fallback scopes are exhausted, return null (calculation uses defaults)

**Inclusive from_date:** A snapshot with `from_date = 2025-02-01` applies to target dates >= 2025-02-01

**Example:**
- Shift on 2025-01-15, job's payroll day = 20
- Wage snapshot lookup: `targetDate = 2025-01-15`, `jobId = job-uuid` (shift date)
- Tax snapshot lookup: `targetDate = 2025-02-20` (payout date)

### E.4 Multiple Snapshots Same Date

If multiple snapshots have the same `from_date` for the same `(user_id, job_id)`, behavior is undefined in the in-memory resolver, but the database constraint prevents it. The unique index `idx_wage_snapshots_unique_date` enforces one dated snapshot per `(user_id, job_id, from_date)` and `idx_wage_snapshots_baseline` enforces one baseline per `(user_id, job_id)`.

---

## F) Pay Calculation Engine (Math Spec)

### F.1 Precision Constants

```typescript
// Keep hours unrounded throughout calculation and aggregation.
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
const durationHours = totalMinutes / 60;
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
  predefinedRules: SupplementRule[],
  customSupplements: CustomSupplementsData | null
): SupplementRule[] {
  // Custom supplements completely replace predefined rules
  if (customSupplements) {
    if (customSupplements.rules.length === 0) return []; // explicitly no supplements
    return customSupplements.rules.map(rule => ({
      ...rule,
      days: [1, 2, 3, 4, 5, 6, 7], // Shift-specific clock windows also apply after midnight
    }));
  }

  return predefinedRules;
}
```

### F.7 Wage Periods Construction

Implemented in `WagePeriodBuilder.swift` and `supabase/functions/_shared/wagey/payroll/periods.ts`:

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
  rules: SupplementRule[],
): WagePeriod[] {
  const start = toMin(startHHMM);
  let end = toMin(endHHMM);
  if (start == null || end == null) return [];
  if (end <= start) end += 24 * 60;

  const windows: { from: number; to: number; rate: number }[] = [];
  for (const rule of rules) {
    const from = toMin(rule.from);
    const to = toMin(rule.to);
    if (from == null || to == null || from === to) continue;
    // Weekdays identify the rule's start day, including overnight carry from yesterday.
    for (const dayOffset of [-1, 0, 1]) {
      const ruleWeekday = ((weekday - 1 + dayOffset + 7) % 7) + 1;
      if (!rule.days.includes(ruleWeekday)) continue;
      const windowFrom = from + dayOffset * 24 * 60;
      const windowTo = to + dayOffset * 24 * 60 + (to < from ? 24 * 60 : 0);
      if (windowTo <= start || windowFrom >= end) continue;
      windows.push({ from: windowFrom, to: windowTo, rate: resolveSupplementRate(rule, baseRate) });
    }
  }

  const points = new Set<number>([start, end]);
  for (const window of windows) {
    points.add(Math.max(start, window.from));
    points.add(Math.min(end, window.to));
  }
  const sorted = Array.from(points).sort((a, b) => a - b);
  const periods: WagePeriod[] = [];
  for (let index = 0; index < sorted.length - 1; index++) {
    const fromMin = sorted[index], toMin = sorted[index + 1];
    let supplementRate = 0;
    for (const window of windows) {
      if (fromMin >= window.from && toMin <= window.to) {
        supplementRate = Math.max(supplementRate, window.rate);
      }
    }
    periods.push({ fromMin, toMin, baseRate, supplementRate, totalRate: baseRate + supplementRate });
  }
  return periods;
}
```

### F.8 Supplement Rate Resolution

```typescript
function resolveSupplementRate(rule: SupplementRule, baseRate: number): number {
  // Fixed amount per hour in the job currency
  if (rule.rate != null && Number.isFinite(rule.rate) && rule.rate >= 0) {
    return rule.rate;
  }

  // Percentage of base rate
  if (rule.percent != null && Number.isFinite(rule.percent) && rule.percent >= 0) {
    return (baseRate * rule.percent) / 100;
  }

  return 0;
}
```

**Stacking behavior:** Highest-wins. Only the highest supplement rate applies to each time period.

### F.9 Break Deduction

Implemented in `BreakDeduction.swift` and `supabase/functions/_shared/wagey/payroll/breaks.ts`:

Exact `custom_pause_windows` take precedence over automatic break deduction. When normalized pause windows are present, the engine clips those intervals from wage periods, sets `breakAudit.source = "custom_pause_windows"`, sets `method = "none"`, and does not run `applyBreakDeduction`.

```typescript
function applyBreakDeduction(
  periods: WagePeriod[],
  method: BreakMethod,
  thresholdHours: number,
  deductionHours: number
): { periods: WagePeriod[]; audit: BreakAudit } {
  const totalMinutes = periods.reduce((s, p) => s + Math.max(0, p.toMin - p.fromMin), 0);
  const totalHours = totalMinutes / 60;
  thresholdHours = Number.isFinite(thresholdHours) ? Math.max(0, thresholdHours) : totalHours;

  // Only deduct if shift exceeds threshold
  const sanitizedDeduction = Number.isFinite(deductionHours)
    ? Math.min(Math.max(0, deductionHours), totalHours) : 0;
  const toDeduct = method !== "none" && totalHours > thresholdHours ? sanitizedDeduction : 0;

  let adjusted = periods.map(p => ({ ...p }));
  const notes: string[] = [];

  if (toDeduct > 0 && method !== "none") {
    let remaining = Math.round(toDeduct * 60);

    if (method === "end_of_shift") {
      // subtract from the tail
      for (let i = adjusted.length - 1; i >= 0 && remaining > 0; i--) {
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const cut = Math.min(span, remaining);
        adjusted[i].toMin -= cut;
        remaining -= cut;
      }
      notes.push("Deducted at end of shift");
    } else if (method === "proportional") {
      // Deduct exact proportional fractions (not rounded to minutes)
      for (let i = 0; i < adjusted.length; i++) {
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const proportion = span / totalMinutes;
        const cutMinutes = proportion * toDeduct * 60;
        adjusted[i].toMin -= cutMinutes;
      }
      notes.push("Deducted proportionally across periods");
    } else if (method === "base_only") {
      // prefer periods with lowest supplement
      const order = adjusted
        .map((p, idx) => ({ idx, supplement: p.supplementRate }))
        .sort((a, b) => a.supplement - b.supplement)
        .map(o => o.idx);
      for (const i of order) {
        if (remaining <= 0) break;
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const cut = Math.min(span, remaining);
        adjusted[i].toMin -= cut;
        remaining -= cut;
      }
      notes.push("Deducted from base/lowest supplement periods first");
    }
    // trim empty periods
    adjusted = adjusted.filter(p => p.toMin > p.fromMin);
  }

  const paidMinutes = adjusted.reduce((sum, period) => sum + Math.max(0, period.toMin - period.fromMin), 0);
  const deductedHours = Math.max(0, totalMinutes - paidMinutes) / 60;
  const audit: BreakAudit = {
    method,
    thresholdHours,
    deductedHours,
    source: deductedHours > 0 ? "automatic_break" : "none",
    notes,
  };
  return { periods: adjusted, audit };
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
  const hours = (period.toMin - period.fromMin) / 60;
  basePay += hours * period.baseRate;
  supplementPay += hours * period.supplementRate;
}

// Round once per pay component, after summing exact-minute contributions.
basePay = Math.round(basePay * 100) / 100;
supplementPay = Math.round(supplementPay * 100) / 100;
const gross = Math.round((basePay + supplementPay) * 100) / 100;
```

Break audits report the time actually removed. Disabled deductions, the `none` method and shifts at or below the threshold report zero deducted hours and `source = "none"`.

The earnings breakdown preserves explicit overtime intervals, including weekly resets at midnight. It restores only unpaid intervals at their original rates for the pre-deduction display, so an ordinary supplement replaced by overtime is never presented as a break deduction. Displayed deductions reconcile to the rounded pay components.

### F.11 Tax Calculation

Tax is applied downstream in `PayrollEngine`, dashboard aggregation, payout-details code, and Wagey response shaping, not inside `computeShift`:

```typescript
const taxEnabled = snapshot.tax_enabled;
const taxPercentage = Math.min(Math.max(snapshot.tax_percentage, 0), 100);

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
FUNCTION computeShift(shift, snapshot, presetRules):
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
  originalPeriods = copy(periods)

  // 6. Calculate raw duration
  totalMinutes = SUM(period.toMin - period.fromMin FOR period IN periods)
  durationHours = totalMinutes / 60

  // 7. Apply pause handling
  IF shift.custom_pause_windows EXISTS THEN
    periods, deductedHours, appliedPauseWindows =
      clipPeriodsByPauseWindows(periods, shift.custom_pause_windows, shift.start_time, shift.end_time)
    breakAudit = {
      method: "none",
      thresholdHours: 0,
      source: "custom_pause_windows",
      deductedHours,
      appliedPauseWindows,
      notes: appliedPauseWindows.length ? ["Deducted using custom pause windows"] : []
    }
  ELSE
    breakEnabled = snapshot.break_enabled OR true
    breakMethod = snapshot.break_method OR "proportional"
    threshold = snapshot.break_threshold_hours OR 5.5
    breakMinutes = breakEnabled ? (snapshot.break_deduction_minutes OR 30) : 0
    periods, breakAudit = applyBreakDeduction(periods, breakMethod, threshold, breakMinutes/60)
  ENDIF

  // 8. Calculate paid hours
  paidMinutes = SUM(period.toMin - period.fromMin FOR period IN periods)
  paidHours = paidMinutes / 60

  // 9. Calculate pay
  basePay = 0
  supplementPay = 0
  FOR period IN periods:
    hours = (period.toMin - period.fromMin) / 60
    basePay += hours * period.baseRate
    supplementPay += hours * period.supplementRate

  basePay = ROUND(basePay, 2)
  supplementPay = ROUND(supplementPay, 2)
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
    breakAudit
  }
```

---

## G) Aggregations and Higher-Level Metrics

### G.1 Monthly Shift Totals

```typescript
// Resolve active dashboard scope first.
const primaryBucket = JobCurrencyAggregateResolver.resolve({
  shifts: displayedMonthShifts,
  jobs,
  fallbackCurrency,
}).primary;
const primaryMonthShifts = shiftsMatching(primaryBucket, displayedMonthShifts);

// Exclude higher-earning overlapping shifts inside the scoped shift set.
const excludedIds = buildExcludedShiftIds(primaryMonthShifts);
const included = primaryMonthShifts.filter(s => !excludedIds.has(s.id));

const aggregates = included.reduce((acc, shift) => ({
  totalHours: acc.totalHours + shift.computed.paidHours,
  totalEarnings: acc.totalEarnings + shift.computed.gross,
}), { totalHours: 0, totalEarnings: 0 });
```

**Filter:** Shifts where `startDate <= shift_date <= endDate`
**Dashboard scope:** The active iOS dashboard shows the primary job/currency bucket selected by `JobCurrencyAggregateResolver`. The default job bucket wins when it has positive gross; otherwise the highest-gross bucket wins. Secondary buckets feed mixed-currency UI, not the main monthly total.
**Adjustment policy:** Monthly shift totals remain shift-only. Payroll adjustments are added only to payout totals, not to hours or average-hourly metrics.

### G.2 Payout Totals

**Which shifts included:** Previous month's shifts (earnings month = current month - 1), grouped per job/currency for the active iOS payroll card.

**Calculation:**
```typescript
for (const job of jobsSortedByNextPayoutDate) {
  const payoutDate = adjustPayrollDate(job.payroll_day, visiblePayoutMonth, visiblePayoutYear);
  const jobShifts = previousMonthShifts.filter(s => effectiveJobId(s) === job.id);
  const shiftTotals = summarizeShiftTotals(jobShifts, halfTaxMonth, previousEarningsMonth);

  const jobAdjustments = payoutAdjustments.filter(a => effectiveJobId(a) === job.id);
  const adjustmentTotals = payrollAdjustmentTotals(
    jobAdjustments,
    adjustment => taxSettingsForAdjustment(adjustment),
    halfTaxMonth,
    visiblePayoutMonth
  );

  variants.push({
    job,
    payoutDate,
    gross: shiftTotals.gross + adjustmentTotals.gross,
    net: shiftTotals.net + adjustmentTotals.net,
    currency: job.currency,
  });
}
```

Only payable job variants with non-zero gross are considered for the visible payroll card. If multiple payable jobs share the same next adjusted payout date, the card combines them and exposes per-job breakdown rows. Otherwise the next payable job variant is shown.

### G.2.1 Payroll Adjustment Totals

```typescript
function payrollAdjustmentTotals(adjustments, taxSettingsForAdjustment, halfTaxMonth, payoutMonth) {
  return adjustments
    .filter(a => !a.deleted_at)
    .reduce((totals, adjustment) => {
      const gross = adjustment.amount;
      if (adjustment.tax_treatment !== "gross_taxable") {
        return {
          gross: totals.gross + gross,
          net: totals.net + gross,
          taxEnabled: totals.taxEnabled,
        };
      }

      const tax = taxSettingsForAdjustment(adjustment);
      const pct = Math.min(Math.max(tax.percentage, 0), 100);
      const effectivePct = halfTaxMonth === payoutMonth ? pct / 2 : pct;
      const net = tax.enabled ? gross * (1 - effectivePct / 100) : gross;

      return {
        gross: totals.gross + gross,
        net: totals.net + net,
        taxEnabled: totals.taxEnabled || tax.enabled,
      };
    }, { gross: 0, net: 0, taxEnabled: false });
}
```

### G.3 Projected Total

**Definition:** Total earnings including future planned shifts

```typescript
const primaryBucket = JobCurrencyAggregateResolver.resolve(monthShifts, jobs, fallbackCurrency).primary;
const primaryMonthShifts = shiftsMatching(primaryBucket, monthShifts);

const totals = summarizeShiftTotals({
  shifts: primaryMonthShifts,
  now: new Date(),
  earningsMonth,
  halfTaxMonth,
});

const earnedToDate = taxEnabled ? totals.completedNet : totals.completedGross;
const projectedTotal = taxEnabled ? totals.net : totals.gross;
const hasFutureShifts = primaryBucket.plannedShiftCount > 0;
```

Completed totals use `Date.hasShiftEnded`, so a shift on the current date contributes to completed gross/net only after its end time. Future/planned counts come from the primary job/currency bucket.

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

| Aggregate | Formula | Period |
|-----------|---------|--------|
| Total hours | `SUM(paidHours)` | Selected range |
| Total earnings | `SUM(gross)` | Selected range |
| Average per shift | `totalEarnings / shiftCount` | Selected range |
| Average hourly | `totalEarnings / totalHours` | Selected range |
| Month-over-month % | `(current - previous) / previous * 100` | Comparison |

### G.6 Conflict Exclusion

Implemented in `ConflictExclusion.swift`:

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

### G.7 Historical Web Caching Note

The retired Next.js app previously used React request caching and Next.js tag invalidation around payroll-derived reads. That web-specific behavior is historical context only and is no longer part of the active product surface.

---

## H) Active Data Access and Sync

The active iOS app is local-first. Payroll reads are assembled from SwiftData repositories and are recalculated in memory from local rows. Supabase remains the sync backend and the shared server-side source for Wagey tools, but the retired Next.js SSR windowing and cache-tag invalidation model is no longer part of the app behavior.

### H.1 iOS Local Read Context

`MonthlyPayrollReadService` builds the payroll read context:

```swift
PayrollReadContext(
  userId: userId,
  settings: settingsRepository.getSettings(for: userId),
  snapshots: snapshotsRepository.getSnapshots(for: userId, jobId: jobId),
  recurringShifts: recurringShiftsRepository.getRecurringShifts(for: userId, jobId: jobId),
  jobs: jobsRepository.getNonDeletedJobs(for: userId)
)
```

Stored shifts are loaded for the requested inclusive date range, optionally filtered by job. The engine then generates matching virtual shifts locally from recurring templates and computes all payroll values from local rows.

### H.2 Sync-Relevant Tables

The local-first sync model depends on `updated_at`, `revision`, and `deleted_at` metadata on payroll-related tables:

| Table | Sync role |
|-------|-----------|
| `user_shifts` | Stored shifts and per-shift pause/supplement/note overrides |
| `recurring_shifts` | Recurring templates and date-specific overrides |
| `wage_snapshots` | Job-scoped wage/tax/break history |
| `jobs` | Employer configuration, job currency, and payroll-day ownership |
| `payroll_adjustments` | Payout-level manual additions/corrections |
| `user_settings` | Global preferences and legacy default-job mirrors |

Soft-deleted rows remain in sync long enough for clients to observe deletes, then are purged by the soft-delete cleanup job.

### H.3 Shared Wagey / Server-Side Path

Wagey tools use `supabase/functions/_shared/wagey/data.ts` and `supabase/functions/_shared/wagey/payroll/*` to load the same logical inputs, build snapshot buckets, compute shifts, summarize earnings, and include payroll adjustments where payout-level totals are requested.

### H.4 Public Documentation Surface

The marketing site renders a public, structured payroll docs page at `marketing/app/docs/payroll/page.tsx`. That page should stay conceptually aligned with this Markdown spec, but the implementation source of truth remains the iOS payroll services plus shared Supabase TypeScript helpers listed in the appendix.

---

## I) Test Vectors and Fixtures

### Test Case Factory

```typescript
function createShift(overrides: Partial<ShiftRow> = {}): ShiftRow {
  return {
    id: crypto.randomUUID(),
    user_id: "test-user-id",
    job_id: "test-job-id",   // Added: all shifts now have a job_id
    shift_date: "2025-01-15",
    start_time: "09:00",
    end_time: "17:00",
    ...overrides,
  };
}

function createJob(overrides: Partial<Job> = {}): Job {
  return {
    id: "test-job-id",
    user_id: "test-user-id",
    name: "Jobb",
    is_default: true,
    sort_order: 0,
    payroll_day: 15,
    half_tax_month: null,
    monthly_goal: 20000,
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
  supplementPay: 670.00,  // 4h×110 + 2h×115
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

### Test Case 14: Payroll Adjustment with Half-Tax

**Inputs:**
```typescript
const adjustment = {
  amount: 1000,
  tax_treatment: "gross_taxable",
  payout_date: "2025-12-15",
};

const payoutTax = {
  enabled: true,
  percentage: 30,
};

const halfTaxMonth = 12;
```

**Expected:**
```typescript
// Payout month = December, so half-tax applies.
const effectiveTaxPct = 30 / 2; // 15%

{
  gross: 1000.00,
  net: 850.00,
  taxEnabled: true,
}
```

---

## Appendix: File Location Reference

| Component/Module | Path Alias | Purpose |
|------------------|------------|---------|
| `PayrollEngine` | `ios/TidexApp/Services/Payroll/PayrollEngine.swift` | Month orchestration, payout-date tax lookup, totals |
| `PayrollCalculator` | `ios/TidexApp/Services/Payroll/PayrollCalculator.swift` | Core per-shift payroll calculation |
| `WagePeriodBuilder` | `ios/TidexApp/Services/Payroll/WagePeriodBuilder.swift` | Time period construction |
| `BreakDeduction` | `ios/TidexApp/Services/Payroll/BreakDeduction.swift` | Automatic break deduction logic |
| `PayrollAdjustmentCalculator` | `ios/TidexApp/Services/Payroll/PayrollAdjustmentCalculator.swift` | Payout-level adjustment totals |
| `ConflictExclusion` | `ios/TidexApp/Services/Payroll/ConflictExclusion.swift` | Overlap cluster exclusion |
| `RecurringShiftGenerator` | `ios/TidexApp/Services/Payroll/RecurringShiftGenerator.swift` | Virtual shift generation |
| `MonthlyPayrollReadService` | `ios/TidexApp/Services/Payroll/MonthlyPayrollReadService.swift` | Local-first payroll input loading |
| `PayrollDateAdjuster` | `ios/TidexApp/Shared/Utilities/PayrollDateAdjuster.swift` | Display payroll date adjustment |
| `computeShift` | `supabase/functions/_shared/wagey/payroll/calc.ts` | Shared TypeScript per-shift calculation |
| `buildWagePeriods` | `supabase/functions/_shared/wagey/payroll/periods.ts` | Shared TypeScript period construction |
| `applyBreakDeduction` | `supabase/functions/_shared/wagey/payroll/breaks.ts` | Shared TypeScript break deduction |
| `applyCustomPauseWindowClipping` | `supabase/functions/_shared/wagey/payroll/pause-windows.ts` | Exact pause-window clipping |
| `buildSnapshotBuckets` / `resolveSnapshotForDate` | `supabase/functions/_shared/wagey/data.ts` | Server-side snapshot resolution |
| `payroll_adjustments` SQL | `supabase/migrations/20260514000516_add_payroll_adjustments.sql` | Manual payout corrections |
| Public docs page | `marketing/app/docs/payroll/page.tsx` | Public rendered payroll documentation |

---

## Appendix: Implementation Notes

### Notes for Non-TypeScript Implementations

1. **Time handling**: All times are local (no timezone conversion needed for calculation)
2. **Date parsing**: Use UTC-based parsing to avoid DST issues: `YYYY-MM-DDT00:00:00Z`
3. **Numeric precision**: Use decimal types or fixed-point arithmetic for currency
4. **JSON parsing**: `supplements.rules` may be nested inside `{ rules: [...] }` object
5. **Job resolution**: A shift without `job_id` should be assigned the user's default job before calculation

### Common Pitfalls

1. **Supplement day numbering**: Days are 1-7 (Monday-Sunday), not 0-6
2. **Weekday calculation**: JavaScript's `getDay()` returns 0-6 (Sunday-Saturday), needs mapping
3. **Break threshold**: Uses strict `>` comparison, not `>=`
4. **Payout month calculation**: January + 1 = February (handle year rollover)
5. **Snapshot selection**: Two different lookups required, both job-scoped:
   - Wage/supplements/break: Use **shift date** + **shift's job_id**
   - Tax settings: Use **payout date** (shift month + 1) + **shift's job_id**
6. **Cross-midnight**: End time can be less than start time (add 24 hours)
7. **Payroll day resolution**: Shift job `payroll_day` takes priority, then default job, then `user_settings.payroll_day`
8. **Legacy snapshots**: Snapshots with `job_id = NULL` serve as fallback; do not discard them

---

## Verification Log

---

**Date:** 2026-05-17
**Version:** 3.2

### Current Alignment Pass

Verified this document against:
- iOS payroll services in `ios/TidexApp/Services/Payroll/`
- iOS local models/repositories for wage snapshots, jobs, shifts, recurring shifts, and payroll adjustments
- Shared Wagey TypeScript payroll helpers in `supabase/functions/_shared/wagey/`
- Supabase migrations for multi-job support, exact pause windows, shift notes, job currencies, monthly goal overrides, and payroll adjustments
- Public payroll docs page in `marketing/app/docs/payroll/page.tsx`

### Changes Made

- Updated the spec version/date and active entry points to reflect the native iOS app plus shared Wagey TypeScript helpers
- Replaced retired Next.js UI, SSR, API route, DAL cache, and Effect-service descriptions with active iOS local-first read/sync behavior
- Added exact pause windows, break audit source metadata, private shift notes, recurring date-specific notes, job currencies, monthly goal overrides, and sync metadata
- Added payroll adjustments, including schema, tax treatments, payout filtering, and gross/net aggregation behavior
- Corrected cross-midnight supplement behavior: rules are matched by the shift weekday and projected into the extended timeline; next-calendar-day rules are not automatically applied
- Clarified job-scoped snapshot fallback differences between shared TypeScript and iOS local rollout compatibility
- Updated the implementation appendix to real current file paths

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

### App Surfaces (Section C)
- [x] Active iOS dashboard, payroll card/details, shift, and stats surfaces documented
- [x] Retired web app surfaces marked historical

### Data Flow (Section H)
- [x] iOS local-first read context documented
- [x] Sync metadata tables documented
- [x] Shared Wagey/server-side path documented

### Test Vectors (Section I)
- [x] Existing test vectors reviewed for current behavior
- [x] Payroll adjustment behavior added to the spec

### Completeness
- [x] No undocumented tables used in payroll
- [x] No undocumented functions in calculation chain
- [x] No undocumented user settings affecting calculations
- [x] Recurrence/virtual shifts documented

---

**Date:** 2026-05-29
**Version:** 3.3

### Current Alignment Pass

Verified this document against:
- `ios/TidexApp/Services/Payroll/PayrollEngine.swift`
- `ios/TidexApp/Services/Payroll/PayrollCalculator.swift`
- `ios/TidexApp/Services/Payroll/PayrollAdjustmentCalculator.swift`
- `ios/TidexApp/Services/Payroll/JobCurrencyAggregateResolver.swift`
- `ios/TidexApp/Storage/Repositories/SnapshotsRepository.swift`
- `ios/TidexApp/Features/Dashboard/DashboardViewModel.swift`
- `supabase/functions/_shared/wagey/data.ts`
- `supabase/functions/_shared/wagey/payroll/calc.ts`
- `marketing/app/docs/payroll/page.tsx`

### Changes Made

- Clarified active iOS snapshot scope selection versus the shared Wagey TypeScript bucket resolver
- Updated aggregation docs for primary job/currency dashboard scope, completed-shift detection, and payroll-card variants
- Bumped the public docs version marker in the marketing payroll spec
