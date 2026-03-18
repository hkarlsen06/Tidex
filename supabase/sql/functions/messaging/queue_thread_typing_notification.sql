-- Function: queue_thread_typing_notification
-- Description: Enqueues a suppressed visible typing notification for direct threads

CREATE OR REPLACE FUNCTION public.queue_thread_typing_notification(p_thread_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_kind text;
  v_sender_name text;
  v_sender_avatar_url text;
  v_recipient record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_thread_id IS NULL THEN
    RAISE EXCEPTION 'thread_id is required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT t.kind
  INTO v_thread_kind
  FROM public.threads t
  WHERE t.id = p_thread_id;

  IF v_thread_kind IS DISTINCT FROM 'direct' THEN
    RETURN false;
  END IF;

  SELECT
    COALESCE(au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', au.email, 'Someone'),
    COALESCE(us.profile_picture_url, au.raw_user_meta_data->>'avatar_url')
  INTO v_sender_name, v_sender_avatar_url
  FROM auth.users au
  LEFT JOIN public.user_settings us
    ON us.user_id = au.id
  WHERE au.id = v_uid;

  IF v_sender_name IS NULL THEN
    v_sender_name := 'Someone';
  END IF;

  SELECT
    tm.user_id,
    COALESCE(tus.muted, false) AS muted,
    tus.last_read_at,
    COALESCE(tus.unread_count, 0) AS unread_count,
    COALESCE(au.raw_user_meta_data->>'locale', 'en') AS locale
  INTO v_recipient
  FROM public.thread_memberships tm
  LEFT JOIN public.thread_user_state tus
    ON tus.thread_id = tm.thread_id
   AND tus.user_id = tm.user_id
  LEFT JOIN auth.users au
    ON au.id = tm.user_id
  WHERE tm.thread_id = p_thread_id
    AND tm.status = 'active'
    AND tm.user_id <> v_uid
  LIMIT 1;

  IF v_recipient.user_id IS NULL THEN
    RETURN false;
  END IF;

  IF v_recipient.muted THEN
    RETURN false;
  END IF;

  IF v_recipient.last_read_at IS NOT NULL
     AND v_recipient.last_read_at >= now() - INTERVAL '30 seconds' THEN
    RETURN false;
  END IF;

  IF v_recipient.unread_count > 0 THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM internal.notifications_outbox no
    WHERE no.recipient_id = v_recipient.user_id
      AND no.notification_type = 'thread_typing'
      AND no.thread_id = p_thread_id
      AND (
        no.status IN ('pending', 'sending')
        OR (
          no.status IN ('sent', 'skipped')
          AND no.created_at >= now() - INTERVAL '2 minutes'
        )
      )
  ) THEN
    RETURN false;
  END IF;

  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    thread_id,
    due_at,
    title,
    body,
    data_payload,
    idempotency_key
  )
  VALUES (
    v_uid,
    v_recipient.user_id,
    'thread_typing',
    p_thread_id,
    now(),
    v_sender_name,
    CASE
      WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN 'skriver...'
      ELSE 'is typing...'
    END,
    jsonb_build_object(
      'type', 'thread_typing',
      'thread_id', p_thread_id,
      'thread_kind', 'direct',
      'sender_user_id', v_uid,
      'sender_name', v_sender_name,
      'sender_avatar_url', v_sender_avatar_url
    ),
    'thread_typing:' || p_thread_id || ':' || v_recipient.user_id || ':' || gen_random_uuid()::text
  );

  RETURN true;
EXCEPTION
  WHEN unique_violation THEN
    RETURN false;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.queue_thread_typing_notification(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.queue_thread_typing_notification(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.queue_thread_typing_notification(uuid) TO authenticated;
