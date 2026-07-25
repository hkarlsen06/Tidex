-- Native app sharing API replacements for the retired Next.js routes.

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
  v_limit integer := 5;
  v_target_id uuid;
  v_normalized text;
  v_identifier text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT CASE COALESCE(tier, 'free')
    WHEN 'max' THEN 200
    WHEN 'pro' THEN 200
    ELSE 5
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
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Vennligst oppgi en gyldig e-post, telefonnummer eller brukernavn'
      );
    END IF;

    v_identifier := btrim(p_identifier);

    IF position('@' IN v_identifier) > 0 AND left(v_identifier, 1) <> '@' THEN
      SELECT id INTO v_target_id
      FROM auth.users
      WHERE lower(email) = lower(v_identifier)
      LIMIT 1;
    ELSE
      v_identifier := lower(v_identifier);
      IF left(v_identifier, 1) = '@' THEN
        v_identifier := substr(v_identifier, 2);
      END IF;

      SELECT id INTO v_target_id
      FROM public.profiles
      WHERE username = v_identifier
      LIMIT 1;

      IF v_target_id IS NULL THEN
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
    END IF;
  ELSIF p_action = 'shareBack' THEN
    v_target_id := p_recipient_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Ugyldig handling');
  END IF;

  IF v_target_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Fant ingen bruker med denne e-posten, telefonnummeret eller brukernavnet'
    );
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
    COALESCE(us.profile_picture_url, u.raw_user_meta_data->>'avatar_url')
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
    COALESCE(us.profile_picture_url, u.raw_user_meta_data->>'avatar_url')
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

GRANT EXECUTE ON FUNCTION public.manage_sharing_action(text, text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_sharing_screenshot(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_thread_screenshot(uuid) TO authenticated;
