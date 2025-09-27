# Wage Calculations

Authoritative spec for how a single shift is transformed into pay. Pure, deterministic, framework-agnostic. Implemented in `src/lib/payroll`.

- Entry point: `computeShift(shift, settings, presetRules)`
- Never performs I/O. No dates from system clock. All inputs explicit.
- Outputs an enriched shift with derived fields and an audit trail.

---

## 1) Data shapes

```ts
// src/lib/payroll/types.ts (summary)
export type ShiftRow = {
  id: string;
  user_id: string;
  shift_date: string; // ISO date: "2025-09-27"
  start_time: string; // "HH:mm"
  end_time: string; // "HH:mm" (can be next day if end <= start)
  pause_duration_hours?: number | null; // manual pause entered
  hourly_wage_snapshot?: number | null; // locked-in base rate
};

export type BonusRule = {
  days: number[]; // 1=Mon ... 7=Sun
  from: `${number}:${number}`; // inclusive
  to: `${number}:${number}`; // inclusive
  rate: number; // NOK/hour supplement
};

export type UserSettings = {
  use_preset?: boolean | null;
  custom_wage?: number | null;
  current_wage_level?: number | null; // key into preset table
  custom_bonuses?: { rules: BonusRule[] } | null;

  break_policy?:
    | "fixed_0_5_over_5_5h"
    | "proportional_across_periods"
    | "from_base_rate"
    | "none";
  pause_deduction_enabled?: boolean | null;
  pause_deduction_method?:
    | "proportional"
    | "base_only"
    | "end_of_shift"
    | "none"
    | null;
  pause_threshold_hours?: number | null; // e.g. 5.5
  pause_deduction_minutes?: number | null; // e.g. 30
};

export type WagePeriod = {
  fromMin: number; // minutes since day start
  toMin: number; // exclusive
  baseRate: number;
  bonusRate: number;
  totalRate: number; // base + bonus
};

export type ShiftComputed = {
  id: string;
  durationHours: number; // raw duration before any deductions
  paidHours: number; // after policy + manual pauses
  basePay: number; // NOK
  bonusPay: number; // NOK
  gross: number; // NOK
  wagePeriods: WagePeriod[]; // split by bonus changes, after deductions
  breakAudit: {
    method: UserSettings["pause_deduction_method"];
    policy: NonNullable<UserSettings["break_policy"]>;
    thresholdHours: number;
    deductedHours: number; // policy + manual
    notes?: string[];
  };
};
```

---

## 2) Pipeline

1. **Resolve base rate**
   - If `shift.hourly_wage_snapshot` present → use it.
   - Else if `settings.use_preset && settings.current_wage_level` → map to preset table.
   - Else if `settings.custom_wage` → use it.
   - Else fallback to a sane default preset.
2. **Build wage periods**
   - `buildWagePeriods(startHHMM, endHHMM, weekday, baseRate, rules)`
   - Normalizes cross-midnight by allowing `end < start` and adding 24h.
   - Splits [start, end) at every matching `BonusRule` boundary.
   - Each segment gets `bonusRate = max(rule.rate)` that fully covers it.
   - Result: array of contiguous `WagePeriod` segments.
3. **Compute raw duration**
   - `durationHours = sum((toMin - fromMin))/60`, rounded to 2 decimals.
4. **Apply break policy deduction**
   - `applyBreakDeduction(periods, policy, method, threshold, deductionHours)`
   - If `policy === fixed_0_5_over_5_5h` and `duration > threshold` → deduct `pause_deduction_minutes/60` hours.
   - Deduction method:
     - `end_of_shift`: cut from tail periods.
     - `proportional`: cut across all periods by share of minutes.
     - `base_only`: cut from lowest-bonus periods first.
     - `none`: no cut.
   - Returns adjusted periods, audit, and paidHours after policy.
5. **Apply manual pause**
   - If user entered `pause_duration_hours`, subtract from tail deterministically.
   - Drop empty periods after cuts.
6. **Compute pay**
   - For each remaining period:
     - `basePay += hours * baseRate`
     - `bonusPay += hours * bonusRate`
   - `gross = basePay + bonusPay`
   - Round to 2 decimals.
7. **Emit audit**
   - `breakAudit` describes policy, method, thresholds, total deducted hours, and notes.

---

## 3) Function contract

```ts
import { computeShift, ShiftRow, UserSettings, BonusRule } from "@/lib/payroll";

const presetRules: BonusRule[] = [
  // Example presets
  { days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22 },
  { days: [1, 2, 3, 4, 5], from: "21:00", to: "23:59", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 45 },
  { days: [6], from: "15:00", to: "18:00", rate: 55 },
  { days: [6], from: "18:00", to: "23:59", rate: 110 },
  { days: [7], from: "00:00", to: "23:59", rate: 115 },
];

const result = computeShift(shiftRow, userSettings, presetRules);
// → ShiftComputed
```

**Determinism:** same input → same output. No hidden timezones, no DB calls.

---

## 4) Server usage pattern

- Compute **once per fetch** on the server. Send enriched shifts to the client.

```ts
// src/app/(app)/shifts/_data/getShifts.ts
export async function getComputedShifts(userId: string) {
  // 1) load settings
  // 2) load raw shifts
  // 3) map computeShift(...) over rows
  // 4) return enriched list
}
```

- UI renders precomputed fields (`gross`, `paidHours`, etc.). No re-calc during paint.

**Revalidation:** After any mutation, revalidate the server loader so SSR remains the source of truth.

---

## 5) Client usage pattern (optimistic)

- On add/edit:
  1. Compute optimistic `ShiftComputed` with same `computeShift(...)`.
  2. Update local list in state.
  3. Commit mutation to server.
  4. Revalidate. Replace with server result.
- On delete:
  1. Remove from local list.
  2. Commit delete.
  3. Revalidate.

Only recompute affected shifts. Never recompute all on every render.

---

## 6) Example calculation

**Inputs**

- Date: Saturday (day 6)
- Start–End: `14:30` → `22:15`
- Base rate: 185.38 NOK/h
- Preset rules:
  - Sat 13:00–15:00 +45
  - Sat 15:00–18:00 +55
  - Sat 18:00–23:59 +110
- Policy: `fixed_0_5_over_5_5h`, threshold 5.5h, deduction 30 minutes, method `proportional`
- Manual pause: 0.25 h

**Split periods**

- 14:30–15:00 → +45
- 15:00–18:00 → +55
- 18:00–22:15 → +110

**Raw duration**

- (30 + 180 + 255) min = 465 min = **7.75 h**

**Policy deduction**

- 7.75 > 5.5 → deduct 0.5 h proportionally.
- New total: 7.25 h

**Manual pause**

- Deduct 0.25 h from tail.
- New total: **7.00 h paid**

**Pay**

- Compute per period after cuts.
- Sum base and bonus separately.
- Round to 2 decimals.
- Emit `gross = basePay + bonusPay`.

(The exact split after deductions is left to the library; audit will state how many minutes were cut from which segments.)

---

## 7) Cross-midnight and boundaries

- If `end <= start`, treat `end += 24h`.
- Rules can straddle midnight. The builder checks both same-day and +24h windows.
- Rule `to` is inclusive in input and converted to exclusive internally (`+1 minute`) to avoid gaps.

---

## 8) Rounding

- Hours: duration and paidHours rounded to 2 decimals for display.
- Money: basePay and bonusPay rounded to 2 decimals at the end of accumulation.
- Internal minute arithmetic stays integer to avoid drift.

---

## 9) Performance

- `O(k)` per shift where `k` = number of rule boundaries hit.
- Server computes once per fetch. Client computes on targeted updates only.
- No recompute during React renders if you pass precomputed data.

---

## 10) Testing

Add table-driven tests that pin expected outputs:

- Weekday vs weekend rules.
- Cross-midnight shifts.
- Each break method.
- Manual pause with and without policy deduction.
- Snapshot wage override vs preset mapping.

---

## 11) Extensibility

Add features by layering pure steps:

- **Overtime tiers:** After paid periods are finalized, apply tiered multipliers for hours beyond thresholds.
- **Holiday calendar:** Pre-map dates → bonus overlays. Feed as additional `BonusRule`s.
- **Minimum payable block:** Clamp tiny paid fragments after deductions.

---

## 12) Do’s and Don’ts

- Do treat `computeShift` as the sole source of calculation truth.
- Do store snapshots (base rate, maybe resolved bonuses) if your business rules require historic accuracy.
- Do not call calculators inside React render paths.
- Do not read system time inside calculators.

---

## 13) Glossary

- **Base rate:** Hourly wage before supplements.
- **Supplement/Bonus:** Extra NOK/hour by rule window.
- **Policy deduction:** Automatic break when shift crosses a threshold.
- **Manual pause:** User-entered break on top of policy deduction.
- **Paid hours:** Billable hours after all deductions.

```

```
