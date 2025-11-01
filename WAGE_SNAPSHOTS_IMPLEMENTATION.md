# Interval-Based Wage Snapshots Implementation Plan

## Context & Problem Statement

### Current System Issues
Currently, the application has two different approaches to wage tracking:

1. **Single shifts**: Store `hourly_wage_snapshot` and `supplement_rules_snapshot` directly on each `user_shifts` row
   - ✅ Works correctly - shifts remember the wage at creation time
   - ❌ Redundant storage - same wage stored thousands of times
   - ❌ No way to retroactively correct historical wages

2. **Series shifts (ghosts)**: Generated dynamically from `series_shifts` table templates
   - ❌ No snapshots stored anywhere
   - ❌ Ghosts use current user settings for calculations
   - ❌ If user changes wage, all historical ghosts recalculate with new wage (incorrect)

### The Solution: Interval-Based Wage Snapshots

Instead of storing wages per-shift, we'll create a `wage_snapshots` table that stores wage changes as time intervals:

```
wage_snapshots:
- 2025-01-01: 210 kr/hr, Level 3, supplements {...}
- 2025-03-15: 225 kr/hr, Level 4, supplements {...}
- 2025-11-01: 234 kr/hr, Level 5, supplements {...}
```

**Lookup logic**: For any shift date, find the most recent snapshot where `from_date <= shift_date`.

Example:
- Shift on 2025-02-10 → Uses snapshot from 2025-01-01 (210 kr)
- Shift on 2025-06-22 → Uses snapshot from 2025-03-15 (225 kr)
- Shift on 2025-11-15 → Uses snapshot from 2025-11-01 (234 kr)

### Benefits
- ✅ Works for both single and series shifts
- ✅ Minimal storage (only store when wage changes)
- ✅ Handles mid-month wage changes (e.g., promotion on Jan 15)
- ✅ Users can retroactively correct wage history
- ✅ Natural UX: "I got a raise on March 15, 2025"
- ✅ Maintains historical accuracy even after wage changes

---

## Database Schema

### New Table: `wage_snapshots`

```sql
CREATE TABLE wage_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  from_date date NOT NULL,
  hourly_wage numeric(10,2) NOT NULL,
  wage_level integer,  -- NULL = custom wage, NUMBER = tariff level
  supplements jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamp with time zone DEFAULT now(),

  CONSTRAINT unique_user_date UNIQUE(user_id, from_date)
);

CREATE INDEX idx_wage_snapshots_lookup
  ON wage_snapshots(user_id, from_date DESC);
```

### Column Details
- `hourly_wage`: The actual hourly rate used for calculations (resolved from tariff or custom)
- `wage_level`: If user is on tariff, stores the level number (1-9) for display purposes; NULL if custom wage
- `supplements`: JSONB array of supplement rules (same format as current `user_settings.supplement_rules`)
- `from_date`: The date this wage configuration becomes effective (inclusive)

### Changes to Existing Tables
- **Remove** `user_shifts.hourly_wage_snapshot` (no longer needed)
- **Remove** `user_shifts.supplement_rules_snapshot` (no longer needed)

---

## Implementation Phases

This implementation is divided into 7 phases that should be completed sequentially.

---

## Phase 1: Database Migration

**Goal**: Create the `wage_snapshots` table and backfill data for existing users.

### Tasks
1. **Create migration file**: `supabase/migrations/YYYYMMDD_interval_wage_snapshots.sql`

2. **Migration content**:
   - Create `wage_snapshots` table with schema above
   - Backfill: For each user, create one initial snapshot with:
     - `from_date = '2025-01-01'`
     - `hourly_wage` = resolved from their current settings (tariff rate or custom wage)
     - `wage_level` = current level if on tariff, NULL if custom
     - `supplements` = current `user_settings.supplement_rules`
   - Drop `user_shifts.hourly_wage_snapshot` column
   - Drop `user_shifts.supplement_rules_snapshot` column

3. **Tariff rates for backfill**:
   ```sql
   -- Tariff hourly wage rates (from lib/payroll/tariffRates.ts)
   CASE user_settings.wage_level
     WHEN 1 THEN 170.15
     WHEN 2 THEN 178.80
     WHEN 3 THEN 187.46
     WHEN 4 THEN 196.11
     WHEN 5 THEN 210.81
     WHEN 6 THEN 219.46
     WHEN 7 THEN 228.12
     WHEN 8 THEN 236.77
     WHEN 9 THEN 245.43
   END
   ```

### Verification
- Run migration on local Supabase
- Check that `wage_snapshots` table exists
- Verify each user has exactly one snapshot with `from_date = '2025-01-01'`
- Verify old columns are removed from `user_shifts`

### Files to Create/Modify
- **NEW**: `supabase/migrations/YYYYMMDD_interval_wage_snapshots.sql`

---

## Phase 2: Data Access Layer

**Goal**: Create functions to fetch and manipulate wage snapshots, update payroll calculations.

### Tasks

1. **Create `data-access/wage-snapshots.ts`**:
   ```typescript
   export const getUserWageSnapshots = cache(async (userId: string) => {
     // Fetch all snapshots for user, ordered by from_date DESC
     // Use React cache() for request deduplication
   });

   export async function getSnapshotForDate(userId: string, shiftDate: string) {
     // Find the applicable snapshot where from_date <= shiftDate
     // Returns the most recent one
   });

   export async function createWageSnapshot(data: WageSnapshotInput) {
     // Validate from_date doesn't conflict
     // Insert new snapshot
     // Return success/error
   });

   export async function updateWageSnapshot(id: string, data: WageSnapshotInput) {
     // Validate new from_date doesn't conflict with other entries
     // Update snapshot
     // Return success/error
   });

   export async function deleteWageSnapshot(id: string) {
     // Count affected shifts (shifts between this snapshot and next)
     // Delete snapshot
     // Return { affectedShiftCount, success }
   });
   ```

2. **Update `lib/payroll/calc.ts`**:
   - Modify `computeShift()` signature to accept optional `snapshot` parameter
   - Update `resolveBaseRate()`:
     ```typescript
     function resolveBaseRate(
       s: ShiftRow,
       snapshot: WageSnapshot | null,
       settings: UserSettings
     ): number {
       // Use snapshot.hourly_wage if provided
       if (snapshot?.hourly_wage && snapshot.hourly_wage > 0) {
         return snapshot.hourly_wage;
       }

       // Fallback to current settings (for new shifts without snapshots)
       return resolveCurrentWage(settings);
     }
     ```
   - Update supplement resolution to use `snapshot.supplements` if provided

3. **Update `data-access/shifts.ts`**:
   - In `getComputedShifts()`:
     ```typescript
     // Fetch all wage snapshots once
     const snapshots = await getUserWageSnapshots(userId);

     // For each shift, find applicable snapshot
     const computed = shifts.map(shift => {
       const snapshot = snapshots.find(s => s.from_date <= shift.shift_date);
       return computeShift(shift, snapshot, settings, PRESET_RULES);
     });
     ```
   - Apply same logic to ghost shift generation

### Verification
- Shifts use snapshot wages instead of current settings
- Series ghosts now use snapshot wages
- Changing current wage doesn't affect historical shift calculations

### Files to Create/Modify
- **NEW**: `data-access/wage-snapshots.ts`
- **MODIFY**: `lib/payroll/calc.ts`
- **MODIFY**: `data-access/shifts.ts`

---

## Phase 3: Server Actions

**Goal**: Create server actions for creating, updating, and deleting wage snapshots.

### Tasks

1. **Create `app/[locale]/(app)/settings/pay/_actions/wage-snapshots.ts`**:
   ```typescript
   'use server';

   export async function createWageSnapshotAction(data: WageSnapshotInput) {
     // 1. Verify authentication
     const user = await verifySession();

     // 2. Validate from_date format
     if (!isISODate(data.from_date)) return { error: ERRORS.INVALID_DATE };

     // 3. Check for date conflicts
     const existing = await checkExistingSnapshot(user.id, data.from_date);
     if (existing) return { error: "En lønnsoppføring eksisterer allerede for denne datoen" };

     // 4. Create snapshot
     const result = await createWageSnapshot({ ...data, user_id: user.id });

     // 5. Invalidate cache and revalidate
     invalidateAndRevalidate(user.id);

     return result;
   }

   export async function updateWageSnapshotAction(id: string, data: WageSnapshotInput) {
     // Similar flow to create, but update existing
     // Validate new from_date doesn't conflict with OTHER entries
   }

   export async function deleteWageSnapshotAction(id: string) {
     // 1. Verify authentication
     // 2. Count affected shifts
     // 3. Delete snapshot
     // 4. Invalidate and revalidate
     return { affectedShiftCount, success };
   }
   ```

2. **Add validation helper** in `lib/validation/shift-validators.ts`:
   ```typescript
   export function isISODate(date: string): boolean {
     return /^\d{4}-\d{2}-\d{2}$/.test(date);
   }
   ```

3. **Add error messages** in `lib/errors/messages.ts`:
   ```typescript
   export const ERRORS = {
     // ... existing
     WAGE_SNAPSHOT_CONFLICT: "En lønnsoppføring eksisterer allerede for denne datoen",
     INVALID_DATE: "Ugyldig dato",
   };
   ```

### Verification
- Creating snapshot invalidates cache
- Date conflict validation works
- Deleting snapshot returns affected shift count

### Files to Create/Modify
- **NEW**: `app/[locale]/(app)/settings/pay/_actions/wage-snapshots.ts`
- **MODIFY**: `lib/validation/shift-validators.ts` (if needed)
- **MODIFY**: `lib/errors/messages.ts`

---

## Phase 4: UI Components - Wage History List

**Goal**: Update settings page to show wage history list instead of current wage form.

### Tasks

1. **Update `app/[locale]/(app)/settings/pay/page.tsx`**:
   - Remove current wage settings form
   - Fetch all wage snapshots (ordered by `from_date DESC`)
   - Render wage history list
   - Add [+] button in header
   - Layout:
     ```
     ┌─────────────────────────────────────────────┐
     │ Lønnshistorikk                        [+]   │
     ├─────────────────────────────────────────────┤
     │ ✓ Gjeldende: 234 kr/time (fra 1. nov) [👁️] │
     │   Nivå 5 · 3 tillegg                        │
     ├─────────────────────────────────────────────┤
     │   15. mar 2025: 225 kr/time            [👁️] │
     │   Nivå 4 · 3 tillegg                        │
     ├─────────────────────────────────────────────┤
     │   1. jan 2025: 210 kr/time             [👁️] │
     │   Nivå 3 · 2 tillegg                        │
     └─────────────────────────────────────────────┘
     ```

2. **Create `components/settings/pay/WageHistoryList.tsx`**:
   - Display list of wage snapshots
   - Show "current" badge on the most recent entry
   - Format date (e.g., "1. jan 2025" for Norwegian)
   - Show wage amount, source (Level X or "Egendefinert"), supplement count
   - View/edit button on right (👁️ icon)

3. **Add modal state management**:
   - State for modal open/closed
   - State for selected snapshot (null = new entry, object = editing)
   - Clicking [+] opens modal with `selectedSnapshot = null`
   - Clicking [👁️] opens modal with `selectedSnapshot = that entry`

### Verification
- Wage history list displays correctly
- Current entry is marked with checkmark
- Clicking [+] sets up for new entry
- Clicking [👁️] sets up for editing

### Files to Create/Modify
- **MODIFY**: `app/[locale]/(app)/settings/pay/page.tsx`
- **NEW**: `components/settings/pay/WageHistoryList.tsx`

---

## Phase 5: UI Components - Wage History Modal

**Goal**: Create modal for viewing/editing wage snapshots.

### Tasks

1. **Create `components/settings/pay/WageHistoryModal.tsx`**:
   - Modal with:
     - "Grunnlønn" section (shows tariff level selector OR custom wage input)
     - Supplements editor section below (same as current supplements editor)
     - "Gjeldende fra" date picker
     - Save button (calls appropriate server action)
     - Close button

2. **Modal behavior**:
   - **New entry mode** (`selectedSnapshot = null`):
     - Pre-fill with current wage settings
     - Default `from_date` to today
     - Title: "Legg til lønnsøkning"
     - Save calls `createWageSnapshotAction()`

   - **Edit mode** (`selectedSnapshot = {...}`):
     - Pre-fill with snapshot's data
     - Allow editing `from_date`
     - Title: "Rediger lønnsperiode"
     - Save calls `updateWageSnapshotAction()`
     - Show delete button (calls `deleteWageSnapshotAction()`)

3. **Validation**:
   - Show error if `from_date` conflicts with another entry
   - Show confirmation modal before deleting:
     ```
     ┌────────────────────────────────────────────┐
     │ Slett denne lønnsperioden?                 │
     │                                            │
     │ 47 vakter vil bli påvirket. Disse vil     │
     │ bruke forrige lønn (225 kr/time).         │
     │                                            │
     │ [Avbryt] [Slett]                           │
     └────────────────────────────────────────────┘
     ```

4. **Re-use existing components**:
   - Wage source toggle (tariff/custom) from current settings page
   - Supplements editor component (same as current)
   - Make supplements read-only if user is on tariff

### Verification
- Modal opens with correct mode (new/edit)
- Pre-fills correctly
- Date validation works
- Delete confirmation shows affected shift count
- Save triggers revalidation

### Files to Create/Modify
- **NEW**: `components/settings/pay/WageHistoryModal.tsx`
- **MODIFY**: Potentially extract/refactor existing components for reuse

---

## Phase 6: Translations

**Goal**: Add Norwegian and English translations for new UI elements.

### Tasks

1. **Add to `lib/i18n/dictionaries/no.ts`**:
   ```typescript
   {
     settings: {
       pay: {
         wageHistory: "Lønnshistorikk",
         addWageIncrease: "Legg til lønnsøkning",
         editWagePeriod: "Rediger lønnsperiode",
         deleteWagePeriod: "Slett lønnsperiode",
         effectiveFrom: "Gjeldende fra",
         current: "Gjeldende",
         customWage: "Egendefinert",
         level: "Nivå",
         supplements: "tillegg",
         deleteConfirmation: {
           title: "Slett denne lønnsperioden?",
           message: "{{count}} vakter vil bli påvirket. Disse vil bruke forrige lønn ({{wage}} kr/time).",
           cancel: "Avbryt",
           confirm: "Slett"
         },
         errors: {
           dateConflict: "En lønnsoppføring eksisterer allerede for denne datoen",
           invalidDate: "Ugyldig dato"
         }
       }
     }
   }
   ```

2. **Add to `lib/i18n/dictionaries/en.ts`**:
   ```typescript
   {
     settings: {
       pay: {
         wageHistory: "Wage History",
         addWageIncrease: "Add Wage Increase",
         editWagePeriod: "Edit Wage Period",
         deleteWagePeriod: "Delete Wage Period",
         effectiveFrom: "Effective from",
         current: "Current",
         customWage: "Custom",
         level: "Level",
         supplements: "supplements",
         deleteConfirmation: {
           title: "Delete this wage period?",
           message: "{{count}} shifts will be affected. They will use the previous wage ({{wage}} kr/hour).",
           cancel: "Cancel",
           confirm: "Delete"
         },
         errors: {
           dateConflict: "A wage entry already exists for this date",
           invalidDate: "Invalid date"
         }
       }
     }
   }
   ```

### Verification
- All UI text shows correctly in Norwegian
- Switching to English shows English translations
- Pluralization works for shift count

### Files to Create/Modify
- **MODIFY**: `lib/i18n/dictionaries/no.ts`
- **MODIFY**: `lib/i18n/dictionaries/en.ts`

---

## Phase 7: Cache Invalidation & Testing

**Goal**: Ensure cache invalidation works correctly and test all scenarios.

### Tasks

1. **Update `lib/revalidation/paths.ts`** (if needed):
   - Ensure `invalidateAndRevalidate()` clears wage snapshot cache
   - Revalidate paths: `/settings/pay`, `/shifts`, `/`, `/stats`

2. **Test scenarios**:
   - ✅ Create wage snapshot → shifts recalculate with new wage
   - ✅ Edit `from_date` → affected shifts recalculate
   - ✅ Delete snapshot → shifts fall back to previous snapshot
   - ✅ Future snapshot (from_date > today) → doesn't affect current/past shifts
   - ✅ Tariff user creates snapshot → level stored, supplements read-only
   - ✅ Custom user creates snapshot → wage_level is NULL
   - ✅ Date conflict validation → shows error
   - ✅ Series ghosts → use correct snapshot based on shift_date
   - ✅ Single shifts → use correct snapshot based on shift_date
   - ✅ Multi-month view → each month's shifts use correct snapshot

3. **Edge case testing**:
   - User with no snapshots (shouldn't happen after migration, but handle gracefully)
   - Shift before earliest snapshot (use earliest)
   - Shift after latest snapshot (use latest)
   - Same-day wage change (conflict validation)
   - Deleting the only snapshot (should warn/block?)

### Verification
- All test scenarios pass
- No console errors
- Shift calculations are accurate
- Cache invalidation works

### Files to Create/Modify
- **MODIFY**: `lib/revalidation/paths.ts` (if needed)

---

## Summary of Files

### New Files
1. `supabase/migrations/YYYYMMDD_interval_wage_snapshots.sql`
2. `data-access/wage-snapshots.ts`
3. `app/[locale]/(app)/settings/pay/_actions/wage-snapshots.ts`
4. `components/settings/pay/WageHistoryModal.tsx`
5. `components/settings/pay/WageHistoryList.tsx`

### Modified Files
1. `lib/payroll/calc.ts` (add snapshot parameter)
2. `data-access/shifts.ts` (fetch snapshots, pass to computeShift)
3. `app/[locale]/(app)/settings/pay/page.tsx` (new UI layout)
4. `lib/i18n/dictionaries/no.ts` (translations)
5. `lib/i18n/dictionaries/en.ts` (translations)
6. `lib/validation/shift-validators.ts` (possibly add helpers)
7. `lib/errors/messages.ts` (add error messages)
8. `lib/revalidation/paths.ts` (ensure proper cache clearing)

---

## Implementation Order

Complete phases in order:
1. **Phase 1**: Database foundation
2. **Phase 2**: Data layer (enables correct calculations)
3. **Phase 3**: Server actions (enables UI to save changes)
4. **Phase 4**: List UI (enables viewing wage history)
5. **Phase 5**: Modal UI (enables editing wage history)
6. **Phase 6**: Translations (polish)
7. **Phase 7**: Testing & verification (ensure correctness)

Each phase should be completed and verified before moving to the next.
