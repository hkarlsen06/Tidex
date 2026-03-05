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
