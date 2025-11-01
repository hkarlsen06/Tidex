-- ============================================================================
-- Interval-Based Wage Snapshots Migration
-- ============================================================================
-- This migration introduces a new wage snapshot system that stores wage changes
-- as time intervals rather than per-shift snapshots.
--
-- Benefits:
-- - Works for both single and series shifts
-- - Minimal storage (only store when wage changes)
-- - Handles mid-month wage changes
-- - Users can retroactively correct wage history
-- - Maintains historical accuracy even after wage changes
-- ============================================================================

-- ============================================================================
-- Step 1: Create wage_snapshots table
-- ============================================================================

create table if not exists public.wage_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  from_date date not null,
  hourly_wage numeric(10,2) not null,
  wage_level integer,  -- NULL = custom wage, NUMBER (1-9) = tariff level
  supplements jsonb not null default '[]'::jsonb,
  created_at timestamp with time zone default now(),

  constraint unique_user_date unique(user_id, from_date)
);

-- Create index for efficient snapshot lookups
-- Query pattern: WHERE user_id = ? AND from_date <= ? ORDER BY from_date DESC LIMIT 1
create index if not exists idx_wage_snapshots_lookup
  on public.wage_snapshots(user_id, from_date desc);

-- Enable RLS
alter table public.wage_snapshots enable row level security;

-- RLS policies: Users can only access their own snapshots
create policy "Users can read own wage snapshots"
  on public.wage_snapshots for select
  using (auth.uid() = user_id);

create policy "Users can insert own wage snapshots"
  on public.wage_snapshots for insert
  with check (auth.uid() = user_id);

create policy "Users can update own wage snapshots"
  on public.wage_snapshots for update
  using (auth.uid() = user_id);

create policy "Users can delete own wage snapshots"
  on public.wage_snapshots for delete
  using (auth.uid() = user_id);

-- ============================================================================
-- Step 2: Backfill wage snapshots for existing users
-- ============================================================================
-- For each user, create one initial snapshot dated 2025-01-01 with:
-- - Resolved hourly wage (from tariff or custom)
-- - Current wage level (if on tariff)
-- - Current supplement rules
-- Note: Only run if columns still exist (migration is idempotent)

do $$
begin
  -- Check if the columns exist before trying to backfill
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
    and table_name = 'user_settings'
    and column_name = 'use_preset'
  ) then
    insert into public.wage_snapshots (user_id, from_date, hourly_wage, wage_level, supplements)
    select
      us.user_id,
      '2025-01-01'::date as from_date,
      -- Resolve hourly wage based on use_preset flag:
      -- If use_preset = true: use tariff rates based on wage_level
      -- If use_preset = false: use custom_wage
      case
        when us.use_preset = true then
          -- Using tariff: resolve wage from wage_level (matches PRESET_WAGE_RATES in lib/payroll/calc.ts)
          case us.current_wage_level
        when -1 then 129.91
        when -2 then 132.90
        when 1 then 184.54
        when 2 then 185.38
        when 3 then 187.46
        when 4 then 193.05
        when 5 then 210.81
        when 6 then 256.14
        else 184.54  -- Default to level 1 if invalid
      end
    else
      -- Using custom wage: use custom_wage (default to 184.54 if not set)
      coalesce(nullif(us.custom_wage, 0), 184.54)
      end as hourly_wage,
      -- Store wage_level if using tariff (use_preset = true), otherwise NULL
      case
        when us.use_preset = true then us.current_wage_level
        else null
      end as wage_level,
      -- Copy current supplement rules
      coalesce(us.custom_supplements, '{"rules": []}'::jsonb) as supplements
    from public.user_settings us
    where not exists (
      -- Don't create duplicate if snapshot already exists for this user
      select 1 from public.wage_snapshots ws
      where ws.user_id = us.user_id and ws.from_date = '2025-01-01'
    )
    on conflict (user_id, from_date) do nothing;
  end if;
end $$;

-- ============================================================================
-- Step 3: Drop old snapshot columns from user_shifts
-- ============================================================================
-- These columns are no longer needed as snapshots will be looked up from
-- the wage_snapshots table based on shift_date.

alter table public.user_shifts
  drop column if exists hourly_wage_snapshot;

alter table public.user_shifts
  drop column if exists supplement_rules_snapshot;

-- ============================================================================
-- Migration Complete
-- ============================================================================
-- Next steps:
-- 1. Update data-access layer to fetch and use wage snapshots
-- 2. Update payroll calculations to accept snapshot parameter
-- 3. Create server actions for managing wage snapshots
-- 4. Build UI for wage history management
-- ============================================================================
