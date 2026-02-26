# Multi-Job Support — Implementation Plan

> **Goal:** Allow users to track shifts across multiple jobs/employers, each with independent wage rules, tariffs, supplements, and payroll settings.

## Table of Contents

- [Design Principles](#design-principles)
- [Backward Compatibility Contract](#backward-compatibility-contract)
- [Current State Summary](#current-state-summary)
- [Phase 1: Database Schema](#phase-1-database-schema)
- [Phase 2: Backend Services & Sync](#phase-2-backend-services--sync)
- [Phase 3: iOS App Changes](#phase-3-ios-app-changes)
- [Phase 4: Next.js App Changes](#phase-4-nextjs-app-changes)
- [Phase 5: UI — Job Management](#phase-5-ui--job-management)
- [Phase 6: UI — Filtering & Aggregation](#phase-6-ui--filtering--aggregation)
- [Rollout Gates (Backwards Compatibility)](#rollout-gates-backwards-compatibility)
- [Edge Cases & Open Questions](#edge-cases--open-questions)
- [File Impact Reference](#file-impact-reference)

---

## Design Principles

1. **Invisible for single-job users.** The multi-job concept stays hidden until a user explicitly adds a second job. A default job is auto-created; all existing flows work unchanged.
2. **Jobs own wages, shifts own jobs.** A `job` is the organizing unit between users and their shifts/snapshots. Wage configuration is per-job, not per-user.
3. **Backwards-compatible migration.** Existing data migrates to a default job with zero behavior change.
4. **Progressive complexity.** Job management is additive UI — no existing screens are removed or reorganized for single-job users.

## Backward Compatibility Contract

This is non-negotiable for rollout safety:

1. **Legacy writes must keep working.** Older iOS/web clients that do not send `job_id` must still be able to insert/update `user_shifts`, `recurring_shifts`, and `wage_snapshots`.
2. **Legacy settings contract stays live.** `user_settings.payroll_day`, `user_settings.half_tax_month`, and `user_settings.monthly_goal` must remain readable/writable during a compatibility window.
3. **Additive payload changes only.** Shared SQL payloads must keep existing keys and add new `job` fields without removing old `settings` keys.
4. **No destructive schema removal in V1.** Do not drop legacy columns or legacy behavior until telemetry confirms migration to job-aware clients.
5. **Order matters.** Deploy DB compatibility layer first, then ship app changes, then enforce stricter constraints.

---

## Current State Summary

### Database tables affected

| Table | Rows | Current scope | Change needed |
|-------|------|---------------|---------------|
| `user_shifts` | 886 | `user_id` only | Add `job_id` FK |
| `recurring_shifts` | 10 | `user_id` only | Add `job_id` FK |
| `wage_snapshots` | 64 | `user_id` only | Add `job_id` FK |
| `user_settings` | 54 | `user_id` only | Keep legacy fields during compatibility window (dual-write with default `jobs` row) |

### Fields that become job-scoped (while staying mirrored on `user_settings` for legacy clients)

| Field | Why it's job-specific |
|-------|----------------------|
| `payroll_day` | Different employers pay on different days |
| `half_tax_month` | Half-tax applies per employment contract |
| `monthly_goal` | Users set income targets per job |

### Fields that stay on `user_settings` (user-global)

`theme`, `currency`, `default_shifts_view`, `calendar_animation_style`, `profile_picture_url`, `last_active`, `monthly_goals_by_month`

### Unique constraints affected

| Index | Current definition | New definition needed |
|-------|-------------------|----------------------|
| `idx_wage_snapshots_baseline` | `UNIQUE (user_id) WHERE from_date IS NULL` | `UNIQUE (user_id, job_id) WHERE from_date IS NULL` |
| `idx_wage_snapshots_unique_date` | `UNIQUE (user_id, from_date) WHERE from_date IS NOT NULL` | `UNIQUE (user_id, job_id, from_date) WHERE from_date IS NOT NULL` |

Compatibility note: old indexes must not be removed until `job_id` is fully backfilled and insert triggers are live.

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

### Triggers (new required compatibility triggers)
- Existing `set_updated_at_revision` triggers remain.
- Add `job_id` assignment/ownership triggers on `user_shifts`, `recurring_shifts`, `wage_snapshots`.
- Add dual-write mirror triggers between default `jobs` row and legacy `user_settings` payroll fields.

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
  archived_at timestamptz DEFAULT NULL,
  deleted_at  timestamptz DEFAULT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  revision    bigint NOT NULL DEFAULT 1
);

-- Each user can have at most one default job
CREATE UNIQUE INDEX idx_jobs_default
  ON public.jobs (user_id)
  WHERE is_default = true AND deleted_at IS NULL AND archived_at IS NULL;

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

### 1.3 Add compatibility helper + `job_id` assignment triggers (required before NOT NULL)

```sql
-- Guarantees every user has exactly one active default job when needed
CREATE OR REPLACE FUNCTION public.ensure_default_job(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
BEGIN
  SELECT j.id INTO v_job_id
  FROM public.jobs j
  WHERE j.user_id = p_user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
  LIMIT 1;

  IF v_job_id IS NULL THEN
    INSERT INTO public.jobs (user_id, name, is_default)
    VALUES (p_user_id, 'Jobb', true)
    ON CONFLICT DO NOTHING;

    SELECT j.id INTO v_job_id
    FROM public.jobs j
    WHERE j.user_id = p_user_id
      AND j.is_default = true
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
    LIMIT 1;
  END IF;

  RETURN v_job_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_job_id_and_validate_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.job_id IS NULL THEN
    NEW.job_id := public.ensure_default_job(NEW.user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.jobs j
    WHERE j.id = NEW.job_id
      AND j.user_id = NEW.user_id
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'job_id must belong to same user';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER user_shifts_assign_job_id
  BEFORE INSERT OR UPDATE OF user_id, job_id ON public.user_shifts
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_job_id_and_validate_owner();

CREATE TRIGGER recurring_shifts_assign_job_id
  BEFORE INSERT OR UPDATE OF user_id, job_id ON public.recurring_shifts
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_job_id_and_validate_owner();

CREATE TRIGGER wage_snapshots_assign_job_id
  BEFORE INSERT OR UPDATE OF user_id, job_id ON public.wage_snapshots
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_job_id_and_validate_owner();
```

### 1.4 Migrate existing data

```sql
-- Create default jobs for every user that already has data in any affected table
WITH all_user_ids AS (
  SELECT user_id FROM public.user_settings
  UNION
  SELECT user_id FROM public.user_shifts
  UNION
  SELECT user_id FROM public.recurring_shifts
  UNION
  SELECT user_id FROM public.wage_snapshots
)
INSERT INTO public.jobs (user_id, name, is_default, payroll_day, half_tax_month, monthly_goal)
SELECT
  u.user_id,
  'Jobb',
  true,
  COALESCE(us.payroll_day, 15),
  us.half_tax_month,
  COALESCE(us.monthly_goal, 20000)
FROM all_user_ids u
LEFT JOIN public.user_settings us ON us.user_id = u.user_id
WHERE NOT EXISTS (
  SELECT 1
  FROM public.jobs j
  WHERE j.user_id = u.user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
);

-- Backfill rows created before triggers existed
UPDATE public.user_shifts s
SET job_id = public.ensure_default_job(s.user_id)
WHERE s.job_id IS NULL;

UPDATE public.recurring_shifts r
SET job_id = public.ensure_default_job(r.user_id)
WHERE r.job_id IS NULL;

UPDATE public.wage_snapshots w
SET job_id = public.ensure_default_job(w.user_id)
WHERE w.job_id IS NULL;
```

### 1.5 Set `job_id` NOT NULL (after compatibility triggers + backfill)

```sql
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.user_shifts WHERE job_id IS NULL) THEN
    RAISE EXCEPTION 'user_shifts still has NULL job_id';
  END IF;
  IF EXISTS (SELECT 1 FROM public.recurring_shifts WHERE job_id IS NULL) THEN
    RAISE EXCEPTION 'recurring_shifts still has NULL job_id';
  END IF;
  IF EXISTS (SELECT 1 FROM public.wage_snapshots WHERE job_id IS NULL) THEN
    RAISE EXCEPTION 'wage_snapshots still has NULL job_id';
  END IF;
END $$;

ALTER TABLE public.user_shifts ALTER COLUMN job_id SET NOT NULL;
ALTER TABLE public.recurring_shifts ALTER COLUMN job_id SET NOT NULL;
ALTER TABLE public.wage_snapshots ALTER COLUMN job_id SET NOT NULL;
```

### 1.6 Update unique constraints on `wage_snapshots` (safe order)

```sql
-- Create new indexes first (temporary names)
CREATE UNIQUE INDEX idx_wage_snapshots_baseline_job
  ON public.wage_snapshots (user_id, job_id)
  WHERE from_date IS NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX idx_wage_snapshots_unique_date_job
  ON public.wage_snapshots (user_id, job_id, from_date)
  WHERE from_date IS NOT NULL AND deleted_at IS NULL;

-- Remove old user-only uniqueness constraints
DROP INDEX IF EXISTS idx_wage_snapshots_baseline;
DROP INDEX IF EXISTS idx_wage_snapshots_unique_date;

-- Keep canonical index names expected by existing tooling/docs
ALTER INDEX idx_wage_snapshots_baseline_job RENAME TO idx_wage_snapshots_baseline;
ALTER INDEX idx_wage_snapshots_unique_date_job RENAME TO idx_wage_snapshots_unique_date;
```

### 1.7 RLS policies for `jobs`

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
  FOR INSERT TO authenticated
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

### 1.8 Triggers for `jobs`

```sql
-- Reuse existing trigger function
CREATE TRIGGER set_updated_at_revision
  BEFORE UPDATE ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_and_revision();
```

### 1.9 Update `handle_new_user` to create default job

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

### 1.10 Update `prepare_user_for_deletion`

Add `DELETE FROM public.jobs WHERE user_id = target_user_id;` to the cleanup sequence (before cascade deletes the rest).

### 1.11 Keep legacy `user_settings` fields in sync during compatibility window

```sql
-- OLD CLIENTS -> NEW MODEL
-- When legacy clients update payroll fields on user_settings, mirror them to default job.
CREATE OR REPLACE FUNCTION public.sync_legacy_settings_to_default_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  v_job_id := public.ensure_default_job(NEW.user_id);

  UPDATE public.jobs
  SET payroll_day = NEW.payroll_day,
      half_tax_month = NEW.half_tax_month,
      monthly_goal = NEW.monthly_goal
  WHERE id = v_job_id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER user_settings_mirror_to_jobs
  AFTER INSERT OR UPDATE OF payroll_day, half_tax_month, monthly_goal
  ON public.user_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_legacy_settings_to_default_job();

-- NEW MODEL -> OLD CLIENTS
-- When default job payroll fields change, mirror back to user_settings so old apps still read correct values.
CREATE OR REPLACE FUNCTION public.sync_default_job_to_legacy_settings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  IF NEW.is_default = true THEN
    -- Update only existing user_settings rows to avoid creating partial rows
    -- that might violate required-column/default assumptions.
    UPDATE public.user_settings
    SET payroll_day = NEW.payroll_day,
        half_tax_month = NEW.half_tax_month,
        monthly_goal = NEW.monthly_goal
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER jobs_mirror_to_user_settings
  AFTER INSERT OR UPDATE OF payroll_day, half_tax_month, monthly_goal, is_default
  ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_default_job_to_legacy_settings();
```

Do **not** drop `payroll_day`, `half_tax_month`, or `monthly_goal` from `user_settings` in V1.

---

## Phase 2: Backend Services & Sync

### 2.1 Update SQL functions

- [ ] **`get_shared_month_payload`** — Add `job_id` to shift/recurring/snapshot JSON projections and add `jobs` array. Keep existing `settings` keys (`payroll_day`, `half_tax_month`, `monthly_goal`) for old clients.
- [ ] **`get_my_sharer_preview_payloads`** — Same additive strategy as above (no key removals).
- [ ] **`get_shifts_due_for_reminder`** — Join `jobs` for `job_name`, with safe fallback to default label if job metadata is missing.

### 2.2 Update iOS sync engine

**Files:**
- `ios/TidexApp/Storage/Sync/SyncCoordinator.swift`
- `ios/TidexApp/Storage/Sync/SyncServerModels.swift`

**Changes:**
- [ ] Add new sync table for `jobs` — fetch from `public.jobs`, store as `LocalJob` (new SwiftData model)
- [ ] Sync `jobs` before shifts/snapshots (jobs must exist before FK references)
- [ ] Add `job_id` to `SyncShiftRow`, `SyncRecurringShiftRow`, `SyncWageSnapshotRow` (decode as optional during rollout; resolve nil to default job)
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
- [ ] Update payroll calculation to read `payroll_day` from job with fallback to mirrored legacy `user_settings.payroll_day`
- [ ] Keep `SettingsService` dual-write compatibility for default job fields during transition
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
- [ ] Keep server-side compatibility when `job_id` is omitted (DB trigger fills default job)
- [ ] Add job-scoped validation where needed

**Files (under `next/app/[locale]/(app)/settings/pay/_actions/`):**
- `wage-snapshots.ts`

**Changes:**
- [ ] Add `job_id` to snapshot creation/update
- [ ] Keep server-side compatibility when `job_id` is omitted (DB trigger fills default job)
- [ ] Update `checkExistingSnapshot` to be job-scoped

---

## Phase 3: iOS App Changes

### 3.1 New models

- [ ] Create `Job.swift` — Codable struct matching DB schema
- [ ] Create `LocalJob.swift` — SwiftData `@Model` with sync metadata
- [ ] Add `JobField` enum to `SyncTypes.swift`

### 3.2 Update existing models

**Files:**
- `ios/TidexApp/Models/Shift.swift` — Add `job_id` to `ShiftRow` and `CodingKeys` (decode defensively for rollout)
- `ios/TidexApp/Models/WageSnapshot.swift` — Add `job_id` (decode defensively for rollout)
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
- [ ] Read `payroll_day` from job context, with fallback to mirrored legacy `user_settings` values

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
- The sharing SQL functions (updated in Phase 2.1) will provide job context while preserving existing settings keys

---

## Phase 5: UI — Job Management

### 5.1 Job settings page

- [ ] New settings section (or page) for managing jobs
- [ ] Create/edit/archive/delete jobs
- [ ] Set job name, color, payroll_day, half_tax_month, monthly_goal
- [ ] Reorder jobs (sort_order)
- [ ] Cannot delete the last/default job (guard)
- [ ] Archived jobs are hidden from Add Shift pickers but remain visible in historical views

### 5.2 Job selector in shift creation

- [ ] Add job picker to `AddShiftCoordinator` (iOS) and add-shift page (Next.js)
- [ ] If user has exactly one active job, assign it automatically
- [ ] If user has 2+ active jobs, show picker and require explicit selection before save
- [ ] Keep picker hidden for single-job users (invisible by default)

### 5.3 Job indicator on shift cards

- [ ] Color dot or badge on `ShiftRowCard` (iOS) and shift list items (Next.js)
- [ ] Only show if user has 2+ jobs
- [ ] Calendar day outline rendering for mixed-job days:
  - split top-to-bottom by all jobs present that day
  - top segment = earliest shift job color
  - bottom segment = latest shift job color

### 5.4 Onboarding

- [ ] When a new user sets up their wage for the first time, they're implicitly configuring their default job
- [ ] No changes to the initial onboarding flow unless user explicitly adds a second job

---

## Phase 6: UI — Filtering & Aggregation

### 6.1 Job filter in shift views

- [ ] V1: filter bar/pill in **Shifts list** only (defer calendar filtering)
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
- [ ] UI source of truth for pay settings moves to job settings (while DB keeps legacy mirrored fields for old clients)

---

## Rollout Gates (Backwards Compatibility)

1. **Gate A: DB compatibility layer live**
   - `jobs` exists
   - `job_id` columns exist
   - assignment triggers + mirror triggers exist
   - backfill complete (`NULL job_id` count = 0)
2. **Gate B: legacy client smoke pass**
   - old iOS build can still create/edit/delete shift
   - old iOS build can still create/edit wage snapshot
   - old iOS build can still change `payroll_day`/`half_tax_month`/`monthly_goal`
3. **Gate C: new app rollout**
   - new iOS/web writes explicit `job_id`
   - job-aware UI/features enabled
4. **Gate D: deprecation (future, not V1)**
   - only after telemetry/version floor is met, remove mirror triggers and legacy fields

---

## Edge Cases & Open Questions

### Decided

| Question | Decision |
|----------|----------|
| What happens when a user deletes a job with existing shifts? | Soft-delete the job. Shifts remain but are hidden from active views. User can reassign shifts before deletion. |
| Do we support both archive and delete? | Yes. Archive (`archived_at`) hides job from Add Shift pickers; delete is soft-delete (`deleted_at`). |
| Can shifts exist without a job? | No. `job_id NOT NULL` after migration. |
| Is workplace/job selection mandatory? | Yes. With 2+ active jobs, user must explicitly pick one before save; with 1 active job it is auto-assigned. |
| What's the default job name? | "Jobb" (Norwegian). User can rename immediately. |
| How does sharing work with multiple jobs? | Share access is still user-level (all jobs). Shared views show job names as context. |
| How are recurring shifts assigned? | A recurring pattern and all generated virtual shifts belong to one job (no per-occurrence override). |
| Where does V1 filtering apply? | Shifts list only. Calendar filtering is deferred. |
| How are mixed-job calendar days visualized? | Day outline is split top-to-bottom from earliest shift color to latest shift color. |
| How do old clients continue to work? | DB compatibility triggers assign default `job_id` on missing writes and mirror payroll fields between default job and `user_settings`. |

### Open (decide before implementation)

- [ ] **Per-job notification preferences?** — Should shift reminders be configurable per job, or remain global? (Recommendation: keep global initially, per-job later.)
- [ ] **Job-scoped shift sharing?** — Should users be able to share only specific jobs? (Recommendation: defer — keep user-level sharing initially.)
- [ ] **Tax across jobs** — Norwegian tax brackets apply to combined income. Should the app show a combined tax view? (Recommendation: defer — show per-job tax for now, aggregate later.)
- [ ] **Maximum number of jobs** — Should we cap it? (Recommendation: cap at 10 to keep UI clean.)
- [ ] **Legacy deprecation gate** — What exact telemetry threshold and app-version floor must be met before removing mirrored `user_settings` fields/triggers?

---

## File Impact Reference

### Database / Supabase

| File / Resource | Type of change |
|----------------|----------------|
| New migration: `create_jobs_table` | DDL (includes `archived_at`) |
| New migration: `add_job_id_columns` | DDL + compatibility triggers + data migration |
| New migration: `update_wage_snapshot_constraints` | DDL |
| New SQL function: `ensure_default_job` | Compatibility helper |
| New SQL trigger fn: `assign_job_id_and_validate_owner` | Compatibility + integrity |
| New SQL trigger fn: `sync_legacy_settings_to_default_job` | Legacy mirror |
| New SQL trigger fn: `sync_default_job_to_legacy_settings` | Legacy mirror |
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
| `next/lib/services/settings.ts` | Keep legacy field compatibility + dual-write bridge |
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
