-- The app records each time it opens, so admin "Last active" no longer depends on token refreshes.
-- Token refreshes happen at most once an hour and also during background pushes.
-- The row also keeps the app build and device of the latest open, for every user,
-- including users without a registered push device.

CREATE TABLE IF NOT EXISTS internal.user_app_activity (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_active_at timestamptz NOT NULL DEFAULT now(),
  last_active_at timestamptz NOT NULL DEFAULT now(),
  open_count integer NOT NULL DEFAULT 1,
  app_version text,
  build_number text,
  os_version text,
  device_model text,
  locale text,
  time_zone text
);

ALTER TABLE internal.user_app_activity ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.user_app_activity FROM PUBLIC, anon, authenticated;

-- Called by the app each time it comes to the foreground.
CREATE OR REPLACE FUNCTION public.record_app_activity(
  p_app_version text DEFAULT NULL,
  p_build_number text DEFAULT NULL,
  p_os_version text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_locale text DEFAULT NULL,
  p_time_zone text DEFAULT NULL
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

  INSERT INTO internal.user_app_activity AS a (
    user_id, app_version, build_number, os_version, device_model, locale, time_zone
  )
  VALUES (
    v_user_id,
    left(p_app_version, 32),
    left(p_build_number, 32),
    left(p_os_version, 32),
    left(p_device_model, 64),
    left(p_locale, 64),
    left(p_time_zone, 64)
  )
  ON CONFLICT (user_id) DO UPDATE SET
    last_active_at = now(),
    open_count = a.open_count + 1,
    app_version = EXCLUDED.app_version,
    build_number = EXCLUDED.build_number,
    os_version = EXCLUDED.os_version,
    device_model = EXCLUDED.device_model,
    locale = EXCLUDED.locale,
    time_zone = EXCLUDED.time_zone;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.record_app_activity(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_app_activity(text, text, text, text, text, text) TO authenticated;

-- When a user last used the app, for the admin users list and the Active broadcast audience.
CREATE OR REPLACE FUNCTION internal.admin_user_last_active(p_user_id uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  -- The last time the app recorded an open. Users who haven't opened a build that records
  -- opens fall back to the latest session refresh (the app refreshes its token while in use)
  -- or sign-in. auth.sessions.refreshed_at is a UTC timestamp without a time zone.
  SELECT COALESCE(
    (SELECT a.last_active_at FROM internal.user_app_activity a WHERE a.user_id = p_user_id),
    GREATEST(
      (
        SELECT max(GREATEST(s.refreshed_at AT TIME ZONE 'UTC', s.updated_at))
        FROM auth.sessions s
        WHERE s.user_id = p_user_id
      ),
      (SELECT u.last_sign_in_at FROM auth.users u WHERE u.id = p_user_id)
    )
  );
$function$;

REVOKE ALL ON FUNCTION internal.admin_user_last_active(uuid) FROM PUBLIC, anon, authenticated;

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
        'appVersion', a.app_version,
        'buildNumber', a.build_number,
        'osVersion', a.os_version,
        'deviceModel', a.device_model,
        'locale', a.locale,
        'timeZone', a.time_zone
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
