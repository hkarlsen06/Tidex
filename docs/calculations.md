# Wage Calculation Reference

This document explains the logic used throughout the project to derive paid hours and gross pay for employee shifts. It focuses on the decision process, inputs, and outputs rather than reproducing the source code. Use it as a high-level guide when reasoning about payroll behaviour or making changes.

## System Overview

- **Authoritative results live on the server.** Every API response that returns shifts calls the server-side calculator to attach `duration_hours`, `paid_hours`, `gross`, and the break policy that was applied.
- **The SPA mirrors the rules locally** so the UI can preview totals, simulate alternate break deductions, and render audit details while offline. Client math should match the server unless deliberately diverging for exploratory tools.
- **Snapshots ensure stable numbers.** When a shift is created, the server locks in the employee’s hourly wage and tariff level so later updates do not retroactively change historical payouts.

## Server-side Logic (`server/payroll/calc.js` and supporting helpers)

### Inputs

- `start_time` and `end_time` in `HH:mm` (converted from stored UTC timestamps).
- `break_minutes` recorded manually for a shift.
- `hourly_wage_snapshot` captured at insert/update time.
- Organization break policy resolved via `getOrgSettings(managerId)` (defaults to `fixed_0_5_over_5_5h`).

### Step-by-step flow (`calcEmployeeShift`)

1. **Time normalisation** – convert the start/end pair to minutes since midnight. If the end is earlier or equal to the start, treat the shift as crossing midnight and add 24 hours, ensuring a zero- or negative-length shift never produces pay.
2. **Duration calculation** – compute raw hours worked before deductions (`durationHours`).
3. **Policy deduction** – call `applyBreakPolicy` to calculate automatic break time dictated by the organisation:
   - `fixed_0_5_over_5_5h`: subtract 0.5 hours once a shift exceeds 5.5 hours.
   - `proportional_across_periods` and `from_base_rate`: currently act like the fixed rule but are placeholders for future split-by-period logic.
   - `none`: perform no automatic deduction.
   - Unknown policies fall back to `none` to avoid accidental over-deduction.
4. **Manual break handling** – subtract the user-entered `break_minutes` (converted to hours) from the duration in addition to any policy deduction.
5. **Paid hours** – clamp the remainder to zero or above to guard against over-reporting break time.
6. **Gross wage** – multiply paid hours by `hourly_wage_snapshot`.
7. **Rounding** – round all numeric outputs to two decimals without mutating the original shift row.

### API integration (`server/server.js`)

- **Time conversion helpers** (`hhmmToUtcIso`, `formatTimeHHmm`) translate between stored UTC timestamps and the calculator’s `HH:mm` inputs.
- **Route usage**: `GET /employee-shifts`, `POST /employee-shifts`, and `PUT /employee-shifts/:id` all invoke `calcEmployeeShift` before responding so the client always receives derived fields alongside the raw shift data.
- **Snapshot enforcement**: `computeEmployeeSnapshot` fetches tariff/custom wage data, resolves the effective hourly rate (tariff table or custom value), and provides the fields stored with each shift record.
- **Break policy resolution**: `getOrgSettings` reads an organisation-specific policy from dedicated Supabase tables when present, then falls back to per-user settings or an in-memory default.

### Key considerations

- **Cross-midnight safety** – identical start/end times imply a 24-hour shift to avoid zero pay for valid overnight work.
- **Rounded outputs** – rounding happens at the calculator boundary; the database continues to store raw minutes and wage snapshots.
- **Extensibility hooks** – policy names like `proportional_across_periods` anticipate future wage-period-aware logic without breaking callers today.

## Client-side Logic (`app/src/js/appLogic.js`)

The SPA reimplements wage math to power interactive views, offline editing, and compliance audits. While richer than the server helper, it uses the same foundational ideas.

### Data sources

- **Wage rate selection** – prefer the per-shift `hourly_wage_snapshot`. If absent (e.g., locally drafted shifts), fall back to the user’s currently selected preset or custom wage.
- **Bonus rules** – load preset or user-defined bonus windows that add per-hour supplements based on day-of-week and time of day.
- **Break settings** – toggleable controls govern whether deductions occur, the applied method, threshold hours (default 5.5), and deduction length (default 30 minutes).

### Local calculation flow (`calculateShift`)

1. **Time handling** – convert start/end to minutes, supporting cross-midnight and 24-hour edge cases identical to the server.
2. **Raw duration** – compute unadjusted hours and reject non-positive results to avoid showing nonsense totals.
3. **Break deduction decision** (`calculateLegalBreakDeduction`):
   - When disabled or under threshold, return early with zero deduction.
   - When enabled, gather wage periods (see below) and apply one of four strategies:
     - `proportional`: remove time evenly across all wage periods.
     - `base_only`: remove time from base-rate periods (or the lowest available bonus rates when no pure base period exists).
     - `end_of_shift`: subtract the deduction from the tail of the shift (legacy behaviour kept for compatibility warnings).
     - `none`: treat the break as paid time.
   - Produce an audit trail indicating the chosen method, deducted hours, and any compliance notes.
4. **Wage period construction** (`calculateWagePeriods`):
   - Split the shift timeline into contiguous segments, considering bonus rule windows, shift day-of-week, and overnight spans.
   - Each segment tracks its base wage, bonus rate, total rate, and coverage for audit output.
5. **Applying deductions**:
   - For proportional/base-only methods, `calculateAdjustedWages` recomputes hours, base wage, and bonus from the adjusted periods.
   - For end-of-shift/none, simply subtract the deduction hours (if any) from total paid hours and recompute bonuses on the adjusted range.
6. **Result object** – return rounded totals: `hours`/`paidHours`, split earnings (`baseWage`, `bonus`), aggregate `total`, and the break deduction audit record for UI display.

### Additional client behaviours

- **Audit tooling** – compliance warnings highlight legacy deduction methods that may violate labour rules.
- **Tax preview** – after local wage computation, UI components may optionally apply user-configured tax percentages; this happens outside the wage logic described here.
- **Offline resilience** – calculations rely solely on in-memory data, enabling projections even without a network connection. Upon sync, server results remain canonical.

## Testing Notes

- `server/tests/payroll.test.js` still reflects an older overtime-centric structure (`regularHours`, `overtimeHours`, `totalPay`). The current server helper returns `durationHours`, `paidHours`, and `gross`. Update or replace these tests if you need automated coverage for the new calculator interface.

## Implementation Checklist (when modifying payroll logic)

- Update both the server helper and the client mirror if behaviour changes (or document intentional divergences).
- Adjust Supabase migrations or settings queries if new organisation-level configuration is introduced.
- Revisit API docs (`docs/API.md`, `docs/DATABASE.md`, `docs/ARCHITECTURE_AND_SNAPSHOTS.md`) to keep derivation logic in sync.
- Expand or modernise test coverage to validate new scenarios (e.g., policy-specific deductions, bonus edge cases, cross-midnight shifts).

Presets:

exportconstapp= {

// Constants

    PAUSE_THRESHOLD: 5.5,

    PAUSE_DEDUCTION: 0.5,

    MONTHS: ['januar', 'februar', 'mars', 'april', 'mai', 'juni',

'juli', 'august', 'september', 'oktober', 'november', 'desember'],

    WEEKDAYS: ['søndag', 'mandag', 'tirsdag', 'onsdag', 'torsdag', 'fredag', 'lørdag'],

    PRESET_WAGE_RATES: {

// Use negative numbers for young workers to avoid conflicts with regular levels 1-6

'-1': 129.91, // under16

'-2': 132.90, // under18

1: 184.54,

2: 185.38,

3: 187.46,

4: 193.05,

5: 210.81,

6: 256.14

    },

// Organization settings cache

    orgSettings: { break_policy: 'fixed_0_5_over_5_5h' },

// Data loading state

    isDataLoading: true,

    PRESET_BONUSES: {

    rules: [

    { days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22 },

    { days: [1, 2, 3, 4, 5], from: "21:00", to: "23:59", rate: 45 },

    { days: [6], from: "13:00", to: "15:00", rate: 45 },

    { days: [6], from: "15:00", to: "18:00", rate: 55 },

    { days: [6], from: "18:00", to: "23:59", rate: 110 },

    { days: [7], from: "00:00", to: "23:59", rate: 115 }

    ]

    },
