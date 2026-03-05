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
