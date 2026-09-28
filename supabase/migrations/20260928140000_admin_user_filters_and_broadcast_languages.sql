-- Admin console: user sorting and filtering, per-language broadcasts, and broadcast details.
--
-- 1. internal.admin_broadcast_language(locale) decides which broadcast text a user gets.
--    Norwegian locales (no, nb, nn and their regional forms) get Norwegian; everyone else gets English.
-- 2. admin_list_users_api gains p_sort and p_filter and returns language and lastActiveAt.
--    The old three-argument signature is dropped. Its callers still resolve to the new function
--    because the new parameters have defaults. isGrandfathered and plan stay for older app builds.
-- 3. admin_send_broadcast_api accepts text in only one language. Recipients whose language is
--    missing get the other language. The Norwegian text is now stored on the broadcast.
-- 4. admin_get_broadcast_detail_api returns a broadcast's stored text and its delivery rows.

CREATE OR REPLACE FUNCTION internal.admin_broadcast_language(p_locale text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT CASE WHEN lower(COALESCE(p_locale, '')) ~ '^(no|nb|nn)([-_].*)?$' THEN 'no' ELSE 'en' END;
$function$;

REVOKE ALL ON FUNCTION internal.admin_broadcast_language(text) FROM PUBLIC, anon, authenticated;

ALTER TABLE internal.admin_broadcasts
  ALTER COLUMN title DROP NOT NULL,
  ALTER COLUMN body DROP NOT NULL,
  ADD CONSTRAINT admin_broadcasts_has_text_check CHECK (
    (title IS NOT NULL AND body IS NOT NULL) OR (title_no IS NOT NULL AND body_no IS NOT NULL)
  );

DROP FUNCTION public.admin_list_users_api(integer, integer, text);

CREATE FUNCTION public.admin_list_users_api(
  p_page integer DEFAULT 1,
  p_per_page integer DEFAULT 20,
  p_search text DEFAULT NULL,
  p_sort text DEFAULT 'name',
  p_filter text DEFAULT 'all'
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
BEGIN
  PERFORM public.assert_is_admin();

  IF v_sort NOT IN ('name', 'newest', 'last_sign_in', 'last_active') THEN
    RAISE EXCEPTION 'Invalid sort. Must be name, newest, last_sign_in, or last_active';
  END IF;
  IF v_filter NOT IN ('all', 'active', 'new', 'admins', 'banned', 'norwegian', 'english') THEN
    RAISE EXCEPTION 'Invalid filter. Must be all, active, new, admins, banned, norwegian, or english';
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
        us.last_active
      FROM auth.users u
      LEFT JOIN public.user_settings us ON us.user_id = u.id
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
        WHEN 'new' THEN b.created_at >= now() - interval '30 days'
        WHEN 'admins' THEN b.is_admin OR b.is_super_admin
        WHEN 'banned' THEN b.banned_until IS NOT NULL
        WHEN 'norwegian' THEN b.language = 'no'
        WHEN 'english' THEN b.language = 'en'
        ELSE true
      END
    ),
    enriched AS (
      SELECT
        f.*,
        COALESCE(p.before_paywall, false) AS is_grandfathered,
        s.provider,
        s.product_id,
        s.price_id,
        s.status
      FROM filtered f
      LEFT JOIN public.profiles p ON p.id = f.id
      LEFT JOIN LATERAL (
        SELECT provider, product_id, price_id, status, current_period_end
        FROM public.subscriptions s
        WHERE s.user_id = f.id
        ORDER BY COALESCE(s.current_period_end, '2099-12-31'::timestamptz) DESC
        LIMIT 1
      ) s ON true
    ),
    counted AS (
      SELECT COUNT(*)::integer AS total_count FROM enriched
    ),
    paged AS (
      SELECT *
      FROM enriched
      ORDER BY
        CASE WHEN v_sort = 'newest' THEN created_at END DESC,
        CASE WHEN v_sort = 'last_sign_in' THEN last_sign_in_at END DESC NULLS LAST,
        CASE WHEN v_sort = 'last_active' THEN last_active END DESC NULLS LAST,
        lower(COALESCE(name, email, phone, '')),
        created_at DESC,
        id
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
            'lastSignInAt', last_sign_in_at,
            'lastActiveAt', last_active,
            'createdAt', created_at,
            'language', language,
            'isBanned', banned_until IS NOT NULL,
            'bannedUntil', banned_until,
            'isAdmin', is_admin,
            'isSuperAdmin', is_super_admin,
            'isGrandfathered', is_grandfathered,
            'plan',
              CASE
                WHEN provider = 'admin_trial' AND status = 'active' THEN 'trial'
                WHEN status IN ('active', 'trialing', 'grace')
                  AND (
                    COALESCE(product_id, '') ILIKE '%max%'
                    OR COALESCE(price_id, '') ILIKE '%max%'
                    OR COALESCE(product_id, '') IN ('no.tidex.max', 'no.tidex.max.year')
                    OR COALESCE(price_id, '') IN ('no.tidex.max', 'no.tidex.max.year')
                  ) THEN 'max'
                WHEN status IN ('active', 'trialing', 'grace') THEN 'pro'
                ELSE 'free'
              END
          )
          ORDER BY
            CASE WHEN v_sort = 'newest' THEN created_at END DESC,
            CASE WHEN v_sort = 'last_sign_in' THEN last_sign_in_at END DESC NULLS LAST,
            CASE WHEN v_sort = 'last_active' THEN last_active END DESC NULLS LAST,
            lower(COALESCE(name, email, phone, '')),
            created_at DESC,
            id
        ),
        '[]'::jsonb
      ),
      'totalCount', (SELECT total_count FROM counted),
      'page', v_page,
      'perPage', v_per_page,
      'resultsArePartial', false
    )
    FROM paged
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_users_api(integer, integer, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_users_api(integer, integer, text, text, text) TO authenticated, service_role;

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
  ELSIF p_target = 'pro' THEN
    SELECT array_agg(DISTINCT pd.user_id)
    INTO v_target_user_ids
    FROM internal.push_devices pd
    INNER JOIN public.subscriptions s ON s.user_id = pd.user_id
    WHERE s.status IN ('active', 'trialing');
  ELSIF p_target = 'active' THEN
    SELECT array_agg(DISTINCT pd.user_id)
    INTO v_target_user_ids
    FROM internal.push_devices pd
    INNER JOIN public.user_settings us ON us.user_id = pd.user_id
    WHERE us.last_active >= now() - interval '7 days';
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

CREATE FUNCTION public.admin_get_broadcast_detail_api(p_broadcast_id uuid)
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

REVOKE ALL ON FUNCTION public.admin_get_broadcast_detail_api(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_broadcast_detail_api(uuid) TO authenticated, service_role;
