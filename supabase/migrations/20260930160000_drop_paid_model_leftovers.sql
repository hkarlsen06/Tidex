-- Tidex has been free since 2026-09-28. Removes paywall, trial and Stripe objects that no
-- app build or edge function calls anymore. Objects that iOS 2.7.x and older still call
-- (get_my_entitlement, user_entitlements, get_paywall_config) and the Apple notification
-- plumbing stay until those builds retire (see TODO.md).

-- admin_toggle_grandfathered_api could set before_paywall = false, which would put a user
-- on an old build behind a paywall with nothing to buy.
DROP FUNCTION IF EXISTS public.admin_toggle_grandfathered_api(uuid, text, boolean);
DROP FUNCTION IF EXISTS public.admin_manage_trial_api(uuid, text, text, integer);
DROP FUNCTION IF EXISTS public.admin_get_subscribers_api(text);
DROP FUNCTION IF EXISTS public.admin_get_subscribers();
DROP FUNCTION IF EXISTS public.admin_count_target_users_pro();
DROP FUNCTION IF EXISTS public.admin_get_target_users_pro();
DROP FUNCTION IF EXISTS public.has_shift_storage_entitlement(uuid);
DROP FUNCTION IF EXISTS public.get_user_entitlement_status(uuid);
DROP FUNCTION IF EXISTS public.get_user_id_by_app_account_token(uuid);

-- Left over from the deleted stripe_webhook function and the Stripe Sync integration.
DROP TABLE IF EXISTS internal.stripe_events;
SELECT pgmq.drop_queue('stripe_sync_work')
WHERE EXISTS (SELECT 1 FROM pgmq.list_queues() WHERE queue_name = 'stripe_sync_work');

-- The admin user list no longer reports plan or grandfathered status, and broadcasts no
-- longer offer a 'pro' target. Admins always run the latest build, so old admin screens
-- get no compatibility.

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
