-- ============================================================================
-- Verification Queries for Interval-Based Wage Snapshots Migration
-- ============================================================================
-- Run these queries after applying the migration to verify everything works
-- ============================================================================

-- 1. Check that wage_snapshots table exists and has correct structure
select
  table_name,
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'wage_snapshots'
order by ordinal_position;

-- Expected output:
-- table_name        | column_name  | data_type                   | is_nullable
-- wage_snapshots    | id           | uuid                        | NO
-- wage_snapshots    | user_id      | uuid                        | NO
-- wage_snapshots    | from_date    | date                        | NO
-- wage_snapshots    | hourly_wage  | numeric                     | NO
-- wage_snapshots    | wage_level   | integer                     | YES
-- wage_snapshots    | supplements  | jsonb                       | NO
-- wage_snapshots    | created_at   | timestamp with time zone    | YES

-- ============================================================================

-- 2. Check that indexes were created
select
  indexname,
  indexdef
from pg_indexes
where tablename = 'wage_snapshots';

-- Expected: idx_wage_snapshots_lookup on (user_id, from_date DESC)

-- ============================================================================

-- 3. Check that RLS is enabled and policies exist
select
  schemaname,
  tablename,
  rowsecurity
from pg_tables
where tablename = 'wage_snapshots';

-- Expected: rowsecurity = true

select
  policyname,
  cmd,
  qual,
  with_check
from pg_policies
where tablename = 'wage_snapshots';

-- Expected: 4 policies (select, insert, update, delete)

-- ============================================================================

-- 4. Verify each user has exactly one snapshot with from_date = '2025-01-01'
select
  user_id,
  count(*) as snapshot_count,
  min(from_date) as earliest_date,
  max(from_date) as latest_date
from public.wage_snapshots
group by user_id
having count(*) != 1 or min(from_date) != '2025-01-01';

-- Expected: No rows (all users should have exactly 1 snapshot dated 2025-01-01)

-- ============================================================================

-- 5. Verify snapshot data looks correct (sample check)
-- Note: This check is only run if the old columns still exist
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
    and table_name = 'user_settings'
    and column_name = 'custom_wage'
  ) then
    raise notice 'Old wage columns still exist, running verification query...';
    -- Just log, don't actually run the query in migration
    -- Use separate query tool to verify if needed
  else
    raise notice 'Old wage columns removed, skipping verification';
  end if;
end $$;

-- Manual verification (run separately if needed):
-- select
--   ws.user_id,
--   ws.from_date,
--   ws.hourly_wage,
--   ws.wage_level
-- from public.wage_snapshots ws
-- limit 10;

-- ============================================================================

-- 6. Verify old columns were removed from user_shifts
select
  column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'user_shifts'
  and column_name in ('hourly_wage_snapshot', 'supplement_rules_snapshot');

-- Expected: No rows (columns should be dropped)

-- ============================================================================

-- 7. Test snapshot lookup query (simulate what the app will do)
-- Replace 'YOUR_USER_ID' with an actual user_id from your database
-- Commented out to prevent migration errors - run manually if needed
/*
select
  id,
  from_date,
  hourly_wage,
  wage_level,
  supplements
from public.wage_snapshots
where user_id = 'YOUR_USER_ID'
  and from_date <= '2025-06-15'  -- Example shift date
order by from_date desc
limit 1;
*/

-- Expected: Returns the most recent snapshot before or on 2025-06-15

-- ============================================================================
-- End of verification queries
-- ============================================================================
