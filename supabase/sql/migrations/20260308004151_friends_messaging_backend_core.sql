CREATE TABLE public.threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('direct', 'room', 'feed')),
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  title text NULL,
  avatar_url text NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_message_id uuid NULL,
  last_message_sender_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.direct_threads (
  thread_id uuid PRIMARY KEY REFERENCES public.threads(id) ON DELETE CASCADE,
  user_low_id uuid NOT NULL REFERENCES auth.users(id),
  user_high_id uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT direct_threads_distinct_users CHECK (user_low_id <> user_high_id),
  CONSTRAINT direct_threads_ordered_users CHECK (user_low_id < user_high_id),
  CONSTRAINT direct_threads_user_pair_key UNIQUE (user_low_id, user_high_id)
);

CREATE TABLE public.thread_memberships (
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'poster', 'reader')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'left')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz NULL,
  PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES auth.users(id),
  message_type text NOT NULL DEFAULT 'user' CHECK (message_type IN ('user', 'system')),
  body text NULL,
  client_id uuid NOT NULL,
  reply_to_message_id uuid NULL REFERENCES public.messages(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  edited_at timestamptz NULL,
  deleted_at timestamptz NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT messages_sender_client_id_key UNIQUE (thread_id, sender_user_id, client_id)
);

CREATE TABLE public.thread_user_state (
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  last_read_message_id uuid NULL REFERENCES public.messages(id) ON DELETE SET NULL,
  last_read_at timestamptz NULL,
  muted boolean NOT NULL DEFAULT false,
  archived_at timestamptz NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE public.message_attachments (
  id uuid PRIMARY KEY,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  attachment_index integer NOT NULL CHECK (attachment_index >= 0),
  kind text NOT NULL CHECK (kind IN ('image')),
  storage_bucket text NOT NULL,
  storage_path text NOT NULL,
  mime_type text NOT NULL,
  byte_size bigint NOT NULL CHECK (byte_size > 0),
  width integer NULL CHECK (width IS NULL OR width > 0),
  height integer NULL CHECK (height IS NULL OR height > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT message_attachments_message_id_attachment_index_key UNIQUE (message_id, attachment_index),
  CONSTRAINT message_attachments_storage_object_key UNIQUE (storage_bucket, storage_path)
);

ALTER TABLE public.threads
  ADD CONSTRAINT threads_last_message_id_fkey
  FOREIGN KEY (last_message_id)
  REFERENCES public.messages(id)
  ON DELETE SET NULL;

CREATE INDEX threads_last_message_at_id_idx
  ON public.threads (last_message_at DESC, id DESC);

CREATE INDEX thread_memberships_user_id_status_idx
  ON public.thread_memberships (user_id, status);

CREATE INDEX messages_thread_id_created_at_id_idx
  ON public.messages (thread_id, created_at DESC, id DESC);

CREATE INDEX message_attachments_message_id_attachment_index_idx
  ON public.message_attachments (message_id, attachment_index);

ALTER TABLE public.threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.direct_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thread_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thread_user_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_attachments ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_user_pair_abuse_blocked(p_other_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_other_user_id IS NULL OR v_uid = p_other_user_id THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND ss.blocked_by_user_id IS NOT NULL
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.is_user_pair_abuse_blocked(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.is_user_pair_abuse_blocked(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_user_pair_abuse_blocked(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_create_direct_thread(p_other_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_other_user_id IS NULL OR v_uid = p_other_user_id THEN
    RETURN false;
  END IF;

  IF public.is_user_pair_abuse_blocked(p_other_user_id) THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND COALESCE(ss.hidden, false) = false
      AND ss.blocked_by_user_id IS NULL
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_access_thread(p_thread_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.thread_memberships tm
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_access_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_post_to_thread(p_thread_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_other_user_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  SELECT tm.role, tm.status
  INTO v_role, v_status
  FROM public.thread_memberships tm
  WHERE tm.thread_id = p_thread_id
    AND tm.user_id = v_uid
  LIMIT 1;

  IF v_status IS DISTINCT FROM 'active' OR v_role IS NULL OR v_role = 'reader' THEN
    RETURN false;
  END IF;

  SELECT CASE
    WHEN dt.user_low_id = v_uid THEN dt.user_high_id
    WHEN dt.user_high_id = v_uid THEN dt.user_low_id
    ELSE NULL
  END
  INTO v_other_user_id
  FROM public.direct_threads dt
  WHERE dt.thread_id = p_thread_id
  LIMIT 1;

  IF v_other_user_id IS NOT NULL AND public.is_user_pair_abuse_blocked(v_other_user_id) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_post_to_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_post_to_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_post_to_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_upload_message_attachment_object(p_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_parts text[];
  v_thread_id uuid;
  v_path_user_id uuid;
BEGIN
  IF v_uid IS NULL OR p_path IS NULL OR p_path = '' THEN
    RETURN false;
  END IF;

  IF lower(p_path) !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|heic|heif|jpeg|jpg|png)$' THEN
    RETURN false;
  END IF;

  v_parts := string_to_array(p_path, '/');

  IF array_length(v_parts, 1) <> 3 THEN
    RETURN false;
  END IF;

  v_thread_id := v_parts[1]::uuid;
  v_path_user_id := v_parts[2]::uuid;

  IF v_path_user_id <> v_uid THEN
    RETURN false;
  END IF;

  RETURN public.can_post_to_thread(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_read_message_attachment_object(p_path text, p_owner_id text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_path IS NULL OR p_path = '' THEN
    RETURN false;
  END IF;

  IF p_owner_id = v_uid::text THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.message_attachments ma
    JOIN public.messages m
      ON m.id = ma.message_id
    WHERE ma.storage_bucket = 'message-attachments'
      AND ma.storage_path = p_path
      AND public.can_access_thread(m.thread_id)
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_message_payload(p_message_id uuid)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    m.id,
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.body,
    m.client_id,
    m.reply_to_message_id,
    m.created_at,
    m.edited_at,
    m.deleted_at,
    m.metadata,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', ma.id,
            'attachment_index', ma.attachment_index,
            'kind', ma.kind,
            'storage_bucket', ma.storage_bucket,
            'storage_path', ma.storage_path,
            'mime_type', ma.mime_type,
            'byte_size', ma.byte_size,
            'width', ma.width,
            'height', ma.height,
            'created_at', ma.created_at
          )
          ORDER BY ma.attachment_index ASC
        )
        FROM public.message_attachments ma
        WHERE ma.message_id = m.id
      ),
      '[]'::jsonb
    ) AS attachments
  FROM public.messages m
  WHERE m.id = p_message_id
    AND public.can_access_thread(m.thread_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_message_payload(uuid) TO authenticated;

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
  ),
  read_marker AS (
    SELECT
      tus.thread_id,
      rm.created_at AS last_read_created_at,
      rm.id AS last_read_message_id
    FROM public.thread_user_state tus
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    JOIN auth_context cu
      ON cu.user_id = tus.user_id
    WHERE tus.thread_id = p_thread_id
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
    EXISTS (
      SELECT 1
      FROM public.message_attachments lma
      WHERE lma.message_id = c.last_message_id
    ) AS last_message_has_image,
    COALESCE(
      (
        SELECT count(*)
        FROM public.messages um
        LEFT JOIN read_marker rm
          ON rm.thread_id = um.thread_id
        WHERE um.thread_id = c.id
          AND um.deleted_at IS NULL
          AND um.sender_user_id <> c.user_id
          AND (
            rm.last_read_message_id IS NULL
            OR (um.created_at, um.id) > (rm.last_read_created_at, rm.last_read_message_id)
          )
      ),
      0
    ) AS unread_count,
    COALESCE(c.muted, false) AS muted,
    c.created_at
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  LEFT JOIN public.messages lm
    ON lm.id = c.last_message_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_thread_summary(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_or_create_direct_thread(p_other_user_id uuid)
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
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_user_low_id uuid;
  v_user_high_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_create_direct_thread(p_other_user_id) THEN
    RAISE EXCEPTION 'Direct thread creation is not allowed for this user pair';
  END IF;

  v_user_low_id := LEAST(v_uid, p_other_user_id);
  v_user_high_id := GREATEST(v_uid, p_other_user_id);

  LOOP
    SELECT dt.thread_id
    INTO v_thread_id
    FROM public.direct_threads dt
    WHERE dt.user_low_id = v_user_low_id
      AND dt.user_high_id = v_user_high_id
    LIMIT 1;

    EXIT WHEN v_thread_id IS NOT NULL;

    BEGIN
      INSERT INTO public.threads (
        kind,
        created_by_user_id
      )
      VALUES (
        'direct',
        v_uid
      )
      RETURNING id INTO v_thread_id;

      INSERT INTO public.direct_threads (
        thread_id,
        user_low_id,
        user_high_id
      )
      VALUES (
        v_thread_id,
        v_user_low_id,
        v_user_high_id
      );

      EXIT;
    EXCEPTION
      WHEN unique_violation THEN
        v_thread_id := NULL;
    END;
  END LOOP;

  INSERT INTO public.thread_memberships (
    thread_id,
    user_id,
    role,
    status
  )
  VALUES
    (v_thread_id, v_user_low_id, 'member', 'active'),
    (v_thread_id, v_user_high_id, 'member', 'active')
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET
    role = EXCLUDED.role,
    status = 'active',
    left_at = NULL;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id
  )
  VALUES
    (v_thread_id, v_user_low_id),
    (v_thread_id, v_user_high_id)
  ON CONFLICT (thread_id, user_id) DO NOTHING;

  RETURN QUERY
  SELECT *
  FROM public.get_thread_summary(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_my_threads(
  p_limit integer DEFAULT 30,
  p_before_last_message_at timestamptz DEFAULT NULL,
  p_before_thread_id uuid DEFAULT NULL
)
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
  WITH visible_threads AS (
    SELECT t.id, t.last_message_at
    FROM public.thread_memberships tm
    JOIN public.threads t
      ON t.id = tm.thread_id
    WHERE auth.uid() IS NOT NULL
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
      AND (
        p_before_last_message_at IS NULL
        OR p_before_thread_id IS NULL
        OR (t.last_message_at, t.id) < (p_before_last_message_at, p_before_thread_id)
      )
    ORDER BY t.last_message_at DESC, t.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  )
  SELECT summary.*
  FROM visible_threads vt
  CROSS JOIN LATERAL public.get_thread_summary(vt.id) AS summary
  ORDER BY summary.last_message_at DESC, summary.thread_id DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_thread_messages(
  p_thread_id uuid,
  p_limit integer DEFAULT 50,
  p_before_created_at timestamptz DEFAULT NULL,
  p_before_message_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF (p_before_created_at IS NULL) <> (p_before_message_id IS NULL) THEN
    RAISE EXCEPTION 'Pagination cursor requires both created_at and message_id';
  END IF;

  RETURN QUERY
  WITH selected_messages AS (
    SELECT m.id, m.created_at
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
      AND (
        p_before_created_at IS NULL
        OR (m.created_at, m.id) < (p_before_created_at, p_before_message_id)
      )
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
  )
  SELECT payload.*
  FROM selected_messages sm
  CROSS JOIN LATERAL public.get_message_payload(sm.id) AS payload
  ORDER BY payload.created_at ASC, payload.id ASC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_message(
  p_thread_id uuid,
  p_client_id uuid,
  p_body text,
  p_attachments jsonb DEFAULT '[]'::jsonb
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_normalized_body text;
  v_attachment_count integer := 0;
  v_existing_message_id uuid;
  v_message_id uuid;
  v_attachment record;
  v_object record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'client_id is required';
  END IF;

  IF NOT public.can_post_to_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Posting is not allowed for this thread';
  END IF;

  IF p_attachments IS NULL THEN
    p_attachments := '[]'::jsonb;
  END IF;

  IF jsonb_typeof(p_attachments) <> 'array' THEN
    RAISE EXCEPTION 'Attachments must be a JSON array';
  END IF;

  SELECT m.id
  INTO v_existing_message_id
  FROM public.messages m
  WHERE m.thread_id = p_thread_id
    AND m.sender_user_id = v_uid
    AND m.client_id = p_client_id
  LIMIT 1;

  IF v_existing_message_id IS NOT NULL THEN
    RETURN QUERY
    SELECT *
    FROM public.get_message_payload(v_existing_message_id);
    RETURN;
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NOT NULL AND char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  SELECT count(*)
  INTO v_attachment_count
  FROM jsonb_array_elements(p_attachments);

  IF v_attachment_count = 0 AND v_normalized_body IS NULL THEN
    RAISE EXCEPTION 'A message must include text or at least one attachment';
  END IF;

  IF v_attachment_count > 4 THEN
    RAISE EXCEPTION 'Too many attachments';
  END IF;

  FOR v_attachment IN
    SELECT
      ordinality - 1 AS attachment_index,
      (value->>'attachment_id')::uuid AS attachment_id,
      value->>'storage_path' AS storage_path,
      value->>'mime_type' AS mime_type,
      NULLIF(value->>'byte_size', '')::bigint AS byte_size,
      NULLIF(value->>'width', '')::integer AS width,
      NULLIF(value->>'height', '')::integer AS height
    FROM jsonb_array_elements(p_attachments) WITH ORDINALITY
  LOOP
    IF v_attachment.attachment_id IS NULL
       OR v_attachment.storage_path IS NULL
       OR v_attachment.mime_type IS NULL
       OR v_attachment.byte_size IS NULL THEN
      RAISE EXCEPTION 'Attachment descriptors must include attachment_id, storage_path, mime_type, and byte_size';
    END IF;

    IF v_attachment.mime_type NOT IN (
      'image/webp',
      'image/heic',
      'image/heif',
      'image/jpeg',
      'image/png'
    ) THEN
      RAISE EXCEPTION 'Unsupported attachment mime type: %', v_attachment.mime_type;
    END IF;

    IF NOT public.can_upload_message_attachment_object(v_attachment.storage_path) THEN
      RAISE EXCEPTION 'Invalid attachment path for this thread or user';
    END IF;

    IF split_part(split_part(v_attachment.storage_path, '/', 3), '.', 1)::uuid <> v_attachment.attachment_id THEN
      RAISE EXCEPTION 'Attachment path must contain the attachment_id in the file name';
    END IF;

    SELECT o.owner_id, o.metadata
    INTO v_object
    FROM storage.objects o
    WHERE o.bucket_id = 'message-attachments'
      AND o.name = v_attachment.storage_path
    LIMIT 1;

    IF v_object.owner_id IS NULL THEN
      RAISE EXCEPTION 'Attachment object not found';
    END IF;

    IF v_object.owner_id <> v_uid::text THEN
      RAISE EXCEPTION 'Attachment object owner mismatch';
    END IF;

    IF COALESCE(v_object.metadata->>'mimetype', '') <> v_attachment.mime_type THEN
      RAISE EXCEPTION 'Attachment mime type does not match stored object metadata';
    END IF;

    IF COALESCE((v_object.metadata->>'size')::bigint, -1) <> v_attachment.byte_size THEN
      RAISE EXCEPTION 'Attachment size does not match stored object metadata';
    END IF;

    IF v_attachment.byte_size <= 0 OR v_attachment.byte_size > 5242880 THEN
      RAISE EXCEPTION 'Attachment size exceeds the 5 MB limit';
    END IF;

    IF v_attachment.width IS NOT NULL AND v_attachment.width <= 0 THEN
      RAISE EXCEPTION 'Attachment width must be positive';
    END IF;

    IF v_attachment.height IS NOT NULL AND v_attachment.height <= 0 THEN
      RAISE EXCEPTION 'Attachment height must be positive';
    END IF;
  END LOOP;

  INSERT INTO public.messages (
    thread_id,
    sender_user_id,
    message_type,
    body,
    client_id
  )
  VALUES (
    p_thread_id,
    v_uid,
    'user',
    v_normalized_body,
    p_client_id
  )
  RETURNING messages.id INTO v_message_id;

  INSERT INTO public.message_attachments (
    id,
    message_id,
    attachment_index,
    kind,
    storage_bucket,
    storage_path,
    mime_type,
    byte_size,
    width,
    height
  )
  SELECT
    (value->>'attachment_id')::uuid,
    v_message_id,
    ordinality - 1,
    'image',
    'message-attachments',
    value->>'storage_path',
    value->>'mime_type',
    NULLIF(value->>'byte_size', '')::bigint,
    NULLIF(value->>'width', '')::integer,
    NULLIF(value->>'height', '')::integer
  FROM jsonb_array_elements(p_attachments) WITH ORDINALITY;

  UPDATE public.threads
  SET
    last_message_id = v_message_id,
    last_message_sender_id = v_uid,
    last_message_at = (
      SELECT m.created_at
      FROM public.messages m
      WHERE m.id = v_message_id
    )
  WHERE threads.id = p_thread_id;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(v_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, jsonb) TO authenticated;

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

  SELECT *
  INTO v_existing_state
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  IF v_existing_state.last_read_message_id IS NOT NULL THEN
    SELECT *
    INTO v_existing_message
    FROM public.messages m
    WHERE m.id = v_existing_state.last_read_message_id
    LIMIT 1;
  END IF;

  IF v_existing_message.id IS NULL
     OR (v_target_message.created_at, v_target_message.id) > (v_existing_message.created_at, v_existing_message.id) THEN
    INSERT INTO public.thread_user_state (
      thread_id,
      user_id,
      last_read_message_id,
      last_read_at,
      updated_at
    )
    VALUES (
      p_thread_id,
      v_uid,
      v_target_message.id,
      v_target_message.created_at,
      now()
    )
    ON CONFLICT (thread_id, user_id) DO UPDATE
    SET
      last_read_message_id = EXCLUDED.last_read_message_id,
      last_read_at = EXCLUDED.last_read_at,
      updated_at = now();
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

REVOKE EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_thread_muted(
  p_thread_id uuid,
  p_muted boolean
)
RETURNS public.thread_user_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result public.thread_user_state%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id,
    muted,
    updated_at
  )
  VALUES (
    p_thread_id,
    v_uid,
    COALESCE(p_muted, false),
    now()
  )
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET
    muted = EXCLUDED.muted,
    updated_at = now();

  SELECT *
  INTO v_result
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) FROM public;
REVOKE EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_message_content_validity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_message_id uuid := COALESCE(NEW.id, OLD.id);
  v_has_body boolean;
  v_attachment_count integer;
BEGIN
  SELECT
    NULLIF(regexp_replace(COALESCE(m.body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL,
    (
      SELECT count(*)
      FROM public.message_attachments ma
      WHERE ma.message_id = m.id
    )
  INTO v_has_body, v_attachment_count
  FROM public.messages m
  WHERE m.id = v_message_id;

  IF COALESCE(v_has_body, false) = false AND COALESCE(v_attachment_count, 0) = 0 THEN
    RAISE EXCEPTION 'A message must include text or at least one attachment';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

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

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'message-attachments',
  'message-attachments',
  false,
  5242880,
  ARRAY[
    'image/webp',
    'image/heic',
    'image/heif',
    'image/jpeg',
    'image/png'
  ]
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Members can view accessible threads" ON public.threads;
CREATE POLICY "Members can view accessible threads"
ON public.threads FOR SELECT TO authenticated
USING (public.can_access_thread(id));

DROP POLICY IF EXISTS "Members can view accessible direct thread pairs" ON public.direct_threads;
CREATE POLICY "Members can view accessible direct thread pairs"
ON public.direct_threads FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP POLICY IF EXISTS "Members can view accessible thread memberships" ON public.thread_memberships;
CREATE POLICY "Members can view accessible thread memberships"
ON public.thread_memberships FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP POLICY IF EXISTS "Members can view accessible thread state" ON public.thread_user_state;
CREATE POLICY "Members can view accessible thread state"
ON public.thread_user_state FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP POLICY IF EXISTS "Users can insert own thread state" ON public.thread_user_state;
CREATE POLICY "Users can insert own thread state"
ON public.thread_user_state FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND public.can_access_thread(thread_id)
);

DROP POLICY IF EXISTS "Users can update own thread state" ON public.thread_user_state;
CREATE POLICY "Users can update own thread state"
ON public.thread_user_state FOR UPDATE TO authenticated
USING (
  user_id = auth.uid()
  AND public.can_access_thread(thread_id)
)
WITH CHECK (
  user_id = auth.uid()
  AND public.can_access_thread(thread_id)
);

DROP POLICY IF EXISTS "Members can view accessible messages" ON public.messages;
CREATE POLICY "Members can view accessible messages"
ON public.messages FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP POLICY IF EXISTS "Members can view accessible message attachments" ON public.message_attachments;
CREATE POLICY "Members can view accessible message attachments"
ON public.message_attachments FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = message_id
      AND public.can_access_thread(m.thread_id)
  )
);

DROP POLICY IF EXISTS "Users can upload message attachments" ON storage.objects;
CREATE POLICY "Users can upload message attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'message-attachments'
  AND public.can_upload_message_attachment_object(name)
);

DROP POLICY IF EXISTS "Users can read published or own message attachments" ON storage.objects;
CREATE POLICY "Users can read published or own message attachments"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'message-attachments'
  AND public.can_read_message_attachment_object(name, owner_id)
);

DROP TRIGGER IF EXISTS thread_user_state_set_updated_at ON public.thread_user_state;
CREATE TRIGGER thread_user_state_set_updated_at
  BEFORE UPDATE ON public.thread_user_state
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS messages_enforce_content_validity ON public.messages;
CREATE CONSTRAINT TRIGGER messages_enforce_content_validity
  AFTER INSERT OR UPDATE ON public.messages
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_message_content_validity();

DROP TRIGGER IF EXISTS on_thread_message_notify ON public.messages;
CREATE TRIGGER on_thread_message_notify
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_thread_message_notification();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'supabase_realtime'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'threads'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.threads;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'messages'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'thread_user_state'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.thread_user_state;
    END IF;
  END IF;
END $$;
