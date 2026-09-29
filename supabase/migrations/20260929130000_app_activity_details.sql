-- More app details on each recorded open, plus an hourly record of who was active for the
-- admin active-users charts.

ALTER TABLE internal.user_app_activity
  ADD COLUMN IF NOT EXISTS active_days integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS previous_app_version text,
  ADD COLUMN IF NOT EXISTS previous_build_number text,
  ADD COLUMN IF NOT EXISTS app_language text,
  ADD COLUMN IF NOT EXISTS install_source text,
  ADD COLUMN IF NOT EXISTS notification_permission text,
  ADD COLUMN IF NOT EXISTS background_refresh text,
  ADD COLUMN IF NOT EXISTS widget_kinds text[],
  ADD COLUMN IF NOT EXISTS appearance text,
  ADD COLUMN IF NOT EXISTS text_size text,
  ADD COLUMN IF NOT EXISTS reduce_motion boolean;

-- One row per user per UTC hour with at least one app open. Kept for 32 days.
CREATE TABLE IF NOT EXISTS internal.app_activity_hours (
  hour timestamptz NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  PRIMARY KEY (hour, user_id)
);

CREATE INDEX IF NOT EXISTS app_activity_hours_user_id_idx ON internal.app_activity_hours (user_id);

ALTER TABLE internal.app_activity_hours ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.app_activity_hours FROM PUBLIC, anon, authenticated;

INSERT INTO internal.app_activity_hours (hour, user_id)
SELECT date_trunc('hour', last_active_at), user_id
FROM internal.user_app_activity
ON CONFLICT DO NOTHING;

DROP FUNCTION IF EXISTS public.record_app_activity(text, text, text, text, text, text);

-- Called by the app each time it comes to the foreground.
CREATE OR REPLACE FUNCTION public.record_app_activity(
  p_app_version text DEFAULT NULL,
  p_build_number text DEFAULT NULL,
  p_os_version text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_locale text DEFAULT NULL,
  p_time_zone text DEFAULT NULL,
  p_app_language text DEFAULT NULL,
  p_install_source text DEFAULT NULL,
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
    app_language, install_source, notification_permission, background_refresh, widget_kinds,
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
    left(p_install_source, 32),
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
    install_source = EXCLUDED.install_source,
    notification_permission = EXCLUDED.notification_permission,
    background_refresh = EXCLUDED.background_refresh,
    widget_kinds = EXCLUDED.widget_kinds,
    appearance = EXCLUDED.appearance,
    text_size = EXCLUDED.text_size,
    reduce_motion = EXCLUDED.reduce_motion;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.record_app_activity(
  text, text, text, text, text, text, text, text, text, text, text[], text, text, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_app_activity(
  text, text, text, text, text, text, text, text, text, text, text[], text, text, boolean
) TO authenticated;

-- Distinct active users per hour for the last 24 hours and per day for the last 30 days.
-- Days follow p_time_zone. Only counts opens from builds that record them.
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
          'users', (SELECT count(*) FROM internal.app_activity_hours x WHERE x.hour = h.start)
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

CREATE OR REPLACE FUNCTION public.admin_get_user_stats_api(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  RETURN jsonb_build_object(
    'shiftCount', (SELECT count(*) FROM public.user_shifts WHERE user_id = p_user_id AND deleted_at IS NULL),
    'shiftsLast30Days', (
      SELECT count(*) FROM public.user_shifts
      WHERE user_id = p_user_id AND deleted_at IS NULL
        AND shift_date BETWEEN current_date - 30 AND current_date
    ),
    'upcomingShiftCount', (
      SELECT count(*) FROM public.user_shifts
      WHERE user_id = p_user_id AND deleted_at IS NULL AND shift_date > current_date
    ),
    'firstShiftDate', (SELECT min(shift_date) FROM public.user_shifts WHERE user_id = p_user_id AND deleted_at IS NULL),
    'latestShiftDate', (
      SELECT max(shift_date) FROM public.user_shifts
      WHERE user_id = p_user_id AND deleted_at IS NULL AND shift_date <= current_date
    ),
    'lastShiftAddedAt', (SELECT max(created_at) FROM public.user_shifts WHERE user_id = p_user_id),
    'jobCount', (
      SELECT count(*) FROM public.jobs
      WHERE user_id = p_user_id AND deleted_at IS NULL AND archived_at IS NULL
    ),
    'recurringScheduleCount', (
      SELECT count(*) FROM public.recurring_shifts WHERE user_id = p_user_id AND deleted_at IS NULL
    ),
    'eventCount', (SELECT count(*) FROM public.events WHERE user_id = p_user_id AND deleted_at IS NULL),
    'sharesTheirShiftsWith', (SELECT count(*) FROM public.shift_shares WHERE owner_id = p_user_id),
    'seesShiftsFrom', (SELECT count(*) FROM public.shift_shares WHERE viewer_id = p_user_id),
    'messagesSent', (
      SELECT count(*) FROM public.messages WHERE sender_user_id = p_user_id AND deleted_at IS NULL
    ),
    'messagesLast30Days', (
      SELECT count(*) FROM public.messages
      WHERE sender_user_id = p_user_id AND deleted_at IS NULL AND created_at >= now() - interval '30 days'
    ),
    'feedbackCount', (SELECT count(*) FROM public.feedback WHERE user_id = p_user_id),
    'reportsFiled', (SELECT count(*) FROM public.abuse_reports WHERE reporter_user_id = p_user_id),
    'reportsReceived', (SELECT count(*) FROM public.abuse_reports WHERE reported_user_id = p_user_id),
    'calendarFeedLastUsedAt', (
      SELECT max(last_used_at) FROM internal.calendar_subscription_tokens
      WHERE user_id = p_user_id AND revoked_at IS NULL
    ),
    'hasCalendarFeed', EXISTS (
      SELECT 1 FROM internal.calendar_subscription_tokens WHERE user_id = p_user_id AND revoked_at IS NULL
    ),
    'appActivity', (
      SELECT jsonb_build_object(
        'firstActiveAt', a.first_active_at,
        'lastActiveAt', a.last_active_at,
        'openCount', a.open_count,
        'activeDays', a.active_days,
        'appVersion', a.app_version,
        'buildNumber', a.build_number,
        'previousAppVersion', a.previous_app_version,
        'previousBuildNumber', a.previous_build_number,
        'installSource', a.install_source,
        'osVersion', a.os_version,
        'deviceModel', a.device_model,
        'locale', a.locale,
        'appLanguage', a.app_language,
        'timeZone', a.time_zone,
        'notificationPermission', a.notification_permission,
        'backgroundRefresh', a.background_refresh,
        'widgetKinds', a.widget_kinds,
        'appearance', a.appearance,
        'textSize', a.text_size,
        'reduceMotion', a.reduce_motion
      )
      FROM internal.user_app_activity a
      WHERE a.user_id = p_user_id
    ),
    'devices', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', pd.id,
          'platform', pd.platform,
          'appVersion', pd.app_version,
          'timeZone', pd.time_zone,
          'lastSeenAt', COALESCE(pd.last_seen_at, pd.updated_at)
        )
        ORDER BY COALESCE(pd.last_seen_at, pd.updated_at) DESC NULLS LAST
      )
      FROM internal.push_devices pd
      WHERE pd.user_id = p_user_id
    ), '[]'::jsonb)
  );
END;
$function$;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'purge-app-activity-hours';

SELECT cron.schedule(
  'purge-app-activity-hours',
  '50 4 * * *',
  $cron$DELETE FROM internal.app_activity_hours WHERE hour < now() - interval '32 days';$cron$
);
