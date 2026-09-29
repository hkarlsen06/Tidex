-- Called by the app each time it comes to the foreground.
CREATE OR REPLACE FUNCTION public.record_app_activity(
  p_app_version text DEFAULT NULL,
  p_build_number text DEFAULT NULL,
  p_os_version text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_locale text DEFAULT NULL,
  p_time_zone text DEFAULT NULL,
  p_app_language text DEFAULT NULL,
  p_notification_permission text DEFAULT NULL,
  p_background_refresh text DEFAULT NULL,
  p_widget_kinds text[] DEFAULT NULL,
  p_appearance text DEFAULT NULL,
  p_text_size text DEFAULT NULL,
  p_reduce_motion boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  -- An admin browsing as this user is not the user opening the app.
  IF public.is_impersonation_session() THEN
    RETURN;
  END IF;

  INSERT INTO internal.app_activity_hours (hour, user_id)
  VALUES (date_trunc('hour', now()), v_user_id)
  ON CONFLICT DO NOTHING;

  INSERT INTO internal.user_app_activity AS a (
    user_id, app_version, build_number, os_version, device_model, locale, time_zone,
    app_language, notification_permission, background_refresh, widget_kinds,
    appearance, text_size, reduce_motion
  )
  VALUES (
    v_user_id,
    left(p_app_version, 32),
    left(p_build_number, 32),
    left(p_os_version, 32),
    left(p_device_model, 64),
    left(p_locale, 64),
    left(p_time_zone, 64),
    left(p_app_language, 32),
    left(p_notification_permission, 32),
    left(p_background_refresh, 32),
    (SELECT array_agg(left(k, 64)) FROM unnest(p_widget_kinds[1:20]) AS k),
    left(p_appearance, 16),
    left(p_text_size, 32),
    p_reduce_motion
  )
  ON CONFLICT (user_id) DO UPDATE SET
    last_active_at = now(),
    open_count = a.open_count + 1,
    -- Days are counted in Norwegian time, where most users live.
    active_days = a.active_days + CASE
      WHEN (a.last_active_at AT TIME ZONE 'Europe/Oslo')::date < (now() AT TIME ZONE 'Europe/Oslo')::date
      THEN 1 ELSE 0
    END,
    previous_app_version = CASE
      WHEN (a.app_version, a.build_number) IS DISTINCT FROM (EXCLUDED.app_version, EXCLUDED.build_number)
      THEN a.app_version ELSE a.previous_app_version
    END,
    previous_build_number = CASE
      WHEN (a.app_version, a.build_number) IS DISTINCT FROM (EXCLUDED.app_version, EXCLUDED.build_number)
      THEN a.build_number ELSE a.previous_build_number
    END,
    app_version = EXCLUDED.app_version,
    build_number = EXCLUDED.build_number,
    os_version = EXCLUDED.os_version,
    device_model = EXCLUDED.device_model,
    locale = EXCLUDED.locale,
    time_zone = EXCLUDED.time_zone,
    app_language = EXCLUDED.app_language,
    notification_permission = EXCLUDED.notification_permission,
    background_refresh = EXCLUDED.background_refresh,
    widget_kinds = EXCLUDED.widget_kinds,
    appearance = EXCLUDED.appearance,
    text_size = EXCLUDED.text_size,
    reduce_motion = EXCLUDED.reduce_motion;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.record_app_activity(
  text, text, text, text, text, text, text, text, text, text[], text, text, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_app_activity(
  text, text, text, text, text, text, text, text, text, text[], text, text, boolean
) TO authenticated;
