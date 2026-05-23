-- Function: queue_message_reaction_notification
-- Description: Corrects Norwegian reaction push notification copy.

CREATE OR REPLACE FUNCTION public.queue_message_reaction_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_thread_kind text;
  v_message_sender_user_id uuid;
  v_message_created_at timestamptz;
  v_sender_name text;
  v_sender_avatar_url text;
  v_recipient_id uuid;
  v_recipient_muted boolean := false;
  v_recipient_locale text := 'en';
  v_normalized_locale text := 'en';
BEGIN
  SELECT
    t.kind,
    m.sender_user_id,
    m.created_at
  INTO
    v_thread_kind,
    v_message_sender_user_id,
    v_message_created_at
  FROM public.messages m
  INNER JOIN public.threads t
    ON t.id = m.thread_id
  WHERE m.id = NEW.message_id
    AND m.thread_id = NEW.thread_id
    AND m.deleted_at IS NULL
  LIMIT 1;

  IF v_thread_kind IS DISTINCT FROM 'direct' THEN
    RETURN NEW;
  END IF;

  IF v_message_sender_user_id IS NULL OR v_message_sender_user_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT
    tm.user_id,
    COALESCE(tus.muted, false) AS muted,
    COALESCE(au.raw_user_meta_data->>'locale', 'en') AS locale
  INTO
    v_recipient_id,
    v_recipient_muted,
    v_recipient_locale
  FROM public.thread_memberships tm
  LEFT JOIN public.thread_user_state tus
    ON tus.thread_id = tm.thread_id
   AND tus.user_id = tm.user_id
  LEFT JOIN auth.users au
    ON au.id = tm.user_id
  WHERE tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND tm.user_id = v_message_sender_user_id
  LIMIT 1;

  IF v_recipient_id IS NULL OR v_recipient_muted THEN
    RETURN NEW;
  END IF;

  SELECT
    COALESCE(au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', au.email, 'Someone'),
    COALESCE(us.profile_picture_url, au.raw_user_meta_data->>'avatar_url')
  INTO v_sender_name, v_sender_avatar_url
  FROM auth.users au
  LEFT JOIN public.user_settings us
    ON us.user_id = au.id
  WHERE au.id = NEW.user_id;

  IF v_sender_name IS NULL THEN
    v_sender_name := 'Someone';
  END IF;

  v_normalized_locale := lower(COALESCE(v_recipient_locale, 'en'));

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
    NEW.user_id,
    v_recipient_id,
    'thread_reaction',
    NEW.thread_id,
    now(),
    v_sender_name,
    CASE
      WHEN v_normalized_locale IN ('no', 'nb', 'nn')
        OR v_normalized_locale LIKE 'no-%'
        OR v_normalized_locale LIKE 'nb-%'
        OR v_normalized_locale LIKE 'nn-%'
      THEN v_sender_name || ' reagerte ' || NEW.emoji || ' på meldingen din'
      ELSE v_sender_name || ' reacted ' || NEW.emoji || ' to your message'
    END,
    jsonb_build_object(
      'type', 'thread_reaction',
      'thread_id', NEW.thread_id,
      'thread_kind', 'direct',
      'message_id', NEW.message_id,
      'sender_user_id', NEW.user_id,
      'sender_name', v_sender_name,
      'sender_avatar_url', v_sender_avatar_url,
      'reaction_emoji', NEW.emoji,
      'message_created_at', COALESCE(v_message_created_at, NEW.created_at)
    ),
    'thread_reaction:' || NEW.message_id::text || ':' || NEW.user_id::text || ':'
      || to_char(NEW.created_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS') || ':'
      || encode(convert_to(NEW.emoji, 'UTF8'), 'hex')
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;
