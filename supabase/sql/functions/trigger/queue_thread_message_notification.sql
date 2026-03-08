-- Function: queue_thread_message_notification
-- Description: Enqueues push notifications for newly inserted thread messages

CREATE OR REPLACE FUNCTION public.queue_thread_message_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_sender_name text;
  v_thread_kind text;
  v_recipient record;
  v_body_preview text;
BEGIN
  SELECT COALESCE(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', email, 'Someone')
  INTO v_sender_name
  FROM auth.users
  WHERE id = NEW.sender_user_id;

  IF v_sender_name IS NULL THEN
    v_sender_name := 'Someone';
  END IF;

  SELECT t.kind
  INTO v_thread_kind
  FROM public.threads t
  WHERE t.id = NEW.thread_id;

  v_body_preview := NULLIF(
    left(regexp_replace(COALESCE(NEW.body, ''), '\s+', ' ', 'g'), 120),
    ''
  );

  FOR v_recipient IN
    SELECT
      tm.user_id,
      COALESCE(tus.muted, false) AS muted,
      COALESCE(au.raw_user_meta_data->>'locale', 'en') AS locale
    FROM public.thread_memberships tm
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = tm.thread_id
     AND tus.user_id = tm.user_id
    LEFT JOIN auth.users au
      ON au.id = tm.user_id
    WHERE tm.thread_id = NEW.thread_id
      AND tm.status = 'active'
      AND tm.user_id <> NEW.sender_user_id
  LOOP
    IF v_recipient.muted THEN
      CONTINUE;
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
    )
    VALUES (
      NEW.sender_user_id,
      v_recipient.user_id,
      'thread_message',
      now(),
      v_sender_name,
      COALESCE(
        v_body_preview,
        CASE
          WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' sendte et bilde'
          ELSE v_sender_name || ' sent a photo'
        END
      ),
      jsonb_build_object(
        'type', 'thread_message',
        'thread_id', NEW.thread_id,
        'message_id', NEW.id,
        'thread_kind', COALESCE(v_thread_kind, 'direct'),
        'sender_user_id', NEW.sender_user_id
      ),
      'thread_message:' || NEW.id || ':' || v_recipient.user_id
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$function$;
