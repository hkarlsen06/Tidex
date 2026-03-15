-- iOS migration away from Next.js app/API

-- Source: supabase/sql/functions/auth/assert_admin.sql
CREATE OR REPLACE FUNCTION public.assert_is_admin()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.assert_is_superadmin()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'Superadmin access required';
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.assert_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.assert_is_superadmin() TO authenticated;

-- Source: supabase/sql/functions/utility/find_user_by_identifier.sql
REVOKE ALL ON FUNCTION public.find_user_by_email(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_user_by_phone(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_users_by_ids(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_user_by_email(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_users_by_ids(uuid[]) TO authenticated;

-- Source: supabase/sql/functions/notification/mobile_notification_api.sql
CREATE OR REPLACE FUNCTION public.register_push_device(
  p_platform text,
  p_apns_token text DEFAULT NULL,
  p_fcm_token text DEFAULT NULL,
  p_device_id text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_app_version text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_existing_id uuid;
  v_insert_fcm text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_platform IS NULL OR p_platform NOT IN ('ios', 'android', 'web') THEN
    RAISE EXCEPTION 'Invalid platform. Must be ios, android, or web';
  END IF;

  IF COALESCE(NULLIF(p_apns_token, ''), NULLIF(p_fcm_token, '')) IS NULL THEN
    RAISE EXCEPTION 'Either apnsToken or fcmToken is required';
  END IF;

  IF p_apns_token IS NOT NULL THEN
    DELETE FROM internal.push_devices
    WHERE apns_token = p_apns_token
      AND user_id <> v_user_id;
  END IF;

  IF p_device_id IS NOT NULL THEN
    SELECT id
    INTO v_existing_id
    FROM internal.push_devices
    WHERE user_id = v_user_id
      AND device_id = p_device_id
    ORDER BY updated_at DESC
    LIMIT 1;
  END IF;

  IF v_existing_id IS NULL AND p_fcm_token IS NOT NULL THEN
    SELECT id
    INTO v_existing_id
    FROM internal.push_devices
    WHERE fcm_token = p_fcm_token
    LIMIT 1;
  END IF;

  IF v_existing_id IS NULL AND p_apns_token IS NOT NULL AND p_fcm_token IS NULL THEN
    SELECT id
    INTO v_existing_id
    FROM internal.push_devices
    WHERE user_id = v_user_id
      AND platform = p_platform
    ORDER BY updated_at DESC
    LIMIT 1;
  END IF;

  IF v_existing_id IS NOT NULL THEN
    UPDATE internal.push_devices
    SET
      device_id = p_device_id,
      device_model = p_device_model,
      app_version = p_app_version,
      last_seen_at = v_now,
      updated_at = v_now,
      apns_token = COALESCE(p_apns_token, apns_token),
      fcm_token = COALESCE(p_fcm_token, fcm_token)
    WHERE id = v_existing_id;

    IF p_device_id IS NOT NULL THEN
      DELETE FROM internal.push_devices
      WHERE user_id = v_user_id
        AND device_id = p_device_id
        AND id <> v_existing_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'action', 'updated');
  END IF;

  v_insert_fcm := p_fcm_token;
  IF p_apns_token IS NOT NULL AND v_insert_fcm IS NULL THEN
    v_insert_fcm := 'apns_' || left(p_apns_token, 32);
  END IF;

  BEGIN
    INSERT INTO internal.push_devices (
      user_id,
      platform,
      apns_token,
      fcm_token,
      device_id,
      device_model,
      app_version,
      last_seen_at,
      updated_at
    ) VALUES (
      v_user_id,
      p_platform,
      p_apns_token,
      v_insert_fcm,
      p_device_id,
      p_device_model,
      p_app_version,
      v_now,
      v_now
    );
  EXCEPTION
    WHEN unique_violation THEN
      RETURN jsonb_build_object('success', true, 'action', 'already_registered');
  END;

  RETURN jsonb_build_object('success', true, 'action', 'inserted');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.register_push_device(text, text, text, text, text, text) TO authenticated;

-- Source: supabase/sql/functions/sharing/mobile_sharing_api.sql
CREATE OR REPLACE FUNCTION public.get_sharing_friends_api()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_limit integer := 1;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT CASE COALESCE(tier, 'free')
    WHEN 'max' THEN 20
    WHEN 'pro' THEN 10
    ELSE 1
  END
  INTO v_limit
  FROM public.user_entitlements
  WHERE user_id = v_user_id;

  RETURN (
    WITH incoming_shares AS (
      SELECT owner_id, created_at, show_earnings, hidden, muted, blocked_by_user_id
      FROM public.shift_shares
      WHERE viewer_id = v_user_id
    ),
    outgoing_shares AS (
      SELECT viewer_id, created_at, show_earnings, owner_muted, blocked_by_user_id
      FROM public.shift_shares
      WHERE owner_id = v_user_id
    ),
    all_user_ids AS (
      SELECT owner_id AS user_id FROM incoming_shares
      UNION
      SELECT viewer_id AS user_id FROM outgoing_shares
    ),
    profiles AS (
      SELECT
        u.id,
        u.email,
        u.phone,
        COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS first_name,
        u.raw_user_meta_data->>'avatar_url' AS oauth_avatar_url,
        us.profile_picture_url
      FROM auth.users u
      JOIN all_user_ids ids ON ids.user_id = u.id
      LEFT JOIN public.user_settings us ON us.user_id = u.id
    ),
    combined AS (
      SELECT
        p.id,
        p.email,
        p.phone,
        p.first_name,
        p.profile_picture_url,
        p.oauth_avatar_url,
        i.created_at AS incoming_created_at,
        i.show_earnings AS incoming_show_earnings,
        i.hidden AS incoming_hidden,
        i.muted AS incoming_muted,
        i.blocked_by_user_id AS incoming_blocked_by_user_id,
        o.created_at AS outgoing_created_at,
        o.show_earnings AS outgoing_show_earnings,
        o.owner_muted AS outgoing_owner_muted,
        o.blocked_by_user_id AS outgoing_blocked_by_user_id
      FROM profiles p
      LEFT JOIN incoming_shares i ON i.owner_id = p.id
      LEFT JOIN outgoing_shares o ON o.viewer_id = p.id
    ),
    friend_rows AS (
      SELECT
        id,
        jsonb_build_object(
          'id', id,
          'email', email,
          'phone', phone,
          'firstName', first_name,
          'profilePictureUrl', profile_picture_url,
          'oauthAvatarUrl', oauth_avatar_url,
          'sharesWithMe',
            CASE WHEN incoming_created_at IS NULL THEN NULL ELSE jsonb_build_object(
              'blocked', incoming_hidden,
              'showEarningsToMe', incoming_show_earnings,
              'sharedAt', incoming_created_at,
              'notificationFrequency', CASE WHEN incoming_muted THEN 'muted' ELSE 'instant' END
            ) END,
          'iShareWith',
            CASE WHEN outgoing_created_at IS NULL THEN NULL ELSE jsonb_build_object(
              'showEarningsToThem', outgoing_show_earnings,
              'sharedAt', outgoing_created_at,
              'ownerMuted', COALESCE(outgoing_owner_muted, false)
            ) END
        ) AS friend_json,
        COALESCE(incoming_blocked_by_user_id, outgoing_blocked_by_user_id) AS blocked_by_user_id,
        lower(COALESCE(first_name, email, phone, '')) AS sort_name
      FROM combined
    ),
    visible_friends AS (
      SELECT friend_json, sort_name
      FROM friend_rows
      WHERE blocked_by_user_id IS NULL
    ),
    blocked_friends AS (
      SELECT friend_json, sort_name
      FROM friend_rows
      WHERE blocked_by_user_id = v_user_id
    ),
    outgoing_count AS (
      SELECT COUNT(*)::integer AS count
      FROM outgoing_shares
    )
    SELECT jsonb_build_object(
      'friends', COALESCE((SELECT jsonb_agg(friend_json ORDER BY sort_name) FROM visible_friends), '[]'::jsonb),
      'blockedFriends', COALESCE((SELECT jsonb_agg(friend_json ORDER BY sort_name) FROM blocked_friends), '[]'::jsonb),
      'capacity', jsonb_build_object(
        'canAdd', COALESCE((SELECT count FROM outgoing_count), 0) < v_limit,
        'currentCount', COALESCE((SELECT count FROM outgoing_count), 0),
        'limit', v_limit
      )
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.manage_sharing_action(
  p_action text,
  p_identifier text DEFAULT NULL,
  p_recipient_id uuid DEFAULT NULL,
  p_show_earnings boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_limit integer := 1;
  v_target_id uuid;
  v_normalized text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT CASE COALESCE(tier, 'free')
    WHEN 'max' THEN 20
    WHEN 'pro' THEN 10
    ELSE 1
  END
  INTO v_limit
  FROM public.user_entitlements
  WHERE user_id = v_user_id;

  IF (SELECT COUNT(*) FROM public.shift_shares WHERE owner_id = v_user_id) >= v_limit THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du har nådd maksimalt antall delinger for ditt abonnement');
  END IF;

  IF p_action = 'createShare' THEN
    IF p_identifier IS NULL OR btrim(p_identifier) = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Vennligst oppgi en gyldig e-post eller telefonnummer');
    END IF;

    IF position('@' IN p_identifier) > 0 THEN
      SELECT id INTO v_target_id FROM auth.users WHERE lower(email) = lower(btrim(p_identifier)) LIMIT 1;
    ELSE
      v_normalized := regexp_replace(p_identifier, '\D', '', 'g');
      IF length(v_normalized) = 8 THEN
        v_normalized := '47' || v_normalized;
      ELSIF left(v_normalized, 2) = '00' THEN
        v_normalized := substr(v_normalized, 3);
      END IF;
      SELECT id INTO v_target_id FROM auth.users WHERE phone = v_normalized LIMIT 1;
    END IF;
  ELSIF p_action = 'shareBack' THEN
    v_target_id := p_recipient_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Ugyldig handling');
  END IF;

  IF v_target_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Fant ingen bruker med denne e-posten eller telefonnummeret');
  END IF;
  IF v_target_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du kan ikke dele med deg selv');
  END IF;
  IF EXISTS (SELECT 1 FROM public.shift_shares WHERE owner_id = v_user_id AND viewer_id = v_target_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du deler allerede vaktene dine med denne brukeren');
  END IF;

  INSERT INTO public.shift_shares (owner_id, viewer_id, show_earnings, muted, owner_muted)
  VALUES (v_user_id, v_target_id, COALESCE(p_show_earnings, false), false, false);

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.report_sharing_screenshot(p_sharer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_name text;
  v_locale text;
  v_avatar_url text;
  v_title text;
  v_body text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_sharer_id = v_user_id THEN
    RETURN jsonb_build_object('success', true, 'skipped', true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.shift_shares WHERE owner_id = p_sharer_id AND viewer_id = v_user_id) THEN
    RAISE EXCEPTION 'No access to sharer';
  END IF;

  SELECT COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', 'Someone'), us.profile_picture_url
  INTO v_name, v_avatar_url
  FROM auth.users u
  LEFT JOIN public.user_settings us ON us.user_id = u.id
  WHERE u.id = v_user_id;

  SELECT COALESCE(u.raw_user_meta_data->>'locale', 'en')
  INTO v_locale
  FROM auth.users u
  WHERE u.id = p_sharer_id;

  v_title := v_name;
  IF lower(v_locale) IN ('no', 'nb', 'nn') OR lower(v_locale) LIKE 'no-%' OR lower(v_locale) LIKE 'nb-%' OR lower(v_locale) LIKE 'nn-%' THEN
    v_body := v_name || ' tok et skjermbilde av vaktene dine';
  ELSE
    v_body := v_name || ' took a screenshot of your shifts';
  END IF;

  INSERT INTO internal.notifications_outbox (owner_id, recipient_id, notification_type, due_at, title, body, data_payload, idempotency_key)
  VALUES (
    v_user_id,
    p_sharer_id,
    'shifts_screenshotted',
    now(),
    v_title,
    v_body,
    jsonb_build_object('type', 'shifts_screenshotted', 'screenshotter_id', v_user_id, 'screenshotter_name', v_name, 'sender_user_id', v_user_id, 'sender_name', v_name, 'sender_avatar_url', v_avatar_url),
    'screenshot:' || v_user_id::text || ':' || p_sharer_id::text || ':' || extract(epoch from now())::bigint::text
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.report_thread_screenshot(p_thread_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_name text;
  v_locale text;
  v_avatar_url text;
  v_recipient_id uuid;
  v_title text;
  v_body text;
  v_kind text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.thread_memberships WHERE thread_id = p_thread_id AND user_id = v_user_id AND status = 'active') THEN
    RAISE EXCEPTION 'No access to thread';
  END IF;

  SELECT kind INTO v_kind FROM public.threads WHERE id = p_thread_id;
  IF v_kind IS DISTINCT FROM 'direct' THEN
    RETURN jsonb_build_object('success', true, 'skipped', true);
  END IF;

  SELECT user_id INTO v_recipient_id
  FROM public.thread_memberships
  WHERE thread_id = p_thread_id AND status = 'active' AND user_id <> v_user_id
  LIMIT 1;

  IF v_recipient_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'skipped', true);
  END IF;

  SELECT COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', 'Someone'), us.profile_picture_url
  INTO v_name, v_avatar_url
  FROM auth.users u
  LEFT JOIN public.user_settings us ON us.user_id = u.id
  WHERE u.id = v_user_id;

  SELECT COALESCE(u.raw_user_meta_data->>'locale', 'en')
  INTO v_locale
  FROM auth.users u
  WHERE u.id = v_recipient_id;

  v_title := v_name;
  IF lower(v_locale) IN ('no', 'nb', 'nn') OR lower(v_locale) LIKE 'no-%' OR lower(v_locale) LIKE 'nb-%' OR lower(v_locale) LIKE 'nn-%' THEN
    v_body := v_name || ' tok et skjermbilde av chatten deres';
  ELSE
    v_body := v_name || ' took a screenshot of your conversation';
  END IF;

  INSERT INTO internal.notifications_outbox (owner_id, recipient_id, notification_type, due_at, title, body, data_payload, idempotency_key)
  VALUES (
    v_user_id,
    v_recipient_id,
    'thread_screenshot',
    now(),
    v_title,
    v_body,
    jsonb_build_object('type', 'thread_screenshot', 'thread_id', p_thread_id, 'screenshotter_id', v_user_id, 'screenshotter_name', v_name, 'sender_user_id', v_user_id, 'sender_name', v_name, 'sender_avatar_url', v_avatar_url),
    'thread_screenshot:' || v_user_id::text || ':' || p_thread_id::text || ':' || extract(epoch from now())::bigint::text
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_sharing_friends_api() TO authenticated;
GRANT EXECUTE ON FUNCTION public.manage_sharing_action(text, text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_sharing_screenshot(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_thread_screenshot(uuid) TO authenticated;

-- Source: supabase/sql/functions/admin/mobile_admin_api.sql
-- NOTE: Keep this migration in sync with the source file.
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
  INSERT INTO internal.admin_audit_log (admin_id, admin_email, action, target_user_id, target_email, metadata)
  VALUES (v_admin_id, COALESCE(v_admin_email, 'unknown'), p_action, p_target_id, p_target_email, COALESCE(p_metadata, '{}'::jsonb))
  RETURNING id INTO v_log_id;
  RETURN v_log_id;
END;
$function$;

-- The admin API functions are defined in the source file and intentionally mirrored here.
-- Due to their size, keep this migration and source synchronized if the contract changes.

CREATE OR REPLACE FUNCTION public.admin_list_users_api(p_page integer DEFAULT 1, p_per_page integer DEFAULT 20, p_search text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_page integer := GREATEST(COALESCE(p_page, 1), 1);
  v_per_page integer := LEAST(GREATEST(COALESCE(p_per_page, 20), 1), 100);
  v_offset integer := (v_page - 1) * v_per_page;
BEGIN
  PERFORM public.assert_is_admin();
  RETURN (
    WITH filtered AS (
      SELECT u.id, u.email, u.phone, COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS name, u.last_sign_in_at, u.created_at, u.banned_until,
        COALESCE(u.raw_app_meta_data->>'role', '') = 'admin' AS is_admin,
        u.id = '032d8c2a-9af6-4777-99f0-24e2c4058bf3'::uuid AS is_super_admin
      FROM auth.users u
      WHERE p_search IS NULL OR p_search = ''
        OR lower(COALESCE(u.email, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(u.phone, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '')) LIKE '%' || lower(p_search) || '%'
        OR u.id::text LIKE '%' || lower(p_search) || '%'
    ),
    enriched AS (
      SELECT f.*, COALESCE(p.before_paywall, false) AS is_grandfathered, s.provider, s.product_id, s.price_id, s.status
      FROM filtered f
      LEFT JOIN public.profiles p ON p.id = f.id
      LEFT JOIN LATERAL (
        SELECT provider, product_id, price_id, status, current_period_end
        FROM public.subscriptions s
        WHERE s.user_id = f.id
        ORDER BY COALESCE(current_period_end, '2099-12-31'::timestamptz) DESC
        LIMIT 1
      ) s ON true
    ),
    counted AS (SELECT COUNT(*)::integer AS total_count FROM enriched),
    paged AS (
      SELECT *
      FROM enriched
      ORDER BY lower(COALESCE(name, email, phone, '')), created_at DESC
      LIMIT v_per_page OFFSET v_offset
    )
    SELECT jsonb_build_object(
      'users', COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'email', email, 'phone', phone, 'name', name, 'lastSignInAt', last_sign_in_at, 'createdAt', created_at,
        'isBanned', banned_until IS NOT NULL, 'bannedUntil', banned_until, 'isAdmin', is_admin, 'isSuperAdmin', is_super_admin,
        'isGrandfathered', is_grandfathered,
        'plan', CASE
          WHEN provider = 'admin_trial' AND status = 'active' THEN 'trial'
          WHEN status IN ('active', 'trialing', 'grace') AND (
            COALESCE(product_id, '') ILIKE '%max%' OR COALESCE(price_id, '') ILIKE '%max%'
            OR COALESCE(product_id, '') IN ('no.tidex.max', 'no.tidex.max.year')
            OR COALESCE(price_id, '') IN ('no.tidex.max', 'no.tidex.max.year')
          ) THEN 'max'
          WHEN status IN ('active', 'trialing', 'grace') THEN 'pro'
          ELSE 'free'
        END
      )), '[]'::jsonb),
      'totalCount', (SELECT total_count FROM counted),
      'page', v_page,
      'perPage', v_per_page,
      'resultsArePartial', false
    ) FROM paged
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_toggle_grandfathered_api(p_target_user_id uuid, p_target_email text, p_grant boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_old_value boolean;
BEGIN
  PERFORM public.assert_is_admin();
  SELECT before_paywall INTO v_old_value FROM public.profiles WHERE id = p_target_user_id;
  IF v_old_value IS NULL AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_target_user_id) THEN
    RETURN jsonb_build_object('success', false, 'message', 'User not found');
  END IF;
  UPDATE public.profiles SET before_paywall = p_grant, updated_at = now() WHERE id = p_target_user_id;
  PERFORM public.admin_log_action_rpc(CASE WHEN p_grant THEN 'grant_grandfathered' ELSE 'revoke_grandfathered' END, p_target_user_id, p_target_email, jsonb_build_object('old_value', v_old_value, 'new_value', p_grant));
  RETURN jsonb_build_object('success', true, 'message', CASE WHEN p_grant THEN 'Lifetime access granted' ELSE 'Lifetime access revoked' END);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_manage_trial_api(p_target_user_id uuid, p_target_email text, p_action text, p_duration_days integer DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_now timestamptz := now();
  v_expires_at timestamptz := now() + make_interval(days => GREATEST(COALESCE(p_duration_days, 7), 1));
  v_existing public.subscriptions%ROWTYPE;
  v_product_id text := 'admin_trial_' || GREATEST(COALESCE(p_duration_days, 7), 1)::text || 'd';
BEGIN
  PERFORM public.assert_is_admin();
  IF p_action NOT IN ('create', 'revoke') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid action. Must be "create" or "revoke"');
  END IF;

  SELECT * INTO v_existing FROM public.subscriptions WHERE user_id = p_target_user_id ORDER BY COALESCE(current_period_end, '2099-12-31'::timestamptz) DESC LIMIT 1;
  IF p_action = 'create' THEN
    IF FOUND AND v_existing.provider <> 'admin_trial' AND v_existing.status IN ('active', 'trialing', 'grace') AND (v_existing.current_period_end IS NULL OR v_existing.current_period_end > v_now) THEN
      RETURN jsonb_build_object('success', false, 'message', 'User already has an active paid subscription');
    END IF;
    IF FOUND THEN
      UPDATE public.subscriptions
      SET provider = 'admin_trial', provider_subscription_id = 'admin_trial_' || p_target_user_id::text || '_' || extract(epoch from v_now)::bigint::text, status = 'active', product_id = v_product_id,
          current_period_start = v_now, current_period_end = v_expires_at, updated_at = v_now, cancel_at_period_end = true, cancellation_reason = 'Free trial only'
      WHERE id = v_existing.id;
    ELSE
      INSERT INTO public.subscriptions (user_id, provider, provider_subscription_id, status, product_id, current_period_start, current_period_end, created_at, updated_at, cancel_at_period_end, cancellation_reason, stripe_customer_id)
      VALUES (p_target_user_id, 'admin_trial', 'admin_trial_' || p_target_user_id::text || '_' || extract(epoch from v_now)::bigint::text, 'active', v_product_id, v_now, v_expires_at, v_now, v_now, true, 'Free trial only', 'cus_admintrial' || left(replace(p_target_user_id::text, '-', ''), 8));
    END IF;
    PERFORM public.admin_log_action_rpc('create_trial_subscription', p_target_user_id, p_target_email, jsonb_build_object('duration_days', GREATEST(COALESCE(p_duration_days, 7), 1)));
    RETURN jsonb_build_object('success', true, 'message', 'Trial subscription created');
  END IF;

  UPDATE public.subscriptions
  SET status = 'canceled', current_period_end = v_now, updated_at = v_now, cancel_at_period_end = true, cancellation_reason = 'Revoked by admin'
  WHERE user_id = p_target_user_id AND provider = 'admin_trial';
  PERFORM public.admin_log_action_rpc('revoke_trial_subscription', p_target_user_id, p_target_email, '{}'::jsonb);
  RETURN jsonb_build_object('success', true, 'message', 'Trial subscription revoked');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_subscribers_api(p_filter text DEFAULT 'all')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();
  RETURN (
    WITH base AS (
      SELECT u.id AS user_id, u.email, u.phone, COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS name,
        s.provider, s.product_id, s.price_id, s.status, s.current_period_end, COALESCE(p.before_paywall, false) AS is_grandfathered
      FROM auth.users u
      LEFT JOIN LATERAL (
        SELECT provider, product_id, price_id, status, current_period_end
        FROM public.subscriptions s
        WHERE s.user_id = u.id
        ORDER BY COALESCE(current_period_end, '2099-12-31'::timestamptz) DESC
        LIMIT 1
      ) s ON true
      LEFT JOIN public.profiles p ON p.id = u.id
      WHERE COALESCE(p.before_paywall, false) = true OR (s.status IN ('active', 'trialing', 'grace') AND (s.current_period_end IS NULL OR s.current_period_end > now()))
    ),
    decorated AS (
      SELECT *, CASE
        WHEN provider = 'admin_trial' AND status = 'active' THEN 'trial'
        WHEN status IN ('active', 'trialing', 'grace') AND (
          COALESCE(product_id, '') ILIKE '%max%' OR COALESCE(price_id, '') ILIKE '%max%'
          OR COALESCE(product_id, '') IN ('no.tidex.max', 'no.tidex.max.year')
          OR COALESCE(price_id, '') IN ('no.tidex.max', 'no.tidex.max.year')
        ) THEN 'max'
        WHEN status IN ('active', 'trialing', 'grace') THEN 'pro'
        ELSE 'free'
      END AS plan
      FROM base
    ),
    filtered AS (
      SELECT * FROM decorated
      WHERE COALESCE(p_filter, 'all') = 'all'
        OR (p_filter = 'grandfathered' AND is_grandfathered = true)
        OR (p_filter IN ('pro', 'max', 'trial') AND plan = p_filter)
    )
    SELECT jsonb_build_object(
      'success', true,
      'subscribers', COALESCE(jsonb_agg(jsonb_build_object(
        'userId', user_id, 'email', email, 'phone', phone, 'name', name, 'provider', provider, 'productId', product_id,
        'priceId', price_id, 'status', status, 'currentPeriodEnd', current_period_end, 'isGrandfathered', is_grandfathered, 'plan', plan
      ) ORDER BY lower(COALESCE(name, email, phone, ''))), '[]'::jsonb)
    ) FROM filtered
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_feedback_api(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();
  RETURN (
    WITH base AS (
      SELECT f.id, f.user_id, f.message, f.user_email, COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS user_name,
        us.profile_picture_url AS user_profile_picture, f.created_at, f.response, f.responded_at, f.responded_by
      FROM public.feedback f
      LEFT JOIN auth.users u ON u.id = f.user_id
      LEFT JOIN public.user_settings us ON us.user_id = f.user_id
      ORDER BY f.created_at DESC
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
      OFFSET GREATEST(COALESCE(p_offset, 0), 0)
    ),
    counted AS (SELECT COUNT(*)::integer AS total FROM public.feedback)
    SELECT jsonb_build_object(
      'feedback', COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'userId', user_id, 'message', message, 'userEmail', user_email, 'userName', user_name,
        'userProfilePicture', user_profile_picture, 'createdAt', created_at, 'response', response, 'respondedAt', responded_at, 'respondedBy', responded_by
      ) ORDER BY created_at DESC), '[]'::jsonb),
      'total', (SELECT total FROM counted)
    ) FROM base
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_respond_feedback_api(p_feedback_id uuid, p_response text)
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
  SET response = btrim(p_response), responded_at = now(), responded_by = v_admin_id
  WHERE id = p_feedback_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Feedback not found');
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_reports_api(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0, p_status text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();
  RETURN (
    WITH filtered AS (
      SELECT * FROM public.abuse_reports
      WHERE p_status IS NULL OR status = p_status
      ORDER BY created_at DESC
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
      OFFSET GREATEST(COALESCE(p_offset, 0), 0)
    ),
    counted AS (SELECT COUNT(*)::integer AS total FROM public.abuse_reports WHERE p_status IS NULL OR status = p_status),
    decorated AS (
      SELECT f.id, f.reporter_user_id, COALESCE(ru.raw_user_meta_data->>'full_name', ru.raw_user_meta_data->>'name') AS reporter_name, ru.email AS reporter_email,
        f.reported_user_id, COALESCE(tu.raw_user_meta_data->>'full_name', tu.raw_user_meta_data->>'name') AS reported_name, tu.email AS reported_email,
        f.thread_id, f.message_id, f.reason, f.note, f.status, f.reviewer_notes, f.reviewed_at, f.reviewed_by, f.created_at
      FROM filtered f
      LEFT JOIN auth.users ru ON ru.id = f.reporter_user_id
      LEFT JOIN auth.users tu ON tu.id = f.reported_user_id
    )
    SELECT jsonb_build_object(
      'reports', COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'reporterUserId', reporter_user_id, 'reporterName', reporter_name, 'reporterEmail', reporter_email,
        'reportedUserId', reported_user_id, 'reportedName', reported_name, 'reportedEmail', reported_email, 'threadId', thread_id,
        'messageId', message_id, 'reason', reason, 'note', note, 'status', status, 'reviewerNotes', reviewer_notes,
        'reviewedAt', reviewed_at, 'reviewedBy', reviewed_by, 'createdAt', created_at
      ) ORDER BY created_at DESC), '[]'::jsonb),
      'total', (SELECT total FROM counted)
    ) FROM decorated
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_report_status_api(p_report_id uuid, p_status text, p_reviewer_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();
  UPDATE public.abuse_reports
  SET status = p_status, reviewer_notes = NULLIF(btrim(COALESCE(p_reviewer_notes, '')), ''), reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = p_report_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found');
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_audit_log_api(p_limit integer DEFAULT 50, p_action_filter text DEFAULT NULL, p_target_filter uuid DEFAULT NULL)
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
      'entries', COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'adminId', admin_id, 'adminEmail', admin_email, 'action', action,
        'targetUserId', target_user_id, 'targetEmail', target_email, 'metadata', metadata, 'createdAt', created_at
      ) ORDER BY created_at DESC), '[]'::jsonb)
    )
    FROM rows
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_execute_sql_api(p_query text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_started_at timestamptz := clock_timestamp();
  v_data jsonb;
BEGIN
  PERFORM public.assert_is_admin();
  SELECT public.admin_execute_sql(btrim(p_query)) INTO v_data;
  PERFORM public.admin_log_action_rpc('sql_executed', NULL, NULL, jsonb_build_object('query', btrim(p_query), 'row_count', COALESCE(jsonb_array_length(v_data), 0), 'execution_time_ms', FLOOR(EXTRACT(EPOCH FROM (clock_timestamp() - v_started_at)) * 1000)));
  RETURN jsonb_build_object('success', true, 'data', COALESCE(v_data, '[]'::jsonb), 'rowCount', COALESCE(jsonb_array_length(v_data), 0), 'executionTimeMs', FLOOR(EXTRACT(EPOCH FROM (clock_timestamp() - v_started_at)) * 1000)::integer);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_shares_api(p_search text DEFAULT NULL, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
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
      SELECT ss.id, ss.owner_id, ou.email AS owner_email, COALESCE(ou.raw_user_meta_data->>'full_name', ou.raw_user_meta_data->>'name') AS owner_name, ou.phone AS owner_phone,
        ss.viewer_id, vu.email AS viewer_email, COALESCE(vu.raw_user_meta_data->>'full_name', vu.raw_user_meta_data->>'name') AS viewer_name, vu.phone AS viewer_phone,
        ss.created_at, ss.show_earnings, ss.hidden AS blocked, ss.muted
      FROM public.shift_shares ss
      LEFT JOIN auth.users ou ON ou.id = ss.owner_id
      LEFT JOIN auth.users vu ON vu.id = ss.viewer_id
      WHERE p_search IS NULL OR p_search = ''
        OR lower(COALESCE(ou.email, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(vu.email, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(ou.phone, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(vu.phone, '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(ou.raw_user_meta_data->>'full_name', ou.raw_user_meta_data->>'name', '')) LIKE '%' || lower(p_search) || '%'
        OR lower(COALESCE(vu.raw_user_meta_data->>'full_name', vu.raw_user_meta_data->>'name', '')) LIKE '%' || lower(p_search) || '%'
        OR ss.owner_id::text LIKE '%' || lower(p_search) || '%'
        OR ss.viewer_id::text LIKE '%' || lower(p_search) || '%'
    ),
    counted AS (SELECT COUNT(*)::integer AS total_count FROM rows),
    paged AS (SELECT * FROM rows ORDER BY created_at DESC LIMIT v_page_size OFFSET v_offset)
    SELECT jsonb_build_object(
      'success', true,
      'shares', COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'ownerId', owner_id, 'ownerEmail', owner_email, 'ownerName', owner_name, 'ownerPhone', owner_phone,
        'viewerId', viewer_id, 'viewerEmail', viewer_email, 'viewerName', viewer_name, 'viewerPhone', viewer_phone,
        'createdAt', created_at, 'showEarnings', show_earnings, 'blocked', blocked, 'muted', muted
      ) ORDER BY created_at DESC), '[]'::jsonb),
      'totalCount', (SELECT total_count FROM counted),
      'page', v_page,
      'pageSize', v_page_size
    ) FROM paged
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_create_share_api(p_owner_id uuid, p_viewer_id uuid, p_show_earnings boolean DEFAULT true)
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
  PERFORM public.admin_log_action_rpc('shift_share_created', v_share_id, NULL, jsonb_build_object('share_id', v_share_id, 'owner_id', p_owner_id, 'owner_email', v_owner_email, 'viewer_id', p_viewer_id, 'viewer_email', v_viewer_email, 'show_earnings', COALESCE(p_show_earnings, true)));
  RETURN jsonb_build_object('success', true, 'id', v_share_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_share_api(p_share_id uuid, p_show_earnings boolean DEFAULT NULL, p_blocked boolean DEFAULT NULL, p_muted boolean DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();
  UPDATE public.shift_shares
  SET show_earnings = COALESCE(p_show_earnings, show_earnings), hidden = COALESCE(p_blocked, hidden), muted = COALESCE(p_muted, muted)
  WHERE id = p_share_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Share not found');
  END IF;
  PERFORM public.admin_log_action_rpc('shift_share_updated', p_share_id, NULL, jsonb_build_object('show_earnings', p_show_earnings, 'blocked', p_blocked, 'muted', p_muted));
  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_share_api(p_share_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();
  DELETE FROM public.shift_shares WHERE id = p_share_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Share not found');
  END IF;
  PERFORM public.admin_log_action_rpc('shift_share_deleted', p_share_id, NULL, '{}'::jsonb);
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
      SELECT ab.id, ab.title, ab.body, ab.target, ab.target_count, ab.status, ab.created_at,
        COUNT(*) FILTER (WHERE nq.status = 'sent')::integer AS sent_count,
        COUNT(*) FILTER (WHERE nq.status = 'failed')::integer AS failed_count,
        COUNT(*) FILTER (WHERE nq.status = 'skipped')::integer AS skipped_count,
        COUNT(*) FILTER (WHERE nq.status IN ('pending', 'processing'))::integer AS pending_count
      FROM internal.admin_broadcasts ab
      LEFT JOIN internal.notification_queue nq ON nq.broadcast_id = ab.id
      GROUP BY ab.id
      ORDER BY ab.created_at DESC
      LIMIT 10
    )
    SELECT jsonb_build_object(
      'broadcasts', COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'body', body, 'target', target, 'targetCount', target_count,
        'status', status, 'createdAt', created_at, 'sentCount', sent_count, 'failedCount', failed_count, 'skippedCount', skipped_count, 'pendingCount', pending_count
      ) ORDER BY created_at DESC), '[]'::jsonb)
    ) FROM rows
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_preview_notification_target_api(p_target text, p_specific_user_ids uuid[] DEFAULT NULL, p_include_self boolean DEFAULT false)
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
    SELECT COUNT(DISTINCT pd.user_id)::integer INTO v_count FROM internal.push_devices pd WHERE p_include_self OR pd.user_id <> auth.uid();
  ELSIF p_target = 'pro' THEN
    SELECT COUNT(DISTINCT pd.user_id)::integer INTO v_count FROM internal.push_devices pd INNER JOIN public.subscriptions s ON s.user_id = pd.user_id WHERE s.status IN ('active', 'trialing');
  ELSIF p_target = 'active' THEN
    SELECT COUNT(DISTINCT pd.user_id)::integer INTO v_count FROM internal.push_devices pd INNER JOIN public.user_settings us ON us.user_id = pd.user_id WHERE us.last_active >= now() - interval '7 days';
  ELSE
    RAISE EXCEPTION 'Invalid target. Must be all, pro, active, or specific';
  END IF;
  RETURN jsonb_build_object('count', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_send_broadcast_api(p_title text, p_title_no text, p_body text, p_body_no text, p_target text, p_deeplink text DEFAULT NULL, p_deeplink_no text DEFAULT NULL, p_specific_user_ids uuid[] DEFAULT NULL, p_include_self boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_admin_id uuid := auth.uid();
  v_broadcast_id uuid;
  v_target_user_ids uuid[];
BEGIN
  PERFORM public.assert_is_admin();
  IF p_target = 'specific' THEN
    v_target_user_ids := COALESCE(p_specific_user_ids, ARRAY[]::uuid[]);
  ELSIF p_target = 'all' THEN
    SELECT array_agg(DISTINCT pd.user_id) INTO v_target_user_ids FROM internal.push_devices pd WHERE p_include_self OR pd.user_id <> v_admin_id;
  ELSIF p_target = 'pro' THEN
    SELECT array_agg(DISTINCT pd.user_id) INTO v_target_user_ids FROM internal.push_devices pd INNER JOIN public.subscriptions s ON s.user_id = pd.user_id WHERE s.status IN ('active', 'trialing');
  ELSIF p_target = 'active' THEN
    SELECT array_agg(DISTINCT pd.user_id) INTO v_target_user_ids FROM internal.push_devices pd INNER JOIN public.user_settings us ON us.user_id = pd.user_id WHERE us.last_active >= now() - interval '7 days';
  ELSE
    RAISE EXCEPTION 'Invalid target';
  END IF;
  IF COALESCE(array_length(v_target_user_ids, 1), 0) = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'No users match target criteria');
  END IF;

  INSERT INTO internal.admin_broadcasts (admin_id, title, body, deeplink, target, target_count)
  VALUES (v_admin_id, btrim(p_title), btrim(p_body), NULLIF(btrim(COALESCE(p_deeplink, '')), ''), p_target, array_length(v_target_user_ids, 1))
  RETURNING id INTO v_broadcast_id;

  INSERT INTO internal.notifications_outbox (owner_id, recipient_id, broadcast_id, notification_type, due_at, title, body, data_payload, idempotency_key)
  SELECT v_admin_id, u.id, v_broadcast_id, 'admin_broadcast', now(),
    CASE WHEN COALESCE(u.raw_user_meta_data->>'locale', 'en') IN ('no', 'nb', 'nn')
      OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'no-%'
      OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'nb-%'
      OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'nn-%'
    THEN btrim(p_title_no) ELSE btrim(p_title) END,
    CASE WHEN COALESCE(u.raw_user_meta_data->>'locale', 'en') IN ('no', 'nb', 'nn')
      OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'no-%'
      OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'nb-%'
      OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'nn-%'
    THEN btrim(p_body_no) ELSE btrim(p_body) END,
    jsonb_build_object(
      'type', 'admin_broadcast',
      'deeplink',
        CASE WHEN (COALESCE(u.raw_user_meta_data->>'locale', 'en') IN ('no', 'nb', 'nn')
          OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'no-%'
          OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'nb-%'
          OR COALESCE(u.raw_user_meta_data->>'locale', 'en') LIKE 'nn-%')
          AND NULLIF(btrim(COALESCE(p_deeplink_no, '')), '') IS NOT NULL
        THEN NULLIF(btrim(COALESCE(p_deeplink_no, '')), '') ELSE NULLIF(btrim(COALESCE(p_deeplink, '')), '') END,
      'broadcast_id', v_broadcast_id
    ),
    'broadcast:' || v_broadcast_id::text || ':' || u.id::text
  FROM auth.users u
  WHERE u.id = ANY(v_target_user_ids);

  UPDATE internal.admin_broadcasts SET status = 'queued' WHERE id = v_broadcast_id;
  PERFORM public.admin_log_action_rpc('broadcast_sent', NULL, NULL, jsonb_build_object('broadcast_id', v_broadcast_id, 'title', btrim(p_title), 'target', p_target, 'target_count', array_length(v_target_user_ids, 1), 'deeplink', NULLIF(btrim(COALESCE(p_deeplink, '')), '')));
  RETURN jsonb_build_object('success', true, 'message', 'Notification queued for ' || array_length(v_target_user_ids, 1)::text || ' users');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_log_action_rpc(text, uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_users_api(integer, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_toggle_grandfathered_api(uuid, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_trial_api(uuid, text, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_subscribers_api(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_feedback_api(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_respond_feedback_api(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_reports_api(integer, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_report_status_api(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_audit_log_api(integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_execute_sql_api(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_shares_api(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_share_api(uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_share_api(uuid, boolean, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_share_api(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_broadcast_history_api() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_preview_notification_target_api(text, uuid[], boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_broadcast_api(text, text, text, text, text, text, text, uuid[], boolean) TO authenticated;
