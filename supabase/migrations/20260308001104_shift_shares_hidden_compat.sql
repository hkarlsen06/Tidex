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
