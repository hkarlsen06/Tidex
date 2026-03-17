-- Fix thread message notification enqueueing to avoid partial-index ON CONFLICT inference failures.

CREATE OR REPLACE FUNCTION public.queue_thread_message_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_sender_name text;
  v_sender_avatar_url text;
  v_thread_kind text;
  v_recipient record;
  v_body_preview text;
  v_rich_content_kind text;
  v_single_message_body text;
  v_unread_message_count integer;
BEGIN
  SELECT
    COALESCE(au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', au.email, 'Someone'),
    COALESCE(us.profile_picture_url, au.raw_user_meta_data->>'avatar_url')
  INTO v_sender_name, v_sender_avatar_url
  FROM auth.users au
  LEFT JOIN public.user_settings us
    ON us.user_id = au.id
  WHERE au.id = NEW.sender_user_id;

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
  v_rich_content_kind := NULLIF(btrim(COALESCE(NEW.metadata->'content'->>'kind', '')), '');

  FOR v_recipient IN
    SELECT
      tm.user_id,
      COALESCE(tus.muted, false) AS muted,
      COALESCE(tus.unread_count, 0) AS unread_count,
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

    v_unread_message_count := GREATEST(v_recipient.unread_count, 1);
    v_single_message_body := COALESCE(
      v_body_preview,
      CASE
        WHEN v_rich_content_kind = 'shift_snapshot' THEN
          CASE
            WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' delte en vakt'
            ELSE v_sender_name || ' shared a shift'
          END
        WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN v_sender_name || ' sendte et bilde'
        ELSE v_sender_name || ' sent a photo'
      END
    );

    UPDATE internal.notifications_outbox
    SET
      owner_id = NEW.sender_user_id,
      due_at = now(),
      title = v_sender_name,
      body = CASE
        WHEN v_unread_message_count >= 4 THEN
          CASE
            WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN
              v_unread_message_count::text || ' nye meldinger'
            ELSE
              v_unread_message_count::text || ' new messages'
          END
        ELSE
          v_single_message_body
      END,
      thread_id = NEW.thread_id,
      data_payload = jsonb_build_object(
        'type', 'thread_message',
        'thread_id', NEW.thread_id,
        'message_id', NEW.id,
        'thread_kind', COALESCE(v_thread_kind, 'direct'),
        'sender_user_id', NEW.sender_user_id,
        'sender_name', v_sender_name,
        'sender_avatar_url', v_sender_avatar_url,
        'message_count', v_unread_message_count,
        'message_created_at', NEW.created_at
      )
    WHERE recipient_id = v_recipient.user_id
      AND notification_type = 'thread_message'
      AND thread_id = NEW.thread_id
      AND status = 'pending';

    IF NOT FOUND THEN
      BEGIN
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
          NEW.sender_user_id,
          v_recipient.user_id,
          'thread_message',
          NEW.thread_id,
          now(),
          v_sender_name,
          CASE
            WHEN v_unread_message_count >= 4 THEN
              CASE
                WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN
                  v_unread_message_count::text || ' nye meldinger'
                ELSE
                  v_unread_message_count::text || ' new messages'
              END
            ELSE
              v_single_message_body
          END,
          jsonb_build_object(
            'type', 'thread_message',
            'thread_id', NEW.thread_id,
            'message_id', NEW.id,
            'thread_kind', COALESCE(v_thread_kind, 'direct'),
            'sender_user_id', NEW.sender_user_id,
            'sender_name', v_sender_name,
            'sender_avatar_url', v_sender_avatar_url,
            'message_count', v_unread_message_count,
            'message_created_at', NEW.created_at
          ),
          'thread_message:' || NEW.id || ':' || v_recipient.user_id
        );
      EXCEPTION
        WHEN unique_violation THEN
          UPDATE internal.notifications_outbox
          SET
            owner_id = NEW.sender_user_id,
            due_at = now(),
            title = v_sender_name,
            body = CASE
              WHEN v_unread_message_count >= 4 THEN
                CASE
                  WHEN v_recipient.locale IN ('no', 'nb', 'nn') THEN
                    v_unread_message_count::text || ' nye meldinger'
                  ELSE
                    v_unread_message_count::text || ' new messages'
                END
              ELSE
                v_single_message_body
            END,
            thread_id = NEW.thread_id,
            data_payload = jsonb_build_object(
              'type', 'thread_message',
              'thread_id', NEW.thread_id,
              'message_id', NEW.id,
              'thread_kind', COALESCE(v_thread_kind, 'direct'),
              'sender_user_id', NEW.sender_user_id,
              'sender_name', v_sender_name,
              'sender_avatar_url', v_sender_avatar_url,
              'message_count', v_unread_message_count,
              'message_created_at', NEW.created_at
            )
          WHERE recipient_id = v_recipient.user_id
            AND notification_type = 'thread_message'
            AND thread_id = NEW.thread_id
            AND status = 'pending';
      END;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;
