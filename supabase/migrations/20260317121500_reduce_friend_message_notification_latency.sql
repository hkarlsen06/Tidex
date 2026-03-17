-- Reduce end-to-end friend message notification latency without changing visible behavior.

ALTER TABLE public.thread_user_state
  ADD COLUMN IF NOT EXISTS unread_count integer NOT NULL DEFAULT 0;

INSERT INTO public.thread_user_state (
  thread_id,
  user_id,
  unread_count,
  updated_at
)
SELECT
  tm.thread_id,
  tm.user_id,
  0,
  now()
FROM public.thread_memberships tm
WHERE tm.status = 'active'
ON CONFLICT (thread_id, user_id) DO NOTHING;

UPDATE public.thread_user_state tus
SET unread_count = COALESCE((
  SELECT COUNT(*)::integer
  FROM public.messages m
  LEFT JOIN public.messages rm
    ON rm.id = tus.last_read_message_id
  WHERE m.thread_id = tus.thread_id
    AND m.sender_user_id <> tus.user_id
    AND m.deleted_at IS NULL
    AND (
      tus.last_read_message_id IS NULL
      OR rm.id IS NULL
      OR (m.created_at, m.id) > (rm.created_at, rm.id)
    )
), 0)
WHERE EXISTS (
  SELECT 1
  FROM public.thread_memberships tm
  WHERE tm.thread_id = tus.thread_id
    AND tm.user_id = tus.user_id
    AND tm.status = 'active'
);

ALTER TABLE internal.notifications_outbox
  ADD COLUMN IF NOT EXISTS thread_id uuid NULL;

UPDATE internal.notifications_outbox
SET thread_id = NULLIF(data_payload->>'thread_id', '')::uuid
WHERE thread_id IS NULL
  AND notification_type = 'thread_message'
  AND NULLIF(data_payload->>'thread_id', '') IS NOT NULL;

WITH ranked_pending AS (
  SELECT
    no.id,
    ROW_NUMBER() OVER (
      PARTITION BY no.recipient_id, no.notification_type, no.thread_id
      ORDER BY no.created_at DESC, no.id DESC
    ) AS row_number
  FROM internal.notifications_outbox no
  WHERE no.status = 'pending'
    AND no.notification_type = 'thread_message'
    AND no.thread_id IS NOT NULL
)
UPDATE internal.notifications_outbox no
SET
  status = 'skipped',
  error_message = 'Superseded by newer pending thread message notification',
  processed_at = now()
FROM ranked_pending pending
WHERE no.id = pending.id
  AND pending.row_number > 1;

CREATE INDEX IF NOT EXISTS notifications_outbox_pending_due_at_id_idx
  ON internal.notifications_outbox (due_at, id)
  WHERE status = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS notifications_outbox_pending_thread_message_idx
  ON internal.notifications_outbox (recipient_id, notification_type, thread_id)
  WHERE status = 'pending'
    AND notification_type = 'thread_message'
    AND thread_id IS NOT NULL;

ALTER TABLE internal.push_devices
  ADD COLUMN IF NOT EXISTS apns_environment text NULL;

ALTER TABLE internal.push_devices
  DROP CONSTRAINT IF EXISTS push_devices_apns_environment_check;

ALTER TABLE internal.push_devices
  ADD CONSTRAINT push_devices_apns_environment_check
  CHECK (apns_environment IS NULL OR apns_environment IN ('production', 'sandbox'));

CREATE OR REPLACE FUNCTION public.update_thread_unread_counts_on_message_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id,
    unread_count,
    updated_at
  )
  SELECT
    NEW.thread_id,
    tm.user_id,
    1,
    now()
  FROM public.thread_memberships tm
  WHERE tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND tm.user_id <> NEW.sender_user_id
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET
    unread_count = COALESCE(thread_user_state.unread_count, 0) + 1,
    updated_at = now();

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_thread_unread_counts_on_message_soft_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.thread_user_state tus
  SET
    unread_count = GREATEST(COALESCE(tus.unread_count, 0) - 1, 0),
    updated_at = now()
  FROM public.thread_memberships tm
  WHERE tus.thread_id = NEW.thread_id
    AND tus.user_id = tm.user_id
    AND tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND tm.user_id <> NEW.sender_user_id
    AND (
      tus.last_read_message_id IS NULL
      OR NOT EXISTS (
        SELECT 1
        FROM public.messages rm
        WHERE rm.id = tus.last_read_message_id
          AND (OLD.created_at, OLD.id) <= (rm.created_at, rm.id)
      )
    );

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_thread_read(
  p_thread_id uuid,
  p_through_message_id uuid
)
RETURNS public.thread_user_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_target_message public.messages%ROWTYPE;
  v_existing_state public.thread_user_state%ROWTYPE;
  v_existing_message public.messages%ROWTYPE;
  v_result public.thread_user_state%ROWTYPE;
  v_newly_read_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT *
  INTO v_target_message
  FROM public.messages m
  WHERE m.id = p_through_message_id
    AND m.thread_id = p_thread_id
  LIMIT 1;

  IF v_target_message.id IS NULL THEN
    RAISE EXCEPTION 'Read marker message does not belong to the thread';
  END IF;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id,
    unread_count,
    updated_at
  )
  VALUES (
    p_thread_id,
    v_uid,
    0,
    now()
  )
  ON CONFLICT (thread_id, user_id) DO NOTHING;

  SELECT *
  INTO v_existing_state
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1
  FOR UPDATE;

  IF v_existing_state.last_read_message_id IS NOT NULL THEN
    SELECT *
    INTO v_existing_message
    FROM public.messages m
    WHERE m.id = v_existing_state.last_read_message_id
    LIMIT 1;
  END IF;

  IF v_existing_message.id IS NULL
     OR (v_target_message.created_at, v_target_message.id) > (v_existing_message.created_at, v_existing_message.id) THEN
    SELECT COUNT(*)::integer
    INTO v_newly_read_count
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.sender_user_id <> v_uid
      AND m.deleted_at IS NULL
      AND (m.created_at, m.id) <= (v_target_message.created_at, v_target_message.id)
      AND (
        v_existing_message.id IS NULL
        OR (m.created_at, m.id) > (v_existing_message.created_at, v_existing_message.id)
      );

    UPDATE public.thread_user_state
    SET
      last_read_message_id = v_target_message.id,
      last_read_at = v_target_message.created_at,
      unread_count = GREATEST(COALESCE(unread_count, 0) - v_newly_read_count, 0),
      updated_at = now()
    WHERE thread_id = p_thread_id
      AND user_id = v_uid;
  END IF;

  SELECT *
  INTO v_result
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_thread_summary(p_thread_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_preview_kind text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH auth_context AS (
    SELECT auth.uid() AS user_id
  ),
  base_thread AS (
    SELECT
      t.id,
      t.kind,
      t.title,
      t.avatar_url,
      t.metadata,
      t.last_message_id,
      t.last_message_sender_id,
      t.last_message_at,
      t.created_at,
      tus.muted,
      tus.unread_count,
      dt.user_low_id,
      dt.user_high_id,
      cu.user_id
    FROM public.threads t
    JOIN auth_context cu
      ON cu.user_id IS NOT NULL
    JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = cu.user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = cu.user_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE t.id = p_thread_id
  ),
  counterpart AS (
    SELECT
      bt.*,
      CASE
        WHEN bt.kind = 'direct' AND bt.user_low_id = bt.user_id THEN bt.user_high_id
        WHEN bt.kind = 'direct' AND bt.user_high_id = bt.user_id THEN bt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM base_thread bt
  )
  SELECT
    c.id AS thread_id,
    c.kind,
    c.title,
    c.avatar_url,
    c.metadata,
    c.counterpart_user_id,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        au.email,
        'Someone'
      )
    END AS counterpart_display_name,
    us.profile_picture_url AS counterpart_profile_picture_url,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'avatar_url',
        au.raw_user_meta_data->>'picture'
      )
    END AS counterpart_oauth_avatar_url,
    c.last_message_id,
    c.last_message_sender_id,
    c.last_message_at,
    lm.body AS last_message_body,
    public.message_preview_kind(
      lm.body,
      lm.metadata,
      COALESCE(last_message_media.has_image, false)
    ) AS last_message_preview_kind,
    COALESCE(last_message_media.has_image, false) AS last_message_has_image,
    COALESCE(c.unread_count, 0)::bigint AS unread_count,
    COALESCE(c.muted, false) AS muted,
    c.created_at
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  LEFT JOIN public.messages lm
    ON lm.id = c.last_message_id
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1
      FROM public.message_attachments lma
      WHERE lma.message_id = c.last_message_id
    ) AS has_image
  ) AS last_message_media
    ON true
  WHERE c.counterpart_user_id IS NULL
     OR NOT public.is_user_pair_abuse_blocked(c.counterpart_user_id);
$function$;

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

  SELECT COALESCE(SUM(COALESCE(tus.unread_count, 0)), 0)::integer
  INTO v_unread_count
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
    );

  RETURN COALESCE(v_unread_count, 0);
END;
$function$;

CREATE OR REPLACE FUNCTION internal.get_unread_direct_message_counts(p_user_ids uuid[])
RETURNS TABLE (
  user_id uuid,
  unread_count integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $$
  WITH requested_users AS (
    SELECT DISTINCT requested.user_id
    FROM unnest(COALESCE(p_user_ids, ARRAY[]::uuid[])) AS requested(user_id)
    WHERE requested.user_id IS NOT NULL
  ),
  unread_per_thread AS (
    SELECT
      requested.user_id,
      t.id,
      COALESCE(tus.unread_count, 0)::integer AS unread_count
    FROM requested_users requested
    INNER JOIN public.threads t
      ON t.kind = 'direct'
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    INNER JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = requested.user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = requested.user_id
    WHERE (
      dt.thread_id IS NULL
      OR NOT EXISTS (
        SELECT 1
        FROM public.shift_shares ss
        WHERE (
          (ss.owner_id = requested.user_id AND ss.viewer_id = CASE
            WHEN dt.user_low_id = requested.user_id THEN dt.user_high_id
            WHEN dt.user_high_id = requested.user_id THEN dt.user_low_id
            ELSE NULL
          END)
          OR
          (ss.owner_id = CASE
            WHEN dt.user_low_id = requested.user_id THEN dt.user_high_id
            WHEN dt.user_high_id = requested.user_id THEN dt.user_low_id
            ELSE NULL
          END AND ss.viewer_id = requested.user_id)
        )
          AND ss.blocked_by_user_id IS NOT NULL
      )
    )
  )
  SELECT
    requested.user_id,
    COALESCE(SUM(unread_per_thread.unread_count), 0)::integer AS unread_count
  FROM requested_users requested
  LEFT JOIN unread_per_thread
    ON unread_per_thread.user_id = requested.user_id
  GROUP BY requested.user_id;
$$;

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
    )
    ON CONFLICT (recipient_id, notification_type, thread_id)
      WHERE status = 'pending' AND notification_type = 'thread_message'
    DO UPDATE
    SET
      owner_id = EXCLUDED.owner_id,
      due_at = EXCLUDED.due_at,
      title = EXCLUDED.title,
      body = EXCLUDED.body,
      thread_id = EXCLUDED.thread_id,
      data_payload = EXCLUDED.data_payload;
  END LOOP;

  RETURN NEW;
END;
$function$;

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
      apns_environment = CASE
        WHEN p_apns_token IS NOT NULL AND p_apns_token IS DISTINCT FROM apns_token THEN NULL
        ELSE apns_environment
      END,
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

DROP TRIGGER IF EXISTS a_update_thread_unread_counts_on_message_insert ON public.messages;
CREATE TRIGGER a_update_thread_unread_counts_on_message_insert
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.update_thread_unread_counts_on_message_insert();

DROP TRIGGER IF EXISTS a_update_thread_unread_counts_on_message_soft_delete ON public.messages;
CREATE TRIGGER a_update_thread_unread_counts_on_message_soft_delete
  AFTER UPDATE OF deleted_at ON public.messages
  FOR EACH ROW
  WHEN (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
  EXECUTE FUNCTION public.update_thread_unread_counts_on_message_soft_delete();
