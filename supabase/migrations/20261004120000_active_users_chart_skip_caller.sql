-- Distinct active users per hour for the last 24 hours and per day for the last 30 days.
-- Days follow p_time_zone. Only counts opens from builds that record them. Leaves out the
-- admin calling it, so the chart shows other people.
CREATE OR REPLACE FUNCTION public.admin_get_active_users_chart_api(p_time_zone text DEFAULT 'Europe/Oslo')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_current_hour timestamptz := date_trunc('hour', now());
  v_today date;
BEGIN
  PERFORM public.assert_is_admin();

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_time_zone) THEN
    RAISE EXCEPTION 'Unknown time zone %', p_time_zone;
  END IF;

  v_today := (now() AT TIME ZONE p_time_zone)::date;

  RETURN jsonb_build_object(
    'hours', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'start', h.start,
          'users', (
            SELECT count(*) FROM internal.app_activity_hours x
            WHERE x.hour = h.start AND x.user_id IS DISTINCT FROM auth.uid()
          )
        )
        ORDER BY h.start
      )
      FROM generate_series(v_current_hour - interval '23 hours', v_current_hour, interval '1 hour') AS h(start)
    ),
    'days', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'date', d.day,
          'users', (
            SELECT count(DISTINCT x.user_id) FROM internal.app_activity_hours x
            WHERE x.hour >= d.day::timestamp AT TIME ZONE p_time_zone
              AND x.hour < (d.day + 1)::timestamp AT TIME ZONE p_time_zone
              AND x.user_id IS DISTINCT FROM auth.uid()
          )
        )
        ORDER BY d.day
      )
      FROM (SELECT v_today - i AS day FROM generate_series(0, 29) AS i) AS d
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_active_users_chart_api(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_active_users_chart_api(text) TO authenticated;
