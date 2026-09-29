-- Admin console: include each user's avatar URL in the users list.

CREATE OR REPLACE FUNCTION public.admin_list_users_api(
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
        internal.admin_user_last_active(u.id) AS last_active,
        COALESCE(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture') AS oauth_avatar_url
      FROM auth.users u
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
        COALESCE(us.profile_picture_url, f.oauth_avatar_url) AS avatar_url
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
