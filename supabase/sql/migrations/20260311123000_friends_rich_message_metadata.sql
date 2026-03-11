-- Friends rich message metadata helpers and additive preview-kind summary fields

CREATE OR REPLACE FUNCTION public.assert_message_metadata_validity(p_metadata jsonb)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_metadata jsonb := COALESCE(p_metadata, '{}'::jsonb);
  v_content jsonb;
  v_kind text;
BEGIN
  IF jsonb_typeof(v_metadata) <> 'object' THEN
    RAISE EXCEPTION 'Metadata must be a JSON object';
  END IF;

  IF pg_column_size(v_metadata) > 8192 THEN
    RAISE EXCEPTION 'Metadata exceeds the 8 KB limit';
  END IF;

  IF NOT (v_metadata ? 'content') THEN
    RETURN;
  END IF;

  v_content := v_metadata->'content';

  IF jsonb_typeof(v_content) <> 'object' THEN
    RAISE EXCEPTION 'Metadata content must be a JSON object';
  END IF;

  v_kind := NULLIF(btrim(v_content->>'kind'), '');

  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'Metadata content kind is required';
  END IF;

  IF public.message_supported_rich_content_kind(v_metadata) IS NOT NULL THEN
    RETURN;
  END IF;

  IF v_kind = 'shift_snapshot' THEN
    RAISE EXCEPTION 'Invalid shift snapshot metadata';
  END IF;

  RAISE EXCEPTION 'Unsupported rich content kind: %', v_kind;
END;
$function$;

CREATE OR REPLACE FUNCTION public.message_supported_rich_content_kind(p_metadata jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_metadata jsonb := COALESCE(p_metadata, '{}'::jsonb);
  v_content jsonb;
  v_kind text;
  v_snapshot jsonb;
  v_includes_earnings boolean;
BEGIN
  IF jsonb_typeof(v_metadata) <> 'object' THEN
    RETURN NULL;
  END IF;

  v_content := v_metadata->'content';

  IF jsonb_typeof(v_content) <> 'object' THEN
    RETURN NULL;
  END IF;

  v_kind := NULLIF(btrim(v_content->>'kind'), '');

  IF v_kind <> 'shift_snapshot' THEN
    RETURN NULL;
  END IF;

  v_snapshot := v_content->'shift_snapshot';

  IF jsonb_typeof(v_snapshot) <> 'object' THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'schema_version') OR v_snapshot->>'schema_version' <> '1' THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'owner_user_id')
     OR COALESCE(jsonb_typeof(v_snapshot->'owner_user_id'), '') <> 'string'
     OR (v_snapshot->>'owner_user_id') !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'owner_display_name')
     OR COALESCE(jsonb_typeof(v_snapshot->'owner_display_name'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'owner_display_name'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'owner_avatar_url'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'shift_id')
     OR COALESCE(jsonb_typeof(v_snapshot->'shift_id'), '') <> 'string'
     OR (v_snapshot->>'shift_id') !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'job_name'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'job_color_hex'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'shift_date')
     OR COALESCE(jsonb_typeof(v_snapshot->'shift_date'), '') <> 'string'
     OR (v_snapshot->>'shift_date') !~ '^\d{4}-\d{2}-\d{2}$'
  THEN
    RETURN NULL;
  END IF;

  BEGIN
    PERFORM (v_snapshot->>'shift_date')::date;
  EXCEPTION
    WHEN others THEN
      RETURN NULL;
  END;

  IF NOT (v_snapshot ? 'start_time')
     OR COALESCE(jsonb_typeof(v_snapshot->'start_time'), '') <> 'string'
     OR (v_snapshot->>'start_time') !~ '^([01]\d|2[0-3]):[0-5]\d$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'end_time')
     OR COALESCE(jsonb_typeof(v_snapshot->'end_time'), '') <> 'string'
     OR (v_snapshot->>'end_time') !~ '^([01]\d|2[0-3]):[0-5]\d$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'paid_hours')
     OR COALESCE(jsonb_typeof(v_snapshot->'paid_hours'), '') <> 'number'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'currency')
     OR COALESCE(jsonb_typeof(v_snapshot->'currency'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'currency'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'includes_earnings')
     OR COALESCE(jsonb_typeof(v_snapshot->'includes_earnings'), '') <> 'boolean'
  THEN
    RETURN NULL;
  END IF;

  v_includes_earnings := (v_snapshot->>'includes_earnings')::boolean;

  IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') NOT IN ('number', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') NOT IN ('number', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF v_includes_earnings THEN
    IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') <> 'number'
       OR COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') <> 'number'
    THEN
      RETURN NULL;
    END IF;
  ELSE
    IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') <> 'null'
       OR COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') <> 'null'
    THEN
      RETURN NULL;
    END IF;
  END IF;

  IF NOT (v_snapshot ? 'tax_enabled')
     OR COALESCE(jsonb_typeof(v_snapshot->'tax_enabled'), '') <> 'boolean'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'source')
     OR COALESCE(jsonb_typeof(v_snapshot->'source'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'source'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  RETURN 'shift_snapshot';
END;
$function$;

CREATE OR REPLACE FUNCTION public.message_has_supported_rich_content(p_metadata jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT public.message_supported_rich_content_kind(p_metadata) IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION public.message_has_renderable_content(
  p_body text,
  p_attachments jsonb,
  p_metadata jsonb
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT
    NULLIF(regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL
    OR (
      CASE
        WHEN COALESCE(jsonb_typeof(p_attachments), 'array') = 'array'
          THEN jsonb_array_length(COALESCE(p_attachments, '[]'::jsonb)) > 0
        ELSE false
      END
    )
    OR public.message_has_supported_rich_content(p_metadata);
$function$;

CREATE OR REPLACE FUNCTION public.message_preview_kind(
  p_body text,
  p_metadata jsonb,
  p_has_image boolean
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  WITH supported_kind AS (
    SELECT public.message_supported_rich_content_kind(p_metadata) AS kind
  )
  SELECT CASE
    WHEN NULLIF(regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL THEN 'text'
    WHEN COALESCE(p_has_image, false) THEN 'image'
    WHEN supported_kind.kind IS NOT NULL THEN supported_kind.kind
    ELSE 'unknown'
  END
  FROM supported_kind;
$function$;

DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, uuid, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, uuid, jsonb);
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, jsonb);

CREATE FUNCTION public.send_message(
  p_thread_id uuid,
  p_client_id uuid,
  p_body text,
  p_reply_to_message_id uuid DEFAULT NULL,
  p_attachments jsonb DEFAULT '[]'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
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
  attachments jsonb,
  reactions jsonb
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

  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = p_reply_to_message_id
      AND m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reply target must exist in the same thread';
  END IF;

  IF p_attachments IS NULL THEN
    p_attachments := '[]'::jsonb;
  END IF;

  IF p_metadata IS NULL THEN
    p_metadata := '{}'::jsonb;
  END IF;

  IF jsonb_typeof(p_attachments) <> 'array' THEN
    RAISE EXCEPTION 'Attachments must be a JSON array';
  END IF;

  PERFORM public.assert_message_metadata_validity(p_metadata);

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

  IF NOT public.message_has_renderable_content(v_normalized_body, p_attachments, p_metadata) THEN
    RAISE EXCEPTION 'A message must include text, at least one attachment, or supported rich content';
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
    client_id,
    reply_to_message_id,
    metadata
  )
  VALUES (
    p_thread_id,
    v_uid,
    'user',
    v_normalized_body,
    p_client_id,
    p_reply_to_message_id,
    p_metadata
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

REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_message_content_validity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_message_id uuid := COALESCE(NEW.id, OLD.id);
  v_body text;
  v_metadata jsonb;
  v_attachments jsonb;
BEGIN
  SELECT
    m.body,
    m.metadata,
    COALESCE(
      (
        SELECT jsonb_agg(jsonb_build_object('id', ma.id) ORDER BY ma.attachment_index ASC)
        FROM public.message_attachments ma
        WHERE ma.message_id = m.id
      ),
      '[]'::jsonb
    )
  INTO v_body, v_metadata, v_attachments
  FROM public.messages m
  WHERE m.id = v_message_id;

  PERFORM public.assert_message_metadata_validity(v_metadata);

  IF NOT public.message_has_renderable_content(v_body, v_attachments, v_metadata) THEN
    RAISE EXCEPTION 'A message must include text, at least one attachment, or supported rich content';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP FUNCTION IF EXISTS public.get_or_create_direct_thread(uuid);
DROP FUNCTION IF EXISTS public.list_my_threads(integer, timestamptz, uuid);
DROP FUNCTION IF EXISTS public.get_thread_summary(uuid);

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
    public.message_preview_kind(
      lm.body,
      lm.metadata,
      COALESCE(last_message_media.has_image, false)
    ) AS last_message_preview_kind,
    COALESCE(last_message_media.has_image, false) AS last_message_has_image,
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

REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_thread_summary(uuid) TO authenticated;

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
  WITH visible_threads AS (
    SELECT t.id, t.last_message_at
    FROM public.thread_memberships tm
    JOIN public.threads t
      ON t.id = tm.thread_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE auth.uid() IS NOT NULL
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
      AND (
        dt.thread_id IS NULL
        OR NOT public.is_user_pair_abuse_blocked(
          CASE
            WHEN dt.user_low_id = auth.uid() THEN dt.user_high_id
            WHEN dt.user_high_id = auth.uid() THEN dt.user_low_id
            ELSE NULL
          END
        )
      )
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
  last_message_preview_kind text,
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
  ON CONFLICT ON CONSTRAINT thread_memberships_pkey DO UPDATE
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
  ON CONFLICT ON CONSTRAINT thread_user_state_pkey DO NOTHING;

  RETURN QUERY
  SELECT *
  FROM public.get_thread_summary(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) TO authenticated;
