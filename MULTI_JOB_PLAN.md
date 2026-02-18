# Multi-Job Support — Implementation Plan

> **Goal:** Allow users to track shifts across multiple jobs/employers, each with independent wage rules, tariffs, supplements, and payroll settings.

## Table of Contents

- [Design Principles](#design-principles)
- [Current State Summary](#current-state-summary)
- [Phase 1: Database Schema](#phase-1-database-schema)
- [Phase 2: Backend Services & Sync](#phase-2-backend-services--sync)
- [Phase 3: iOS App Changes](#phase-3-ios-app-changes)
- [Phase 4: Next.js App Changes](#phase-4-nextjs-app-changes)
- [Phase 5: UI — Job Management](#phase-5-ui--job-management)
- [Phase 6: UI — Filtering & Aggregation](#phase-6-ui--filtering--aggregation)
- [Edge Cases & Open Questions](#edge-cases--open-questions)
- [File Impact Reference](#file-impact-reference)

---

## Design Principles

1. **Invisible for single-job users.** The multi-job concept stays hidden until a user explicitly adds a second job. A default job is auto-created; all existing flows work unchanged.
2. **Jobs own wages, shifts own jobs.** A `job` is the organizing unit between users and their shifts/snapshots. Wage configuration is per-job, not per-user.
3. **Backwards-compatible migration.** Existing data migrates to a default job with zero behavior change.
4. **Progressive complexity.** Job management is additive UI — no existing screens are removed or reorganized for single-job users.

---

## Current State Summary

### Database tables affected

| Table | Rows | Current scope | Change needed |
|-------|------|---------------|---------------|
| `user_shifts` | 886 | `user_id` only | Add `job_id` FK |
| `recurring_shifts` | 10 | `user_id` only | Add `job_id` FK |
| `wage_snapshots` | 64 | `user_id` only | Add `job_id` FK |
| `user_settings` | 54 | `user_id` only | Move job-specific fields to `jobs` |

### Fields that move from `user_settings` to `jobs`

| Field | Why it's job-specific |
|-------|----------------------|
| `payroll_day` | Different employers pay on different days |
| `half_tax_month` | Half-tax applies per employment contract |
| `monthly_goal` | Users set income targets per job |

### Fields that stay on `user_settings` (user-global)

`theme`, `currency`, `default_shifts_view`, `calendar_animation_style`, `profile_picture_url`, `last_active`

### Unique constraints affected

| Index | Current definition | New definition needed |
|-------|-------------------|----------------------|
| `idx_wage_snapshots_baseline` | `UNIQUE (user_id) WHERE from_date IS NULL` | `UNIQUE (user_id, job_id) WHERE from_date IS NULL` |
| `idx_wage_snapshots_unique_date` | `UNIQUE (user_id, from_date) WHERE from_date IS NOT NULL` | `UNIQUE (user_id, job_id, from_date) WHERE from_date IS NOT NULL` |

### RLS policies affected (all reference `user_id = auth.uid()` — no change needed for auth, but shared-shifts policies need `job_id` projection):
- `user_shifts`: 5 policies (SELECT includes shift_shares join)
- `recurring_shifts`: 5 policies (SELECT includes shift_shares join)
- `wage_snapshots`: 5 policies (SELECT includes shift_shares join)

### SQL functions affected

| Function | Change needed |
|----------|---------------|
| `get_shared_month_payload` | Add `job_id` to shift/recurring/snapshot JSON projections; optionally include job metadata |
| `get_my_sharer_preview_payloads` | Same as above |
| `get_shifts_due_for_reminder` | Add `job_id` to results (for job name in notification body) |
| `handle_new_user` | Create default job for new users |
| `prepare_user_for_deletion` | Delete user's jobs |
| `user_has_any_shifts` | No change needed (still user-scoped) |
| `user_has_shift_in_month` | No change needed |

### Triggers (no changes needed)
- `set_updated_at_revision` on `user_shifts`, `recurring_shifts`, `wage_snapshots`, `user_settings` — generic, column-agnostic

---

## Phase 1: Database Schema

### 1.1 Create `jobs` table

```sql
CREATE TABLE public.jobs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 100),
  color       text DEFAULT NULL CHECK (color IS NULL OR color ~ '^#[0-9a-fA-F]{6}$'),
  is_default  boolean NOT NULL DEFAULT false,
  sort_order  smallint NOT NULL DEFAULT 0,

  -- Fields migrated from user_settings
  payroll_day           integer CHECK (payroll_day >= 1 AND payroll_day <= 31) DEFAULT 15,
  half_tax_month        integer CHECK ((half_tax_month = ANY (ARRAY[11, 12])) OR half_tax_month IS NULL),
  monthly_goal          integer DEFAULT 20000,

  -- Sync metadata
  deleted_at  timestamptz DEFAULT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  revision    bigint NOT NULL DEFAULT 1
);

-- Each user can have at most one default job
CREATE UNIQUE INDEX idx_jobs_default
  ON public.jobs (user_id)
  WHERE is_default = true AND deleted_at IS NULL;

CREATE INDEX idx_jobs_user_id ON public.jobs (user_id);
CREATE INDEX idx_jobs_user_revision ON public.jobs (user_id, revision);
```

### 1.2 Add `job_id` to core tables

```sql
-- user_shifts
ALTER TABLE public.user_shifts
  ADD COLUMN job_id uuid REFERENCES public.jobs(id);

CREATE INDEX idx_user_shifts_job_id ON public.user_shifts (job_id);

-- recurring_shifts
ALTER TABLE public.recurring_shifts
  ADD COLUMN job_id uuid REFERENCES public.jobs(id);

CREATE INDEX idx_recurring_shifts_job_id ON public.recurring_shifts (job_id);

-- wage_snapshots
ALTER TABLE public.wage_snapshots
  ADD COLUMN job_id uuid REFERENCES public.jobs(id);

CREATE INDEX idx_wage_snapshots_job_id ON public.wage_snapshots (job_id);
```

### 1.3 Migrate existing data

```sql
-- Create a default job for every user who has any data
INSERT INTO public.jobs (user_id, name, is_default, payroll_day, half_tax_month, monthly_goal)
SELECT DISTINCT
  u.user_id,
  'Jobb',  -- Norwegian default name
  true,
  COALESCE(u.payroll_day, 15),
  u.half_tax_month,
  COALESCE(u.monthly_goal, 20000)
FROM public.user_settings u;

-- Assign all existing shifts to default job
UPDATE public.user_shifts us
SET job_id = j.id
FROM public.jobs j
WHERE j.user_id = us.user_id AND j.is_default = true;

-- Assign all existing recurring shifts
UPDATE public.recurring_shifts rs
SET job_id = j.id
FROM public.jobs j
WHERE j.user_id = rs.user_id AND j.is_default = true;

-- Assign all existing wage snapshots
UPDATE public.wage_snapshots ws
SET job_id = j.id
FROM public.jobs j
WHERE j.user_id = ws.user_id AND j.is_default = true;
```

### 1.4 Add NOT NULL constraint (after migration)

```sql
ALTER TABLE public.user_shifts ALTER COLUMN job_id SET NOT NULL;
ALTER TABLE public.recurring_shifts ALTER COLUMN job_id SET NOT NULL;
ALTER TABLE public.wage_snapshots ALTER COLUMN job_id SET NOT NULL;
```

### 1.5 Update unique constraints on `wage_snapshots`

```sql
-- Drop old constraints
DROP INDEX IF EXISTS idx_wage_snapshots_baseline;
DROP INDEX IF EXISTS idx_wage_snapshots_unique_date;

-- Create new job-scoped constraints
CREATE UNIQUE INDEX idx_wage_snapshots_baseline
  ON public.wage_snapshots (user_id, job_id)
  WHERE from_date IS NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX idx_wage_snapshots_unique_date
  ON public.wage_snapshots (user_id, job_id, from_date)
  WHERE from_date IS NOT NULL AND deleted_at IS NULL;
```

### 1.6 RLS policies for `jobs`

```sql
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;

-- Users can read own jobs (or jobs of people who share with them)
CREATE POLICY "Users can view own or shared jobs" ON public.jobs
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.shift_shares ss
      WHERE ss.owner_id = jobs.user_id
        AND ss.viewer_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own jobs" ON public.jobs
  FOR INSERT TO public
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own jobs" ON public.jobs
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own jobs" ON public.jobs
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- MFA enforcement (match existing pattern)
CREATE POLICY "Require MFA for users who enrolled" ON public.jobs
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (check_mfa_aal());
```

### 1.7 Triggers for `jobs`

```sql
-- Reuse existing trigger function
CREATE TRIGGER set_updated_at_revision
  BEFORE UPDATE ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_and_revision();
```

### 1.8 Update `handle_new_user` to create default job

```sql
-- Updated handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id) VALUES (new.id)
    ON CONFLICT (id) DO NOTHING;

  -- Create default job for new user
  INSERT INTO public.jobs (user_id, name, is_default)
  VALUES (new.id, 'Jobb', true)
  ON CONFLICT DO NOTHING;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 1.9 Update `prepare_user_for_deletion`

Add `DELETE FROM public.jobs WHERE user_id = target_user_id;` to the cleanup sequence (before cascade deletes the rest).

---

## Phase 2: Backend Services & Sync

### 2.1 Update SQL functions

- [ ] **`get_shared_month_payload`** — Add `job_id` to `jsonb_build_object(...)` for shifts, recurring_shifts, and snapshots. Add a `jobs` field to the result containing the owner's jobs array.
- [ ] **`get_my_sharer_preview_payloads`** — Same changes as above.
- [ ] **`get_shifts_due_for_reminder`** — Join `jobs` to include `job_name` in results so notification text can say "Shift at Coop Extra in 1 hour".

### 2.2 Update iOS sync engine

**Files:**
- `ios/TidexApp/Storage/Sync/SyncCoordinator.swift`
- `ios/TidexApp/Storage/Sync/SyncServerModels.swift`

**Changes:**
- [ ] Add new sync table for `jobs` — fetch from `public.jobs`, store as `LocalJob` (new SwiftData model)
- [ ] Sync `jobs` before shifts/snapshots (jobs must exist before FK references)
- [ ] Add `job_id` to `SyncShiftRow`, `SyncRecurringShiftRow`, `SyncWageSnapshotRow`
- [ ] Add `SyncJobRow` server model

### 2.3 Update Next.js services

**Files:**
- `next/lib/services/shifts.ts` — `ShiftsService`
- `next/lib/services/settings.ts` — `SettingsService`
- `next/data-access/shifts.ts`
- `next/data-access/wage-snapshots.ts`
- `next/data-access/stats.ts`

**Changes:**
- [ ] Add `JobsService` Effect service — CRUD for jobs
- [ ] Add `jobs` DAL (`next/data-access/jobs.ts`)
- [ ] Update `ShiftsService.getShiftsWithComputations()` to accept optional `jobId` filter
- [ ] Update snapshot lookup to be job-scoped: `getSnapshotsForDates(userId, jobId, dates)`
- [ ] Update payroll calculation to read `payroll_day` from job instead of user_settings
- [ ] Update stats queries to support per-job and aggregated views

### 2.4 Update payroll engine

**Files:**
- `next/lib/payroll/calc.ts`
- `next/lib/payroll/types.ts`

**Changes:**
- [ ] Add `job_id` to `ShiftRow` type
- [ ] Add `Job` type with `payroll_day`, `half_tax_month`, `monthly_goal`
- [ ] Update `computeShift()` to accept job context (for payroll_day-based tax snapshot lookup)

### 2.5 Update server actions

**Files (all under `next/app/[locale]/(app)/shifts/_actions/`):**
- `updateShift.ts`, `deleteShift.ts`
- `updateRecurringShift.ts`, `deleteRecurringShift.ts`
- `updateCustomSupplements.ts`
- `convertRecurringShiftToStandalone.ts`
- `moveRecurringShift.ts`, `copyShifts.ts`

**Changes:**
- [ ] Include `job_id` in shift creation/update payloads
- [ ] Add job-scoped validation where needed

**Files (under `next/app/[locale]/(app)/settings/pay/_actions/`):**
- `wage-snapshots.ts`

**Changes:**
- [ ] Add `job_id` to snapshot creation/update
- [ ] Update `checkExistingSnapshot` to be job-scoped

---

## Phase 3: iOS App Changes

### 3.1 New models

- [ ] Create `Job.swift` — Codable struct matching DB schema
- [ ] Create `LocalJob.swift` — SwiftData `@Model` with sync metadata
- [ ] Add `JobField` enum to `SyncTypes.swift`

### 3.2 Update existing models

**Files:**
- `ios/TidexApp/Models/Shift.swift` — Add `job_id` to `ShiftRow` and `CodingKeys`
- `ios/TidexApp/Models/WageSnapshot.swift` — Add `job_id`
- `ios/TidexApp/Storage/Models/LocalUserShift.swift` — Add `jobId` property, update `UserShiftServerSnapshot`, update `UserShiftField` enum
- `ios/TidexApp/Storage/Models/LocalRecurringShift.swift` — Add `jobId`, update snapshot and field enum
- `ios/TidexApp/Storage/Models/LocalWageSnapshot.swift` — Add `jobId`, update snapshot and field enum

### 3.3 Update repositories

**Files:**
- `ios/TidexApp/Storage/Repositories/ShiftsRepository.swift` — Accept `jobId` in create/query methods
- `ios/TidexApp/Storage/Repositories/RecurringShiftsRepository.swift` — Same
- `ios/TidexApp/Storage/Repositories/SnapshotsRepository.swift` — Make `snapshotForDate` job-scoped, update `getBaselineSnapshot(jobId:)`

### 3.4 Update payroll engine (iOS)

**Files:**
- `ios/TidexApp/Services/Payroll/WagePeriodBuilder.swift`
- `ios/TidexApp/Services/Payroll/BreakDeduction.swift`

**Changes:**
- [ ] Read `payroll_day` from job context instead of user settings

### 3.5 Update iOS widget / complications

- [ ] Ensure watch complications and widgets pass `job_id` context or show aggregate data

---

## Phase 4: Next.js App Changes

### 4.1 Update type definitions

**Files:**
- `next/lib/payroll/types.ts` — Add `job_id` to `ShiftRow`, `WageSnapshot`; add `Job` type
- `next/lib/types/` — Add shared `Job` type if not already in payroll types

### 4.2 Update pages (data fetching)

| Page | File | Change |
|------|------|--------|
| Dashboard | `next/app/[locale]/(app)/dashboard/page.tsx` | Fetch jobs, pass to view for filtering |
| Shifts | `next/app/[locale]/(app)/shifts/page.tsx` | Accept job filter param, pass to `getComputedShifts` |
| Add shift | `next/app/[locale]/(app)/shifts/add/page.tsx` | Add job selector |
| Stats | `next/app/[locale]/(app)/stats/page.tsx` | Support per-job and aggregate stats |
| Pay settings | `next/app/[locale]/(app)/settings/pay/page.tsx` | Show per-job wage configuration |

### 4.3 Update shared shifts feature

**Files:**
- Components that render shared shift data need to handle `job_id` and display job names
- The sharing SQL functions (updated in Phase 2.1) will provide job context

---

## Phase 5: UI — Job Management

### 5.1 Job settings page

- [ ] New settings section (or page) for managing jobs
- [ ] Create/edit/delete jobs
- [ ] Set job name, color, payroll_day, half_tax_month, monthly_goal
- [ ] Reorder jobs (sort_order)
- [ ] Cannot delete the last/default job (guard)

### 5.2 Job selector in shift creation

- [ ] Add job picker to `AddShiftCoordinator` (iOS) and add-shift page (Next.js)
- [ ] Default to the user's default job (or last-used job)
- [ ] Only show picker if user has 2+ jobs (invisible for single-job users)

### 5.3 Job indicator on shift cards

- [ ] Color dot or badge on `ShiftRowCard` (iOS) and shift list items (Next.js)
- [ ] Only show if user has 2+ jobs

### 5.4 Onboarding

- [ ] When a new user sets up their wage for the first time, they're implicitly configuring their default job
- [ ] No changes to the initial onboarding flow unless user explicitly adds a second job

---

## Phase 6: UI — Filtering & Aggregation

### 6.1 Job filter in shift views

- [ ] Filter bar/pill in calendar and list views
- [ ] Options: "All jobs" (default), or filter to a specific job
- [ ] Persist filter preference per session (not across sessions)

### 6.2 Per-job and aggregate stats

- [ ] Stats page shows aggregate by default
- [ ] Job filter to view stats for a single job
- [ ] Monthly totals broken down by job (optional)

### 6.3 Dashboard

- [ ] Total earnings card: aggregate across all jobs
- [ ] Optional per-job breakdown row
- [ ] Payroll card: show next payout per job (different payroll_days)

### 6.4 Pay settings

- [ ] Wage snapshot timeline is per-job
- [ ] Job picker to switch between job wage histories
- [ ] Global pay settings (payroll_day, half_tax_month) move to job settings

---

## Edge Cases & Open Questions

### Decided

| Question | Decision |
|----------|----------|
| What happens when a user deletes a job with existing shifts? | Soft-delete the job. Shifts remain but are hidden from active views. User can reassign shifts before deletion. |
| Can shifts exist without a job? | No. `job_id NOT NULL` after migration. |
| What's the default job name? | "Jobb" (Norwegian). User can rename immediately. |
| How does sharing work with multiple jobs? | Share access is still user-level (all jobs). Shared views show job names as context. |

### Open (decide before implementation)

- [ ] **Per-job notification preferences?** — Should shift reminders be configurable per job, or remain global? (Recommendation: keep global initially, per-job later.)
- [ ] **Job-scoped shift sharing?** — Should users be able to share only specific jobs? (Recommendation: defer — keep user-level sharing initially.)
- [ ] **Tax across jobs** — Norwegian tax brackets apply to combined income. Should the app show a combined tax view? (Recommendation: defer — show per-job tax for now, aggregate later.)
- [ ] **Maximum number of jobs** — Should we cap it? (Recommendation: cap at 10 to keep UI clean.)
- [ ] **Job archiving** — Should users be able to archive old jobs (vs. delete)? Archived jobs hide from pickers but shifts remain visible in history. (Recommendation: yes, add `archived_at` column.)

---

## File Impact Reference

### Database / Supabase

| File / Resource | Type of change |
|----------------|----------------|
| New migration: `create_jobs_table` | DDL |
| New migration: `add_job_id_columns` | DDL + data migration |
| New migration: `update_wage_snapshot_constraints` | DDL |
| `supabase/sql/functions/sharing/get_shared_month_payload.sql` | Update SQL |
| `supabase/sql/functions/sharing/get_my_sharer_preview_payloads.sql` | Update SQL |
| `supabase/sql/functions/notification/get_shifts_due_for_reminder.sql` | Update SQL |
| `handle_new_user` function | Update SQL |
| `prepare_user_for_deletion` function | Update SQL |

### iOS (Swift)

| File | Type of change |
|------|----------------|
| **New:** `ios/TidexApp/Models/Job.swift` | New model |
| **New:** `ios/TidexApp/Storage/Models/LocalJob.swift` | New SwiftData model |
| `ios/TidexApp/Models/Shift.swift` | Add `job_id` |
| `ios/TidexApp/Models/WageSnapshot.swift` | Add `job_id` |
| `ios/TidexApp/Storage/Models/LocalUserShift.swift` | Add `jobId` + sync fields |
| `ios/TidexApp/Storage/Models/LocalRecurringShift.swift` | Add `jobId` + sync fields |
| `ios/TidexApp/Storage/Models/LocalWageSnapshot.swift` | Add `jobId` + sync fields |
| `ios/TidexApp/Storage/Sync/SyncCoordinator.swift` | Add `jobs` sync table |
| `ios/TidexApp/Storage/Sync/SyncServerModels.swift` | Add `SyncJobRow` |
| `ios/TidexApp/Storage/SyncTypes.swift` | Add `JobField` enum |
| `ios/TidexApp/Storage/Repositories/ShiftsRepository.swift` | Job-scoped queries |
| `ios/TidexApp/Storage/Repositories/RecurringShiftsRepository.swift` | Job-scoped queries |
| `ios/TidexApp/Storage/Repositories/SnapshotsRepository.swift` | Job-scoped lookups |
| **New:** `ios/TidexApp/Storage/Repositories/JobsRepository.swift` | New repository |
| `ios/TidexApp/Services/Payroll/WagePeriodBuilder.swift` | Read payroll_day from job |
| `ios/TidexApp/Features/AddShift/AddShiftCoordinator.swift` | Job picker |
| `ios/TidexApp/Features/AddShift/Models/ShiftDraft.swift` | Add `jobId` |
| `ios/TidexApp/Features/Shifts/ShiftsView.swift` | Job filter UI |
| `ios/TidexApp/Features/Shifts/ShiftsViewModel.swift` | Job filter logic |
| `ios/TidexApp/Features/Shifts/Components/ShiftRowCard.swift` | Job color indicator |
| `ios/TidexApp/Features/Shifts/Components/ShiftsCalendarView.swift` | Job filter + color dots |
| `ios/TidexApp/Features/Dashboard/DashboardViewModel.swift` | Per-job aggregation |
| `ios/TidexApp/Features/Dashboard/Components/PayrollCard.swift` | Per-job payroll dates |
| `ios/TidexApp/Features/Settings/Pay/PaySettingsView.swift` | Job picker for wage config |
| `ios/TidexApp/Features/Settings/Pay/PaySettingsViewModel.swift` | Job-scoped snapshot loading |
| `ios/TidexApp/Features/Settings/Pay/Components/GlobalPaySettingsCard.swift` | Move fields to job settings |
| `ios/TidexApp/Features/Stats/StatsViewModel.swift` | Per-job stats |
| `ios/TidexApp/Services/Data/ShiftsService.swift` | Add `job_id` to fetches |

### Next.js (TypeScript)

| File | Type of change |
|------|----------------|
| **New:** `next/data-access/jobs.ts` | New DAL |
| **New:** `next/lib/services/jobs.ts` | New Effect service |
| `next/lib/payroll/types.ts` | Add `job_id` to types, add `Job` type |
| `next/lib/payroll/calc.ts` | Accept job context |
| `next/lib/services/shifts.ts` | Job-scoped queries + snapshot lookup |
| `next/lib/services/settings.ts` | Remove job-specific field reads |
| `next/lib/services/stats.ts` | Per-job + aggregate stats |
| `next/data-access/shifts.ts` | Pass job filter |
| `next/data-access/wage-snapshots.ts` | Job-scoped snapshot CRUD |
| `next/data-access/stats.ts` | Job filter support |
| `next/app/[locale]/(app)/dashboard/page.tsx` | Fetch jobs |
| `next/app/[locale]/(app)/shifts/page.tsx` | Job filter |
| `next/app/[locale]/(app)/shifts/add/page.tsx` | Job selector |
| `next/app/[locale]/(app)/stats/page.tsx` | Job filter |
| `next/app/[locale]/(app)/settings/pay/page.tsx` | Job picker + wage per job |
| `next/app/[locale]/(app)/settings/pay/_actions/wage-snapshots.ts` | Job-scoped actions |
| `next/app/[locale]/(app)/shifts/_actions/*.ts` | Include `job_id` in payloads |

### Localization

| Key | English | Norwegian |
|-----|---------|-----------|
| `jobs.default_name` | "Job" | "Jobb" |
| `jobs.add_job` | "Add job" | "Legg til jobb" |
| `jobs.edit_job` | "Edit job" | "Rediger jobb" |
| `jobs.delete_job` | "Delete job" | "Slett jobb" |
| `jobs.all_jobs` | "All jobs" | "Alle jobber" |
| `jobs.job_name` | "Job name" | "Jobbnavn" |
| `jobs.job_color` | "Color" | "Farge" |
| *...more as UI is designed* | | |
