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
