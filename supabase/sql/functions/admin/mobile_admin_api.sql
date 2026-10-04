-- Admin RPCs used by the native iOS app after the Next.js retirement.

CREATE OR REPLACE FUNCTION public.admin_log_action_rpc(
  p_action text,
  p_target_id uuid DEFAULT NULL,
  p_target_email text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_admin_id uuid := auth.uid();
  v_admin_email text;
  v_log_id uuid;
BEGIN
  PERFORM public.assert_is_admin();

  SELECT email INTO v_admin_email FROM auth.users WHERE id = v_admin_id;

  INSERT INTO internal.admin_audit_log (
    admin_id,
    admin_email,
    action,
    target_user_id,
    target_email,
    metadata
  ) VALUES (
    v_admin_id,
    COALESCE(v_admin_email, 'unknown'),
    p_action,
    p_target_id,
    p_target_email,
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$function$;

-- Norwegian locales get Norwegian broadcast text; everyone else gets English.
CREATE OR REPLACE FUNCTION internal.admin_broadcast_language(p_locale text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT CASE WHEN lower(COALESCE(p_locale, '')) ~ '^(no|nb|nn)([-_].*)?$' THEN 'no' ELSE 'en' END;
$function$;

REVOKE ALL ON FUNCTION internal.admin_broadcast_language(text) FROM PUBLIC, anon, authenticated;

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

CREATE OR REPLACE FUNCTION public.admin_list_users_api(
  p_page integer DEFAULT 1,
  p_per_page integer DEFAULT 20,
  p_search text DEFAULT NULL,
  p_sort text DEFAULT 'name',
  p_filter text DEFAULT 'all',
  p_reverse boolean DEFAULT false,
  p_account text DEFAULT 'any',
  p_language text DEFAULT NULL,
  p_provider text DEFAULT NULL,
  p_signed_up_days integer DEFAULT NULL,
  p_active_days integer DEFAULT NULL,
  p_inactive_days integer DEFAULT NULL,
  p_shifts text DEFAULT 'any',
  p_messages text DEFAULT 'any',
  p_friends text DEFAULT 'any',
  p_app_version text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_page integer := GREATEST(COALESCE(p_page, 1), 1);
  v_per_page integer := LEAST(GREATEST(COALESCE(p_per_page, 20), 1), 100);
  v_offset integer := (v_page - 1) * v_per_page;
  v_sort text := COALESCE(p_sort, 'name');
  v_filter text := COALESCE(p_filter, 'all');
  v_reverse boolean := COALESCE(p_reverse, false);
  v_account text := COALESCE(p_account, 'any');
  v_shifts text := COALESCE(p_shifts, 'any');
  v_messages text := COALESCE(p_messages, 'any');
  v_friends text := COALESCE(p_friends, 'any');
BEGIN
  PERFORM public.assert_is_admin();

  IF v_sort NOT IN ('name', 'newest', 'last_sign_in', 'last_active', 'shifts', 'messages', 'friends') THEN
    RAISE EXCEPTION 'Invalid sort. Must be name, newest, last_sign_in, last_active, shifts, messages, or friends';
  END IF;
  IF v_filter NOT IN ('all', 'active', 'new', 'admins', 'banned', 'norwegian', 'english') THEN
    RAISE EXCEPTION 'Invalid filter. Must be all, active, new, admins, banned, norwegian, or english';
  END IF;
  IF v_account NOT IN ('any', 'admins', 'non_admins', 'banned', 'not_banned') THEN
    RAISE EXCEPTION 'Invalid account. Must be any, admins, non_admins, banned, or not_banned';
  END IF;
  IF p_language IS NOT NULL AND p_language NOT IN ('no', 'en') THEN
    RAISE EXCEPTION 'Invalid language. Must be no or en';
  END IF;
  IF v_shifts NOT IN ('any', 'with', 'without')
    OR v_messages NOT IN ('any', 'with', 'without')
    OR v_friends NOT IN ('any', 'with', 'without') THEN
    RAISE EXCEPTION 'Invalid shifts, messages or friends. Must be any, with, or without';
  END IF;

  RETURN (
    WITH base AS (
      SELECT
        u.id,
        u.email,
        u.phone,
        COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS name,
        u.last_sign_in_at,
        u.created_at,
        u.banned_until,
        COALESCE(u.raw_app_meta_data->>'role', '') = 'admin' AS is_admin,
        u.id = '032d8c2a-9af6-4777-99f0-24e2c4058bf3'::uuid AS is_super_admin,
        internal.admin_broadcast_language(u.raw_user_meta_data->>'locale') AS language,
        internal.admin_user_last_active(u.id) AS last_active,
        COALESCE(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture') AS oauth_avatar_url,
        COALESCE(u.raw_app_meta_data->'providers', '[]'::jsonb) AS providers,
        a.app_version,
        COALESCE(sc.n, 0)::integer AS shift_count,
        COALESCE(mc.n, 0)::integer AS message_count,
        COALESCE(fc.n, 0)::integer AS friend_count
      FROM auth.users u
      LEFT JOIN internal.user_app_activity a ON a.user_id = u.id
      LEFT JOIN (
        SELECT user_id, count(*) AS n FROM public.user_shifts WHERE deleted_at IS NULL GROUP BY user_id
      ) sc ON sc.user_id = u.id
      LEFT JOIN (
        SELECT sender_user_id AS user_id, count(*) AS n
        FROM public.messages
        WHERE deleted_at IS NULL AND message_type = 'user'
        GROUP BY sender_user_id
      ) mc ON mc.user_id = u.id
      LEFT JOIN (
        -- People the user shares shifts with in either direction. Hidden links still count; blocks don't.
        SELECT user_id, count(DISTINCT other_id) AS n
        FROM (
          SELECT owner_id AS user_id, viewer_id AS other_id FROM public.shift_shares WHERE blocked_by_user_id IS NULL
          UNION ALL
          SELECT viewer_id, owner_id FROM public.shift_shares WHERE blocked_by_user_id IS NULL
        ) links
        GROUP BY user_id
      ) fc ON fc.user_id = u.id
      WHERE
        (
          p_search IS NULL
          OR p_search = ''
          OR lower(COALESCE(u.email, '')) LIKE '%' || lower(p_search) || '%'
          OR lower(COALESCE(u.phone, '')) LIKE '%' || lower(p_search) || '%'
          OR lower(COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '')) LIKE '%' || lower(p_search) || '%'
          OR u.id::text LIKE '%' || lower(p_search) || '%'
        )
    ),
    filtered AS (
      SELECT *
      FROM base b
      WHERE CASE v_filter
          WHEN 'active' THEN b.last_active >= now() - interval '7 days'
          WHEN 'new' THEN b.created_at >= now() - interval '7 days'
          WHEN 'admins' THEN b.is_admin OR b.is_super_admin
          WHEN 'banned' THEN b.banned_until IS NOT NULL
          WHEN 'norwegian' THEN b.language = 'no'
          WHEN 'english' THEN b.language = 'en'
          ELSE true
        END
        AND CASE v_account
          WHEN 'admins' THEN b.is_admin OR b.is_super_admin
          WHEN 'non_admins' THEN NOT (b.is_admin OR b.is_super_admin)
          WHEN 'banned' THEN b.banned_until IS NOT NULL
          WHEN 'not_banned' THEN b.banned_until IS NULL
          ELSE true
        END
        AND (p_language IS NULL OR b.language = p_language)
        AND (p_provider IS NULL OR b.providers ? p_provider)
        AND (p_signed_up_days IS NULL OR b.created_at >= now() - make_interval(days => p_signed_up_days))
        AND (p_active_days IS NULL OR b.last_active >= now() - make_interval(days => p_active_days))
        AND (
          p_inactive_days IS NULL
          OR b.last_active IS NULL
          OR b.last_active < now() - make_interval(days => p_inactive_days)
        )
        AND (v_shifts = 'any' OR (b.shift_count > 0) = (v_shifts = 'with'))
        AND (v_messages = 'any' OR (b.message_count > 0) = (v_messages = 'with'))
        AND (v_friends = 'any' OR (b.friend_count > 0) = (v_friends = 'with'))
        -- 'none' matches users whose app hasn't reported a version yet.
        AND (
          p_app_version IS NULL
          OR b.app_version = p_app_version
          OR (p_app_version = 'none' AND b.app_version IS NULL)
        )
    ),
    enriched AS (
      SELECT
        f.*,
        -- Same fallback as counterpart avatars in get_thread_summary.
        COALESCE(us.profile_picture_url, f.oauth_avatar_url) AS avatar_url,
        lower(COALESCE(f.name, f.email, f.phone, '')) AS name_key,
        CASE v_sort
          WHEN 'newest' THEN extract(epoch FROM f.created_at)
          WHEN 'last_sign_in' THEN extract(epoch FROM f.last_sign_in_at)
          WHEN 'last_active' THEN extract(epoch FROM f.last_active)
          WHEN 'shifts' THEN f.shift_count
          WHEN 'messages' THEN f.message_count
          WHEN 'friends' THEN f.friend_count
        END AS sort_value
      FROM filtered f
      LEFT JOIN public.user_settings us ON us.user_id = f.id
    ),
    ordered AS (
      -- Dates and counts run newest or highest first, names A to Z. p_reverse flips the order.
      -- Users without a value stay last either way.
      SELECT
        e.*,
        row_number() OVER (
          ORDER BY
            CASE WHEN NOT v_reverse THEN e.sort_value END DESC NULLS LAST,
            CASE WHEN v_reverse THEN e.sort_value END ASC NULLS LAST,
            CASE WHEN v_sort = 'name' AND v_reverse THEN e.name_key END DESC,
            e.name_key,
            e.created_at DESC,
            e.id
        ) AS position
      FROM enriched e
    ),
    paged AS (
      SELECT *
      FROM ordered
      ORDER BY position
      LIMIT v_per_page
      OFFSET v_offset
    )
    SELECT jsonb_build_object(
      'users', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'email', email,
            'phone', phone,
            'name', name,
            'avatarUrl', avatar_url,
            'lastSignInAt', last_sign_in_at,
            'lastActiveAt', last_active,
            'createdAt', created_at,
            'language', language,
            'isBanned', banned_until IS NOT NULL,
            'bannedUntil', banned_until,
            'isAdmin', is_admin,
            'isSuperAdmin', is_super_admin,
            'appVersion', app_version,
            'shiftCount', shift_count,
            'messageCount', message_count,
            'friendCount', friend_count
          )
          ORDER BY position
        ),
        '[]'::jsonb
      ),
      'totalCount', (SELECT count(*)::integer FROM ordered),
      'appVersions', (
        -- Most recently used version first.
        SELECT COALESCE(jsonb_agg(v.app_version ORDER BY v.last_used DESC), '[]'::jsonb)
        FROM (
          SELECT app_version, max(last_active_at) AS last_used
          FROM internal.user_app_activity
          WHERE app_version IS NOT NULL
          GROUP BY app_version
        ) v
      ),
      'page', v_page,
      'perPage', v_per_page,
      'resultsArePartial', false
    )
    FROM paged
  );
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.admin_get_feedback_api(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  RETURN (
    WITH base AS (
      SELECT
        f.id,
        f.user_id,
        f.message,
        f.user_email,
        COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS user_name,
        -- Same fallback as counterpart avatars in get_thread_summary.
        COALESCE(
          us.profile_picture_url,
          u.raw_user_meta_data->>'avatar_url',
          u.raw_user_meta_data->>'picture'
        ) AS user_profile_picture,
        f.created_at,
        f.response,
        f.responded_at,
        f.responded_by
      FROM public.feedback f
      LEFT JOIN auth.users u ON u.id = f.user_id
      LEFT JOIN public.user_settings us ON us.user_id = f.user_id
      ORDER BY f.created_at DESC
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
      OFFSET GREATEST(COALESCE(p_offset, 0), 0)
    ),
    counted AS (
      SELECT COUNT(*)::integer AS total FROM public.feedback
    )
    SELECT jsonb_build_object(
      'feedback', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'userId', user_id,
            'message', message,
            'userEmail', user_email,
            'userName', user_name,
            'userProfilePicture', user_profile_picture,
            'createdAt', created_at,
            'response', response,
            'respondedAt', responded_at,
            'respondedBy', responded_by
          )
          ORDER BY created_at DESC
        ),
        '[]'::jsonb
      ),
      'total', (SELECT total FROM counted)
    )
    FROM base
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_respond_feedback_api(
  p_feedback_id uuid,
  p_response text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin_id uuid := auth.uid();
BEGIN
  PERFORM public.assert_is_admin();

  UPDATE public.feedback
  SET
    response = btrim(p_response),
    responded_at = now(),
    responded_by = v_admin_id
  WHERE id = p_feedback_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Feedback not found');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_reports_api(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_status text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  RETURN (
    WITH filtered AS (
      SELECT *
      FROM public.abuse_reports
      WHERE p_status IS NULL OR status = p_status
      ORDER BY created_at DESC
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
      OFFSET GREATEST(COALESCE(p_offset, 0), 0)
    ),
    counted AS (
      SELECT COUNT(*)::integer AS total
      FROM public.abuse_reports
      WHERE p_status IS NULL OR status = p_status
    ),
    decorated AS (
      SELECT
        f.id,
        f.reporter_user_id,
        COALESCE(ru.raw_user_meta_data->>'full_name', ru.raw_user_meta_data->>'name') AS reporter_name,
        ru.email AS reporter_email,
        f.reported_user_id,
        COALESCE(tu.raw_user_meta_data->>'full_name', tu.raw_user_meta_data->>'name') AS reported_name,
        tu.email AS reported_email,
        f.thread_id,
        f.message_id,
        f.reason,
        f.note,
        f.status,
        f.reviewer_notes,
        f.reviewed_at,
        f.reviewed_by,
        f.created_at
      FROM filtered f
      LEFT JOIN auth.users ru ON ru.id = f.reporter_user_id
      LEFT JOIN auth.users tu ON tu.id = f.reported_user_id
    )
    SELECT jsonb_build_object(
      'reports', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'reporterUserId', reporter_user_id,
            'reporterName', reporter_name,
            'reporterEmail', reporter_email,
            'reportedUserId', reported_user_id,
            'reportedName', reported_name,
            'reportedEmail', reported_email,
            'threadId', thread_id,
            'messageId', message_id,
            'reason', reason,
            'note', note,
            'status', status,
            'reviewerNotes', reviewer_notes,
            'reviewedAt', reviewed_at,
            'reviewedBy', reviewed_by,
            'createdAt', created_at
          )
          ORDER BY created_at DESC
        ),
        '[]'::jsonb
      ),
      'total', (SELECT total FROM counted)
    )
    FROM decorated
  );
END;
$function$;

-- The conversation around a report, in the list_thread_messages payload shape. Includes deleted messages.
-- User reports without a message anchor on the report time instead.
CREATE OR REPLACE FUNCTION public.admin_get_report_messages_api(
  p_report_id uuid,
  p_context integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_report public.abuse_reports%ROWTYPE;
  v_anchor_at timestamptz;
  v_anchor_id uuid;
  v_context integer := LEAST(GREATEST(COALESCE(p_context, 10), 1), 50);
BEGIN
  PERFORM public.assert_is_admin();

  SELECT * INTO v_report FROM public.abuse_reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('messages', '[]'::jsonb);
  END IF;

  SELECT created_at, id INTO v_anchor_at, v_anchor_id
  FROM public.messages
  WHERE id = v_report.message_id;

  IF v_anchor_at IS NULL THEN
    v_anchor_at := v_report.created_at;
    -- The max uuid makes messages sent at the report time count as "before".
    v_anchor_id := 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid;
  END IF;

  RETURN (
    WITH window_rows AS (
      (
        SELECT m.*
        FROM public.messages m
        WHERE m.thread_id = v_report.thread_id
          AND (m.created_at, m.id) <= (v_anchor_at, v_anchor_id)
        ORDER BY m.created_at DESC, m.id DESC
        LIMIT v_context + 1
      )
      UNION ALL
      (
        SELECT m.*
        FROM public.messages m
        WHERE m.thread_id = v_report.thread_id
          AND (m.created_at, m.id) > (v_anchor_at, v_anchor_id)
        ORDER BY m.created_at, m.id
        LIMIT v_context
      )
    )
    SELECT jsonb_build_object(
      -- Same fallback as counterpart avatars in get_thread_summary.
      'reportedAvatarUrl', (
        SELECT COALESCE(
          us.profile_picture_url,
          au.raw_user_meta_data->>'avatar_url',
          au.raw_user_meta_data->>'picture'
        )
        FROM auth.users au
        LEFT JOIN public.user_settings us ON us.user_id = au.id
        WHERE au.id = v_report.reported_user_id
      ),
      'messages', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', w.id,
            'thread_id', w.thread_id,
            'sender_user_id', w.sender_user_id,
            'message_type', w.message_type,
            'body', w.body,
            'client_id', w.client_id,
            'reply_to_message_id', w.reply_to_message_id,
            'created_at', w.created_at,
            'edited_at', w.edited_at,
            'deleted_at', w.deleted_at,
            'metadata', w.metadata,
            'attachments', COALESCE(
              (
                SELECT jsonb_agg(
                  jsonb_build_object(
                    'id', ma.id,
                    'attachment_index', ma.attachment_index,
                    'kind', ma.kind,
                    'storage_bucket', ma.storage_bucket,
                    'storage_path', ma.storage_path,
                    'mime_type', ma.mime_type,
                    'byte_size', ma.byte_size,
                    'width', ma.width,
                    'height', ma.height,
                    'created_at', ma.created_at,
                    'reactions', '[]'::jsonb
                  )
                  ORDER BY ma.attachment_index
                )
                FROM public.message_attachments ma
                WHERE ma.message_id = w.id
              ),
              '[]'::jsonb
            ),
            'reactions', COALESCE(
              (
                SELECT jsonb_agg(
                  jsonb_build_object('emoji', r.emoji, 'count', r.reaction_count, 'viewer_has_reacted', false)
                  ORDER BY r.reaction_count DESC, r.first_created_at, r.emoji
                )
                FROM (
                  SELECT mr.emoji, count(*)::integer AS reaction_count, min(mr.created_at) AS first_created_at
                  FROM public.message_reactions mr
                  WHERE mr.message_id = w.id AND mr.attachment_id IS NULL
                  GROUP BY mr.emoji
                ) r
              ),
              '[]'::jsonb
            )
          )
          ORDER BY w.created_at, w.id
        ),
        '[]'::jsonb
      )
    )
    FROM window_rows w
  );
END;
$function$;

-- Soft deletes a reported message, the same way delete_message does for its sender.
CREATE OR REPLACE FUNCTION public.admin_delete_message_api(p_message_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_thread_id uuid;
  v_sender_user_id uuid;
  v_latest public.messages%ROWTYPE;
BEGIN
  PERFORM public.assert_is_admin();

  SELECT thread_id, sender_user_id INTO v_thread_id, v_sender_user_id
  FROM public.messages
  WHERE id = p_message_id AND deleted_at IS NULL;

  IF v_thread_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Message not found or already deleted');
  END IF;

  -- Lets the soft delete trigger emit the sync event that removes the message on devices.
  PERFORM set_config('tidex.messaging_v2_emit_message_soft_delete', 'true', true);

  UPDATE public.messages SET deleted_at = now() WHERE id = p_message_id;

  SELECT * INTO v_latest
  FROM public.messages m
  WHERE m.thread_id = v_thread_id AND m.deleted_at IS NULL
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1;

  UPDATE public.threads t
  SET
    last_message_id = v_latest.id,
    last_message_sender_id = v_latest.sender_user_id,
    last_message_at = COALESCE(v_latest.created_at, t.created_at)
  WHERE t.id = v_thread_id;

  PERFORM public.admin_log_action_rpc(
    'message_deleted',
    v_sender_user_id,
    NULL,
    jsonb_build_object('message_id', p_message_id, 'thread_id', v_thread_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_report_status_api(
  p_report_id uuid,
  p_status text,
  p_reviewer_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  UPDATE public.abuse_reports
  SET
    status = p_status,
    reviewer_notes = NULLIF(btrim(COALESCE(p_reviewer_notes, '')), ''),
    reviewed_at = now(),
    reviewed_by = auth.uid()
  WHERE id = p_report_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_audit_log_api(
  p_limit integer DEFAULT 50,
  p_action_filter text DEFAULT NULL,
  p_target_filter uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  RETURN (
    WITH rows AS (
      SELECT
        a.id,
        a.admin_id,
        a.admin_email,
        a.action,
        a.target_user_id,
        a.target_email,
        a.metadata,
        a.created_at
      FROM internal.admin_audit_log a
      WHERE (p_action_filter IS NULL OR a.action = p_action_filter)
        AND (p_target_filter IS NULL OR a.target_user_id = p_target_filter)
      ORDER BY a.created_at DESC
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 1000)
    )
    SELECT jsonb_build_object(
      'success', true,
      'entries', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'adminId', admin_id,
            'adminEmail', admin_email,
            'action', action,
            'targetUserId', target_user_id,
            'targetEmail', target_email,
            'metadata', metadata,
            'createdAt', created_at
          )
          ORDER BY created_at DESC
        ),
        '[]'::jsonb
      )
    )
    FROM rows
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_shares_api(
  p_search text DEFAULT NULL,
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_page integer := GREATEST(COALESCE(p_page, 1), 1);
  v_page_size integer := LEAST(GREATEST(COALESCE(p_page_size, 20), 1), 100);
  v_offset integer := (v_page - 1) * v_page_size;
BEGIN
  PERFORM public.assert_is_admin();

  RETURN (
    WITH rows AS (
      SELECT
        ss.id,
        ss.owner_id,
        ou.email AS owner_email,
        COALESCE(ou.raw_user_meta_data->>'full_name', ou.raw_user_meta_data->>'name') AS owner_name,
        ou.phone AS owner_phone,
        ss.viewer_id,
        vu.email AS viewer_email,
        COALESCE(vu.raw_user_meta_data->>'full_name', vu.raw_user_meta_data->>'name') AS viewer_name,
        vu.phone AS viewer_phone,
        ss.created_at,
        ss.show_earnings,
        ss.hidden AS blocked,
        ss.muted
      FROM public.shift_shares ss
      LEFT JOIN auth.users ou ON ou.id = ss.owner_id
      LEFT JOIN auth.users vu ON vu.id = ss.viewer_id
      WHERE
        p_search IS NULL
        OR p_search = ''
        OR lower(COALESCE(ou.email, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(vu.email, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(ou.phone, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(vu.phone, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(ou.raw_user_meta_data->>'full_name', ou.raw_user_meta_data->>'name', '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(vu.raw_user_meta_data->>'full_name', vu.raw_user_meta_data->>'name', '')) LIKE '%' || lower(p_search) || '%'
        OR ss.owner_id::text LIKE '%' || lower(p_search) || '%'
        OR ss.viewer_id::text LIKE '%' || lower(p_search) || '%'
    ),
    counted AS (
      SELECT COUNT(*)::integer AS total_count FROM rows
    ),
    paged AS (
      SELECT *
      FROM rows
      ORDER BY created_at DESC
      LIMIT v_page_size
      OFFSET v_offset
    )
    SELECT jsonb_build_object(
      'success', true,
      'shares', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'ownerId', owner_id,
            'ownerEmail', owner_email,
            'ownerName', owner_name,
            'ownerPhone', owner_phone,
            'viewerId', viewer_id,
            'viewerEmail', viewer_email,
            'viewerName', viewer_name,
            'viewerPhone', viewer_phone,
            'createdAt', created_at,
            'showEarnings', show_earnings,
            'blocked', blocked,
            'muted', muted
          )
          ORDER BY created_at DESC
        ),
        '[]'::jsonb
      ),
      'totalCount', (SELECT total_count FROM counted),
      'page', v_page,
      'pageSize', v_page_size
    )
    FROM paged
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_create_share_api(
  p_owner_id uuid,
  p_viewer_id uuid,
  p_show_earnings boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_share_id uuid;
  v_owner_email text;
  v_viewer_email text;
BEGIN
  PERFORM public.assert_is_admin();

  IF p_owner_id = p_viewer_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'Owner and viewer cannot be the same user');
  END IF;

  SELECT email INTO v_owner_email FROM auth.users WHERE id = p_owner_id;
  SELECT email INTO v_viewer_email FROM auth.users WHERE id = p_viewer_id;

  INSERT INTO public.shift_shares (owner_id, viewer_id, show_earnings, muted, owner_muted)
  VALUES (p_owner_id, p_viewer_id, COALESCE(p_show_earnings, true), false, false)
  RETURNING id INTO v_share_id;

  PERFORM public.admin_log_action_rpc(
    'shift_share_created',
    v_share_id,
    NULL,
    jsonb_build_object(
      'share_id', v_share_id,
      'owner_id', p_owner_id,
      'owner_email', v_owner_email,
      'viewer_id', p_viewer_id,
      'viewer_email', v_viewer_email,
      'show_earnings', COALESCE(p_show_earnings, true)
    )
  );

  RETURN jsonb_build_object('success', true, 'id', v_share_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_share_api(
  p_share_id uuid,
  p_show_earnings boolean DEFAULT NULL,
  p_blocked boolean DEFAULT NULL,
  p_muted boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  UPDATE public.shift_shares
  SET
    show_earnings = COALESCE(p_show_earnings, show_earnings),
    hidden = COALESCE(p_blocked, hidden),
    muted = COALESCE(p_muted, muted)
  WHERE id = p_share_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Share not found');
  END IF;

  PERFORM public.admin_log_action_rpc(
    'shift_share_updated',
    p_share_id,
    NULL,
    jsonb_build_object(
      'show_earnings', p_show_earnings,
      'blocked', p_blocked,
      'muted', p_muted
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_share_api(
  p_share_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  DELETE FROM public.shift_shares
  WHERE id = p_share_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Share not found');
  END IF;

  PERFORM public.admin_log_action_rpc(
    'shift_share_deleted',
    p_share_id,
    NULL,
    '{}'::jsonb
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_broadcast_history_api()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  RETURN (
    WITH rows AS (
      SELECT
        ab.id,
        COALESCE(ab.title, ab.title_no) AS title,
        COALESCE(ab.body, ab.body_no) AS body,
        ab.target,
        ab.target_count,
        ab.status,
        ab.created_at,
        COUNT(no.id) FILTER (WHERE no.status = 'sent')::integer AS sent_count,
        COUNT(no.id) FILTER (WHERE no.status = 'failed')::integer AS failed_count,
        COUNT(no.id) FILTER (WHERE no.status = 'skipped')::integer AS skipped_count,
        COUNT(no.id) FILTER (WHERE no.status IN ('pending', 'sending'))::integer AS pending_count
      FROM internal.admin_broadcasts ab
      LEFT JOIN internal.notifications_outbox no ON no.broadcast_id = ab.id
      GROUP BY ab.id
      ORDER BY ab.created_at DESC
      LIMIT 10
    )
    SELECT jsonb_build_object(
      'broadcasts', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'title', title,
            'body', body,
            'target', target,
            'targetCount', target_count,
            'status', status,
            'createdAt', created_at,
            'sentCount', sent_count,
            'failedCount', failed_count,
            'skippedCount', skipped_count,
            'pendingCount', pending_count
          )
          ORDER BY created_at DESC
        ),
        '[]'::jsonb
      )
    )
    FROM rows
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_broadcast_detail_api(p_broadcast_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM public.assert_is_admin();

  SELECT jsonb_build_object(
    'id', ab.id,
    'title', ab.title,
    'body', ab.body,
    'deeplink', ab.deeplink,
    'titleNo', ab.title_no,
    'bodyNo', ab.body_no,
    'deeplinkNo', ab.deeplink_no,
    'target', ab.target,
    'targetCount', ab.target_count,
    'status', ab.status,
    'createdAt', ab.created_at,
    'adminEmail', au.email,
    'recipients', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', d.id,
          'userId', d.recipient_id,
          'name', d.name,
          'email', d.email,
          'phone', d.phone,
          'status', d.status,
          'title', d.title,
          'deeplink', d.data_payload->>'deeplink',
          'attempts', d.attempts,
          'errorMessage', d.error_message,
          'processedAt', d.processed_at
        )
        ORDER BY
          CASE d.status WHEN 'failed' THEN 0 WHEN 'pending' THEN 1 WHEN 'sending' THEN 1 WHEN 'skipped' THEN 2 ELSE 3 END,
          lower(COALESCE(d.name, d.email, d.phone, ''))
      )
      FROM (
        SELECT
          no.id,
          no.recipient_id,
          COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS name,
          u.email,
          u.phone,
          no.status,
          no.title,
          no.data_payload,
          no.attempts,
          no.error_message,
          no.processed_at
        FROM internal.notifications_outbox no
        LEFT JOIN auth.users u ON u.id = no.recipient_id
        WHERE no.broadcast_id = ab.id
        LIMIT 2000
      ) d
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM internal.admin_broadcasts ab
  LEFT JOIN auth.users au ON au.id = ab.admin_id
  WHERE ab.id = p_broadcast_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Broadcast not found';
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_preview_notification_target_api(
  p_target text,
  p_specific_user_ids uuid[] DEFAULT NULL,
  p_include_self boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_count integer := 0;
BEGIN
  PERFORM public.assert_is_admin();

  IF p_target = 'specific' THEN
    v_count := COALESCE(array_length(p_specific_user_ids, 1), 0);
    RETURN jsonb_build_object('count', v_count);
  END IF;

  IF p_target = 'all' THEN
    SELECT COUNT(DISTINCT pd.user_id)::integer
    INTO v_count
    FROM internal.push_devices pd
    WHERE p_include_self OR pd.user_id <> auth.uid();
  ELSIF p_target = 'active' THEN
    SELECT COUNT(DISTINCT pd.user_id)::integer
    INTO v_count
    FROM internal.push_devices pd
    WHERE internal.admin_user_last_active(pd.user_id) >= now() - interval '7 days';
  ELSIF p_target = 'new' THEN
    SELECT COUNT(DISTINCT pd.user_id)::integer
    INTO v_count
    FROM internal.push_devices pd
    INNER JOIN auth.users u ON u.id = pd.user_id
    WHERE u.created_at >= now() - interval '7 days';
  ELSE
    RAISE EXCEPTION 'Invalid target. Must be all, active, new, or specific';
  END IF;

  RETURN jsonb_build_object('count', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_send_broadcast_api(
  p_title text,
  p_title_no text,
  p_body text,
  p_body_no text,
  p_target text,
  p_deeplink text DEFAULT NULL,
  p_deeplink_no text DEFAULT NULL,
  p_specific_user_ids uuid[] DEFAULT NULL,
  p_include_self boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_admin_id uuid := auth.uid();
  v_broadcast_id uuid;
  v_target_user_ids uuid[];
  v_title text := NULLIF(btrim(COALESCE(p_title, '')), '');
  v_body text := NULLIF(btrim(COALESCE(p_body, '')), '');
  v_deeplink text := NULLIF(btrim(COALESCE(p_deeplink, '')), '');
  v_title_no text := NULLIF(btrim(COALESCE(p_title_no, '')), '');
  v_body_no text := NULLIF(btrim(COALESCE(p_body_no, '')), '');
  v_deeplink_no text := NULLIF(btrim(COALESCE(p_deeplink_no, '')), '');
  v_has_en boolean;
  v_has_no boolean;
BEGIN
  PERFORM public.assert_is_admin();

  v_has_en := v_title IS NOT NULL AND v_body IS NOT NULL;
  v_has_no := v_title_no IS NOT NULL AND v_body_no IS NOT NULL;

  IF NOT v_has_en AND NOT v_has_no THEN
    RETURN jsonb_build_object('success', false, 'message', 'Add a title and message in at least one language');
  END IF;
  IF char_length(COALESCE(v_title, '')) > 100 OR char_length(COALESCE(v_title_no, '')) > 100 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Titles can be at most 100 characters');
  END IF;
  IF char_length(COALESCE(v_body, '')) > 500 OR char_length(COALESCE(v_body_no, '')) > 500 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Messages can be at most 500 characters');
  END IF;

  IF p_target = 'specific' THEN
    v_target_user_ids := COALESCE(p_specific_user_ids, ARRAY[]::uuid[]);
  ELSIF p_target = 'all' THEN
    SELECT array_agg(DISTINCT pd.user_id)
    INTO v_target_user_ids
    FROM internal.push_devices pd
    WHERE p_include_self OR pd.user_id <> v_admin_id;
  ELSIF p_target = 'active' THEN
    SELECT array_agg(DISTINCT pd.user_id)
    INTO v_target_user_ids
    FROM internal.push_devices pd
    WHERE internal.admin_user_last_active(pd.user_id) >= now() - interval '7 days';
  ELSIF p_target = 'new' THEN
    SELECT array_agg(DISTINCT pd.user_id)
    INTO v_target_user_ids
    FROM internal.push_devices pd
    INNER JOIN auth.users u ON u.id = pd.user_id
    WHERE u.created_at >= now() - interval '7 days';
  ELSE
    RAISE EXCEPTION 'Invalid target';
  END IF;

  IF COALESCE(array_length(v_target_user_ids, 1), 0) = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'No users match target criteria');
  END IF;

  INSERT INTO internal.admin_broadcasts (
    admin_id,
    title,
    body,
    deeplink,
    title_no,
    body_no,
    deeplink_no,
    target,
    target_count
  ) VALUES (
    v_admin_id,
    CASE WHEN v_has_en THEN v_title END,
    CASE WHEN v_has_en THEN v_body END,
    CASE WHEN v_has_en THEN v_deeplink END,
    CASE WHEN v_has_no THEN v_title_no END,
    CASE WHEN v_has_no THEN v_body_no END,
    CASE WHEN v_has_no THEN v_deeplink_no END,
    p_target,
    array_length(v_target_user_ids, 1)
  )
  RETURNING id INTO v_broadcast_id;

  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    broadcast_id,
    notification_type,
    due_at,
    title,
    body,
    data_payload,
    idempotency_key
  )
  SELECT
    v_admin_id,
    r.id,
    v_broadcast_id,
    'admin_broadcast',
    now(),
    CASE WHEN r.use_no THEN v_title_no ELSE v_title END,
    CASE WHEN r.use_no THEN v_body_no ELSE v_body END,
    jsonb_build_object(
      'type', 'admin_broadcast',
      'deeplink', CASE WHEN r.use_no THEN COALESCE(v_deeplink_no, v_deeplink) ELSE v_deeplink END,
      'broadcast_id', v_broadcast_id
    ),
    'broadcast:' || v_broadcast_id::text || ':' || r.id::text
  FROM (
    SELECT
      u.id,
      (internal.admin_broadcast_language(u.raw_user_meta_data->>'locale') = 'no' AND v_has_no)
        OR NOT v_has_en AS use_no
    FROM auth.users u
    WHERE u.id = ANY(v_target_user_ids)
  ) r;

  UPDATE internal.admin_broadcasts
  SET status = 'queued'
  WHERE id = v_broadcast_id;

  PERFORM public.admin_log_action_rpc(
    'broadcast_sent',
    NULL,
    NULL,
    jsonb_build_object(
      'broadcast_id', v_broadcast_id,
      'title', COALESCE(CASE WHEN v_has_en THEN v_title END, v_title_no),
      'languages', to_jsonb(array_remove(ARRAY[
        CASE WHEN v_has_en THEN 'en' END,
        CASE WHEN v_has_no THEN 'no' END
      ], NULL)),
      'target', p_target,
      'target_count', array_length(v_target_user_ids, 1),
      'deeplink', COALESCE(v_deeplink, v_deeplink_no)
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Notification queued for ' || array_length(v_target_user_ids, 1)::text || ' users'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_log_action_rpc(text, uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_users_api(integer, integer, text, text, text, boolean, text, text, text, integer, integer, integer, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_feedback_api(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_respond_feedback_api(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_reports_api(integer, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_report_status_api(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_report_messages_api(uuid, integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_report_messages_api(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_message_api(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_message_api(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_audit_log_api(integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_shares_api(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_share_api(uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_share_api(uuid, boolean, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_share_api(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_broadcast_history_api() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_preview_notification_target_api(text, uuid[], boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_broadcast_api(text, text, text, text, text, text, text, uuid[], boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_broadcast_detail_api(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_user_stats_api(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_active_users_chart_api(text) TO authenticated;
