-- Native app sharing API replacements for the retired Next.js routes.

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
      'friends', COALESCE(
        (SELECT jsonb_agg(friend_json ORDER BY sort_name) FROM visible_friends),
        '[]'::jsonb
      ),
      'blockedFriends', COALESCE(
        (SELECT jsonb_agg(friend_json ORDER BY sort_name) FROM blocked_friends),
        '[]'::jsonb
      ),
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
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Du har nådd maksimalt antall delinger for ditt abonnement'
    );
  END IF;

  IF p_action = 'createShare' THEN
    IF p_identifier IS NULL OR btrim(p_identifier) = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Vennligst oppgi en gyldig e-post eller telefonnummer');
    END IF;

    IF position('@' IN p_identifier) > 0 THEN
      SELECT id INTO v_target_id
      FROM auth.users
      WHERE lower(email) = lower(btrim(p_identifier))
      LIMIT 1;
    ELSE
      v_normalized := regexp_replace(p_identifier, '\D', '', 'g');
      IF length(v_normalized) = 8 THEN
        v_normalized := '47' || v_normalized;
      ELSIF left(v_normalized, 2) = '00' THEN
        v_normalized := substr(v_normalized, 3);
      END IF;

      SELECT id INTO v_target_id
      FROM auth.users
      WHERE phone = v_normalized
      LIMIT 1;
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

  IF EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE owner_id = v_user_id
      AND viewer_id = v_target_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du deler allerede vaktene dine med denne brukeren');
  END IF;

  INSERT INTO public.shift_shares (
    owner_id,
    viewer_id,
    show_earnings,
    muted,
    owner_muted
  ) VALUES (
    v_user_id,
    v_target_id,
    COALESCE(p_show_earnings, false),
    false,
    false
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.report_sharing_screenshot(
  p_sharer_id uuid
)
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

  IF NOT EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE owner_id = p_sharer_id
      AND viewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'No access to sharer';
  END IF;

  SELECT
    COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', 'Someone'),
    us.profile_picture_url
  INTO v_name, v_avatar_url
  FROM auth.users u
  LEFT JOIN public.user_settings us ON us.user_id = u.id
  WHERE u.id = v_user_id;

  SELECT COALESCE(u.raw_user_meta_data->>'locale', 'en')
  INTO v_locale
  FROM auth.users u
  WHERE u.id = p_sharer_id;

  v_title := v_name;
  IF lower(v_locale) IN ('no', 'nb', 'nn')
    OR lower(v_locale) LIKE 'no-%'
    OR lower(v_locale) LIKE 'nb-%'
    OR lower(v_locale) LIKE 'nn-%' THEN
    v_body := v_name || ' tok et skjermbilde av vaktene dine';
  ELSE
    v_body := v_name || ' took a screenshot of your shifts';
  END IF;

  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    due_at,
    title,
    body,
    data_payload,
    idempotency_key
  ) VALUES (
    v_user_id,
    p_sharer_id,
    'shifts_screenshotted',
    now(),
    v_title,
    v_body,
    jsonb_build_object(
      'type', 'shifts_screenshotted',
      'screenshotter_id', v_user_id,
      'screenshotter_name', v_name,
      'sender_user_id', v_user_id,
      'sender_name', v_name,
      'sender_avatar_url', v_avatar_url
    ),
    'screenshot:' || v_user_id::text || ':' || p_sharer_id::text || ':' || extract(epoch from now())::bigint::text
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.report_thread_screenshot(
  p_thread_id uuid
)
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

  IF NOT EXISTS (
    SELECT 1
    FROM public.thread_memberships
    WHERE thread_id = p_thread_id
      AND user_id = v_user_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'No access to thread';
  END IF;

  SELECT kind
  INTO v_kind
  FROM public.threads
  WHERE id = p_thread_id;

  IF v_kind IS DISTINCT FROM 'direct' THEN
    RETURN jsonb_build_object('success', true, 'skipped', true);
  END IF;

  SELECT user_id
  INTO v_recipient_id
  FROM public.thread_memberships
  WHERE thread_id = p_thread_id
    AND status = 'active'
    AND user_id <> v_user_id
  LIMIT 1;

  IF v_recipient_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'skipped', true);
  END IF;

  SELECT
    COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', 'Someone'),
    us.profile_picture_url
  INTO v_name, v_avatar_url
  FROM auth.users u
  LEFT JOIN public.user_settings us ON us.user_id = u.id
  WHERE u.id = v_user_id;

  SELECT COALESCE(u.raw_user_meta_data->>'locale', 'en')
  INTO v_locale
  FROM auth.users u
  WHERE u.id = v_recipient_id;

  v_title := v_name;
  IF lower(v_locale) IN ('no', 'nb', 'nn')
    OR lower(v_locale) LIKE 'no-%'
    OR lower(v_locale) LIKE 'nb-%'
    OR lower(v_locale) LIKE 'nn-%' THEN
    v_body := v_name || ' tok et skjermbilde av chatten deres';
  ELSE
    v_body := v_name || ' took a screenshot of your conversation';
  END IF;

  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    due_at,
    title,
    body,
    data_payload,
    idempotency_key
  ) VALUES (
    v_user_id,
    v_recipient_id,
    'thread_screenshot',
    now(),
    v_title,
    v_body,
    jsonb_build_object(
      'type', 'thread_screenshot',
      'thread_id', p_thread_id,
      'screenshotter_id', v_user_id,
      'screenshotter_name', v_name,
      'sender_user_id', v_user_id,
      'sender_name', v_name,
      'sender_avatar_url', v_avatar_url
    ),
    'thread_screenshot:' || v_user_id::text || ':' || p_thread_id::text || ':' || extract(epoch from now())::bigint::text
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_sharing_friends_api() TO authenticated;
GRANT EXECUTE ON FUNCTION public.manage_sharing_action(text, text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_sharing_screenshot(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_thread_screenshot(uuid) TO authenticated;
