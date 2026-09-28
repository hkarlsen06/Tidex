-- Add a per-job custom pay period config. NULL keeps the current behavior
-- (calendar month, paid on payroll_day the month after).
--
-- Two shapes are accepted, matching ios/TidexApp/Models/PayPeriod.swift:
--   {"type":"monthly","startDay":1-28,"payoutMonthOffset":0|1}
--   {"type":"biweekly","anchorEnd":"yyyy-MM-dd","payoutDelayDays":0-27}

alter table public.jobs
  add column if not exists pay_period jsonb;

comment on column public.jobs.pay_period is
  'Custom pay period config (monthly with a start day, or biweekly with an anchor end date). NULL means calendar month, paid on payroll_day the month after.';

-- A missing required key makes a branch evaluate to NULL rather than false, and Postgres
-- treats a NULL check result as passing. coalesce(..., false) forces a hard rejection instead.
alter table public.jobs
  add constraint jobs_pay_period_valid check (
    pay_period is null
    or coalesce(
      jsonb_typeof(pay_period) = 'object'
      and (
        (
          (pay_period ->> 'type') = 'monthly'
          and (pay_period - 'type' - 'startDay' - 'payoutMonthOffset') = '{}'::jsonb
          and (pay_period ->> 'startDay') ~ '^([1-9]|1[0-9]|2[0-8])$'
          and (pay_period ->> 'payoutMonthOffset') ~ '^[01]$'
        )
        or (
          (pay_period ->> 'type') = 'biweekly'
          and (pay_period - 'type' - 'anchorEnd' - 'payoutDelayDays') = '{}'::jsonb
          and (pay_period ->> 'anchorEnd') ~ '^\d{4}-\d{2}-\d{2}$'
          and (pay_period ->> 'payoutDelayDays') ~ '^([0-9]|1[0-9]|2[0-7])$'
        )
      ),
      false
    )
  );
