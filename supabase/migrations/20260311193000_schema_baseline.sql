-- Source: /tmp/tidex-supabase-migrations-backup/20260213213839_fix_performance_advisors.sql


-- Add missing index for foreign key wage_snapshots.tariff_type_id
CREATE INDEX idx_wage_snapshots_tariff_type_id
  ON public.wage_snapshots (tariff_type_id);

-- Drop unused indexes on public schema
DROP INDEX IF EXISTS public.idx_feedback_created_at;
DROP INDEX IF EXISTS public.idx_feedback_responded_by;
DROP INDEX IF EXISTS public.idx_feedback_user_id;
DROP INDEX IF EXISTS public.idx_recurring_shifts_user_active;
DROP INDEX IF EXISTS public.idx_series_shifts_user_id;

-- Drop unused indexes on internal schema
DROP INDEX IF EXISTS internal.notifications_outbox_created_at_idx;
DROP INDEX IF EXISTS internal.idx_ntw_shift_operations;
DROP INDEX IF EXISTS internal.tariff_versions_effective_date_idx;
;


-- Source: /tmp/tidex-supabase-migrations-backup/20260213213854_add_feedback_fk_indexes.sql


-- Re-add indexes to cover foreign keys on feedback table
CREATE INDEX idx_feedback_user_id ON public.feedback (user_id);
CREATE INDEX idx_feedback_responded_by ON public.feedback (responded_by);
;


-- Source: /tmp/tidex-supabase-migrations-backup/20260213223705_add_feedback_responded_and_share_started_triggers.sql

-- Add triggers for feedback_responded and share_started notifications
-- These make DB triggers the single source for enqueuing these notification types

DROP TRIGGER IF EXISTS a_on_feedback_responded_notify ON public.feedback;
CREATE TRIGGER a_on_feedback_responded_notify
  AFTER UPDATE ON public.feedback
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_feedback_responded_notification();

DROP TRIGGER IF EXISTS on_share_started_notify ON public.shift_shares;
CREATE TRIGGER on_share_started_notify
  AFTER INSERT ON public.shift_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_share_started_notification();;


-- Source: /tmp/tidex-supabase-migrations-backup/20260213224238_remove_shift_batching_infrastructure.sql

-- Remove shift-change notification batching infrastructure
-- All shift-change notifications have been removed; only direct notifications remain.

-- 1. Unschedule the 15-minute worker cron
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'process-shift-notifications';

-- 2. Drop public/iOS entrypoint and worker pipeline
DROP FUNCTION IF EXISTS public.enqueue_shift_notification(uuid, text, text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.run_notification_workers();
DROP FUNCTION IF EXISTS internal.process_notification_windows();
DROP FUNCTION IF EXISTS internal.upsert_notification_window(uuid, timestamptz, text, date, uuid);

-- 3. Drop localization helpers only used by removed shift pipeline
DROP FUNCTION IF EXISTS internal.format_shift_date(date, boolean, text);
DROP FUNCTION IF EXISTS internal.build_shift_title(text, text, text);
DROP FUNCTION IF EXISTS internal.build_shift_body(date, text, text, boolean, text, text, text);
DROP FUNCTION IF EXISTS internal.build_batched_body(integer, integer, integer, text);

-- 4. Drop aggregation table
DROP TABLE IF EXISTS internal.notification_time_windows;

-- 5. Update prepare_user_for_deletion to remove reference to dropped table
CREATE OR REPLACE FUNCTION public.prepare_user_for_deletion(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, internal
AS $$
BEGIN
  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_id cannot be null';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF auth.uid() != target_user_id THEN
    RAISE EXCEPTION 'You can only delete your own account';
  END IF;

  DELETE FROM internal.impersonation_rate_limits WHERE admin_user_id = target_user_id;
  DELETE FROM internal.app_account_tokens WHERE user_id = target_user_id;
  DELETE FROM internal.push_devices WHERE user_id = target_user_id;
  DELETE FROM internal.notifications_outbox WHERE owner_id = target_user_id OR recipient_id = target_user_id;

  INSERT INTO internal.admin_audit_log (
    admin_id, action, target_user_id, admin_email, target_email, metadata
  )
  SELECT
    target_user_id, 'user_deleted_self', target_user_id,
    COALESCE(u.email, u.phone, 'unknown'),
    COALESCE(u.email, u.phone, 'unknown'),
    jsonb_build_object('deletion_type', 'self_service', 'deleted_at', now())
  FROM auth.users u
  WHERE u.id = target_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.prepare_user_for_deletion(uuid) TO authenticated;

-- 6. Update cleanup cron to only clean outbox (notification_time_windows no longer exists)
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cleanup-shift-notification-events';
SELECT cron.schedule(
  'cleanup-shift-notification-events',
  '0 4 * * *',
  $$DELETE FROM internal.notifications_outbox WHERE status = 'sent' AND created_at < NOW() - INTERVAL '3 days';$$
);;


-- Source: /tmp/tidex-supabase-migrations-backup/20260215143225_wagey_bonus_functions.sql

-- Function: increment_wagey_bonus
-- Description: Atomically adds bonus credits to a user's wagey_invocations JSON
-- Used by: apple-verify-purchase edge function when processing consumable purchases

CREATE OR REPLACE FUNCTION public.increment_wagey_bonus(p_user_id uuid, p_credits integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_current jsonb;
  v_bonus integer;
begin
  select p.wagey_invocations
  into v_current
  from public.profiles p
  where p.id = p_user_id
  for update;

  if v_current is null then
    v_current := '{"count": 0, "month": null, "bonus": 0}'::jsonb;
  end if;

  v_bonus := coalesce((v_current->>'bonus')::integer, 0) + p_credits;

  update public.profiles
  set
    wagey_invocations = v_current || jsonb_build_object('bonus', v_bonus),
    updated_at = now()
  where id = p_user_id;
end;
$function$;

-- Function: increment_wagey_invocation
-- Description: Atomically increments Wagey (AI) invocation count with monthly reset
-- Used by: Wagey chat feature rate limiting
-- Supports bonus credits: when monthly limit is reached, consumes bonus instead of blocking

CREATE OR REPLACE FUNCTION public.increment_wagey_invocation(p_user_id uuid, p_current_month text, p_max_invocations integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_current jsonb;
  v_count integer;
  v_month text;
  v_bonus integer;
  v_new_count integer;
  v_new_bonus integer;
  v_allowed boolean;
begin
  -- Get current invocations with row lock
  select p.wagey_invocations
  into v_current
  from public.profiles p
  where p.id = p_user_id
  for update;

  if v_current is null then
    v_current := '{"count": 0, "month": null, "bonus": 0}'::jsonb;
  end if;

  v_count := coalesce((v_current->>'count')::integer, 0);
  v_month := v_current->>'month';
  v_bonus := coalesce((v_current->>'bonus')::integer, 0);

  if v_month is null or v_month != p_current_month then
    -- New month: reset count, preserve bonus
    v_new_count := 1;
    v_new_bonus := v_bonus;
    v_allowed := true;
  else
    if v_count < p_max_invocations then
      -- Within monthly limit
      v_new_count := v_count + 1;
      v_new_bonus := v_bonus;
      v_allowed := true;
    elsif v_bonus > 0 then
      -- Monthly limit reached but bonus available: consume one bonus credit
      v_new_count := v_count;
      v_new_bonus := v_bonus - 1;
      v_allowed := true;
    else
      -- Monthly limit reached, no bonus
      v_new_count := v_count;
      v_new_bonus := v_bonus;
      v_allowed := false;
    end if;
  end if;

  if v_allowed then
    update public.profiles
    set
      wagey_invocations = jsonb_build_object('count', v_new_count, 'month', p_current_month, 'bonus', v_new_bonus),
      updated_at = now()
    where id = p_user_id;
  end if;

  return jsonb_build_object(
    'allowed', v_allowed,
    'count', v_new_count,
    'remaining', greatest(0, p_max_invocations - v_new_count),
    'bonus', v_new_bonus
  );
end;
$function$;


-- Source: /tmp/tidex-supabase-migrations-backup/20260228004726_fix_sharing_functions_include_deleted_jobs.sql

-- Fix sharing payload functions: include deleted jobs in compute context

-- Function: get_shared_month_payload
-- Description:
--   Returns a raw month payload for one owner that has shared with the authenticated viewer.
--   Payload is consumed by iOS for client-side monthly computation.
--
-- Authorization:
--   - Viewer is auth.uid().
--   - Access requires shift_shares(owner_id = p_owner_id, viewer_id = auth.uid(), blocked = false).
--   - Unauthorized/blocked access returns no row.
--
-- Redaction:
--   - If show_earnings = false:
--       * wage/tax inputs are redacted in snapshots.
--       * shift custom supplements are redacted.
--       * recurring date_specific_supplements are redacted.

CREATE OR REPLACE FUNCTION public.get_shared_month_payload(
  p_owner_id uuid,
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  owner_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND ss.owner_id = p_owner_id
      AND COALESCE(ss.blocked, false) = false
    LIMIT 1
  ),
  month_bounds AS (
    SELECT
      make_date(p_year, p_month, 1) AS start_date,
      ((make_date(p_year, p_month, 1) + interval '1 month')::date - 1) AS end_date
  )
  SELECT
    a.owner_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal',
            COALESCE(
              CASE
                WHEN jsonb_typeof(us.monthly_goals_by_month) = 'object'
                  AND COALESCE(
                    us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'),
                    ''
                  ) ~ '^[0-9]+$'
                THEN (us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'))::integer
                ELSE NULL
              END,
              us.monthly_goal
            ),
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.owner_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.owner_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        CROSS JOIN month_bounds mb
        WHERE s.user_id = a.owner_id
          AND s.deleted_at IS NULL
          AND s.shift_date >= mb.start_date
          AND s.shift_date <= mb.end_date
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.owner_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.owner_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.owner_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) TO authenticated;

-- Function: get_my_sharer_preview_payloads
-- Description:
--   Returns raw payloads for each sharer visible to the authenticated viewer.
--   Intended for client-side preview computation (active/upcoming/past).
--
-- Authorization:
--   - Viewer is auth.uid().
--   - Only rows from shift_shares where viewer_id = auth.uid() and blocked = false.
--
-- Redaction:
--   - If show_earnings = false:
--       * wage/tax inputs are redacted in snapshots.
--       * shift custom supplements are redacted.
--       * recurring date_specific_supplements are redacted.

CREATE OR REPLACE FUNCTION public.get_my_sharer_preview_payloads(
  p_sharer_ids uuid[] DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  sharer_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id AS sharer_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND COALESCE(ss.blocked, false) = false
      AND (p_sharer_ids IS NULL OR ss.owner_id = ANY(p_sharer_ids))
  )
  SELECT
    a.sharer_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal', us.monthly_goal,
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.sharer_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.sharer_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        WHERE s.user_id = a.sharer_id
          AND s.deleted_at IS NULL
          AND (p_start_date IS NULL OR s.shift_date >= p_start_date)
          AND (p_end_date IS NULL OR s.shift_date <= p_end_date)
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.sharer_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.sharer_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.sharer_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a
  ORDER BY a.sharer_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) TO authenticated;


-- Source: supabase/sql/migrations/20260214141437_create_consumable_transactions.sql

-- Migration: create_consumable_transactions
-- Applied remotely as version 20260214141437

create table public.consumable_transactions (
  id uuid default gen_random_uuid() primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  apple_transaction_id text not null unique,
  apple_original_transaction_id text not null,
  apple_product_id text not null,
  credits_granted integer not null default 0,
  environment text not null default 'Sandbox',
  created_at timestamptz not null default now()
);

create index idx_consumable_transactions_user_id on public.consumable_transactions (user_id);

alter table public.consumable_transactions enable row level security;

create policy "Users can view own consumable transactions"
  on public.consumable_transactions
  for select
  using (auth.uid() = user_id);


-- Source: supabase/sql/migrations/20260221164831_make_impersonation_sessions_target_user_id_nullable.sql

ALTER TABLE internal.impersonation_sessions
  ALTER COLUMN target_user_id DROP NOT NULL;;


-- Source: supabase/sql/migrations/20260221232601_add_monthly_goals_by_month_jsonb_v2.sql

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
  add column if not exists monthly_goals_by_month jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_settings_monthly_goals_by_month_valid_entries'
      and conrelid = 'public.user_settings'::regclass
  ) then
    alter table public.user_settings
      add constraint user_settings_monthly_goals_by_month_valid_entries
      check (public.is_valid_monthly_goals_by_month(monthly_goals_by_month));
  end if;
end $$;

comment on column public.user_settings.monthly_goals_by_month is
  'Sparse month-specific goal overrides keyed by YYYY-MM. Falls back to monthly_goal when key is missing.';;


-- Source: supabase/sql/migrations/20260226140000_multi_job_support_compat.sql

-- Multi-job support compatibility migration
-- Adds jobs table + job_id references while preserving legacy user_settings payroll fields.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Core jobs table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 100),
  color text DEFAULT NULL CHECK (color IS NULL OR color ~ '^#[0-9a-fA-F]{6}$'),
  is_default boolean NOT NULL DEFAULT false,
  sort_order smallint NOT NULL DEFAULT 0,
  payroll_day integer CHECK (payroll_day >= 1 AND payroll_day <= 31) DEFAULT 15,
  half_tax_month integer CHECK ((half_tax_month = ANY (ARRAY[11, 12])) OR half_tax_month IS NULL),
  monthly_goal integer DEFAULT 20000,
  archived_at timestamptz DEFAULT NULL,
  deleted_at timestamptz DEFAULT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  revision bigint NOT NULL DEFAULT 1
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_jobs_default
  ON public.jobs (user_id)
  WHERE is_default = true AND deleted_at IS NULL AND archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_jobs_user_id ON public.jobs (user_id);
CREATE INDEX IF NOT EXISTS idx_jobs_user_revision ON public.jobs (user_id, revision);

ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'jobs'
      AND policyname = 'Users can view own or shared jobs'
  ) THEN
    CREATE POLICY "Users can view own or shared jobs" ON public.jobs
      FOR SELECT TO authenticated
      USING (
        user_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.shift_shares ss
          WHERE ss.owner_id = jobs.user_id
            AND ss.viewer_id = auth.uid()
            AND COALESCE(ss.blocked, false) = false
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'jobs'
      AND policyname = 'Users can insert own jobs'
  ) THEN
    CREATE POLICY "Users can insert own jobs" ON public.jobs
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'jobs'
      AND policyname = 'Users can update own jobs'
  ) THEN
    CREATE POLICY "Users can update own jobs" ON public.jobs
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'jobs'
      AND policyname = 'Users can delete own jobs'
  ) THEN
    CREATE POLICY "Users can delete own jobs" ON public.jobs
      FOR DELETE TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'jobs'
      AND policyname = 'Require MFA for users who enrolled'
  ) THEN
    CREATE POLICY "Require MFA for users who enrolled" ON public.jobs
      AS RESTRICTIVE
      FOR ALL
      TO authenticated
      USING (public.check_mfa_aal());
  END IF;
END;
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.jobs TO authenticated;

-- Keep jobs.updated_at + revision in sync with existing revisioned tables.
CREATE OR REPLACE FUNCTION public.set_jobs_updated_at_and_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  NEW.revision := COALESCE(OLD.revision, 0) + 1;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_jobs_updated_at_revision ON public.jobs;
CREATE TRIGGER set_jobs_updated_at_revision
  BEFORE UPDATE ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.set_jobs_updated_at_and_revision();

-- ---------------------------------------------------------------------------
-- 2) Compatibility helper + mirror trigger functions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_default_job(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
  v_payroll_day integer;
  v_half_tax_month integer;
  v_monthly_goal integer;
BEGIN
  SELECT j.id
  INTO v_job_id
  FROM public.jobs j
  WHERE j.user_id = p_user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
  LIMIT 1;

  IF v_job_id IS NULL THEN
    SELECT
      COALESCE(us.payroll_day, 15),
      us.half_tax_month,
      COALESCE(us.monthly_goal, 20000)
    INTO v_payroll_day, v_half_tax_month, v_monthly_goal
    FROM public.user_settings us
    WHERE us.user_id = p_user_id
    LIMIT 1;

    INSERT INTO public.jobs (
      user_id,
      name,
      is_default,
      payroll_day,
      half_tax_month,
      monthly_goal
    )
    VALUES (
      p_user_id,
      'Jobb',
      true,
      COALESCE(v_payroll_day, 15),
      v_half_tax_month,
      COALESCE(v_monthly_goal, 20000)
    )
    ON CONFLICT DO NOTHING;

    SELECT j.id
    INTO v_job_id
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
    UPDATE public.user_settings
    SET payroll_day = NEW.payroll_day,
        half_tax_month = NEW.half_tax_month,
        monthly_goal = NEW.monthly_goal
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) Add job_id columns + ownership validation triggers
-- ---------------------------------------------------------------------------
ALTER TABLE public.user_shifts
  ADD COLUMN IF NOT EXISTS job_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_shifts_job_id_fkey_jobs'
  ) THEN
    ALTER TABLE public.user_shifts
      ADD CONSTRAINT user_shifts_job_id_fkey_jobs
      FOREIGN KEY (job_id)
      REFERENCES public.jobs(id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_user_shifts_job_id ON public.user_shifts (job_id);

ALTER TABLE public.recurring_shifts
  ADD COLUMN IF NOT EXISTS job_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'recurring_shifts_job_id_fkey_jobs'
  ) THEN
    ALTER TABLE public.recurring_shifts
      ADD CONSTRAINT recurring_shifts_job_id_fkey_jobs
      FOREIGN KEY (job_id)
      REFERENCES public.jobs(id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_recurring_shifts_job_id ON public.recurring_shifts (job_id);

ALTER TABLE public.wage_snapshots
  ADD COLUMN IF NOT EXISTS job_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'wage_snapshots_job_id_fkey_jobs'
  ) THEN
    ALTER TABLE public.wage_snapshots
      ADD CONSTRAINT wage_snapshots_job_id_fkey_jobs
      FOREIGN KEY (job_id)
      REFERENCES public.jobs(id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_wage_snapshots_job_id ON public.wage_snapshots (job_id);

DROP TRIGGER IF EXISTS user_shifts_assign_job_id ON public.user_shifts;
CREATE TRIGGER user_shifts_assign_job_id
  BEFORE INSERT OR UPDATE OF user_id, job_id ON public.user_shifts
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_job_id_and_validate_owner();

DROP TRIGGER IF EXISTS recurring_shifts_assign_job_id ON public.recurring_shifts;
CREATE TRIGGER recurring_shifts_assign_job_id
  BEFORE INSERT OR UPDATE OF user_id, job_id ON public.recurring_shifts
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_job_id_and_validate_owner();

DROP TRIGGER IF EXISTS wage_snapshots_assign_job_id ON public.wage_snapshots;
CREATE TRIGGER wage_snapshots_assign_job_id
  BEFORE INSERT OR UPDATE OF user_id, job_id ON public.wage_snapshots
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_job_id_and_validate_owner();

DROP TRIGGER IF EXISTS user_settings_mirror_to_jobs ON public.user_settings;
CREATE TRIGGER user_settings_mirror_to_jobs
  AFTER INSERT OR UPDATE OF payroll_day, half_tax_month, monthly_goal
  ON public.user_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_legacy_settings_to_default_job();

DROP TRIGGER IF EXISTS jobs_mirror_to_user_settings ON public.jobs;
CREATE TRIGGER jobs_mirror_to_user_settings
  AFTER INSERT OR UPDATE OF payroll_day, half_tax_month, monthly_goal, is_default
  ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_default_job_to_legacy_settings();

-- ---------------------------------------------------------------------------
-- 4) Backfill default jobs + foreign keys
-- ---------------------------------------------------------------------------
WITH all_user_ids AS (
  SELECT user_id FROM public.user_settings
  UNION
  SELECT user_id FROM public.user_shifts
  UNION
  SELECT user_id FROM public.recurring_shifts
  UNION
  SELECT user_id FROM public.wage_snapshots
)
INSERT INTO public.jobs (
  user_id,
  name,
  is_default,
  payroll_day,
  half_tax_month,
  monthly_goal
)
SELECT
  u.user_id,
  'Jobb',
  true,
  COALESCE(us.payroll_day, 15),
  us.half_tax_month,
  COALESCE(us.monthly_goal, 20000)
FROM all_user_ids u
LEFT JOIN public.user_settings us
  ON us.user_id = u.user_id
WHERE NOT EXISTS (
  SELECT 1
  FROM public.jobs j
  WHERE j.user_id = u.user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
);

UPDATE public.user_shifts s
SET job_id = public.ensure_default_job(s.user_id)
WHERE s.job_id IS NULL;

UPDATE public.recurring_shifts r
SET job_id = public.ensure_default_job(r.user_id)
WHERE r.job_id IS NULL;

UPDATE public.wage_snapshots w
SET job_id = public.ensure_default_job(w.user_id)
WHERE w.job_id IS NULL;

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
END;
$$;

ALTER TABLE public.user_shifts ALTER COLUMN job_id SET NOT NULL;
ALTER TABLE public.recurring_shifts ALTER COLUMN job_id SET NOT NULL;
ALTER TABLE public.wage_snapshots ALTER COLUMN job_id SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 5) Update wage_snapshot uniqueness for per-job snapshots
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.idx_wage_snapshots_baseline_job') IS NULL THEN
    CREATE UNIQUE INDEX idx_wage_snapshots_baseline_job
      ON public.wage_snapshots (user_id, job_id)
      WHERE from_date IS NULL AND deleted_at IS NULL;
  END IF;

  IF to_regclass('public.idx_wage_snapshots_unique_date_job') IS NULL THEN
    CREATE UNIQUE INDEX idx_wage_snapshots_unique_date_job
      ON public.wage_snapshots (user_id, job_id, from_date)
      WHERE from_date IS NOT NULL AND deleted_at IS NULL;
  END IF;
END;
$$;

DROP INDEX IF EXISTS public.idx_wage_snapshots_baseline;
DROP INDEX IF EXISTS public.idx_wage_snapshots_unique_date;

DO $$
BEGIN
  IF to_regclass('public.idx_wage_snapshots_baseline_job') IS NOT NULL THEN
    ALTER INDEX public.idx_wage_snapshots_baseline_job RENAME TO idx_wage_snapshots_baseline;
  END IF;

  IF to_regclass('public.idx_wage_snapshots_unique_date_job') IS NOT NULL THEN
    ALTER INDEX public.idx_wage_snapshots_unique_date_job RENAME TO idx_wage_snapshots_unique_date;
  END IF;
END;
$$;


-- ---------------------------------------------------------------------------
-- 6) Refresh dependent SQL functions for compatibility rollout
-- ---------------------------------------------------------------------------

-- Function: handle_new_user
-- Description: Trigger function that creates a profile + default job for new users
-- Used by: AFTER INSERT trigger on auth.users

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.jobs (user_id, name, is_default)
  VALUES (NEW.id, 'Jobb', true)
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$function$;

-- Function: prepare_user_for_deletion
-- Description: Prepares a user account for deletion by cleaning up internal tables.
--              Call this function before calling auth.admin.deleteUser().
--
-- Usage: SELECT public.prepare_user_for_deletion('user-uuid-here');
--
-- Security: SECURITY DEFINER to access internal schema tables.
--           Validates auth.uid() = target_user_id to prevent users from deleting others.

CREATE OR REPLACE FUNCTION public.prepare_user_for_deletion(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, internal
AS $$
BEGIN
  -- Validate input
  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_id cannot be null';
  END IF;

  -- SECURITY: Ensure the calling user can only delete their own account
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF auth.uid() != target_user_id THEN
    RAISE EXCEPTION 'You can only delete your own account';
  END IF;

  -- Delete from internal tables that should be cleaned up (not preserved)
  DELETE FROM internal.impersonation_rate_limits WHERE admin_user_id = target_user_id;
  DELETE FROM internal.app_account_tokens WHERE user_id = target_user_id;
  DELETE FROM internal.push_devices WHERE user_id = target_user_id;
  DELETE FROM internal.notifications_outbox WHERE owner_id = target_user_id OR recipient_id = target_user_id;

  -- Note: The following are handled by ON DELETE SET NULL or ON DELETE CASCADE:
  -- - internal.admin_audit_log (SET NULL - preserves audit trail)
  -- - internal.admin_broadcasts (SET NULL - preserves broadcast history)
  -- - internal.impersonation_sessions (SET NULL - preserves session history)
  -- - internal.apple_orphan_notifications (SET NULL)
  -- - public.jobs and dependent tables (CASCADE from auth.users)

  -- Log the account deletion preparation (before the user is deleted)
  INSERT INTO internal.admin_audit_log (
    admin_id,
    action,
    target_user_id,
    admin_email,
    target_email,
    metadata
  )
  SELECT
    target_user_id,
    'user_deleted_self',
    target_user_id,
    COALESCE(u.email, u.phone, 'unknown'),
    COALESCE(u.email, u.phone, 'unknown'),
    jsonb_build_object('deletion_type', 'self_service', 'deleted_at', now())
  FROM auth.users u
  WHERE u.id = target_user_id;

END;
$$;

GRANT EXECUTE ON FUNCTION public.prepare_user_for_deletion(uuid) TO authenticated;

COMMENT ON FUNCTION public.prepare_user_for_deletion(uuid) IS
'Prepares a user account for deletion by cleaning up internal tables.
Call this function before calling auth.admin.deleteUser().
The function is SECURITY DEFINER to access internal schema tables.
Security: Validates auth.uid() = target_user_id to prevent users from deleting others.';

-- Function: get_shared_month_payload
-- Description:
--   Returns a raw month payload for one owner that has shared with the authenticated viewer.
--   Payload is consumed by iOS for client-side monthly computation.
--
-- Authorization:
--   - Viewer is auth.uid().
--   - Access requires shift_shares(owner_id = p_owner_id, viewer_id = auth.uid(), blocked = false).
--   - Unauthorized/blocked access returns no row.
--
-- Redaction:
--   - If show_earnings = false:
--       * wage/tax inputs are redacted in snapshots.
--       * shift custom supplements are redacted.
--       * recurring date_specific_supplements are redacted.

DROP FUNCTION IF EXISTS public.get_shared_month_payload(uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.get_shared_month_payload(
  p_owner_id uuid,
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  owner_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND ss.owner_id = p_owner_id
      AND COALESCE(ss.blocked, false) = false
    LIMIT 1
  ),
  month_bounds AS (
    SELECT
      make_date(p_year, p_month, 1) AS start_date,
      ((make_date(p_year, p_month, 1) + interval '1 month')::date - 1) AS end_date
  )
  SELECT
    a.owner_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal',
            COALESCE(
              CASE
                WHEN jsonb_typeof(us.monthly_goals_by_month) = 'object'
                  AND COALESCE(
                    us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'),
                    ''
                  ) ~ '^[0-9]+$'
                THEN (us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'))::integer
                ELSE NULL
              END,
              us.monthly_goal
            ),
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.owner_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.owner_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        CROSS JOIN month_bounds mb
        WHERE s.user_id = a.owner_id
          AND s.deleted_at IS NULL
          AND s.shift_date >= mb.start_date
          AND s.shift_date <= mb.end_date
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.owner_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.owner_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.owner_id
          AND j.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) TO authenticated;

-- Function: get_my_sharer_preview_payloads
-- Description:
--   Returns raw payloads for each sharer visible to the authenticated viewer.
--   Intended for client-side preview computation (active/upcoming/past).
--
-- Authorization:
--   - Viewer is auth.uid().
--   - Only rows from shift_shares where viewer_id = auth.uid() and blocked = false.
--
-- Redaction:
--   - If show_earnings = false:
--       * wage/tax inputs are redacted in snapshots.
--       * shift custom supplements are redacted.
--       * recurring date_specific_supplements are redacted.

DROP FUNCTION IF EXISTS public.get_my_sharer_preview_payloads(uuid[], date, date);

CREATE OR REPLACE FUNCTION public.get_my_sharer_preview_payloads(
  p_sharer_ids uuid[] DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  sharer_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id AS sharer_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND COALESCE(ss.blocked, false) = false
      AND (p_sharer_ids IS NULL OR ss.owner_id = ANY(p_sharer_ids))
  )
  SELECT
    a.sharer_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal', us.monthly_goal,
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.sharer_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.sharer_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        WHERE s.user_id = a.sharer_id
          AND s.deleted_at IS NULL
          AND (p_start_date IS NULL OR s.shift_date >= p_start_date)
          AND (p_end_date IS NULL OR s.shift_date <= p_end_date)
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.sharer_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.sharer_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.sharer_id
          AND j.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a
  ORDER BY a.sharer_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) TO authenticated;

-- Function: get_shifts_due_for_reminder
-- Description: Returns shifts that are due for reminder notifications based on user preferences
-- Used by: process-shift-reminders edge function

DROP FUNCTION IF EXISTS public.get_shifts_due_for_reminder();

CREATE OR REPLACE FUNCTION public.get_shifts_due_for_reminder()
 RETURNS TABLE(
   user_id uuid,
   shift_instance_key text,
   shift_date date,
   start_time time without time zone,
   end_time time without time zone,
   reminder_minutes integer,
   minutes_until_shift integer,
   job_id uuid,
   job_name text
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  cron_interval_minutes CONSTANT INTEGER := 1;  -- Cron runs every 1 minute
BEGIN
  RETURN QUERY
  WITH user_prefs AS (
    SELECT DISTINCT
      pd.user_id,
      COALESCE(np.shift_reminders_enabled, true) AS enabled,
      COALESCE(np.shift_reminder_minutes_array, ARRAY[300]) AS reminder_mins_array
    FROM internal.push_devices pd
    LEFT JOIN public.notification_preferences np ON np.user_id = pd.user_id
    WHERE COALESCE(np.shift_reminders_enabled, true) = true
  ),
  user_reminders AS (
    SELECT
      up.user_id,
      unnest(up.reminder_mins_array) AS reminder_mins
    FROM user_prefs up
  ),
  single_shifts AS (
    SELECT
      us.user_id,
      us.job_id,
      COALESCE(j.name, 'Jobb') AS job_name,
      'single:' || us.id || ':' || us.shift_date || ':' || us.start_time AS instance_key,
      us.shift_date,
      us.start_time::TIME AS start_time,
      us.end_time::TIME AS end_time,
      ((us.shift_date::TEXT || ' ' || us.start_time)::TIMESTAMP AT TIME ZONE 'Europe/Oslo') AS shift_start_ts
    FROM public.user_shifts us
    LEFT JOIN public.jobs j ON j.id = us.job_id
    WHERE us.shift_date >= CURRENT_DATE
      AND us.shift_date <= CURRENT_DATE + INTERVAL '3 days'
      AND us.deleted_at IS NULL
  ),
  shift_reminders AS (
    SELECT
      ss.user_id,
      ss.job_id,
      ss.job_name,
      ss.instance_key,
      ss.shift_date,
      ss.start_time,
      ss.end_time,
      ss.shift_start_ts,
      ur.reminder_mins
    FROM single_shifts ss
    JOIN user_reminders ur ON ur.user_id = ss.user_id
  ),
  due_shifts AS (
    SELECT
      sr.*,
      EXTRACT(EPOCH FROM (sr.shift_start_ts - NOW())) / 60 AS mins_until
    FROM shift_reminders sr
    WHERE sr.shift_start_ts > NOW()
  )
  SELECT
    ds.user_id,
    ds.instance_key AS shift_instance_key,
    ds.shift_date,
    ds.start_time,
    ds.end_time,
    ds.reminder_mins AS reminder_minutes,
    CEIL(ds.mins_until)::INTEGER AS minutes_until_shift,
    ds.job_id,
    ds.job_name
  FROM due_shifts ds
  WHERE ds.mins_until <= ds.reminder_mins
    AND ds.mins_until >= (ds.reminder_mins - cron_interval_minutes);
END;
$function$;

COMMIT;


-- Source: supabase/sql/migrations/20260228153000_add_show_dashboard_clock_buttons_to_user_settings.sql

-- Add a user setting controlling dashboard clock button visibility.
alter table public.user_settings
  add column if not exists show_dashboard_clock_buttons boolean not null default true;

comment on column public.user_settings.show_dashboard_clock_buttons is
  'Whether Clock in/Clock out buttons are shown on the dashboard UI.';


-- Source: supabase/sql/migrations/20260301120000_add_default_startup_tab_to_user_settings.sql

-- Add default startup tab preference for mobile app launch behavior.
alter table public.user_settings
  add column if not exists default_startup_tab text not null default 'home';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_settings_default_startup_tab_valid'
      and conrelid = 'public.user_settings'::regclass
  ) then
    alter table public.user_settings
      add constraint user_settings_default_startup_tab_valid
      check (default_startup_tab in ('home', 'shifts', 'add', 'stats', 'sharing'));
  end if;
end $$;

comment on column public.user_settings.default_startup_tab is
  'Default tab to open when launching the app: home, shifts, add, stats, or sharing.';


-- Source: supabase/sql/migrations/20260305153000_job_scoped_immutable_currency.sql

-- Job-scoped immutable currency

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS currency text;

UPDATE public.jobs j
SET currency = COALESCE(us.currency, 'kr')
FROM public.user_settings us
WHERE us.user_id = j.user_id
  AND j.currency IS NULL;

UPDATE public.jobs
SET currency = 'kr'
WHERE currency IS NULL;

ALTER TABLE public.jobs
  ALTER COLUMN currency SET DEFAULT 'kr',
  ALTER COLUMN currency SET NOT NULL;

-- Function: ensure_job_currency_on_insert
-- Description:
--   Backward-compatibility guard for legacy clients that send jobs.currency as NULL.
--   Prefers user_settings.currency, then falls back to 'kr'.

CREATE OR REPLACE FUNCTION public.ensure_job_currency_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.currency IS NULL THEN
    SELECT COALESCE(us.currency, 'kr')
    INTO NEW.currency
    FROM public.user_settings us
    WHERE us.user_id = NEW.user_id
    LIMIT 1;

    NEW.currency := COALESCE(NEW.currency, 'kr');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS jobs_ensure_currency_on_insert ON public.jobs;
CREATE TRIGGER jobs_ensure_currency_on_insert
  BEFORE INSERT ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_job_currency_on_insert();

-- Function: reject_job_currency_change
-- Description:
--   Enforces immutable job currency after INSERT.

CREATE OR REPLACE FUNCTION public.reject_job_currency_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.currency IS DISTINCT FROM NEW.currency THEN
    RAISE EXCEPTION 'job currency is immutable' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS jobs_prevent_currency_change ON public.jobs;
CREATE TRIGGER jobs_prevent_currency_change
  BEFORE UPDATE OF currency ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_job_currency_change();

-- Function: ensure_default_job
-- Description:
--   Ensures a user has one active default job and returns its ID.
--   Used by compatibility triggers for legacy clients that omit job_id.

CREATE OR REPLACE FUNCTION public.ensure_default_job(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
  v_payroll_day integer;
  v_half_tax_month integer;
  v_monthly_goal integer;
  v_currency text;
BEGIN
  SELECT j.id
  INTO v_job_id
  FROM public.jobs j
  WHERE j.user_id = p_user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
  LIMIT 1;

  IF v_job_id IS NULL THEN
    SELECT
      COALESCE(us.payroll_day, 15),
      us.half_tax_month,
      COALESCE(us.monthly_goal, 20000),
      COALESCE(us.currency, 'kr')
    INTO v_payroll_day, v_half_tax_month, v_monthly_goal, v_currency
    FROM public.user_settings us
    WHERE us.user_id = p_user_id
    LIMIT 1;

    INSERT INTO public.jobs (
      user_id,
      name,
      is_default,
      payroll_day,
      half_tax_month,
      monthly_goal,
      currency
    )
    VALUES (
      p_user_id,
      'Jobb',
      true,
      COALESCE(v_payroll_day, 15),
      v_half_tax_month,
      COALESCE(v_monthly_goal, 20000),
      COALESCE(v_currency, 'kr')
    )
    ON CONFLICT DO NOTHING;

    SELECT j.id
    INTO v_job_id
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

-- Function: handle_new_user
-- Description: Trigger function that creates a profile + default job for new users
-- Used by: AFTER INSERT trigger on auth.users

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.jobs (user_id, name, is_default, currency)
  VALUES (
    NEW.id,
    'Jobb',
    true,
    COALESCE(
      (
        SELECT us.currency
        FROM public.user_settings us
        WHERE us.user_id = NEW.id
        LIMIT 1
      ),
      'kr'
    )
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$function$;

-- Function: sync_default_job_to_legacy_settings
-- Description:
--   Mirrors default-job payroll fields to legacy user_settings fields.

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
    UPDATE public.user_settings
    SET payroll_day = NEW.payroll_day,
        half_tax_month = NEW.half_tax_month,
        monthly_goal = NEW.monthly_goal,
        currency = NEW.currency
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;

-- Function: sync_legacy_settings_to_default_job
-- Description:
--   Mirrors legacy payroll fields from user_settings to default job.

CREATE OR REPLACE FUNCTION public.sync_legacy_settings_to_default_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
  v_default_currency text;
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

  SELECT COALESCE(j.currency, 'kr')
  INTO v_default_currency
  FROM public.jobs j
  WHERE j.id = v_job_id
  LIMIT 1;

  IF NEW.currency IS DISTINCT FROM v_default_currency THEN
    UPDATE public.user_settings
    SET currency = v_default_currency
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_settings_mirror_to_jobs ON public.user_settings;
CREATE TRIGGER user_settings_mirror_to_jobs
  AFTER INSERT OR UPDATE OF payroll_day, half_tax_month, monthly_goal, currency
  ON public.user_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_legacy_settings_to_default_job();

DROP TRIGGER IF EXISTS jobs_mirror_to_user_settings ON public.jobs;
CREATE TRIGGER jobs_mirror_to_user_settings
  AFTER INSERT OR UPDATE OF payroll_day, half_tax_month, monthly_goal, is_default, currency
  ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_default_job_to_legacy_settings();

-- Function: get_shared_month_payload
-- Description:
--   Returns a raw month payload for one owner that has shared with the authenticated viewer.
--   Payload is consumed by iOS for client-side monthly computation.
--
-- Authorization:
--   - Viewer is auth.uid().
--   - Access requires shift_shares(owner_id = p_owner_id, viewer_id = auth.uid(), blocked = false).
--   - Unauthorized/blocked access returns no row.
--
-- Redaction:
--   - If show_earnings = false:
--       * wage/tax inputs are redacted in snapshots.
--       * shift custom supplements are redacted.
--       * recurring date_specific_supplements are redacted.

CREATE OR REPLACE FUNCTION public.get_shared_month_payload(
  p_owner_id uuid,
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  owner_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND ss.owner_id = p_owner_id
      AND COALESCE(ss.blocked, false) = false
    LIMIT 1
  ),
  month_bounds AS (
    SELECT
      make_date(p_year, p_month, 1) AS start_date,
      ((make_date(p_year, p_month, 1) + interval '1 month')::date - 1) AS end_date
  )
  SELECT
    a.owner_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal',
            COALESCE(
              CASE
                WHEN jsonb_typeof(us.monthly_goals_by_month) = 'object'
                  AND COALESCE(
                    us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'),
                    ''
                  ) ~ '^[0-9]+$'
                THEN (us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'))::integer
                ELSE NULL
              END,
              us.monthly_goal
            ),
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.owner_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.owner_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        CROSS JOIN month_bounds mb
        WHERE s.user_id = a.owner_id
          AND s.deleted_at IS NULL
          AND s.shift_date >= mb.start_date
          AND s.shift_date <= mb.end_date
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.owner_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.owner_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'currency', j.currency,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.owner_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) TO authenticated;

-- Function: get_my_sharer_preview_payloads
-- Description:
--   Returns raw payloads for each sharer visible to the authenticated viewer.
--   Intended for client-side preview computation (active/upcoming/past).
--
-- Authorization:
--   - Viewer is auth.uid().
--   - Only rows from shift_shares where viewer_id = auth.uid() and blocked = false.
--
-- Redaction:
--   - If show_earnings = false:
--       * wage/tax inputs are redacted in snapshots.
--       * shift custom supplements are redacted.
--       * recurring date_specific_supplements are redacted.

CREATE OR REPLACE FUNCTION public.get_my_sharer_preview_payloads(
  p_sharer_ids uuid[] DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  sharer_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id AS sharer_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND COALESCE(ss.blocked, false) = false
      AND (p_sharer_ids IS NULL OR ss.owner_id = ANY(p_sharer_ids))
  )
  SELECT
    a.sharer_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal', us.monthly_goal,
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.sharer_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.sharer_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        WHERE s.user_id = a.sharer_id
          AND s.deleted_at IS NULL
          AND (p_start_date IS NULL OR s.shift_date >= p_start_date)
          AND (p_end_date IS NULL OR s.shift_date <= p_end_date)
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.sharer_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.sharer_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'currency', j.currency,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.sharer_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a
  ORDER BY a.sharer_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) TO authenticated;


-- Source: supabase/sql/migrations/20260307110000_cascade_delete_wage_snapshots_for_jobs.sql

BEGIN;

ALTER TABLE public.wage_snapshots
  DROP CONSTRAINT IF EXISTS wage_snapshots_job_id_fkey_jobs;

ALTER TABLE public.wage_snapshots
  ADD CONSTRAINT wage_snapshots_job_id_fkey_jobs
  FOREIGN KEY (job_id)
  REFERENCES public.jobs(id)
  ON DELETE CASCADE;

COMMIT;


-- Source: supabase/sql/migrations/20260307214500_stop_auto_creating_default_jobs.sql

-- Stop creating default jobs for users who have not started work setup.
-- Keep lazy default-job creation for legacy work writes that omit job_id.

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_legacy_settings_to_default_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
  v_default_currency text;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  SELECT j.id
  INTO v_job_id
  FROM public.jobs j
  WHERE j.user_id = NEW.user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
  LIMIT 1;

  IF v_job_id IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.jobs
  SET payroll_day = NEW.payroll_day,
      half_tax_month = NEW.half_tax_month,
      monthly_goal = NEW.monthly_goal
  WHERE id = v_job_id;

  SELECT COALESCE(j.currency, 'kr')
  INTO v_default_currency
  FROM public.jobs j
  WHERE j.id = v_job_id
  LIMIT 1;

  IF NEW.currency IS DISTINCT FROM v_default_currency THEN
    UPDATE public.user_settings
    SET currency = v_default_currency
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;


-- Source: supabase/sql/migrations/20260308001104_shift_shares_hidden_compat.sql

ALTER TABLE public.shift_shares
  ADD COLUMN IF NOT EXISTS hidden boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS blocked_by_user_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'shift_shares_blocked_by_user_id_fkey'
  ) THEN
    ALTER TABLE public.shift_shares
      ADD CONSTRAINT shift_shares_blocked_by_user_id_fkey
      FOREIGN KEY (blocked_by_user_id)
      REFERENCES auth.users(id)
      ON DELETE SET NULL;
  END IF;
END $$;

COMMENT ON COLUMN public.shift_shares.blocked IS 'Legacy compatibility field for hidden-from-view state. Keep in sync with hidden during the migration window.';
COMMENT ON COLUMN public.shift_shares.hidden IS 'Current hidden-from-view field. Replaces legacy blocked semantics for new clients.';
COMMENT ON COLUMN public.shift_shares.blocked_by_user_id IS 'Reserved for abuse-block state. Null means no abuse block.';

CREATE OR REPLACE FUNCTION public.enforce_shift_shares_update_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    return new;
  end if;

  if new.id != old.id then
    raise exception 'Cannot modify id column';
  end if;
  if new.owner_id != old.owner_id then
    raise exception 'Cannot modify owner_id column';
  end if;
  if new.viewer_id != old.viewer_id then
    raise exception 'Cannot modify viewer_id column';
  end if;
  if new.created_at != old.created_at then
    raise exception 'Cannot modify created_at column';
  end if;

  if v_uid = old.viewer_id then
    if new.show_earnings is distinct from old.show_earnings then
      raise exception 'Viewers cannot modify show_earnings column';
    end if;
    if new.owner_muted is distinct from old.owner_muted then
      raise exception 'Viewers cannot modify owner_muted column';
    end if;
    if new.blocked_by_user_id is distinct from old.blocked_by_user_id then
      raise exception 'Clients cannot modify blocked_by_user_id directly';
    end if;
  end if;

  if v_uid = old.owner_id then
    if new.blocked is distinct from old.blocked then
      raise exception 'Owners cannot modify blocked column';
    end if;
    if new.hidden is distinct from old.hidden then
      raise exception 'Owners cannot modify hidden column';
    end if;
    if new.muted is distinct from old.muted then
      raise exception 'Owners cannot modify muted column';
    end if;
    if new.blocked_by_user_id is distinct from old.blocked_by_user_id then
      raise exception 'Clients cannot modify blocked_by_user_id directly';
    end if;
  end if;

  if v_uid is not null and new.blocked_by_user_id is distinct from old.blocked_by_user_id then
    raise exception 'Clients cannot modify blocked_by_user_id directly';
  end if;

  return new;
end;
$function$;

UPDATE public.shift_shares
SET hidden = COALESCE(blocked, false)
WHERE hidden IS DISTINCT FROM COALESCE(blocked, false);

CREATE OR REPLACE FUNCTION public.sync_shift_shares_hidden_legacy_blocked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.hidden := COALESCE(NEW.hidden, false);
    NEW.blocked := COALESCE(NEW.blocked, false);

    IF NEW.hidden IS DISTINCT FROM NEW.blocked THEN
      IF NEW.hidden = false AND NEW.blocked = true THEN
        NEW.hidden := NEW.blocked;
      ELSIF NEW.hidden = true AND NEW.blocked = false THEN
        NEW.blocked := NEW.hidden;
      ELSE
        RAISE EXCEPTION 'shift_shares.hidden and shift_shares.blocked must match during compatibility window';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.hidden IS DISTINCT FROM OLD.hidden
     AND NEW.blocked IS DISTINCT FROM OLD.blocked THEN
    IF NEW.hidden IS DISTINCT FROM NEW.blocked THEN
      RAISE EXCEPTION 'shift_shares.hidden and shift_shares.blocked cannot diverge during compatibility window';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.hidden IS DISTINCT FROM OLD.hidden THEN
    NEW.blocked := NEW.hidden;
  ELSIF NEW.blocked IS DISTINCT FROM OLD.blocked THEN
    NEW.hidden := NEW.blocked;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS aa_shift_shares_sync_hidden_blocked ON public.shift_shares;
CREATE TRIGGER aa_shift_shares_sync_hidden_blocked
  BEFORE INSERT OR UPDATE ON public.shift_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_shift_shares_hidden_legacy_blocked();

CREATE OR REPLACE FUNCTION public.get_shared_month_payload(
  p_owner_id uuid,
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  owner_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND ss.owner_id = p_owner_id
      AND COALESCE(ss.hidden, false) = false
    LIMIT 1
  ),
  month_bounds AS (
    SELECT
      make_date(p_year, p_month, 1) AS start_date,
      ((make_date(p_year, p_month, 1) + interval '1 month')::date - 1) AS end_date
  )
  SELECT
    a.owner_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal',
            COALESCE(
              CASE
                WHEN jsonb_typeof(us.monthly_goals_by_month) = 'object'
                  AND COALESCE(
                    us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'),
                    ''
                  ) ~ '^[0-9]+$'
                THEN (us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'))::integer
                ELSE NULL
              END,
              us.monthly_goal
            ),
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.owner_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.owner_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        CROSS JOIN month_bounds mb
        WHERE s.user_id = a.owner_id
          AND s.deleted_at IS NULL
          AND s.shift_date >= mb.start_date
          AND s.shift_date <= mb.end_date
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.owner_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.owner_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'currency', j.currency,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.owner_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_sharer_preview_payloads(
  p_sharer_ids uuid[] DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  sharer_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id AS sharer_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND COALESCE(ss.hidden, false) = false
      AND (p_sharer_ids IS NULL OR ss.owner_id = ANY(p_sharer_ids))
  )
  SELECT
    a.sharer_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal', us.monthly_goal,
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.sharer_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.sharer_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        WHERE s.user_id = a.sharer_id
          AND s.deleted_at IS NULL
          AND (p_start_date IS NULL OR s.shift_date >= p_start_date)
          AND (p_end_date IS NULL OR s.shift_date <= p_end_date)
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.sharer_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.sharer_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'currency', j.currency,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.sharer_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a
  ORDER BY a.sharer_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_sharers()
RETURNS TABLE (
  id uuid,
  email text,
  phone text,
  first_name text,
  profile_picture_url text,
  oauth_avatar_url text,
  shared_at timestamptz,
  show_earnings boolean,
  blocked boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    ss.owner_id AS id,
    au.email,
    au.phone,
    COALESCE(
      au.raw_user_meta_data->>'full_name',
      au.raw_user_meta_data->>'name'
    ) AS first_name,
    us.profile_picture_url,
    COALESCE(
      au.raw_user_meta_data->>'avatar_url',
      au.raw_user_meta_data->>'picture'
    ) AS oauth_avatar_url,
    ss.created_at AS shared_at,
    COALESCE(ss.show_earnings, false) AS show_earnings,
    COALESCE(ss.hidden, false) AS blocked
  FROM public.shift_shares ss
  LEFT JOIN auth.users au
    ON au.id = ss.owner_id
  LEFT JOIN public.user_settings us
    ON us.user_id = ss.owner_id
  WHERE auth.uid() IS NOT NULL
    AND ss.viewer_id = auth.uid()
    AND COALESCE(ss.hidden, false) = false
  ORDER BY ss.created_at DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharers() TO authenticated;


-- Source: supabase/sql/migrations/20260308004151_friends_messaging_backend_core.sql

CREATE TABLE public.threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('direct', 'room', 'feed')),
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  title text NULL,
  avatar_url text NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_message_id uuid NULL,
  last_message_sender_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.direct_threads (
  thread_id uuid PRIMARY KEY REFERENCES public.threads(id) ON DELETE CASCADE,
  user_low_id uuid NOT NULL REFERENCES auth.users(id),
  user_high_id uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT direct_threads_distinct_users CHECK (user_low_id <> user_high_id),
  CONSTRAINT direct_threads_ordered_users CHECK (user_low_id < user_high_id),
  CONSTRAINT direct_threads_user_pair_key UNIQUE (user_low_id, user_high_id)
);

CREATE TABLE public.thread_memberships (
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'poster', 'reader')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'left')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz NULL,
  PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES auth.users(id),
  message_type text NOT NULL DEFAULT 'user' CHECK (message_type IN ('user', 'system')),
  body text NULL,
  client_id uuid NOT NULL,
  reply_to_message_id uuid NULL REFERENCES public.messages(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  edited_at timestamptz NULL,
  deleted_at timestamptz NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT messages_sender_client_id_key UNIQUE (thread_id, sender_user_id, client_id)
);

CREATE TABLE public.thread_user_state (
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  last_read_message_id uuid NULL REFERENCES public.messages(id) ON DELETE SET NULL,
  last_read_at timestamptz NULL,
  muted boolean NOT NULL DEFAULT false,
  archived_at timestamptz NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE public.message_attachments (
  id uuid PRIMARY KEY,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  attachment_index integer NOT NULL CHECK (attachment_index >= 0),
  kind text NOT NULL CHECK (kind IN ('image')),
  storage_bucket text NOT NULL,
  storage_path text NOT NULL,
  mime_type text NOT NULL,
  byte_size bigint NOT NULL CHECK (byte_size > 0),
  width integer NULL CHECK (width IS NULL OR width > 0),
  height integer NULL CHECK (height IS NULL OR height > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT message_attachments_message_id_attachment_index_key UNIQUE (message_id, attachment_index),
  CONSTRAINT message_attachments_storage_object_key UNIQUE (storage_bucket, storage_path)
);

ALTER TABLE public.threads
  ADD CONSTRAINT threads_last_message_id_fkey
  FOREIGN KEY (last_message_id)
  REFERENCES public.messages(id)
  ON DELETE SET NULL;

CREATE INDEX threads_last_message_at_id_idx
  ON public.threads (last_message_at DESC, id DESC);

CREATE INDEX thread_memberships_user_id_status_idx
  ON public.thread_memberships (user_id, status);

CREATE INDEX messages_thread_id_created_at_id_idx
  ON public.messages (thread_id, created_at DESC, id DESC);

CREATE INDEX message_attachments_message_id_attachment_index_idx
  ON public.message_attachments (message_id, attachment_index);

ALTER TABLE public.threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.direct_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thread_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thread_user_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_attachments ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_user_pair_abuse_blocked(p_other_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_other_user_id IS NULL OR v_uid = p_other_user_id THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND ss.blocked_by_user_id IS NOT NULL
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.is_user_pair_abuse_blocked(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.is_user_pair_abuse_blocked(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_user_pair_abuse_blocked(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_create_direct_thread(p_other_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_other_user_id IS NULL OR v_uid = p_other_user_id THEN
    RETURN false;
  END IF;

  IF public.is_user_pair_abuse_blocked(p_other_user_id) THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND ss.blocked_by_user_id IS NULL
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_access_thread(p_thread_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.thread_memberships tm
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_access_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_post_to_thread(p_thread_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_other_user_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  SELECT tm.role, tm.status
  INTO v_role, v_status
  FROM public.thread_memberships tm
  WHERE tm.thread_id = p_thread_id
    AND tm.user_id = v_uid
  LIMIT 1;

  IF v_status IS DISTINCT FROM 'active' OR v_role IS NULL OR v_role = 'reader' THEN
    RETURN false;
  END IF;

  SELECT CASE
    WHEN dt.user_low_id = v_uid THEN dt.user_high_id
    WHEN dt.user_high_id = v_uid THEN dt.user_low_id
    ELSE NULL
  END
  INTO v_other_user_id
  FROM public.direct_threads dt
  WHERE dt.thread_id = p_thread_id
  LIMIT 1;

  IF v_other_user_id IS NOT NULL AND public.is_user_pair_abuse_blocked(v_other_user_id) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_post_to_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_post_to_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_post_to_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_upload_message_attachment_object(p_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_parts text[];
  v_thread_id uuid;
  v_path_user_id uuid;
BEGIN
  IF v_uid IS NULL OR p_path IS NULL OR p_path = '' THEN
    RETURN false;
  END IF;

  IF lower(p_path) !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|heic|heif|jpeg|jpg|png)$' THEN
    RETURN false;
  END IF;

  v_parts := string_to_array(p_path, '/');

  IF array_length(v_parts, 1) <> 3 THEN
    RETURN false;
  END IF;

  v_thread_id := v_parts[1]::uuid;
  v_path_user_id := v_parts[2]::uuid;

  IF v_path_user_id <> v_uid THEN
    RETURN false;
  END IF;

  RETURN public.can_post_to_thread(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_read_message_attachment_object(p_path text, p_owner_id text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_path IS NULL OR p_path = '' THEN
    RETURN false;
  END IF;

  IF p_owner_id = v_uid::text THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.message_attachments ma
    JOIN public.messages m
      ON m.id = ma.message_id
    WHERE ma.storage_bucket = 'message-attachments'
      AND ma.storage_path = p_path
      AND public.can_access_thread(m.thread_id)
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_message_payload(p_message_id uuid)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    m.id,
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.body,
    m.client_id,
    m.reply_to_message_id,
    m.created_at,
    m.edited_at,
    m.deleted_at,
    m.metadata,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', ma.id,
            'attachment_index', ma.attachment_index,
            'kind', ma.kind,
            'storage_bucket', ma.storage_bucket,
            'storage_path', ma.storage_path,
            'mime_type', ma.mime_type,
            'byte_size', ma.byte_size,
            'width', ma.width,
            'height', ma.height,
            'created_at', ma.created_at
          )
          ORDER BY ma.attachment_index ASC
        )
        FROM public.message_attachments ma
        WHERE ma.message_id = m.id
      ),
      '[]'::jsonb
    ) AS attachments
  FROM public.messages m
  WHERE m.id = p_message_id
    AND public.can_access_thread(m.thread_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_message_payload(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_thread_summary(p_thread_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH auth_context AS (
    SELECT auth.uid() AS user_id
  ),
  base_thread AS (
    SELECT
      t.id,
      t.kind,
      t.title,
      t.avatar_url,
      t.metadata,
      t.last_message_id,
      t.last_message_sender_id,
      t.last_message_at,
      t.created_at,
      tus.muted,
      dt.user_low_id,
      dt.user_high_id,
      cu.user_id
    FROM public.threads t
    JOIN auth_context cu
      ON cu.user_id IS NOT NULL
    JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = cu.user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = cu.user_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE t.id = p_thread_id
  ),
  counterpart AS (
    SELECT
      bt.*,
      CASE
        WHEN bt.kind = 'direct' AND bt.user_low_id = bt.user_id THEN bt.user_high_id
        WHEN bt.kind = 'direct' AND bt.user_high_id = bt.user_id THEN bt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM base_thread bt
  ),
  read_marker AS (
    SELECT
      tus.thread_id,
      rm.created_at AS last_read_created_at,
      rm.id AS last_read_message_id
    FROM public.thread_user_state tus
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    JOIN auth_context cu
      ON cu.user_id = tus.user_id
    WHERE tus.thread_id = p_thread_id
  )
  SELECT
    c.id AS thread_id,
    c.kind,
    c.title,
    c.avatar_url,
    c.metadata,
    c.counterpart_user_id,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        au.email,
        'Someone'
      )
    END AS counterpart_display_name,
    us.profile_picture_url AS counterpart_profile_picture_url,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'avatar_url',
        au.raw_user_meta_data->>'picture'
      )
    END AS counterpart_oauth_avatar_url,
    c.last_message_id,
    c.last_message_sender_id,
    c.last_message_at,
    lm.body AS last_message_body,
    EXISTS (
      SELECT 1
      FROM public.message_attachments lma
      WHERE lma.message_id = c.last_message_id
    ) AS last_message_has_image,
    COALESCE(
      (
        SELECT count(*)
        FROM public.messages um
        LEFT JOIN read_marker rm
          ON rm.thread_id = um.thread_id
        WHERE um.thread_id = c.id
          AND um.deleted_at IS NULL
          AND um.sender_user_id <> c.user_id
          AND (
            rm.last_read_message_id IS NULL
            OR (um.created_at, um.id) > (rm.last_read_created_at, rm.last_read_message_id)
          )
      ),
      0
    ) AS unread_count,
    COALESCE(c.muted, false) AS muted,
    c.created_at
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  LEFT JOIN public.messages lm
    ON lm.id = c.last_message_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_thread_summary(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_or_create_direct_thread(p_other_user_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_user_low_id uuid;
  v_user_high_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_create_direct_thread(p_other_user_id) THEN
    RAISE EXCEPTION 'Direct thread creation is not allowed for this user pair';
  END IF;

  v_user_low_id := LEAST(v_uid, p_other_user_id);
  v_user_high_id := GREATEST(v_uid, p_other_user_id);

  LOOP
    SELECT dt.thread_id
    INTO v_thread_id
    FROM public.direct_threads dt
    WHERE dt.user_low_id = v_user_low_id
      AND dt.user_high_id = v_user_high_id
    LIMIT 1;

    EXIT WHEN v_thread_id IS NOT NULL;

    BEGIN
      INSERT INTO public.threads (
        kind,
        created_by_user_id
      )
      VALUES (
        'direct',
        v_uid
      )
      RETURNING id INTO v_thread_id;

      INSERT INTO public.direct_threads (
        thread_id,
        user_low_id,
        user_high_id
      )
      VALUES (
        v_thread_id,
        v_user_low_id,
        v_user_high_id
      );

      EXIT;
    EXCEPTION
      WHEN unique_violation THEN
        v_thread_id := NULL;
    END;
  END LOOP;

  INSERT INTO public.thread_memberships (
    thread_id,
    user_id,
    role,
    status
  )
  VALUES
    (v_thread_id, v_user_low_id, 'member', 'active'),
    (v_thread_id, v_user_high_id, 'member', 'active')
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET
    role = EXCLUDED.role,
    status = 'active',
    left_at = NULL;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id
  )
  VALUES
    (v_thread_id, v_user_low_id),
    (v_thread_id, v_user_high_id)
  ON CONFLICT (thread_id, user_id) DO NOTHING;

  RETURN QUERY
  SELECT *
  FROM public.get_thread_summary(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_my_threads(
  p_limit integer DEFAULT 30,
  p_before_last_message_at timestamptz DEFAULT NULL,
  p_before_thread_id uuid DEFAULT NULL
)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH visible_threads AS (
    SELECT t.id, t.last_message_at
    FROM public.thread_memberships tm
    JOIN public.threads t
      ON t.id = tm.thread_id
    WHERE auth.uid() IS NOT NULL
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
      AND (
        p_before_last_message_at IS NULL
        OR p_before_thread_id IS NULL
        OR (t.last_message_at, t.id) < (p_before_last_message_at, p_before_thread_id)
      )
    ORDER BY t.last_message_at DESC, t.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  )
  SELECT summary.*
  FROM visible_threads vt
  CROSS JOIN LATERAL public.get_thread_summary(vt.id) AS summary
  ORDER BY summary.last_message_at DESC, summary.thread_id DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_thread_messages(
  p_thread_id uuid,
  p_limit integer DEFAULT 50,
  p_before_created_at timestamptz DEFAULT NULL,
  p_before_message_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF (p_before_created_at IS NULL) <> (p_before_message_id IS NULL) THEN
    RAISE EXCEPTION 'Pagination cursor requires both created_at and message_id';
  END IF;

  RETURN QUERY
  WITH selected_messages AS (
    SELECT m.id, m.created_at
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
      AND (
        p_before_created_at IS NULL
        OR (m.created_at, m.id) < (p_before_created_at, p_before_message_id)
      )
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
  )
  SELECT payload.*
  FROM selected_messages sm
  CROSS JOIN LATERAL public.get_message_payload(sm.id) AS payload
  ORDER BY payload.created_at ASC, payload.id ASC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_message(
  p_thread_id uuid,
  p_client_id uuid,
  p_body text,
  p_attachments jsonb DEFAULT '[]'::jsonb
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_normalized_body text;
  v_attachment_count integer := 0;
  v_existing_message_id uuid;
  v_message_id uuid;
  v_attachment record;
  v_object record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'client_id is required';
  END IF;

  IF NOT public.can_post_to_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Posting is not allowed for this thread';
  END IF;

  IF p_attachments IS NULL THEN
    p_attachments := '[]'::jsonb;
  END IF;

  IF jsonb_typeof(p_attachments) <> 'array' THEN
    RAISE EXCEPTION 'Attachments must be a JSON array';
  END IF;

  SELECT m.id
  INTO v_existing_message_id
  FROM public.messages m
  WHERE m.thread_id = p_thread_id
    AND m.sender_user_id = v_uid
    AND m.client_id = p_client_id
  LIMIT 1;

  IF v_existing_message_id IS NOT NULL THEN
    RETURN QUERY
    SELECT *
    FROM public.get_message_payload(v_existing_message_id);
    RETURN;
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NOT NULL AND char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  SELECT count(*)
  INTO v_attachment_count
  FROM jsonb_array_elements(p_attachments);

  IF v_attachment_count = 0 AND v_normalized_body IS NULL THEN
    RAISE EXCEPTION 'A message must include text or at least one attachment';
  END IF;

  IF v_attachment_count > 4 THEN
    RAISE EXCEPTION 'Too many attachments';
  END IF;

  FOR v_attachment IN
    SELECT
      ordinality - 1 AS attachment_index,
      (value->>'attachment_id')::uuid AS attachment_id,
      value->>'storage_path' AS storage_path,
      value->>'mime_type' AS mime_type,
      NULLIF(value->>'byte_size', '')::bigint AS byte_size,
      NULLIF(value->>'width', '')::integer AS width,
      NULLIF(value->>'height', '')::integer AS height
    FROM jsonb_array_elements(p_attachments) WITH ORDINALITY
  LOOP
    IF v_attachment.attachment_id IS NULL
       OR v_attachment.storage_path IS NULL
       OR v_attachment.mime_type IS NULL
       OR v_attachment.byte_size IS NULL THEN
      RAISE EXCEPTION 'Attachment descriptors must include attachment_id, storage_path, mime_type, and byte_size';
    END IF;

    IF v_attachment.mime_type NOT IN (
      'image/webp',
      'image/heic',
      'image/heif',
      'image/jpeg',
      'image/png'
    ) THEN
      RAISE EXCEPTION 'Unsupported attachment mime type: %', v_attachment.mime_type;
    END IF;

    IF NOT public.can_upload_message_attachment_object(v_attachment.storage_path) THEN
      RAISE EXCEPTION 'Invalid attachment path for this thread or user';
    END IF;

    IF split_part(split_part(v_attachment.storage_path, '/', 3), '.', 1)::uuid <> v_attachment.attachment_id THEN
      RAISE EXCEPTION 'Attachment path must contain the attachment_id in the file name';
    END IF;

    SELECT o.owner_id, o.metadata
    INTO v_object
    FROM storage.objects o
    WHERE o.bucket_id = 'message-attachments'
      AND o.name = v_attachment.storage_path
    LIMIT 1;

    IF v_object.owner_id IS NULL THEN
      RAISE EXCEPTION 'Attachment object not found';
    END IF;

    IF v_object.owner_id <> v_uid::text THEN
      RAISE EXCEPTION 'Attachment object owner mismatch';
    END IF;

    IF COALESCE(v_object.metadata->>'mimetype', '') <> v_attachment.mime_type THEN
      RAISE EXCEPTION 'Attachment mime type does not match stored object metadata';
    END IF;

    IF COALESCE((v_object.metadata->>'size')::bigint, -1) <> v_attachment.byte_size THEN
      RAISE EXCEPTION 'Attachment size does not match stored object metadata';
    END IF;

    IF v_attachment.byte_size <= 0 OR v_attachment.byte_size > 5242880 THEN
      RAISE EXCEPTION 'Attachment size exceeds the 5 MB limit';
    END IF;

    IF v_attachment.width IS NOT NULL AND v_attachment.width <= 0 THEN
      RAISE EXCEPTION 'Attachment width must be positive';
    END IF;

    IF v_attachment.height IS NOT NULL AND v_attachment.height <= 0 THEN
      RAISE EXCEPTION 'Attachment height must be positive';
    END IF;
  END LOOP;

  INSERT INTO public.messages (
    thread_id,
    sender_user_id,
    message_type,
    body,
    client_id
  )
  VALUES (
    p_thread_id,
    v_uid,
    'user',
    v_normalized_body,
    p_client_id
  )
  RETURNING messages.id INTO v_message_id;

  INSERT INTO public.message_attachments (
    id,
    message_id,
    attachment_index,
    kind,
    storage_bucket,
    storage_path,
    mime_type,
    byte_size,
    width,
    height
  )
  SELECT
    (value->>'attachment_id')::uuid,
    v_message_id,
    ordinality - 1,
    'image',
    'message-attachments',
    value->>'storage_path',
    value->>'mime_type',
    NULLIF(value->>'byte_size', '')::bigint,
    NULLIF(value->>'width', '')::integer,
    NULLIF(value->>'height', '')::integer
  FROM jsonb_array_elements(p_attachments) WITH ORDINALITY;

  UPDATE public.threads
  SET
    last_message_id = v_message_id,
    last_message_sender_id = v_uid,
    last_message_at = (
      SELECT m.created_at
      FROM public.messages m
      WHERE m.id = v_message_id
    )
  WHERE threads.id = p_thread_id;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(v_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_thread_read(
  p_thread_id uuid,
  p_through_message_id uuid
)
RETURNS public.thread_user_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_target_message public.messages%ROWTYPE;
  v_existing_state public.thread_user_state%ROWTYPE;
  v_existing_message public.messages%ROWTYPE;
  v_result public.thread_user_state%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT *
  INTO v_target_message
  FROM public.messages m
  WHERE m.id = p_through_message_id
    AND m.thread_id = p_thread_id
  LIMIT 1;

  IF v_target_message.id IS NULL THEN
    RAISE EXCEPTION 'Read marker message does not belong to the thread';
  END IF;

  SELECT *
  INTO v_existing_state
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  IF v_existing_state.last_read_message_id IS NOT NULL THEN
    SELECT *
    INTO v_existing_message
    FROM public.messages m
    WHERE m.id = v_existing_state.last_read_message_id
    LIMIT 1;
  END IF;

  IF v_existing_message.id IS NULL
     OR (v_target_message.created_at, v_target_message.id) > (v_existing_message.created_at, v_existing_message.id) THEN
    INSERT INTO public.thread_user_state (
      thread_id,
      user_id,
      last_read_message_id,
      last_read_at,
      updated_at
    )
    VALUES (
      p_thread_id,
      v_uid,
      v_target_message.id,
      v_target_message.created_at,
      now()
    )
    ON CONFLICT (thread_id, user_id) DO UPDATE
    SET
      last_read_message_id = EXCLUDED.last_read_message_id,
      last_read_at = EXCLUDED.last_read_at,
      updated_at = now();
  END IF;

  SELECT *
  INTO v_result
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_thread_muted(
  p_thread_id uuid,
  p_muted boolean
)
RETURNS public.thread_user_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result public.thread_user_state%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id,
    muted,
    updated_at
  )
  VALUES (
    p_thread_id,
    v_uid,
    COALESCE(p_muted, false),
    now()
  )
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET
    muted = EXCLUDED.muted,
    updated_at = now();

  SELECT *
  INTO v_result
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) FROM public;
REVOKE EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_message_content_validity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_message_id uuid := COALESCE(NEW.id, OLD.id);
  v_has_body boolean;
  v_attachment_count integer;
BEGIN
  SELECT
    NULLIF(regexp_replace(COALESCE(m.body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL,
    (
      SELECT count(*)
      FROM public.message_attachments ma
      WHERE ma.message_id = m.id
    )
  INTO v_has_body, v_attachment_count
  FROM public.messages m
  WHERE m.id = v_message_id;

  IF COALESCE(v_has_body, false) = false AND COALESCE(v_attachment_count, 0) = 0 THEN
    RAISE EXCEPTION 'A message must include text or at least one attachment';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_thread_message_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_sender_name text;
  v_thread_kind text;
  v_recipient record;
  v_body_preview text;
  v_rich_content_kind text;
BEGIN
  SELECT COALESCE(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', email, 'Someone')
  INTO v_sender_name
  FROM auth.users
  WHERE id = NEW.sender_user_id;

  IF v_sender_name IS NULL THEN
    v_sender_name := 'Someone';
  END IF;

  SELECT t.kind
  INTO v_thread_kind
  FROM public.threads t
  WHERE t.id = NEW.thread_id;

  v_body_preview := NULLIF(
    left(regexp_replace(COALESCE(NEW.body, ''), '\s+', ' ', 'g'), 120),
    ''
  );
  v_rich_content_kind := NULLIF(btrim(COALESCE(NEW.metadata->'content'->>'kind', '')), '');

  FOR v_recipient IN
    SELECT
      tm.user_id,
      COALESCE(tus.muted, false) AS muted,
      COALESCE(au.raw_user_meta_data->>'locale', 'en') AS locale
    FROM public.thread_memberships tm
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = tm.thread_id
     AND tus.user_id = tm.user_id
    LEFT JOIN auth.users au
      ON au.id = tm.user_id
    WHERE tm.thread_id = NEW.thread_id
      AND tm.status = 'active'
      AND tm.user_id <> NEW.sender_user_id
  LOOP
    IF v_recipient.muted THEN
      CONTINUE;
    END IF;

    INSERT INTO internal.notifications_outbox (
      owner_id,
      recipient_id,
      notification_type,
      due_at,
      title,
      body,
      data_payload,
      idempotency_key
    )
    VALUES (
      NEW.sender_user_id,
      v_recipient.user_id,
      'thread_message',
      now(),
      v_sender_name,
      COALESCE(
        v_body_preview,
        CASE
          WHEN v_rich_content_kind = 'shift_snapshot' THEN
            CASE
              WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' delte en vakt'
              ELSE v_sender_name || ' shared a shift'
            END
          WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' sendte et bilde'
          ELSE v_sender_name || ' sent a photo'
        END
      ),
      jsonb_build_object(
        'type', 'thread_message',
        'thread_id', NEW.thread_id,
        'message_id', NEW.id,
        'thread_kind', COALESCE(v_thread_kind, 'direct'),
        'sender_user_id', NEW.sender_user_id
      ),
      'thread_message:' || NEW.id || ':' || v_recipient.user_id
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$function$;

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'message-attachments',
  'message-attachments',
  false,
  5242880,
  ARRAY[
    'image/webp',
    'image/heic',
    'image/heif',
    'image/jpeg',
    'image/png'
  ]
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Members can view accessible threads" ON public.threads;
CREATE POLICY "Members can view accessible threads"
ON public.threads FOR SELECT TO authenticated
USING (public.can_access_thread(id));

DROP POLICY IF EXISTS "Members can view accessible direct thread pairs" ON public.direct_threads;
CREATE POLICY "Members can view accessible direct thread pairs"
ON public.direct_threads FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP POLICY IF EXISTS "Members can view accessible thread memberships" ON public.thread_memberships;
CREATE POLICY "Members can view accessible thread memberships"
ON public.thread_memberships FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP POLICY IF EXISTS "Members can view accessible thread state" ON public.thread_user_state;
CREATE POLICY "Members can view accessible thread state"
ON public.thread_user_state FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP POLICY IF EXISTS "Users can insert own thread state" ON public.thread_user_state;
CREATE POLICY "Users can insert own thread state"
ON public.thread_user_state FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND public.can_access_thread(thread_id)
);

DROP POLICY IF EXISTS "Users can update own thread state" ON public.thread_user_state;
CREATE POLICY "Users can update own thread state"
ON public.thread_user_state FOR UPDATE TO authenticated
USING (
  user_id = auth.uid()
  AND public.can_access_thread(thread_id)
)
WITH CHECK (
  user_id = auth.uid()
  AND public.can_access_thread(thread_id)
);

DROP POLICY IF EXISTS "Members can view accessible messages" ON public.messages;
CREATE POLICY "Members can view accessible messages"
ON public.messages FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP POLICY IF EXISTS "Members can view accessible message attachments" ON public.message_attachments;
CREATE POLICY "Members can view accessible message attachments"
ON public.message_attachments FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = message_id
      AND public.can_access_thread(m.thread_id)
  )
);

DROP POLICY IF EXISTS "Users can upload message attachments" ON storage.objects;
CREATE POLICY "Users can upload message attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'message-attachments'
  AND public.can_upload_message_attachment_object(name)
);

DROP POLICY IF EXISTS "Users can read published or own message attachments" ON storage.objects;
CREATE POLICY "Users can read published or own message attachments"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'message-attachments'
  AND public.can_read_message_attachment_object(name, owner_id)
);

DROP TRIGGER IF EXISTS thread_user_state_set_updated_at ON public.thread_user_state;
CREATE TRIGGER thread_user_state_set_updated_at
  BEFORE UPDATE ON public.thread_user_state
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS messages_enforce_content_validity ON public.messages;
CREATE CONSTRAINT TRIGGER messages_enforce_content_validity
  AFTER INSERT OR UPDATE ON public.messages
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_message_content_validity();

DROP TRIGGER IF EXISTS on_thread_message_notify ON public.messages;
CREATE TRIGGER on_thread_message_notify
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_thread_message_notification();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'supabase_realtime'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'threads'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.threads;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'messages'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'thread_user_state'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.thread_user_state;
    END IF;
  END IF;
END $$;


-- Source: supabase/sql/migrations/20260308013308_friends_messaging_safety_flows.sql

CREATE TABLE IF NOT EXISTS public.abuse_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid NOT NULL REFERENCES auth.users(id),
  reported_user_id uuid NOT NULL REFERENCES auth.users(id),
  thread_id uuid NOT NULL REFERENCES public.threads(id),
  message_id uuid NULL REFERENCES public.messages(id) ON DELETE SET NULL,
  reason text NOT NULL CHECK (
    reason = ANY (
      ARRAY[
        'harassment_or_bullying'::text,
        'sexual_content'::text,
        'hate_or_discriminatory_content'::text,
        'violence_or_threats'::text,
        'spam'::text,
        'inappropriate_profile_or_conduct'::text,
        'other'::text
      ]
    )
  ),
  note text NULL,
  status text NOT NULL DEFAULT 'open' CHECK (
    status = ANY (
      ARRAY[
        'open'::text,
        'in_review'::text,
        'actioned'::text,
        'dismissed'::text
      ]
    )
  ),
  reviewer_notes text NULL,
  reviewed_at timestamptz NULL,
  reviewed_by uuid NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT abuse_reports_reporter_not_reported CHECK (reporter_user_id <> reported_user_id),
  CONSTRAINT abuse_reports_note_length CHECK (note IS NULL OR char_length(note) <= 500)
);

CREATE INDEX IF NOT EXISTS idx_abuse_reports_status_created_at
  ON public.abuse_reports (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_abuse_reports_thread_created_at
  ON public.abuse_reports (thread_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_abuse_reports_reported_user_created_at
  ON public.abuse_reports (reported_user_id, created_at DESC);

ALTER TABLE public.abuse_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own abuse reports" ON public.abuse_reports;
CREATE POLICY "Users can view own abuse reports"
  ON public.abuse_reports
  FOR SELECT
  TO authenticated
  USING (reporter_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own abuse reports" ON public.abuse_reports;
CREATE POLICY "Users can insert own abuse reports"
  ON public.abuse_reports
  FOR INSERT
  TO authenticated
  WITH CHECK (reporter_user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.enforce_shift_shares_update_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
declare
  v_uid uuid := (select auth.uid());
begin
  if current_setting('tidex.allow_shift_share_abuse_block_update', true) = 'true' then
    return new;
  end if;

  -- Allow trusted maintenance/service-role updates without an auth user.
  if v_uid is null then
    return new;
  end if;

  -- Immutable columns
  if new.id != old.id then
    raise exception 'Cannot modify id column';
  end if;
  if new.owner_id != old.owner_id then
    raise exception 'Cannot modify owner_id column';
  end if;
  if new.viewer_id != old.viewer_id then
    raise exception 'Cannot modify viewer_id column';
  end if;
  if new.created_at != old.created_at then
    raise exception 'Cannot modify created_at column';
  end if;

  -- Viewer updates
  if v_uid = old.viewer_id then
    if new.show_earnings is distinct from old.show_earnings then
      raise exception 'Viewers cannot modify show_earnings column';
    end if;
    if new.owner_muted is distinct from old.owner_muted then
      raise exception 'Viewers cannot modify owner_muted column';
    end if;
    if new.blocked_by_user_id is distinct from old.blocked_by_user_id then
      raise exception 'Clients cannot modify blocked_by_user_id directly';
    end if;
  end if;

  -- Owner updates
  if v_uid = old.owner_id then
    if new.blocked is distinct from old.blocked then
      raise exception 'Owners cannot modify blocked column';
    end if;
    if new.hidden is distinct from old.hidden then
      raise exception 'Owners cannot modify hidden column';
    end if;
    if new.muted is distinct from old.muted then
      raise exception 'Owners cannot modify muted column';
    end if;
    if new.blocked_by_user_id is distinct from old.blocked_by_user_id then
      raise exception 'Clients cannot modify blocked_by_user_id directly';
    end if;
  end if;

  -- Direct client writes must not set abuse-block state yet.
  if v_uid is not null and new.blocked_by_user_id is distinct from old.blocked_by_user_id then
    raise exception 'Clients cannot modify blocked_by_user_id directly';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_abuse_report(
  p_thread_id uuid,
  p_reported_user_id uuid,
  p_message_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_reason text := lower(btrim(COALESCE(p_reason, '')));
  v_note text := NULLIF(btrim(COALESCE(p_note, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_thread_id IS NULL THEN
    RAISE EXCEPTION 'Thread is required';
  END IF;

  IF p_reported_user_id IS NULL THEN
    RAISE EXCEPTION 'Reported user is required';
  END IF;

  IF p_reported_user_id = v_uid THEN
    RAISE EXCEPTION 'Cannot report yourself';
  END IF;

  IF v_reason NOT IN (
    'harassment_or_bullying',
    'sexual_content',
    'hate_or_discriminatory_content',
    'violence_or_threats',
    'spam',
    'inappropriate_profile_or_conduct',
    'other'
  ) THEN
    RAISE EXCEPTION 'Invalid abuse report reason';
  END IF;

  IF v_note IS NOT NULL AND char_length(v_note) > 500 THEN
    RAISE EXCEPTION 'Report note must be 500 characters or less';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.thread_memberships tm
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = v_uid
      AND tm.status = 'active'
      AND tm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Thread not accessible';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.thread_memberships tm
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = p_reported_user_id
      AND tm.status = 'active'
      AND tm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reported user is not a member of this thread';
  END IF;

  IF p_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = p_message_id
      AND m.thread_id = p_thread_id
      AND m.sender_user_id = p_reported_user_id
  ) THEN
    RAISE EXCEPTION 'Reported message is invalid for this thread and user';
  END IF;

  INSERT INTO public.abuse_reports (
    reporter_user_id,
    reported_user_id,
    thread_id,
    message_id,
    reason,
    note
  )
  VALUES (
    v_uid,
    p_reported_user_id,
    p_thread_id,
    p_message_id,
    v_reason,
    v_note
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_abuse_report(uuid, uuid, uuid, text, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.create_abuse_report(uuid, uuid, uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_abuse_report(uuid, uuid, uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.block_user_pair(p_other_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_other_user_id IS NULL THEN
    RAISE EXCEPTION 'Blocked user is required';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Cannot block yourself';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
       OR (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
  ) THEN
    RAISE EXCEPTION 'No sharing relationship exists for this user pair';
  END IF;

  PERFORM set_config('tidex.allow_shift_share_abuse_block_update', 'true', true);

  UPDATE public.shift_shares ss
  SET hidden = true,
      blocked_by_user_id = v_uid
  WHERE (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
     OR (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.block_user_pair(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.block_user_pair(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.block_user_pair(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.queue_abuse_report_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_reporter_name text;
  v_summary text;
BEGIN
  SELECT COALESCE(
    au.raw_user_meta_data->>'full_name',
    au.raw_user_meta_data->>'name',
    au.email,
    'Tidex user'
  )
  INTO v_reporter_name
  FROM auth.users au
  WHERE au.id = NEW.reporter_user_id;

  v_summary := CASE
    WHEN NEW.message_id IS NULL THEN 'reporterte en samtale'
    ELSE 'rapporterte en melding'
  END;

  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    title,
    body,
    data_payload,
    idempotency_key,
    due_at,
    status
  )
  SELECT
    NEW.reporter_user_id,
    admin_user.id,
    'abuse_report_submitted',
    'Ny misbruksrapport',
    v_reporter_name || ' ' || v_summary,
    jsonb_build_object(
      'type', 'abuse_report_submitted',
      'report_id', NEW.id,
      'thread_id', NEW.thread_id,
      'message_id', NEW.message_id,
      'reported_user_id', NEW.reported_user_id,
      'deeplink', 'https://app.tidex.no/settings/admin?tab=reports&reportId=' || NEW.id::text
    ),
    'abuse_report:' || NEW.id::text || ':' || admin_user.id::text,
    NOW(),
    'pending'
  FROM auth.users admin_user
  WHERE admin_user.raw_app_meta_data->>'role' = 'admin'
    AND admin_user.deleted_at IS NULL
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_abuse_report_notify ON public.abuse_reports;
CREATE TRIGGER on_abuse_report_notify
  AFTER INSERT ON public.abuse_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_abuse_report_notification();


-- Source: supabase/sql/migrations/20260308032000_allow_hidden_sharers_preview_and_detail_access.sql

-- Allow hidden sharers to still provide previews and detail payloads when explicitly opened.

CREATE OR REPLACE FUNCTION public.get_my_sharer_preview_payloads(
  p_sharer_ids uuid[] DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  sharer_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id AS sharer_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND (p_sharer_ids IS NULL OR ss.owner_id = ANY(p_sharer_ids))
  )
  SELECT
    a.sharer_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal', us.monthly_goal,
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.sharer_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.sharer_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        WHERE s.user_id = a.sharer_id
          AND s.deleted_at IS NULL
          AND (p_start_date IS NULL OR s.shift_date >= p_start_date)
          AND (p_end_date IS NULL OR s.shift_date <= p_end_date)
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.sharer_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.sharer_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'currency', j.currency,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.sharer_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a
  ORDER BY a.sharer_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_shared_month_payload(
  p_owner_id uuid,
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  owner_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND ss.owner_id = p_owner_id
    LIMIT 1
  ),
  month_bounds AS (
    SELECT
      make_date(p_year, p_month, 1) AS start_date,
      ((make_date(p_year, p_month, 1) + interval '1 month')::date - 1) AS end_date
  )
  SELECT
    a.owner_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal',
            COALESCE(
              CASE
                WHEN jsonb_typeof(us.monthly_goals_by_month) = 'object'
                  AND COALESCE(
                    us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'),
                    ''
                  ) ~ '^[0-9]+$'
                THEN (us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'))::integer
                ELSE NULL
              END,
              us.monthly_goal
            ),
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.owner_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.owner_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        CROSS JOIN month_bounds mb
        WHERE s.user_id = a.owner_id
          AND s.deleted_at IS NULL
          AND s.shift_date >= mb.start_date
          AND s.shift_date <= mb.end_date
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.owner_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.owner_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'currency', j.currency,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.owner_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) TO authenticated;


-- Source: supabase/sql/migrations/20260308032000_friends_message_replies.sql

-- Function: send_message
-- Description: Validates and inserts a canonical user message with private attachments

CREATE OR REPLACE FUNCTION public.send_message(
  p_thread_id uuid,
  p_client_id uuid,
  p_body text,
  p_reply_to_message_id uuid DEFAULT NULL,
  p_attachments jsonb DEFAULT '[]'::jsonb
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_normalized_body text;
  v_attachment_count integer := 0;
  v_existing_message_id uuid;
  v_message_id uuid;
  v_attachment record;
  v_object record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'client_id is required';
  END IF;

  IF NOT public.can_post_to_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Posting is not allowed for this thread';
  END IF;

  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = p_reply_to_message_id
      AND m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reply target must exist in the same thread';
  END IF;

  IF p_attachments IS NULL THEN
    p_attachments := '[]'::jsonb;
  END IF;

  IF jsonb_typeof(p_attachments) <> 'array' THEN
    RAISE EXCEPTION 'Attachments must be a JSON array';
  END IF;

  SELECT m.id
  INTO v_existing_message_id
  FROM public.messages m
  WHERE m.thread_id = p_thread_id
    AND m.sender_user_id = v_uid
    AND m.client_id = p_client_id
  LIMIT 1;

  IF v_existing_message_id IS NOT NULL THEN
    RETURN QUERY
    SELECT *
    FROM public.get_message_payload(v_existing_message_id);
    RETURN;
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NOT NULL AND char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  SELECT count(*)
  INTO v_attachment_count
  FROM jsonb_array_elements(p_attachments);

  IF v_attachment_count = 0 AND v_normalized_body IS NULL THEN
    RAISE EXCEPTION 'A message must include text or at least one attachment';
  END IF;

  IF v_attachment_count > 4 THEN
    RAISE EXCEPTION 'Too many attachments';
  END IF;

  FOR v_attachment IN
    SELECT
      ordinality - 1 AS attachment_index,
      (value->>'attachment_id')::uuid AS attachment_id,
      value->>'storage_path' AS storage_path,
      value->>'mime_type' AS mime_type,
      NULLIF(value->>'byte_size', '')::bigint AS byte_size,
      NULLIF(value->>'width', '')::integer AS width,
      NULLIF(value->>'height', '')::integer AS height
    FROM jsonb_array_elements(p_attachments) WITH ORDINALITY
  LOOP
    IF v_attachment.attachment_id IS NULL
       OR v_attachment.storage_path IS NULL
       OR v_attachment.mime_type IS NULL
       OR v_attachment.byte_size IS NULL THEN
      RAISE EXCEPTION 'Attachment descriptors must include attachment_id, storage_path, mime_type, and byte_size';
    END IF;

    IF v_attachment.mime_type NOT IN (
      'image/webp',
      'image/heic',
      'image/heif',
      'image/jpeg',
      'image/png'
    ) THEN
      RAISE EXCEPTION 'Unsupported attachment mime type: %', v_attachment.mime_type;
    END IF;

    IF NOT public.can_upload_message_attachment_object(v_attachment.storage_path) THEN
      RAISE EXCEPTION 'Invalid attachment path for this thread or user';
    END IF;

    IF split_part(split_part(v_attachment.storage_path, '/', 3), '.', 1)::uuid <> v_attachment.attachment_id THEN
      RAISE EXCEPTION 'Attachment path must contain the attachment_id in the file name';
    END IF;

    SELECT o.owner_id, o.metadata
    INTO v_object
    FROM storage.objects o
    WHERE o.bucket_id = 'message-attachments'
      AND o.name = v_attachment.storage_path
    LIMIT 1;

    IF v_object.owner_id IS NULL THEN
      RAISE EXCEPTION 'Attachment object not found';
    END IF;

    IF v_object.owner_id <> v_uid::text THEN
      RAISE EXCEPTION 'Attachment object owner mismatch';
    END IF;

    IF COALESCE(v_object.metadata->>'mimetype', '') <> v_attachment.mime_type THEN
      RAISE EXCEPTION 'Attachment mime type does not match stored object metadata';
    END IF;

    IF COALESCE((v_object.metadata->>'size')::bigint, -1) <> v_attachment.byte_size THEN
      RAISE EXCEPTION 'Attachment size does not match stored object metadata';
    END IF;

    IF v_attachment.byte_size <= 0 OR v_attachment.byte_size > 5242880 THEN
      RAISE EXCEPTION 'Attachment size exceeds the 5 MB limit';
    END IF;

    IF v_attachment.width IS NOT NULL AND v_attachment.width <= 0 THEN
      RAISE EXCEPTION 'Attachment width must be positive';
    END IF;

    IF v_attachment.height IS NOT NULL AND v_attachment.height <= 0 THEN
      RAISE EXCEPTION 'Attachment height must be positive';
    END IF;
  END LOOP;

  INSERT INTO public.messages (
    thread_id,
    sender_user_id,
    message_type,
    body,
    client_id,
    reply_to_message_id
  )
  VALUES (
    p_thread_id,
    v_uid,
    'user',
    v_normalized_body,
    p_client_id,
    p_reply_to_message_id
  )
  RETURNING messages.id INTO v_message_id;

  INSERT INTO public.message_attachments (
    id,
    message_id,
    attachment_index,
    kind,
    storage_bucket,
    storage_path,
    mime_type,
    byte_size,
    width,
    height
  )
  SELECT
    (value->>'attachment_id')::uuid,
    v_message_id,
    ordinality - 1,
    'image',
    'message-attachments',
    value->>'storage_path',
    value->>'mime_type',
    NULLIF(value->>'byte_size', '')::bigint,
    NULLIF(value->>'width', '')::integer,
    NULLIF(value->>'height', '')::integer
  FROM jsonb_array_elements(p_attachments) WITH ORDINALITY;

  UPDATE public.threads
  SET
    last_message_id = v_message_id,
    last_message_sender_id = v_uid,
    last_message_at = (
      SELECT m.created_at
      FROM public.messages m
      WHERE m.id = v_message_id
    )
  WHERE threads.id = p_thread_id;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(v_message_id);
END;
$function$;

DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, jsonb);

REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb) TO authenticated;


-- Source: supabase/sql/migrations/20260308143000_include_hidden_sharers_in_get_my_sharers.sql

-- Include hidden sharers in get_my_sharers and expose the hidden flag directly.

DROP FUNCTION IF EXISTS public.get_my_sharers();

CREATE OR REPLACE FUNCTION public.get_my_sharers()
RETURNS TABLE (
  id uuid,
  email text,
  phone text,
  first_name text,
  profile_picture_url text,
  oauth_avatar_url text,
  shared_at timestamptz,
  show_earnings boolean,
  hidden boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    ss.owner_id AS id,
    au.email,
    au.phone,
    COALESCE(
      au.raw_user_meta_data->>'full_name',
      au.raw_user_meta_data->>'name'
    ) AS first_name,
    us.profile_picture_url,
    COALESCE(
      au.raw_user_meta_data->>'avatar_url',
      au.raw_user_meta_data->>'picture'
    ) AS oauth_avatar_url,
    ss.created_at AS shared_at,
    COALESCE(ss.show_earnings, false) AS show_earnings,
    COALESCE(ss.hidden, false) AS hidden
  FROM public.shift_shares ss
  LEFT JOIN auth.users au
    ON au.id = ss.owner_id
  LEFT JOIN public.user_settings us
    ON us.user_id = ss.owner_id
  WHERE auth.uid() IS NOT NULL
    AND ss.viewer_id = auth.uid()
  ORDER BY ss.created_at DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharers() TO authenticated;


-- Source: supabase/sql/migrations/20260308164500_allow_hidden_sharers_in_direct_threads.sql

-- Hidden sharers remain eligible for direct threads; only abuse blocks revoke chat access.

CREATE OR REPLACE FUNCTION public.can_create_direct_thread(p_other_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_other_user_id IS NULL OR v_uid = p_other_user_id THEN
    RETURN false;
  END IF;

  IF public.is_user_pair_abuse_blocked(p_other_user_id) THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND ss.blocked_by_user_id IS NULL
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) TO authenticated;


-- Source: supabase/sql/migrations/20260308234019_friends_message_reactions.sql

CREATE TABLE public.message_reactions (
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id, emoji),
  CONSTRAINT message_reactions_emoji_valid CHECK (
    btrim(emoji) <> ''
    AND char_length(emoji) <= 16
  )
);

CREATE INDEX message_reactions_thread_id_message_id_idx
  ON public.message_reactions (thread_id, message_id);

CREATE INDEX message_reactions_message_id_created_at_idx
  ON public.message_reactions (message_id, created_at ASC);

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view accessible message reactions" ON public.message_reactions;
CREATE POLICY "Members can view accessible message reactions"
ON public.message_reactions FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP FUNCTION IF EXISTS public.toggle_message_reaction(uuid, text);
DROP FUNCTION IF EXISTS public.list_thread_messages(uuid, integer, timestamptz, uuid);
DROP FUNCTION IF EXISTS public.get_message_payload(uuid);

CREATE OR REPLACE FUNCTION public.get_message_payload(p_message_id uuid)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb,
  reactions jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    m.id,
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.body,
    m.client_id,
    m.reply_to_message_id,
    m.created_at,
    m.edited_at,
    m.deleted_at,
    m.metadata,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', ma.id,
            'attachment_index', ma.attachment_index,
            'kind', ma.kind,
            'storage_bucket', ma.storage_bucket,
            'storage_path', ma.storage_path,
            'mime_type', ma.mime_type,
            'byte_size', ma.byte_size,
            'width', ma.width,
            'height', ma.height,
            'created_at', ma.created_at
          )
          ORDER BY ma.attachment_index ASC
        )
        FROM public.message_attachments ma
        WHERE ma.message_id = m.id
      ),
      '[]'::jsonb
    ) AS attachments,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'emoji', reaction_summary.emoji,
            'count', reaction_summary.reaction_count,
            'viewer_has_reacted', reaction_summary.viewer_has_reacted
          )
          ORDER BY
            reaction_summary.viewer_has_reacted DESC,
            reaction_summary.reaction_count DESC,
            reaction_summary.first_created_at ASC,
            reaction_summary.emoji ASC
        )
        FROM (
          SELECT
            mr.emoji,
            COUNT(*)::integer AS reaction_count,
            BOOL_OR(mr.user_id = auth.uid()) AS viewer_has_reacted,
            MIN(mr.created_at) AS first_created_at
          FROM public.message_reactions mr
          WHERE mr.message_id = m.id
          GROUP BY mr.emoji
        ) AS reaction_summary
      ),
      '[]'::jsonb
    ) AS reactions
  FROM public.messages m
  WHERE m.id = p_message_id
    AND public.can_access_thread(m.thread_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_message_payload(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_thread_messages(
  p_thread_id uuid,
  p_limit integer DEFAULT 50,
  p_before_created_at timestamptz DEFAULT NULL,
  p_before_message_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb,
  reactions jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF (p_before_created_at IS NULL) <> (p_before_message_id IS NULL) THEN
    RAISE EXCEPTION 'Pagination cursor requires both created_at and message_id';
  END IF;

  RETURN QUERY
  WITH selected_messages AS (
    SELECT m.id, m.created_at
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
      AND (
        p_before_created_at IS NULL
        OR (m.created_at, m.id) < (p_before_created_at, p_before_message_id)
      )
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
  )
  SELECT payload.*
  FROM selected_messages sm
  CROSS JOIN LATERAL public.get_message_payload(sm.id) AS payload
  ORDER BY payload.created_at ASC, payload.id ASC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.toggle_message_reaction(
  p_message_id uuid,
  p_emoji text
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb,
  reactions jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_emoji text := btrim(COALESCE(p_emoji, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF v_emoji = '' OR char_length(v_emoji) > 16 THEN
    RAISE EXCEPTION 'Reaction emoji is invalid';
  END IF;

  SELECT m.thread_id
  INTO v_thread_id
  FROM public.messages m
  WHERE m.id = p_message_id
    AND m.deleted_at IS NULL
  LIMIT 1;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF NOT public.can_post_to_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread is read only';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji
  ) THEN
    DELETE FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji;
  ELSE
    INSERT INTO public.message_reactions (
      thread_id,
      message_id,
      user_id,
      emoji
    )
    VALUES (
      v_thread_id,
      p_message_id,
      v_uid,
      v_emoji
    );
  END IF;

  RETURN QUERY
  SELECT payload.*
  FROM public.get_message_payload(p_message_id) AS payload;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text) TO authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'supabase_realtime'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'message_reactions'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions;
    END IF;
  END IF;
END $$;


-- Source: supabase/sql/migrations/20260309005000_fix_send_message_return_shape.sql

-- Fix send_message to match get_message_payload after reactions were added.
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, uuid, jsonb);
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, jsonb);

CREATE FUNCTION public.send_message(
  p_thread_id uuid,
  p_client_id uuid,
  p_body text,
  p_reply_to_message_id uuid DEFAULT NULL,
  p_attachments jsonb DEFAULT '[]'::jsonb
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb,
  reactions jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_normalized_body text;
  v_attachment_count integer := 0;
  v_existing_message_id uuid;
  v_message_id uuid;
  v_attachment record;
  v_object record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'client_id is required';
  END IF;

  IF NOT public.can_post_to_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Posting is not allowed for this thread';
  END IF;

  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = p_reply_to_message_id
      AND m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reply target must exist in the same thread';
  END IF;

  IF p_attachments IS NULL THEN
    p_attachments := '[]'::jsonb;
  END IF;

  IF jsonb_typeof(p_attachments) <> 'array' THEN
    RAISE EXCEPTION 'Attachments must be a JSON array';
  END IF;

  SELECT m.id
  INTO v_existing_message_id
  FROM public.messages m
  WHERE m.thread_id = p_thread_id
    AND m.sender_user_id = v_uid
    AND m.client_id = p_client_id
  LIMIT 1;

  IF v_existing_message_id IS NOT NULL THEN
    RETURN QUERY
    SELECT *
    FROM public.get_message_payload(v_existing_message_id);
    RETURN;
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NOT NULL AND char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  SELECT count(*)
  INTO v_attachment_count
  FROM jsonb_array_elements(p_attachments);

  IF v_attachment_count = 0 AND v_normalized_body IS NULL THEN
    RAISE EXCEPTION 'A message must include text or at least one attachment';
  END IF;

  IF v_attachment_count > 4 THEN
    RAISE EXCEPTION 'Too many attachments';
  END IF;

  FOR v_attachment IN
    SELECT
      ordinality - 1 AS attachment_index,
      (value->>'attachment_id')::uuid AS attachment_id,
      value->>'storage_path' AS storage_path,
      value->>'mime_type' AS mime_type,
      NULLIF(value->>'byte_size', '')::bigint AS byte_size,
      NULLIF(value->>'width', '')::integer AS width,
      NULLIF(value->>'height', '')::integer AS height
    FROM jsonb_array_elements(p_attachments) WITH ORDINALITY
  LOOP
    IF v_attachment.attachment_id IS NULL
       OR v_attachment.storage_path IS NULL
       OR v_attachment.mime_type IS NULL
       OR v_attachment.byte_size IS NULL THEN
      RAISE EXCEPTION 'Attachment descriptors must include attachment_id, storage_path, mime_type, and byte_size';
    END IF;

    IF v_attachment.mime_type NOT IN (
      'image/webp',
      'image/heic',
      'image/heif',
      'image/jpeg',
      'image/png'
    ) THEN
      RAISE EXCEPTION 'Unsupported attachment mime type: %', v_attachment.mime_type;
    END IF;

    IF NOT public.can_upload_message_attachment_object(v_attachment.storage_path) THEN
      RAISE EXCEPTION 'Invalid attachment path for this thread or user';
    END IF;

    IF split_part(split_part(v_attachment.storage_path, '/', 3), '.', 1)::uuid <> v_attachment.attachment_id THEN
      RAISE EXCEPTION 'Attachment path must contain the attachment_id in the file name';
    END IF;

    SELECT o.owner_id, o.metadata
    INTO v_object
    FROM storage.objects o
    WHERE o.bucket_id = 'message-attachments'
      AND o.name = v_attachment.storage_path
    LIMIT 1;

    IF v_object.owner_id IS NULL THEN
      RAISE EXCEPTION 'Attachment object not found';
    END IF;

    IF v_object.owner_id <> v_uid::text THEN
      RAISE EXCEPTION 'Attachment object owner mismatch';
    END IF;

    IF COALESCE(v_object.metadata->>'mimetype', '') <> v_attachment.mime_type THEN
      RAISE EXCEPTION 'Attachment mime type does not match stored object metadata';
    END IF;

    IF COALESCE((v_object.metadata->>'size')::bigint, -1) <> v_attachment.byte_size THEN
      RAISE EXCEPTION 'Attachment size does not match stored object metadata';
    END IF;

    IF v_attachment.byte_size <= 0 OR v_attachment.byte_size > 5242880 THEN
      RAISE EXCEPTION 'Attachment size exceeds the 5 MB limit';
    END IF;

    IF v_attachment.width IS NOT NULL AND v_attachment.width <= 0 THEN
      RAISE EXCEPTION 'Attachment width must be positive';
    END IF;

    IF v_attachment.height IS NOT NULL AND v_attachment.height <= 0 THEN
      RAISE EXCEPTION 'Attachment height must be positive';
    END IF;
  END LOOP;

  INSERT INTO public.messages (
    thread_id,
    sender_user_id,
    message_type,
    body,
    client_id,
    reply_to_message_id
  )
  VALUES (
    p_thread_id,
    v_uid,
    'user',
    v_normalized_body,
    p_client_id,
    p_reply_to_message_id
  )
  RETURNING messages.id INTO v_message_id;

  INSERT INTO public.message_attachments (
    id,
    message_id,
    attachment_index,
    kind,
    storage_bucket,
    storage_path,
    mime_type,
    byte_size,
    width,
    height
  )
  SELECT
    (value->>'attachment_id')::uuid,
    v_message_id,
    ordinality - 1,
    'image',
    'message-attachments',
    value->>'storage_path',
    value->>'mime_type',
    NULLIF(value->>'byte_size', '')::bigint,
    NULLIF(value->>'width', '')::integer,
    NULLIF(value->>'height', '')::integer
  FROM jsonb_array_elements(p_attachments) WITH ORDINALITY;

  UPDATE public.threads
  SET
    last_message_id = v_message_id,
    last_message_sender_id = v_uid,
    last_message_at = (
      SELECT m.created_at
      FROM public.messages m
      WHERE m.id = v_message_id
    )
  WHERE threads.id = p_thread_id;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(v_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb) TO authenticated;


-- Source: supabase/sql/migrations/20260309020930_friends_block_visibility_and_unblock.sql

-- Ensure abuse-blocked user pairs are hidden from sharing and messaging surfaces,
-- and add an explicit unblock RPC for clients.

CREATE OR REPLACE FUNCTION public.get_my_sharers()
RETURNS TABLE (
  id uuid,
  email text,
  phone text,
  first_name text,
  profile_picture_url text,
  oauth_avatar_url text,
  shared_at timestamptz,
  show_earnings boolean,
  hidden boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    ss.owner_id AS id,
    au.email,
    au.phone,
    COALESCE(
      au.raw_user_meta_data->>'full_name',
      au.raw_user_meta_data->>'name'
    ) AS first_name,
    us.profile_picture_url,
    COALESCE(
      au.raw_user_meta_data->>'avatar_url',
      au.raw_user_meta_data->>'picture'
    ) AS oauth_avatar_url,
    ss.created_at AS shared_at,
    COALESCE(ss.show_earnings, false) AS show_earnings,
    COALESCE(ss.hidden, false) AS hidden
  FROM public.shift_shares ss
  LEFT JOIN auth.users au
    ON au.id = ss.owner_id
  LEFT JOIN public.user_settings us
    ON us.user_id = ss.owner_id
  WHERE auth.uid() IS NOT NULL
    AND ss.viewer_id = auth.uid()
    AND ss.blocked_by_user_id IS NULL
  ORDER BY ss.created_at DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharers() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_shared_month_payload(
  p_owner_id uuid,
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  owner_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND ss.owner_id = p_owner_id
      AND ss.blocked_by_user_id IS NULL
    LIMIT 1
  ),
  month_bounds AS (
    SELECT
      make_date(p_year, p_month, 1) AS start_date,
      ((make_date(p_year, p_month, 1) + interval '1 month')::date - 1) AS end_date
  )
  SELECT
    a.owner_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal',
            COALESCE(
              CASE
                WHEN jsonb_typeof(us.monthly_goals_by_month) = 'object'
                  AND COALESCE(
                    us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'),
                    ''
                  ) ~ '^[0-9]+$'
                THEN (us.monthly_goals_by_month ->> to_char(make_date(p_year, p_month, 1), 'YYYY-MM'))::integer
                ELSE NULL
              END,
              us.monthly_goal
            ),
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.owner_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.owner_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        CROSS JOIN month_bounds mb
        WHERE s.user_id = a.owner_id
          AND s.deleted_at IS NULL
          AND s.shift_date >= mb.start_date
          AND s.shift_date <= mb.end_date
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.owner_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.owner_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'currency', j.currency,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.owner_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_sharer_preview_payloads(
  p_sharer_ids uuid[] DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  sharer_id uuid,
  show_earnings boolean,
  settings jsonb,
  shifts jsonb,
  recurring_shifts jsonb,
  snapshots jsonb,
  jobs jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH authorized AS (
    SELECT
      ss.owner_id AS sharer_id,
      COALESCE(ss.show_earnings, false) AS show_earnings
    FROM public.shift_shares ss
    WHERE auth.uid() IS NOT NULL
      AND ss.viewer_id = auth.uid()
      AND ss.blocked_by_user_id IS NULL
      AND (p_sharer_ids IS NULL OR ss.owner_id = ANY(p_sharer_ids))
  )
  SELECT
    a.sharer_id,
    a.show_earnings,
    COALESCE(
      (
        SELECT jsonb_build_object(
          'user_id', us.user_id,
          'created_at', us.created_at,
          'updated_at', us.updated_at,
          'last_active', us.last_active,
          'monthly_goal', us.monthly_goal,
          'monthly_goals_by_month', us.monthly_goals_by_month,
          'default_shifts_view', us.default_shifts_view,
          'profile_picture_url', us.profile_picture_url,
          'payroll_day', us.payroll_day,
          'theme', us.theme,
          'calendar_animation_style', us.calendar_animation_style,
          'half_tax_month', us.half_tax_month,
          'currency', us.currency
        )
        FROM public.user_settings us
        WHERE us.user_id = a.sharer_id
        LIMIT 1
      ),
      jsonb_build_object(
        'user_id', a.sharer_id
      )
    ) AS settings,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'user_id', s.user_id,
            'job_id', s.job_id,
            'shift_date', s.shift_date,
            'start_time', s.start_time,
            'end_time', s.end_time,
            'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
            'recurring_id', NULL,
            'recurring_anchor_weekday', NULL
          )
          ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
        )
        FROM public.user_shifts s
        WHERE s.user_id = a.sharer_id
          AND s.deleted_at IS NULL
          AND (p_start_date IS NULL OR s.shift_date >= p_start_date)
          AND (p_end_date IS NULL OR s.shift_date <= p_end_date)
      ),
      '[]'::jsonb
    ) AS shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'job_id', r.job_id,
            'start_time', r.start_time,
            'end_time', r.end_time,
            'repeat_interval_weeks', r.repeat_interval_weeks,
            'selected_days', r.selected_days,
            'end_condition', r.end_condition,
            'exclusions', r.exclusions,
            'date_specific_supplements',
              CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
          )
          ORDER BY r.id ASC
        )
        FROM public.recurring_shifts r
        WHERE r.user_id = a.sharer_id
          AND r.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS recurring_shifts,
    COALESCE(
      (
        SELECT jsonb_agg(
          CASE
            WHEN a.show_earnings THEN jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', w.hourly_wage,
              'wage_level', w.wage_level,
              'tariff_type_id', w.tariff_type_id,
              'supplements', w.supplements,
              'tax_enabled', w.tax_enabled,
              'tax_percentage', w.tax_percentage,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
            ELSE jsonb_build_object(
              'id', w.id,
              'user_id', w.user_id,
              'job_id', w.job_id,
              'from_date', w.from_date,
              'hourly_wage', 0,
              'wage_level', NULL,
              'tariff_type_id', NULL,
              'supplements', jsonb_build_object('rules', jsonb_build_array()),
              'tax_enabled', false,
              'tax_percentage', 0,
              'break_enabled', w.break_enabled,
              'break_method', w.break_method,
              'break_threshold_hours', w.break_threshold_hours,
              'break_deduction_minutes', w.break_deduction_minutes,
              'created_at', w.created_at
            )
          END
          ORDER BY w.from_date DESC NULLS LAST, w.id ASC
        )
        FROM public.wage_snapshots w
        WHERE w.user_id = a.sharer_id
          AND w.deleted_at IS NULL
      ),
      '[]'::jsonb
    ) AS snapshots,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', j.id,
            'user_id', j.user_id,
            'name', j.name,
            'color', j.color,
            'is_default', j.is_default,
            'sort_order', j.sort_order,
            'currency', j.currency,
            'payroll_day', j.payroll_day,
            'half_tax_month', j.half_tax_month,
            'monthly_goal', j.monthly_goal,
            'archived_at', j.archived_at,
            'deleted_at', j.deleted_at,
            'created_at', j.created_at,
            'updated_at', j.updated_at
          )
          ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
        )
        FROM public.jobs j
        WHERE j.user_id = a.sharer_id
      ),
      '[]'::jsonb
    ) AS jobs
  FROM authorized a
  ORDER BY a.sharer_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_access_thread(p_thread_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH current_membership AS (
    SELECT
      tm.thread_id,
      CASE
        WHEN dt.user_low_id = auth.uid() THEN dt.user_high_id
        WHEN dt.user_high_id = auth.uid() THEN dt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM public.thread_memberships tm
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = tm.thread_id
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
  )
  SELECT EXISTS (
    SELECT 1
    FROM current_membership cm
    WHERE cm.counterpart_user_id IS NULL
      OR NOT public.is_user_pair_abuse_blocked(cm.counterpart_user_id)
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_access_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_thread_summary(p_thread_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH auth_context AS (
    SELECT auth.uid() AS user_id
  ),
  base_thread AS (
    SELECT
      t.id,
      t.kind,
      t.title,
      t.avatar_url,
      t.metadata,
      t.last_message_id,
      t.last_message_sender_id,
      t.last_message_at,
      t.created_at,
      tus.muted,
      dt.user_low_id,
      dt.user_high_id,
      cu.user_id
    FROM public.threads t
    JOIN auth_context cu
      ON cu.user_id IS NOT NULL
    JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = cu.user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = cu.user_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE t.id = p_thread_id
  ),
  counterpart AS (
    SELECT
      bt.*,
      CASE
        WHEN bt.kind = 'direct' AND bt.user_low_id = bt.user_id THEN bt.user_high_id
        WHEN bt.kind = 'direct' AND bt.user_high_id = bt.user_id THEN bt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM base_thread bt
  ),
  read_marker AS (
    SELECT
      tus.thread_id,
      rm.created_at AS last_read_created_at,
      rm.id AS last_read_message_id
    FROM public.thread_user_state tus
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    JOIN auth_context cu
      ON cu.user_id = tus.user_id
    WHERE tus.thread_id = p_thread_id
  )
  SELECT
    c.id AS thread_id,
    c.kind,
    c.title,
    c.avatar_url,
    c.metadata,
    c.counterpart_user_id,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        au.email,
        'Someone'
      )
    END AS counterpart_display_name,
    us.profile_picture_url AS counterpart_profile_picture_url,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'avatar_url',
        au.raw_user_meta_data->>'picture'
      )
    END AS counterpart_oauth_avatar_url,
    c.last_message_id,
    c.last_message_sender_id,
    c.last_message_at,
    lm.body AS last_message_body,
    EXISTS (
      SELECT 1
      FROM public.message_attachments lma
      WHERE lma.message_id = c.last_message_id
    ) AS last_message_has_image,
    COALESCE(
      (
        SELECT count(*)
        FROM public.messages um
        LEFT JOIN read_marker rm
          ON rm.thread_id = um.thread_id
        WHERE um.thread_id = c.id
          AND um.deleted_at IS NULL
          AND um.sender_user_id <> c.user_id
          AND (
            rm.last_read_message_id IS NULL
            OR (um.created_at, um.id) > (rm.last_read_created_at, rm.last_read_message_id)
          )
      ),
      0
    ) AS unread_count,
    COALESCE(c.muted, false) AS muted,
    c.created_at
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  LEFT JOIN public.messages lm
    ON lm.id = c.last_message_id
  WHERE c.counterpart_user_id IS NULL
     OR NOT public.is_user_pair_abuse_blocked(c.counterpart_user_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_thread_summary(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_my_threads(
  p_limit integer DEFAULT 30,
  p_before_last_message_at timestamptz DEFAULT NULL,
  p_before_thread_id uuid DEFAULT NULL
)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH visible_threads AS (
    SELECT t.id, t.last_message_at
    FROM public.thread_memberships tm
    JOIN public.threads t
      ON t.id = tm.thread_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE auth.uid() IS NOT NULL
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
      AND (
        dt.thread_id IS NULL
        OR NOT public.is_user_pair_abuse_blocked(
          CASE
            WHEN dt.user_low_id = auth.uid() THEN dt.user_high_id
            WHEN dt.user_high_id = auth.uid() THEN dt.user_low_id
            ELSE NULL
          END
        )
      )
      AND (
        p_before_last_message_at IS NULL
        OR p_before_thread_id IS NULL
        OR (t.last_message_at, t.id) < (p_before_last_message_at, p_before_thread_id)
      )
    ORDER BY t.last_message_at DESC, t.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  )
  SELECT summary.*
  FROM visible_threads vt
  CROSS JOIN LATERAL public.get_thread_summary(vt.id) AS summary
  ORDER BY summary.last_message_at DESC, summary.thread_id DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unblock_user_pair(p_other_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_other_user_id IS NULL THEN
    RAISE EXCEPTION 'Blocked user is required';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Cannot unblock yourself';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND ss.blocked_by_user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'No active block exists for this user pair';
  END IF;

  PERFORM set_config('tidex.allow_shift_share_abuse_block_update', 'true', true);

  UPDATE public.shift_shares ss
  SET hidden = false,
      blocked_by_user_id = NULL
  WHERE (
    (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
    OR
    (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
  )
    AND ss.blocked_by_user_id = v_uid;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.unblock_user_pair(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.unblock_user_pair(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.unblock_user_pair(uuid) TO authenticated;


-- Source: supabase/sql/migrations/20260309113000_remove_server_shift_reminders.sql

-- Remove obsolete server-side shift reminder infrastructure.
-- Shift reminders are scheduled locally in the iOS app.

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  FOR v_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname IN ('process-shift-reminders', 'cleanup-shift-reminders-sent')
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS public.get_shifts_due_for_reminder();
DROP TABLE IF EXISTS public.shift_reminders_sent;


-- Source: supabase/sql/migrations/20260311025138_fix_thread_message_notification_rich_content.sql

-- Fix thread message push copy for metadata-only rich content

CREATE OR REPLACE FUNCTION public.queue_thread_message_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_sender_name text;
  v_sender_avatar_url text;
  v_thread_kind text;
  v_recipient record;
  v_body_preview text;
  v_rich_content_kind text;
BEGIN
  SELECT
    COALESCE(au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', au.email, 'Someone'),
    COALESCE(us.profile_picture_url, au.raw_user_meta_data->>'avatar_url')
  INTO v_sender_name, v_sender_avatar_url
  FROM auth.users au
  LEFT JOIN public.user_settings us
    ON us.user_id = au.id
  WHERE au.id = NEW.sender_user_id;

  IF v_sender_name IS NULL THEN
    v_sender_name := 'Someone';
  END IF;

  SELECT t.kind
  INTO v_thread_kind
  FROM public.threads t
  WHERE t.id = NEW.thread_id;

  v_body_preview := NULLIF(
    left(regexp_replace(COALESCE(NEW.body, ''), '\s+', ' ', 'g'), 120),
    ''
  );
  v_rich_content_kind := NULLIF(btrim(COALESCE(NEW.metadata->'content'->>'kind', '')), '');

  FOR v_recipient IN
    SELECT
      tm.user_id,
      COALESCE(tus.muted, false) AS muted,
      COALESCE(au.raw_user_meta_data->>'locale', 'en') AS locale
    FROM public.thread_memberships tm
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = tm.thread_id
     AND tus.user_id = tm.user_id
    LEFT JOIN auth.users au
      ON au.id = tm.user_id
    WHERE tm.thread_id = NEW.thread_id
      AND tm.status = 'active'
      AND tm.user_id <> NEW.sender_user_id
  LOOP
    IF v_recipient.muted THEN
      CONTINUE;
    END IF;

    INSERT INTO internal.notifications_outbox (
      owner_id,
      recipient_id,
      notification_type,
      due_at,
      title,
      body,
      data_payload,
      idempotency_key
    )
    VALUES (
      NEW.sender_user_id,
      v_recipient.user_id,
      'thread_message',
      now(),
      v_sender_name,
      COALESCE(
        v_body_preview,
        CASE
          WHEN v_rich_content_kind = 'shift_snapshot' THEN
            CASE
              WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' delte en vakt'
              ELSE v_sender_name || ' shared a shift'
            END
          WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' sendte et bilde'
          ELSE v_sender_name || ' sent a photo'
        END
      ),
      jsonb_build_object(
        'type', 'thread_message',
        'thread_id', NEW.thread_id,
        'message_id', NEW.id,
        'thread_kind', COALESCE(v_thread_kind, 'direct'),
        'sender_user_id', NEW.sender_user_id,
        'sender_name', v_sender_name,
        'sender_avatar_url', v_sender_avatar_url
      ),
      'thread_message:' || NEW.id || ':' || v_recipient.user_id
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$function$;


-- Source: supabase/sql/migrations/20260311123000_friends_rich_message_metadata.sql

-- Friends rich message metadata helpers and additive preview-kind summary fields

CREATE OR REPLACE FUNCTION public.assert_message_metadata_validity(p_metadata jsonb)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_metadata jsonb := COALESCE(p_metadata, '{}'::jsonb);
  v_content jsonb;
  v_kind text;
BEGIN
  IF jsonb_typeof(v_metadata) <> 'object' THEN
    RAISE EXCEPTION 'Metadata must be a JSON object';
  END IF;

  IF pg_column_size(v_metadata) > 8192 THEN
    RAISE EXCEPTION 'Metadata exceeds the 8 KB limit';
  END IF;

  IF NOT (v_metadata ? 'content') THEN
    RETURN;
  END IF;

  v_content := v_metadata->'content';

  IF jsonb_typeof(v_content) <> 'object' THEN
    RAISE EXCEPTION 'Metadata content must be a JSON object';
  END IF;

  v_kind := NULLIF(btrim(v_content->>'kind'), '');

  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'Metadata content kind is required';
  END IF;

  IF public.message_supported_rich_content_kind(v_metadata) IS NOT NULL THEN
    RETURN;
  END IF;

  IF v_kind = 'shift_snapshot' THEN
    RAISE EXCEPTION 'Invalid shift snapshot metadata';
  END IF;

  RAISE EXCEPTION 'Unsupported rich content kind: %', v_kind;
END;
$function$;

CREATE OR REPLACE FUNCTION public.message_supported_rich_content_kind(p_metadata jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_metadata jsonb := COALESCE(p_metadata, '{}'::jsonb);
  v_content jsonb;
  v_kind text;
  v_snapshot jsonb;
  v_includes_earnings boolean;
BEGIN
  IF jsonb_typeof(v_metadata) <> 'object' THEN
    RETURN NULL;
  END IF;

  v_content := v_metadata->'content';

  IF jsonb_typeof(v_content) <> 'object' THEN
    RETURN NULL;
  END IF;

  v_kind := NULLIF(btrim(v_content->>'kind'), '');

  IF v_kind <> 'shift_snapshot' THEN
    RETURN NULL;
  END IF;

  v_snapshot := v_content->'shift_snapshot';

  IF jsonb_typeof(v_snapshot) <> 'object' THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'schema_version') OR v_snapshot->>'schema_version' <> '1' THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'owner_user_id')
     OR COALESCE(jsonb_typeof(v_snapshot->'owner_user_id'), '') <> 'string'
     OR (v_snapshot->>'owner_user_id') !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'owner_display_name')
     OR COALESCE(jsonb_typeof(v_snapshot->'owner_display_name'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'owner_display_name'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'owner_avatar_url'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'shift_id')
     OR COALESCE(jsonb_typeof(v_snapshot->'shift_id'), '') <> 'string'
     OR (v_snapshot->>'shift_id') !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'job_name'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'job_color_hex'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'shift_date')
     OR COALESCE(jsonb_typeof(v_snapshot->'shift_date'), '') <> 'string'
     OR (v_snapshot->>'shift_date') !~ '^\d{4}-\d{2}-\d{2}$'
  THEN
    RETURN NULL;
  END IF;

  BEGIN
    PERFORM (v_snapshot->>'shift_date')::date;
  EXCEPTION
    WHEN others THEN
      RETURN NULL;
  END;

  IF NOT (v_snapshot ? 'start_time')
     OR COALESCE(jsonb_typeof(v_snapshot->'start_time'), '') <> 'string'
     OR (v_snapshot->>'start_time') !~ '^([01]\d|2[0-3]):[0-5]\d$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'end_time')
     OR COALESCE(jsonb_typeof(v_snapshot->'end_time'), '') <> 'string'
     OR (v_snapshot->>'end_time') !~ '^([01]\d|2[0-3]):[0-5]\d$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'paid_hours')
     OR COALESCE(jsonb_typeof(v_snapshot->'paid_hours'), '') <> 'number'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'currency')
     OR COALESCE(jsonb_typeof(v_snapshot->'currency'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'currency'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'includes_earnings')
     OR COALESCE(jsonb_typeof(v_snapshot->'includes_earnings'), '') <> 'boolean'
  THEN
    RETURN NULL;
  END IF;

  v_includes_earnings := (v_snapshot->>'includes_earnings')::boolean;

  IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') NOT IN ('number', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') NOT IN ('number', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF v_includes_earnings THEN
    IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') <> 'number'
       OR COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') <> 'number'
    THEN
      RETURN NULL;
    END IF;
  ELSE
    IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') <> 'null'
       OR COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') <> 'null'
    THEN
      RETURN NULL;
    END IF;
  END IF;

  IF NOT (v_snapshot ? 'tax_enabled')
     OR COALESCE(jsonb_typeof(v_snapshot->'tax_enabled'), '') <> 'boolean'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'source')
     OR COALESCE(jsonb_typeof(v_snapshot->'source'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'source'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  RETURN 'shift_snapshot';
END;
$function$;

CREATE OR REPLACE FUNCTION public.message_has_supported_rich_content(p_metadata jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT public.message_supported_rich_content_kind(p_metadata) IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION public.message_has_renderable_content(
  p_body text,
  p_attachments jsonb,
  p_metadata jsonb
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT
    NULLIF(regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL
    OR (
      CASE
        WHEN COALESCE(jsonb_typeof(p_attachments), 'array') = 'array'
          THEN jsonb_array_length(COALESCE(p_attachments, '[]'::jsonb)) > 0
        ELSE false
      END
    )
    OR public.message_has_supported_rich_content(p_metadata);
$function$;

CREATE OR REPLACE FUNCTION public.message_preview_kind(
  p_body text,
  p_metadata jsonb,
  p_has_image boolean
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  WITH supported_kind AS (
    SELECT public.message_supported_rich_content_kind(p_metadata) AS kind
  )
  SELECT CASE
    WHEN NULLIF(regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL THEN 'text'
    WHEN COALESCE(p_has_image, false) THEN 'image'
    WHEN supported_kind.kind IS NOT NULL THEN supported_kind.kind
    ELSE 'unknown'
  END
  FROM supported_kind;
$function$;

DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, uuid, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, uuid, jsonb);
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, jsonb);

CREATE FUNCTION public.send_message(
  p_thread_id uuid,
  p_client_id uuid,
  p_body text,
  p_reply_to_message_id uuid DEFAULT NULL,
  p_attachments jsonb DEFAULT '[]'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb,
  reactions jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_normalized_body text;
  v_attachment_count integer := 0;
  v_existing_message_id uuid;
  v_message_id uuid;
  v_attachment record;
  v_object record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'client_id is required';
  END IF;

  IF NOT public.can_post_to_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Posting is not allowed for this thread';
  END IF;

  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = p_reply_to_message_id
      AND m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reply target must exist in the same thread';
  END IF;

  IF p_attachments IS NULL THEN
    p_attachments := '[]'::jsonb;
  END IF;

  IF p_metadata IS NULL THEN
    p_metadata := '{}'::jsonb;
  END IF;

  IF jsonb_typeof(p_attachments) <> 'array' THEN
    RAISE EXCEPTION 'Attachments must be a JSON array';
  END IF;

  PERFORM public.assert_message_metadata_validity(p_metadata);

  SELECT m.id
  INTO v_existing_message_id
  FROM public.messages m
  WHERE m.thread_id = p_thread_id
    AND m.sender_user_id = v_uid
    AND m.client_id = p_client_id
  LIMIT 1;

  IF v_existing_message_id IS NOT NULL THEN
    RETURN QUERY
    SELECT *
    FROM public.get_message_payload(v_existing_message_id);
    RETURN;
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NOT NULL AND char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  SELECT count(*)
  INTO v_attachment_count
  FROM jsonb_array_elements(p_attachments);

  IF NOT public.message_has_renderable_content(v_normalized_body, p_attachments, p_metadata) THEN
    RAISE EXCEPTION 'A message must include text, at least one attachment, or supported rich content';
  END IF;

  IF v_attachment_count > 4 THEN
    RAISE EXCEPTION 'Too many attachments';
  END IF;

  FOR v_attachment IN
    SELECT
      ordinality - 1 AS attachment_index,
      (value->>'attachment_id')::uuid AS attachment_id,
      value->>'storage_path' AS storage_path,
      value->>'mime_type' AS mime_type,
      NULLIF(value->>'byte_size', '')::bigint AS byte_size,
      NULLIF(value->>'width', '')::integer AS width,
      NULLIF(value->>'height', '')::integer AS height
    FROM jsonb_array_elements(p_attachments) WITH ORDINALITY
  LOOP
    IF v_attachment.attachment_id IS NULL
       OR v_attachment.storage_path IS NULL
       OR v_attachment.mime_type IS NULL
       OR v_attachment.byte_size IS NULL THEN
      RAISE EXCEPTION 'Attachment descriptors must include attachment_id, storage_path, mime_type, and byte_size';
    END IF;

    IF v_attachment.mime_type NOT IN (
      'image/webp',
      'image/heic',
      'image/heif',
      'image/jpeg',
      'image/png'
    ) THEN
      RAISE EXCEPTION 'Unsupported attachment mime type: %', v_attachment.mime_type;
    END IF;

    IF NOT public.can_upload_message_attachment_object(v_attachment.storage_path) THEN
      RAISE EXCEPTION 'Invalid attachment path for this thread or user';
    END IF;

    IF split_part(split_part(v_attachment.storage_path, '/', 3), '.', 1)::uuid <> v_attachment.attachment_id THEN
      RAISE EXCEPTION 'Attachment path must contain the attachment_id in the file name';
    END IF;

    SELECT o.owner_id, o.metadata
    INTO v_object
    FROM storage.objects o
    WHERE o.bucket_id = 'message-attachments'
      AND o.name = v_attachment.storage_path
    LIMIT 1;

    IF v_object.owner_id IS NULL THEN
      RAISE EXCEPTION 'Attachment object not found';
    END IF;

    IF v_object.owner_id <> v_uid::text THEN
      RAISE EXCEPTION 'Attachment object owner mismatch';
    END IF;

    IF COALESCE(v_object.metadata->>'mimetype', '') <> v_attachment.mime_type THEN
      RAISE EXCEPTION 'Attachment mime type does not match stored object metadata';
    END IF;

    IF COALESCE((v_object.metadata->>'size')::bigint, -1) <> v_attachment.byte_size THEN
      RAISE EXCEPTION 'Attachment size does not match stored object metadata';
    END IF;

    IF v_attachment.byte_size <= 0 OR v_attachment.byte_size > 5242880 THEN
      RAISE EXCEPTION 'Attachment size exceeds the 5 MB limit';
    END IF;

    IF v_attachment.width IS NOT NULL AND v_attachment.width <= 0 THEN
      RAISE EXCEPTION 'Attachment width must be positive';
    END IF;

    IF v_attachment.height IS NOT NULL AND v_attachment.height <= 0 THEN
      RAISE EXCEPTION 'Attachment height must be positive';
    END IF;
  END LOOP;

  INSERT INTO public.messages (
    thread_id,
    sender_user_id,
    message_type,
    body,
    client_id,
    reply_to_message_id,
    metadata
  )
  VALUES (
    p_thread_id,
    v_uid,
    'user',
    v_normalized_body,
    p_client_id,
    p_reply_to_message_id,
    p_metadata
  )
  RETURNING messages.id INTO v_message_id;

  INSERT INTO public.message_attachments (
    id,
    message_id,
    attachment_index,
    kind,
    storage_bucket,
    storage_path,
    mime_type,
    byte_size,
    width,
    height
  )
  SELECT
    (value->>'attachment_id')::uuid,
    v_message_id,
    ordinality - 1,
    'image',
    'message-attachments',
    value->>'storage_path',
    value->>'mime_type',
    NULLIF(value->>'byte_size', '')::bigint,
    NULLIF(value->>'width', '')::integer,
    NULLIF(value->>'height', '')::integer
  FROM jsonb_array_elements(p_attachments) WITH ORDINALITY;

  UPDATE public.threads
  SET
    last_message_id = v_message_id,
    last_message_sender_id = v_uid,
    last_message_at = (
      SELECT m.created_at
      FROM public.messages m
      WHERE m.id = v_message_id
    )
  WHERE threads.id = p_thread_id;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(v_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_message_content_validity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_message_id uuid := COALESCE(NEW.id, OLD.id);
  v_body text;
  v_metadata jsonb;
  v_attachments jsonb;
BEGIN
  SELECT
    m.body,
    m.metadata,
    COALESCE(
      (
        SELECT jsonb_agg(jsonb_build_object('id', ma.id) ORDER BY ma.attachment_index ASC)
        FROM public.message_attachments ma
        WHERE ma.message_id = m.id
      ),
      '[]'::jsonb
    )
  INTO v_body, v_metadata, v_attachments
  FROM public.messages m
  WHERE m.id = v_message_id;

  PERFORM public.assert_message_metadata_validity(v_metadata);

  IF NOT public.message_has_renderable_content(v_body, v_attachments, v_metadata) THEN
    RAISE EXCEPTION 'A message must include text, at least one attachment, or supported rich content';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP FUNCTION IF EXISTS public.get_or_create_direct_thread(uuid);
DROP FUNCTION IF EXISTS public.list_my_threads(integer, timestamptz, uuid);
DROP FUNCTION IF EXISTS public.get_thread_summary(uuid);

CREATE OR REPLACE FUNCTION public.get_thread_summary(p_thread_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_preview_kind text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH auth_context AS (
    SELECT auth.uid() AS user_id
  ),
  base_thread AS (
    SELECT
      t.id,
      t.kind,
      t.title,
      t.avatar_url,
      t.metadata,
      t.last_message_id,
      t.last_message_sender_id,
      t.last_message_at,
      t.created_at,
      tus.muted,
      dt.user_low_id,
      dt.user_high_id,
      cu.user_id
    FROM public.threads t
    JOIN auth_context cu
      ON cu.user_id IS NOT NULL
    JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = cu.user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = cu.user_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE t.id = p_thread_id
  ),
  counterpart AS (
    SELECT
      bt.*,
      CASE
        WHEN bt.kind = 'direct' AND bt.user_low_id = bt.user_id THEN bt.user_high_id
        WHEN bt.kind = 'direct' AND bt.user_high_id = bt.user_id THEN bt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM base_thread bt
  ),
  read_marker AS (
    SELECT
      tus.thread_id,
      rm.created_at AS last_read_created_at,
      rm.id AS last_read_message_id
    FROM public.thread_user_state tus
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    JOIN auth_context cu
      ON cu.user_id = tus.user_id
    WHERE tus.thread_id = p_thread_id
  )
  SELECT
    c.id AS thread_id,
    c.kind,
    c.title,
    c.avatar_url,
    c.metadata,
    c.counterpart_user_id,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        au.email,
        'Someone'
      )
    END AS counterpart_display_name,
    us.profile_picture_url AS counterpart_profile_picture_url,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'avatar_url',
        au.raw_user_meta_data->>'picture'
      )
    END AS counterpart_oauth_avatar_url,
    c.last_message_id,
    c.last_message_sender_id,
    c.last_message_at,
    lm.body AS last_message_body,
    public.message_preview_kind(
      lm.body,
      lm.metadata,
      COALESCE(last_message_media.has_image, false)
    ) AS last_message_preview_kind,
    COALESCE(last_message_media.has_image, false) AS last_message_has_image,
    COALESCE(
      (
        SELECT count(*)
        FROM public.messages um
        LEFT JOIN read_marker rm
          ON rm.thread_id = um.thread_id
        WHERE um.thread_id = c.id
          AND um.deleted_at IS NULL
          AND um.sender_user_id <> c.user_id
          AND (
            rm.last_read_message_id IS NULL
            OR (um.created_at, um.id) > (rm.last_read_created_at, rm.last_read_message_id)
          )
      ),
      0
    ) AS unread_count,
    COALESCE(c.muted, false) AS muted,
    c.created_at
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  LEFT JOIN public.messages lm
    ON lm.id = c.last_message_id
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1
      FROM public.message_attachments lma
      WHERE lma.message_id = c.last_message_id
    ) AS has_image
  ) AS last_message_media
    ON true
  WHERE c.counterpart_user_id IS NULL
     OR NOT public.is_user_pair_abuse_blocked(c.counterpart_user_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_thread_summary(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_my_threads(
  p_limit integer DEFAULT 30,
  p_before_last_message_at timestamptz DEFAULT NULL,
  p_before_thread_id uuid DEFAULT NULL
)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_preview_kind text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH visible_threads AS (
    SELECT t.id, t.last_message_at
    FROM public.thread_memberships tm
    JOIN public.threads t
      ON t.id = tm.thread_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE auth.uid() IS NOT NULL
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
      AND (
        dt.thread_id IS NULL
        OR NOT public.is_user_pair_abuse_blocked(
          CASE
            WHEN dt.user_low_id = auth.uid() THEN dt.user_high_id
            WHEN dt.user_high_id = auth.uid() THEN dt.user_low_id
            ELSE NULL
          END
        )
      )
      AND (
        p_before_last_message_at IS NULL
        OR p_before_thread_id IS NULL
        OR (t.last_message_at, t.id) < (p_before_last_message_at, p_before_thread_id)
      )
    ORDER BY t.last_message_at DESC, t.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  )
  SELECT summary.*
  FROM visible_threads vt
  CROSS JOIN LATERAL public.get_thread_summary(vt.id) AS summary
  ORDER BY summary.last_message_at DESC, summary.thread_id DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_or_create_direct_thread(p_other_user_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_preview_kind text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_user_low_id uuid;
  v_user_high_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_create_direct_thread(p_other_user_id) THEN
    RAISE EXCEPTION 'Direct thread creation is not allowed for this user pair';
  END IF;

  v_user_low_id := LEAST(v_uid, p_other_user_id);
  v_user_high_id := GREATEST(v_uid, p_other_user_id);

  LOOP
    SELECT dt.thread_id
    INTO v_thread_id
    FROM public.direct_threads dt
    WHERE dt.user_low_id = v_user_low_id
      AND dt.user_high_id = v_user_high_id
    LIMIT 1;

    EXIT WHEN v_thread_id IS NOT NULL;

    BEGIN
      INSERT INTO public.threads (
        kind,
        created_by_user_id
      )
      VALUES (
        'direct',
        v_uid
      )
      RETURNING id INTO v_thread_id;

      INSERT INTO public.direct_threads (
        thread_id,
        user_low_id,
        user_high_id
      )
      VALUES (
        v_thread_id,
        v_user_low_id,
        v_user_high_id
      );

      EXIT;
    EXCEPTION
      WHEN unique_violation THEN
        v_thread_id := NULL;
    END;
  END LOOP;

  INSERT INTO public.thread_memberships (
    thread_id,
    user_id,
    role,
    status
  )
  VALUES
    (v_thread_id, v_user_low_id, 'member', 'active'),
    (v_thread_id, v_user_high_id, 'member', 'active')
  ON CONFLICT ON CONSTRAINT thread_memberships_pkey DO UPDATE
  SET
    role = EXCLUDED.role,
    status = 'active',
    left_at = NULL;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id
  )
  VALUES
    (v_thread_id, v_user_low_id),
    (v_thread_id, v_user_high_id)
  ON CONFLICT ON CONSTRAINT thread_user_state_pkey DO NOTHING;

  RETURN QUERY
  SELECT *
  FROM public.get_thread_summary(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) TO authenticated;


-- Source: supabase/sql/migrations/20260311160000_friends_message_edits_and_deletes.sql

DROP FUNCTION IF EXISTS public.edit_message(uuid, text);

CREATE FUNCTION public.edit_message(
  p_message_id uuid,
  p_body text
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb,
  reactions jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_sender_user_id uuid;
  v_message_type text;
  v_deleted_at timestamptz;
  v_existing_body text;
  v_normalized_body text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.deleted_at,
    NULLIF(regexp_replace(COALESCE(m.body, ''), '^\s+|\s+$', '', 'g'), '')
  INTO
    v_thread_id,
    v_sender_user_id,
    v_message_type,
    v_deleted_at,
    v_existing_body
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF v_sender_user_id <> v_uid THEN
    RAISE EXCEPTION 'Only the sender can edit this message';
  END IF;

  IF v_message_type <> 'user' THEN
    RAISE EXCEPTION 'Only user messages can be edited';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Deleted messages cannot be edited';
  END IF;

  IF v_existing_body IS NULL THEN
    RAISE EXCEPTION 'Only text messages can be edited';
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NULL THEN
    RAISE EXCEPTION 'Message body cannot be empty';
  END IF;

  IF char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  IF v_normalized_body IS DISTINCT FROM v_existing_body THEN
    UPDATE public.messages
    SET
      body = v_normalized_body,
      edited_at = now()
    WHERE messages.id = p_message_id;
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(p_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.edit_message(uuid, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.edit_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;

DROP FUNCTION IF EXISTS public.delete_message(uuid);

CREATE FUNCTION public.delete_message(p_message_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_preview_kind text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_sender_user_id uuid;
  v_message_type text;
  v_deleted_at timestamptz;
  v_latest_message_id uuid;
  v_latest_sender_user_id uuid;
  v_latest_created_at timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.deleted_at
  INTO
    v_thread_id,
    v_sender_user_id,
    v_message_type,
    v_deleted_at
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF v_sender_user_id <> v_uid THEN
    RAISE EXCEPTION 'Only the sender can delete this message';
  END IF;

  IF v_message_type <> 'user' THEN
    RAISE EXCEPTION 'Only user messages can be deleted';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Message is already deleted';
  END IF;

  UPDATE public.messages
  SET deleted_at = now()
  WHERE messages.id = p_message_id;

  SELECT
    m.id,
    m.sender_user_id,
    m.created_at
  INTO
    v_latest_message_id,
    v_latest_sender_user_id,
    v_latest_created_at
  FROM public.messages m
  WHERE m.thread_id = v_thread_id
    AND m.deleted_at IS NULL
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1;

  UPDATE public.threads t
  SET
    last_message_id = v_latest_message_id,
    last_message_sender_id = v_latest_sender_user_id,
    last_message_at = COALESCE(v_latest_created_at, t.created_at)
  WHERE t.id = v_thread_id;

  RETURN QUERY
  SELECT *
  FROM public.get_thread_summary(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.delete_message(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.delete_message(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;


-- Source: supabase/sql/migrations/20260311183000_notification_coalescing_and_badges.sql

CREATE OR REPLACE FUNCTION public.get_unread_direct_message_count(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_requester_id uuid := auth.uid();
  v_request_role text := current_setting('request.jwt.claim.role', true);
  v_target_user_id uuid;
  v_unread_count integer;
BEGIN
  IF v_request_role = 'service_role' THEN
    v_target_user_id := p_user_id;
  ELSE
    IF v_requester_id IS NULL THEN
      RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_user_id IS NOT NULL AND p_user_id <> v_requester_id THEN
      RAISE EXCEPTION 'Cannot read another user''s unread direct message count';
    END IF;

    v_target_user_id := COALESCE(p_user_id, v_requester_id);
  END IF;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Target user is required';
  END IF;

  WITH unread_per_thread AS (
    SELECT
      t.id,
      COUNT(*)::integer AS unread_count
    FROM public.threads t
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    INNER JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = v_target_user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = v_target_user_id
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    INNER JOIN public.messages m
      ON m.thread_id = t.id
     AND m.sender_user_id <> v_target_user_id
    WHERE t.kind = 'direct'
      AND (
        dt.thread_id IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM public.shift_shares ss
          WHERE (
            (ss.owner_id = v_target_user_id AND ss.viewer_id = CASE
              WHEN dt.user_low_id = v_target_user_id THEN dt.user_high_id
              WHEN dt.user_high_id = v_target_user_id THEN dt.user_low_id
              ELSE NULL
            END)
            OR
            (ss.owner_id = CASE
              WHEN dt.user_low_id = v_target_user_id THEN dt.user_high_id
              WHEN dt.user_high_id = v_target_user_id THEN dt.user_low_id
              ELSE NULL
            END AND ss.viewer_id = v_target_user_id)
          )
            AND ss.blocked_by_user_id IS NOT NULL
        )
      )
      AND m.deleted_at IS NULL
      AND (
        tus.last_read_message_id IS NULL
        OR rm.id IS NULL
        OR (m.created_at, m.id) > (rm.created_at, rm.id)
      )
    GROUP BY t.id
  )
  SELECT COALESCE(SUM(unread_count), 0)::integer
  INTO v_unread_count
  FROM unread_per_thread;

  RETURN COALESCE(v_unread_count, 0);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_direct_message_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_direct_message_count(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.queue_thread_message_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_sender_name text;
  v_sender_avatar_url text;
  v_thread_kind text;
  v_recipient record;
  v_existing_notification record;
  v_body_preview text;
  v_rich_content_kind text;
  v_single_message_body text;
  v_unread_message_count integer;
BEGIN
  SELECT
    COALESCE(au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', au.email, 'Someone'),
    COALESCE(us.profile_picture_url, au.raw_user_meta_data->>'avatar_url')
  INTO v_sender_name, v_sender_avatar_url
  FROM auth.users au
  LEFT JOIN public.user_settings us
    ON us.user_id = au.id
  WHERE au.id = NEW.sender_user_id;

  IF v_sender_name IS NULL THEN
    v_sender_name := 'Someone';
  END IF;

  SELECT t.kind
  INTO v_thread_kind
  FROM public.threads t
  WHERE t.id = NEW.thread_id;

  v_body_preview := NULLIF(
    left(regexp_replace(COALESCE(NEW.body, ''), '\s+', ' ', 'g'), 120),
    ''
  );
  v_rich_content_kind := NULLIF(btrim(COALESCE(NEW.metadata->'content'->>'kind', '')), '');

  FOR v_recipient IN
    SELECT
      tm.user_id,
      COALESCE(tus.muted, false) AS muted,
      COALESCE(au.raw_user_meta_data->>'locale', 'en') AS locale
    FROM public.thread_memberships tm
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = tm.thread_id
     AND tus.user_id = tm.user_id
    LEFT JOIN auth.users au
      ON au.id = tm.user_id
    WHERE tm.thread_id = NEW.thread_id
      AND tm.status = 'active'
      AND tm.user_id <> NEW.sender_user_id
  LOOP
    IF v_recipient.muted THEN
      CONTINUE;
    END IF;

    v_single_message_body := COALESCE(
      v_body_preview,
      CASE
        WHEN v_rich_content_kind = 'shift_snapshot' THEN
          CASE
            WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' delte en vakt'
            ELSE v_sender_name || ' shared a shift'
          END
        WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' sendte et bilde'
        ELSE v_sender_name || ' sent a photo'
      END
    );

    SELECT COUNT(*)::integer
    INTO v_unread_message_count
    FROM public.messages m
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = NEW.thread_id
     AND tus.user_id = v_recipient.user_id
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    WHERE m.thread_id = NEW.thread_id
      AND m.sender_user_id <> v_recipient.user_id
      AND (
        tus.last_read_message_id IS NULL
        OR rm.id IS NULL
        OR (m.created_at, m.id) > (rm.created_at, rm.id)
      );

    SELECT
      no.id
    INTO v_existing_notification
    FROM internal.notifications_outbox no
    WHERE no.status = 'pending'
      AND no.notification_type = 'thread_message'
      AND no.recipient_id = v_recipient.user_id
      AND no.data_payload->>'thread_id' = NEW.thread_id::text
    ORDER BY no.created_at DESC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF FOUND THEN
      UPDATE internal.notifications_outbox
      SET
        owner_id = NEW.sender_user_id,
        due_at = now(),
        title = v_sender_name,
        body = CASE
          WHEN v_unread_message_count >= 4 THEN
            CASE
              WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN
                v_unread_message_count::text || ' nye meldinger'
              ELSE
                v_unread_message_count::text || ' new messages'
            END
          ELSE
            v_single_message_body
        END,
        data_payload = jsonb_build_object(
          'type', 'thread_message',
          'thread_id', NEW.thread_id,
          'message_id', NEW.id,
          'thread_kind', COALESCE(v_thread_kind, 'direct'),
          'sender_user_id', NEW.sender_user_id,
          'sender_name', v_sender_name,
          'sender_avatar_url', v_sender_avatar_url,
          'message_count', v_unread_message_count
        )
      WHERE id = v_existing_notification.id;
    ELSE
      INSERT INTO internal.notifications_outbox (
        owner_id,
        recipient_id,
        notification_type,
        due_at,
        title,
        body,
        data_payload,
        idempotency_key
      )
      VALUES (
        NEW.sender_user_id,
        v_recipient.user_id,
        'thread_message',
        now(),
        v_sender_name,
        CASE
          WHEN v_unread_message_count >= 4 THEN
            CASE
              WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN
                v_unread_message_count::text || ' nye meldinger'
              ELSE
                v_unread_message_count::text || ' new messages'
            END
          ELSE
            v_single_message_body
        END,
        jsonb_build_object(
          'type', 'thread_message',
          'thread_id', NEW.thread_id,
          'message_id', NEW.id,
          'thread_kind', COALESCE(v_thread_kind, 'direct'),
          'sender_user_id', NEW.sender_user_id,
          'sender_name', v_sender_name,
          'sender_avatar_url', v_sender_avatar_url,
          'message_count', v_unread_message_count
        ),
        'thread_message:' || NEW.id || ':' || v_recipient.user_id
      )
      ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.trigger_push_notifications_after_outbox_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'net', 'pg_temp'
AS $function$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
BEGIN
  SELECT decrypted_secret INTO supabase_url
  FROM vault.decrypted_secrets WHERE name = 'supabase_url';

  SELECT decrypted_secret INTO service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF supabase_url IS NOT NULL AND service_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_key
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trigger_send_push_after_insert ON internal.notifications_outbox;

CREATE TRIGGER trigger_send_push_after_insert
  AFTER INSERT OR UPDATE OF due_at, title, body, data_payload ON internal.notifications_outbox
  FOR EACH STATEMENT
  EXECUTE FUNCTION internal.trigger_push_notifications_after_outbox_insert();


-- Source: supabase/sql/functions/notification/get_unread_direct_message_count.sql

-- Function: get_unread_direct_message_count
-- Description: Returns the total unread direct-message count for a user.

CREATE OR REPLACE FUNCTION public.get_unread_direct_message_count(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_requester_id uuid := auth.uid();
  v_request_role text := current_setting('request.jwt.claim.role', true);
  v_target_user_id uuid;
  v_unread_count integer;
BEGIN
  IF v_request_role = 'service_role' THEN
    v_target_user_id := p_user_id;
  ELSE
    IF v_requester_id IS NULL THEN
      RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_user_id IS NOT NULL AND p_user_id <> v_requester_id THEN
      RAISE EXCEPTION 'Cannot read another user''s unread direct message count';
    END IF;

    v_target_user_id := COALESCE(p_user_id, v_requester_id);
  END IF;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Target user is required';
  END IF;

  WITH unread_per_thread AS (
    SELECT
      t.id,
      COUNT(*)::integer AS unread_count
    FROM public.threads t
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    INNER JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = v_target_user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = v_target_user_id
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    INNER JOIN public.messages m
      ON m.thread_id = t.id
     AND m.sender_user_id <> v_target_user_id
    WHERE t.kind = 'direct'
      AND (
        dt.thread_id IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM public.shift_shares ss
          WHERE (
            (ss.owner_id = v_target_user_id AND ss.viewer_id = CASE
              WHEN dt.user_low_id = v_target_user_id THEN dt.user_high_id
              WHEN dt.user_high_id = v_target_user_id THEN dt.user_low_id
              ELSE NULL
            END)
            OR
            (ss.owner_id = CASE
              WHEN dt.user_low_id = v_target_user_id THEN dt.user_high_id
              WHEN dt.user_high_id = v_target_user_id THEN dt.user_low_id
              ELSE NULL
            END AND ss.viewer_id = v_target_user_id)
          )
            AND ss.blocked_by_user_id IS NOT NULL
        )
      )
      AND m.deleted_at IS NULL
      AND (
        tus.last_read_message_id IS NULL
        OR rm.id IS NULL
        OR (m.created_at, m.id) > (rm.created_at, rm.id)
      )
    GROUP BY t.id
  )
  SELECT COALESCE(SUM(unread_count), 0)::integer
  INTO v_unread_count
  FROM unread_per_thread;

  RETURN COALESCE(v_unread_count, 0);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_direct_message_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_direct_message_count(uuid) TO service_role;


-- Source: supabase/sql/functions/trigger/queue_thread_message_notification.sql

-- Function: queue_thread_message_notification
-- Description: Enqueues push notifications for newly inserted thread messages

CREATE OR REPLACE FUNCTION public.queue_thread_message_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_sender_name text;
  v_sender_avatar_url text;
  v_thread_kind text;
  v_recipient record;
  v_existing_notification record;
  v_body_preview text;
  v_rich_content_kind text;
  v_single_message_body text;
  v_unread_message_count integer;
BEGIN
  SELECT
    COALESCE(au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', au.email, 'Someone'),
    COALESCE(us.profile_picture_url, au.raw_user_meta_data->>'avatar_url')
  INTO v_sender_name, v_sender_avatar_url
  FROM auth.users au
  LEFT JOIN public.user_settings us
    ON us.user_id = au.id
  WHERE au.id = NEW.sender_user_id;

  IF v_sender_name IS NULL THEN
    v_sender_name := 'Someone';
  END IF;

  SELECT t.kind
  INTO v_thread_kind
  FROM public.threads t
  WHERE t.id = NEW.thread_id;

  v_body_preview := NULLIF(
    left(regexp_replace(COALESCE(NEW.body, ''), '\s+', ' ', 'g'), 120),
    ''
  );
  v_rich_content_kind := NULLIF(btrim(COALESCE(NEW.metadata->'content'->>'kind', '')), '');

  FOR v_recipient IN
    SELECT
      tm.user_id,
      COALESCE(tus.muted, false) AS muted,
      COALESCE(au.raw_user_meta_data->>'locale', 'en') AS locale
    FROM public.thread_memberships tm
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = tm.thread_id
     AND tus.user_id = tm.user_id
    LEFT JOIN auth.users au
      ON au.id = tm.user_id
    WHERE tm.thread_id = NEW.thread_id
      AND tm.status = 'active'
      AND tm.user_id <> NEW.sender_user_id
  LOOP
    IF v_recipient.muted THEN
      CONTINUE;
    END IF;

    v_single_message_body := COALESCE(
      v_body_preview,
      CASE
        WHEN v_rich_content_kind = 'shift_snapshot' THEN
          CASE
            WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' delte en vakt'
            ELSE v_sender_name || ' shared a shift'
          END
        WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' sendte et bilde'
        ELSE v_sender_name || ' sent a photo'
      END
    );

    SELECT COUNT(*)::integer
    INTO v_unread_message_count
    FROM public.messages m
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = NEW.thread_id
     AND tus.user_id = v_recipient.user_id
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    WHERE m.thread_id = NEW.thread_id
      AND m.sender_user_id <> v_recipient.user_id
      AND (
        tus.last_read_message_id IS NULL
        OR rm.id IS NULL
        OR (m.created_at, m.id) > (rm.created_at, rm.id)
      );

    SELECT
      no.id
    INTO v_existing_notification
    FROM internal.notifications_outbox no
    WHERE no.status = 'pending'
      AND no.notification_type = 'thread_message'
      AND no.recipient_id = v_recipient.user_id
      AND no.data_payload->>'thread_id' = NEW.thread_id::text
    ORDER BY no.created_at DESC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF FOUND THEN
      UPDATE internal.notifications_outbox
      SET
        owner_id = NEW.sender_user_id,
        due_at = now(),
        title = v_sender_name,
        body = CASE
          WHEN v_unread_message_count >= 4 THEN
            CASE
              WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN
                v_unread_message_count::text || ' nye meldinger'
              ELSE
                v_unread_message_count::text || ' new messages'
            END
          ELSE
            v_single_message_body
        END,
        data_payload = jsonb_build_object(
          'type', 'thread_message',
          'thread_id', NEW.thread_id,
          'message_id', NEW.id,
          'thread_kind', COALESCE(v_thread_kind, 'direct'),
          'sender_user_id', NEW.sender_user_id,
          'sender_name', v_sender_name,
          'sender_avatar_url', v_sender_avatar_url,
          'message_count', v_unread_message_count
        )
      WHERE id = v_existing_notification.id;
    ELSE
      INSERT INTO internal.notifications_outbox (
        owner_id,
        recipient_id,
        notification_type,
        due_at,
        title,
        body,
        data_payload,
        idempotency_key
      )
      VALUES (
        NEW.sender_user_id,
        v_recipient.user_id,
        'thread_message',
        now(),
        v_sender_name,
        CASE
          WHEN v_unread_message_count >= 4 THEN
            CASE
              WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN
                v_unread_message_count::text || ' nye meldinger'
              ELSE
                v_unread_message_count::text || ' new messages'
            END
          ELSE
            v_single_message_body
        END,
        jsonb_build_object(
          'type', 'thread_message',
          'thread_id', NEW.thread_id,
          'message_id', NEW.id,
          'thread_kind', COALESCE(v_thread_kind, 'direct'),
          'sender_user_id', NEW.sender_user_id,
          'sender_name', v_sender_name,
          'sender_avatar_url', v_sender_avatar_url,
          'message_count', v_unread_message_count
        ),
        'thread_message:' || NEW.id || ':' || v_recipient.user_id
      )
      ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;


-- Source: supabase/sql/functions/trigger/trigger_push_notifications_after_outbox_insert.sql

-- Function: internal.trigger_push_notifications_after_outbox_insert
-- Description: Trigger function that calls send-push-notifications after outbox inserts or delivery updates
-- Used by: AFTER INSERT / targeted UPDATE trigger on internal.notifications_outbox
-- Schema: internal (to match the trigger table)

CREATE OR REPLACE FUNCTION internal.trigger_push_notifications_after_outbox_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'net', 'pg_temp'
AS $function$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
BEGIN
  -- Get secrets from vault
  SELECT decrypted_secret INTO supabase_url
  FROM vault.decrypted_secrets WHERE name = 'supabase_url';

  SELECT decrypted_secret INTO service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  -- Only call if we have the required secrets
  IF supabase_url IS NOT NULL AND service_key IS NOT NULL THEN
    -- Use pg_net to call edge function asynchronously
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_key
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN NULL;
END;
$function$;

-- Create the AFTER INSERT / targeted UPDATE trigger on notifications_outbox
DROP TRIGGER IF EXISTS trigger_send_push_after_insert ON internal.notifications_outbox;

CREATE TRIGGER trigger_send_push_after_insert
  AFTER INSERT OR UPDATE OF due_at, title, body, data_payload ON internal.notifications_outbox
  FOR EACH STATEMENT
  EXECUTE FUNCTION internal.trigger_push_notifications_after_outbox_insert();

-- Grant execute permission to service_role
GRANT EXECUTE ON FUNCTION internal.trigger_push_notifications_after_outbox_insert() TO service_role;


