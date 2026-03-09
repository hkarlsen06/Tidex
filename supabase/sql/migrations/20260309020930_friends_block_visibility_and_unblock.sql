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
