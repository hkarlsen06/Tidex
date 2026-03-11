CREATE OR REPLACE FUNCTION public.get_unread_direct_message_count(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_requester_id uuid := auth.uid();
  v_request_role text := current_setting('request.jwt.claim.role', true);
  v_target_user_id uuid;
  v_unread_count integer;
BEGIN
  IF v_request_role = 'service_role' THEN
    v_target_user_id := p_user_id;
  ELSE
    IF v_requester_id IS NULL THEN
      RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_user_id IS NOT NULL AND p_user_id <> v_requester_id THEN
      RAISE EXCEPTION 'Cannot read another user''s unread direct message count';
    END IF;

    v_target_user_id := COALESCE(p_user_id, v_requester_id);
  END IF;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Target user is required';
  END IF;

  WITH unread_per_thread AS (
    SELECT
      t.id,
      COUNT(*)::integer AS unread_count
    FROM public.threads t
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    INNER JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = v_target_user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = v_target_user_id
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    INNER JOIN public.messages m
      ON m.thread_id = t.id
     AND m.sender_user_id <> v_target_user_id
    WHERE t.kind = 'direct'
      AND (
        dt.thread_id IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM public.shift_shares ss
          WHERE (
            (ss.owner_id = v_target_user_id AND ss.viewer_id = CASE
              WHEN dt.user_low_id = v_target_user_id THEN dt.user_high_id
              WHEN dt.user_high_id = v_target_user_id THEN dt.user_low_id
              ELSE NULL
            END)
            OR
            (ss.owner_id = CASE
              WHEN dt.user_low_id = v_target_user_id THEN dt.user_high_id
              WHEN dt.user_high_id = v_target_user_id THEN dt.user_low_id
              ELSE NULL
            END AND ss.viewer_id = v_target_user_id)
          )
            AND ss.blocked_by_user_id IS NOT NULL
        )
      )
      AND m.deleted_at IS NULL
      AND (
        tus.last_read_message_id IS NULL
        OR rm.id IS NULL
        OR (m.created_at, m.id) > (rm.created_at, rm.id)
      )
    GROUP BY t.id
  )
  SELECT COALESCE(SUM(unread_count), 0)::integer
  INTO v_unread_count
  FROM unread_per_thread;

  RETURN COALESCE(v_unread_count, 0);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_unread_direct_message_count(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_direct_message_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_direct_message_count(uuid) TO service_role;

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
  v_existing_notification record;
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

    SELECT COUNT(*)::integer
    INTO v_unread_message_count
    FROM public.messages m
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = NEW.thread_id
     AND tus.user_id = v_recipient.user_id
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    WHERE m.thread_id = NEW.thread_id
      AND m.sender_user_id <> v_recipient.user_id
      AND (
        tus.last_read_message_id IS NULL
        OR rm.id IS NULL
        OR (m.created_at, m.id) > (rm.created_at, rm.id)
      );

    SELECT
      no.id
    INTO v_existing_notification
    FROM internal.notifications_outbox no
    WHERE no.status = 'pending'
      AND no.notification_type = 'thread_message'
      AND no.recipient_id = v_recipient.user_id
      AND no.data_payload->>'thread_id' = NEW.thread_id::text
    ORDER BY no.created_at DESC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF FOUND THEN
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
        data_payload = jsonb_build_object(
          'type', 'thread_message',
          'thread_id', NEW.thread_id,
          'message_id', NEW.id,
          'thread_kind', COALESCE(v_thread_kind, 'direct'),
          'sender_user_id', NEW.sender_user_id,
          'sender_name', v_sender_name,
          'sender_avatar_url', v_sender_avatar_url,
          'message_count', v_unread_message_count
        )
      WHERE id = v_existing_notification.id;
    ELSE
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
          'message_count', v_unread_message_count
        ),
        'thread_message:' || NEW.id || ':' || v_recipient.user_id
      )
      ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.trigger_push_notifications_after_outbox_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'net', 'pg_temp'
AS $function$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
BEGIN
  SELECT decrypted_secret INTO supabase_url
  FROM vault.decrypted_secrets WHERE name = 'supabase_url';

  SELECT decrypted_secret INTO service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF supabase_url IS NOT NULL AND service_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_key
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trigger_send_push_after_insert ON internal.notifications_outbox;

CREATE TRIGGER trigger_send_push_after_insert
  AFTER INSERT OR UPDATE OF due_at, title, body, data_payload ON internal.notifications_outbox
  FOR EACH STATEMENT
  EXECUTE FUNCTION internal.trigger_push_notifications_after_outbox_insert();
