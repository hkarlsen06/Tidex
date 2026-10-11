-- Admin console: a user's jobs, wage snapshots, pay settings and payroll adjustments for the
-- Wage setup section on the user detail screen. Rows keep their table column names so the app
-- decodes them with the same models it uses for its own data.

CREATE OR REPLACE FUNCTION public.admin_get_user_wage_setup_api(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  RETURN jsonb_build_object(
    'jobs', COALESCE((
      SELECT jsonb_agg(to_jsonb(j) ORDER BY j.is_default DESC, j.sort_order, j.created_at)
      FROM public.jobs j
      WHERE j.user_id = p_user_id AND j.deleted_at IS NULL AND j.archived_at IS NULL
    ), '[]'::jsonb),
    'snapshots', COALESCE((
      SELECT jsonb_agg(to_jsonb(w) ORDER BY w.from_date NULLS FIRST, w.created_at)
      FROM public.wage_snapshots w
      WHERE w.user_id = p_user_id AND w.deleted_at IS NULL
    ), '[]'::jsonb),
    'settings', (
      SELECT jsonb_build_object(
        'payrollDay', us.payroll_day,
        'monthlyGoal', us.monthly_goal,
        'currency', us.currency,
        'halfTaxMonth', us.half_tax_month
      )
      FROM public.user_settings us
      WHERE us.user_id = p_user_id
    ),
    'adjustments', COALESCE((
      SELECT jsonb_agg(to_jsonb(pa) ORDER BY pa.payout_date DESC, pa.created_at DESC)
      FROM public.payroll_adjustments pa
      WHERE pa.user_id = p_user_id AND pa.deleted_at IS NULL
    ), '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_user_wage_setup_api(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_wage_setup_api(uuid) TO authenticated, service_role;
