-- Admin console: more sort orders and filters that combine in the users list.
--
-- New sorts: shifts, messages and friends (counts), plus p_reverse to flip any order.
-- New filters: account, language, sign-in provider, signup and activity windows, whether
-- the user has shifts, messages or friends, and app version. p_filter stays for older builds.
-- The response also lists the app versions users have, for the version filter.

DROP FUNCTION IF EXISTS public.admin_list_users_api(integer, integer, text, text, text);

CREATE FUNCTION public.admin_list_users_api(
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
        COALESCE(p.before_paywall, false) AS is_grandfathered,
        s.provider,
        s.product_id,
        s.price_id,
        s.status,
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
      LEFT JOIN public.profiles p ON p.id = f.id
      LEFT JOIN public.user_settings us ON us.user_id = f.id
      LEFT JOIN LATERAL (
        SELECT provider, product_id, price_id, status, current_period_end
        FROM public.subscriptions s
        WHERE s.user_id = f.id
        ORDER BY COALESCE(s.current_period_end, '2099-12-31'::timestamptz) DESC
        LIMIT 1
      ) s ON true
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
            'isGrandfathered', is_grandfathered,
            'appVersion', app_version,
            'shiftCount', shift_count,
            'messageCount', message_count,
            'friendCount', friend_count,
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

REVOKE ALL ON FUNCTION public.admin_list_users_api(
  integer, integer, text, text, text, boolean, text, text, text, integer, integer, integer, text, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_users_api(
  integer, integer, text, text, text, boolean, text, text, text, integer, integer, integer, text, text, text, text
) TO authenticated, service_role;
