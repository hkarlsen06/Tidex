# iOS Payroll System

## Architecture

The iOS payroll system mirrors the web backend's pure, deterministic computation model. All calculations are:
- **Pure functions**: No side effects, same inputs = same outputs
- **Snapshot-based**: Configuration versioned by date
- **Server-computed**: Computed once in DAL, cached locally
- **Deterministic**: Bit-for-bit identical to web backend

## Components

### 1. PayrollCalculator (Pure Function)

Computes a single shift's payroll.

```swift
static func computeShift(_ shift: ShiftRow, snapshot: WageSnapshot?) -> ShiftComputed
```

**Inputs**:
- `shift`: ShiftRow with date, times, custom supplements
- `snapshot`: WageSnapshot with wage, supplements, tax, break settings

**Outputs**:
- `ShiftComputed`:
  - `durationHours`: Total hours (including breaks)
  - `paidHours`: Hours after break deduction
  - `basePay`: Base rate × paid hours
  - `supplementPay`: Supplement rate × paid hours
  - `gross`: basePay + supplementPay
  - `wagePeriods`: Breakdown by supplement period
  - `breakAudit`: Break deduction details

**Algorithm**:
1. Resolve base rate (snapshot → fallback to preset)
2. Resolve supplement rules (snapshot → custom → preset)
3. Build wage periods (split by supplement boundaries)
4. Apply break deduction (fixed/proportional)
5. Calculate paid hours (duration - break)
6. Calculate pay (round to 2 decimals for currency)

**Precision**:
- Hours: 3 decimal places (0.001)
- Currency: 2 decimal places (0.01)
- Rounding: Banker's rounding (round half to even)

### 2. PayrollEngine (Monthly Aggregation)

Computes all shifts for a month with tax.

```swift
static func computeShiftsForMonth(
    year: Int,
    month: Int,
    shifts: [ShiftRow],
    recurring: [RecurringShiftRow],
    snapshots: [WageSnapshot],
    settings: UserSettings?
) -> [ShiftWithComputations]
```

**Process**:
1. Generate virtual shifts from recurring patterns
2. Combine with regular shifts
3. For each shift:
   - Find wage snapshot (shift date)
   - Find tax snapshot (payout date)
   - Compute via PayrollCalculator
   - Apply tax settings
4. Sort by date
5. Return [ShiftWithComputations]

**Tax Calculation**:
```swift
let payoutDate = calculatePayoutDate(shiftDate, payrollDay)
let taxSnapshot = snapshotForDate(payoutDate, from: snapshots)
let net = gross * (1 - taxPercentage / 100)
```

**Half-Tax Support**:
```swift
if payoutMonth == halfTaxMonth {
    effectiveTaxRate = effectiveTaxRate / 2
}
```

### 3. SnapshotsService (Snapshot Resolution)

Finds applicable snapshot for a date using binary search.

```swift
nonisolated static func snapshotForDate(_ date: String, from snapshots: [WageSnapshot]) -> WageSnapshot?
```

**Snapshot Priority**:
1. Dated snapshot where `from_date <= target_date` (latest)
2. Baseline snapshot where `from_date == nil`
3. Hardcoded defaults (fallback)

**Binary Search**:
- O(log n) lookup
- Handles unsorted input (sorts internally)
- Null-safe (handles nil from_date)

### 4. WageSnapshot Model

```swift
struct WageSnapshot: Codable {
    let id: String
    let user_id: String
    let from_date: String?              // YYYY-MM-DD or nil for baseline
    let hourly_wage: Double             // Base hourly rate
    let supplement_rules: [SupplementRule]
    let tax_enabled: Bool
    let tax_percentage: Double
    let break_deduction_type: String    // "fixed" or "proportional"
    let break_deduction_minutes: Int
    let created_at: String
    let updated_at: String
}
```

**Key Fields**:
- `from_date`: When this snapshot becomes active (nil = baseline)
- `hourly_wage`: Base rate in currency
- `supplement_rules`: Array of supplement definitions
- `tax_enabled`: Whether tax applies
- `tax_percentage`: Tax rate (e.g., 22.0 for 22%)
- `break_deduction_type`: How breaks are deducted
- `break_deduction_minutes`: Break duration

### 5. SupplementRule Model

```swift
struct SupplementRule: Codable {
    let id: String
    let name: String                    // "Sunday", "Night", etc.
    let supplement_percentage: Double   // e.g., 50.0 for 50%
    let start_time: String?             // HH:mm or nil for all-day
    let end_time: String?               // HH:mm or nil for all-day
    let weekdays: [Int]?                // [0-6] or nil for all days
}
```

## Data Flow in Dashboard

```
DashboardViewModel.loadDashboard()
  ↓
Load from repositories:
  - shifts: ShiftsRepository.getShifts(userId)
  - recurring: RecurringShiftsRepository.getRecurringShifts(userId)
  - snapshots: SnapshotsRepository.getSnapshots(userId)
  - settings: SettingsRepository.getSettings(userId)
  ↓
PayrollEngine.computeShiftsForMonth(
    year: displayYear,
    month: displayMonth,
    shifts: shifts,
    recurring: recurring,
    snapshots: snapshots,
    settings: settings
)
  ↓
For each shift:
  1. SnapshotsService.snapshotForDate(shiftDate) → wage snapshot
  2. SnapshotsService.snapshotForDate(payoutDate) → tax snapshot
  3. PayrollCalculator.computeShift(shift, wageSnapshot)
  4. Apply tax from taxSnapshot
  ↓
Cache in monthCache (5-minute TTL)
  ↓
Compute DashboardData:
  - currentMonthGross: Sum of all shifts
  - currentMonthCompletedGross: Sum of completed shifts
  - currentMonthNet: Apply tax
  - percentageChangeVsPrevious: Compare to previous month
  ↓
Display in PayrollCard & TotalCard
```

## Wage Period Breakdown

Each shift is split into wage periods based on supplement rules.

```swift
struct WagePeriod {
    let startTime: String               // HH:mm
    let endTime: String                 // HH:mm
    let durationMinutes: Double
    let durationHours: Double
    let baseRate: Double
    let supplementRate: Double          // baseRate + supplements
    let supplementPercentage: Double
}
```

**Example**:
- Shift: 10:00-18:00 (8 hours)
- Supplements: Sunday +50%, Night (22:00-06:00) +40%
- Periods:
  1. 10:00-18:00: 8h @ base rate (no supplements apply)
  2. (If shift crossed midnight) 22:00-06:00: 8h @ base + 40%

## Break Deduction

**Fixed Deduction**:
```
paidHours = durationHours - (breakMinutes / 60)
```

**Proportional Deduction**:
```
paidHours = durationHours * (1 - breakMinutes / durationMinutes)
```

**Example**:
- Duration: 8 hours
- Break: 30 minutes
- Fixed: 8 - 0.5 = 7.5 hours
- Proportional: 8 * (1 - 30/480) = 7.75 hours

## Conflict Exclusion

When shifts overlap, the lower-earning shift is excluded from totals.

```swift
let excludedIds = ConflictExclusion.buildExcludedShiftIds(shifts: shifts)
let includedShifts = shifts.filter { !excludedIds.contains($0.id) }
```

## Testing Payroll

```swift
let shift = ShiftRow(
    id: "test",
    shift_date: "2025-01-15",
    start_time: "10:00",
    end_time: "18:00",
    custom_supplements: nil
)

let snapshot = WageSnapshot(
    hourly_wage: 200.0,
    supplement_rules: [],
    tax_enabled: true,
    tax_percentage: 22.0,
    break_deduction_type: "fixed",
    break_deduction_minutes: 30
)

let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

XCTAssertEqual(computed.durationHours, 8.0)
XCTAssertEqual(computed.paidHours, 7.5)
XCTAssertEqual(computed.gross, 1500.0)  // 7.5 * 200
```

## Consistency with Web Backend

The iOS implementation is **bit-for-bit identical** to the web backend (`lib/payroll/calc.ts`):
- Same precision (3 decimals for hours, 2 for currency)
- Same rounding rules
- Same supplement resolution
- Same break deduction logic
- Same tax calculation

This ensures shifts computed on iOS match the server exactly.

