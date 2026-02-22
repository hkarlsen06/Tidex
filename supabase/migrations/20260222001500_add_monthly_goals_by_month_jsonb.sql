-- Add month-specific goal overrides to user_settings.
-- JSON contract:
-- {
--   "YYYY-MM": <positive integer goal>
-- }

create or replace function public.is_valid_monthly_goals_by_month(p_value jsonb)
returns boolean
language sql
immutable
as $$
  select case
    when p_value is null then false
    when jsonb_typeof(p_value) <> 'object' then false
    else not exists (
      select 1
      from jsonb_each(p_value) as kv(key, value)
      where
        kv.key !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
        or jsonb_typeof(kv.value) <> 'number'
        or kv.value::text !~ '^[0-9]+$'
        or (kv.value::text)::numeric < 1
        or (kv.value::text)::numeric > 2147483647
    )
  end
$$;

alter table public.user_settings
  add column monthly_goals_by_month jsonb not null default '{}'::jsonb;

alter table public.user_settings
  add constraint user_settings_monthly_goals_by_month_valid_entries
  check (public.is_valid_monthly_goals_by_month(monthly_goals_by_month));

comment on column public.user_settings.monthly_goals_by_month is
  'Sparse month-specific goal overrides keyed by YYYY-MM. Falls back to monthly_goal when key is missing.';
