-- Admin console: per-user usage stats for the user detail screen.

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

REVOKE ALL ON FUNCTION public.admin_get_user_stats_api(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_stats_api(uuid) TO authenticated, service_role;
