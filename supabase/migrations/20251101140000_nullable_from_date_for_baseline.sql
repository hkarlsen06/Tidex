-- ============================================================================
-- Allow NULL from_date for Baseline Wage Snapshot
-- ============================================================================
-- This migration allows the first wage snapshot to have a NULL from_date,
-- which serves as the baseline/starting point for all wage calculations.
--
-- Concept:
-- - The baseline snapshot (from_date = NULL) applies to ALL shifts that don't
--   match any later dated snapshot
-- - All subsequent snapshots have explicit dates marking when wage changes occurred
-- - Each user must have exactly ONE baseline snapshot
-- - Users can edit the baseline but cannot delete it if other snapshots exist
-- ============================================================================

-- ============================================================================
-- Step 1: Drop existing constraint and make from_date nullable
-- ============================================================================

-- Drop the unique constraint that requires from_date
alter table public.wage_snapshots
  drop constraint if exists unique_user_date;

-- Make from_date nullable
alter table public.wage_snapshots
  alter column from_date drop not null;

-- ============================================================================
-- Step 2: Create new constraints for baseline snapshot
-- ============================================================================

-- Ensure each user has at most ONE baseline snapshot (from_date IS NULL)
create unique index if not exists idx_wage_snapshots_baseline
  on public.wage_snapshots(user_id)
  where from_date is null;

-- Ensure each user has at most ONE snapshot per date (for dated snapshots)
create unique index if not exists idx_wage_snapshots_unique_date
  on public.wage_snapshots(user_id, from_date)
  where from_date is not null;

-- ============================================================================
-- Step 3: Update existing snapshots to use NULL baseline
-- ============================================================================
-- Convert the earliest snapshot for each user to be the baseline (from_date = NULL)

do $$
begin
  -- For each user, find their earliest snapshot and set from_date to NULL
  update public.wage_snapshots ws1
  set from_date = null
  where ws1.id in (
    select distinct on (user_id) id
    from public.wage_snapshots
    order by user_id, from_date asc nulls first
  )
  and ws1.from_date is not null;
end $$;

-- ============================================================================
-- Step 4: Update index for efficient lookups
-- ============================================================================

-- Drop old index
drop index if exists public.idx_wage_snapshots_lookup;

-- Create new index that handles NULL from_date
-- Query pattern for dated snapshots: WHERE user_id = ? AND from_date <= ? ORDER BY from_date DESC LIMIT 1
-- Query pattern for baseline: WHERE user_id = ? AND from_date IS NULL
create index if not exists idx_wage_snapshots_lookup
  on public.wage_snapshots(user_id, from_date desc nulls last);

-- ============================================================================
-- Migration Complete
-- ============================================================================
-- Next steps:
-- 1. Update getSnapshotForDate to use NULL from_date as fallback
-- 2. Update validation to ensure only one baseline per user
-- 3. Update UI to show baseline snapshot differently
-- 4. Update deletion logic to prevent deleting baseline if other snapshots exist
-- ============================================================================
