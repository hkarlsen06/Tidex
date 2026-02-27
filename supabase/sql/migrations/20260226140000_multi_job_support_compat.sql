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
