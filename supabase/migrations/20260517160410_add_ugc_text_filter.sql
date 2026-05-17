-- Add a conservative text safety filter for user-generated messaging content.

CREATE OR REPLACE FUNCTION public.is_objectionable_text(p_text text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_normalized text := regexp_replace(lower(COALESCE(p_text, '')), '[^[:alnum:]]+', ' ', 'g');
BEGIN
  IF btrim(v_normalized) = '' THEN
    RETURN false;
  END IF;

  RETURN v_normalized ~* (
    'kys|' ||
    'kill[[:space:]]+yourself|' ||
    'rape|' ||
    'rapist|' ||
    'porn|' ||
    'pornography|' ||
    'nude[[:space:]]+pics?|' ||
    'send[[:space:]]+nudes?|' ||
    'nigger|' ||
    'nigga|' ||
    'faggot|' ||
    'tranny|' ||
    'retard|' ||
    'heil[[:space:]]+hitler|' ||
    'gas[[:space:]]+the[[:space:]]+jews'
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.is_objectionable_text(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.is_objectionable_text(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_objectionable_text(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_message(
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
  v_message_created_at timestamptz;
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

  IF public.is_objectionable_text(v_normalized_body) THEN
    RAISE EXCEPTION 'Message blocked by safety filter';
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

  PERFORM set_config('tidex.messaging_v2_emit_message_insert', 'false', true);

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
  RETURNING messages.id, messages.created_at INTO v_message_id, v_message_created_at;

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
    last_message_at = v_message_created_at
  WHERE threads.id = p_thread_id;

  PERFORM internal.append_thread_event(
    p_thread_id,
    'message_upserted',
    'message',
    v_message_id,
    internal.build_message_sync_payload_v2(v_message_id),
    v_uid
  );

  PERFORM internal.emit_thread_upserted_inbox_event_v2(
    tm.user_id,
    p_thread_id,
    true,
    v_message_id,
    v_uid,
    v_message_created_at
  )
  FROM public.thread_memberships tm
  WHERE tm.thread_id = p_thread_id
    AND tm.status = 'active'
    AND internal.can_access_thread_as_user(p_thread_id, tm.user_id);

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(v_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.edit_message(
  p_message_id uuid,
  p_body text
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
  v_thread_id uuid;
  v_sender_user_id uuid;
  v_message_type text;
  v_deleted_at timestamptz;
  v_existing_body text;
  v_normalized_body text;
  v_is_preview_source boolean := false;
  v_did_update boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.deleted_at,
    NULLIF(regexp_replace(COALESCE(m.body, ''), '^\s+|\s+$', '', 'g'), '')
  INTO
    v_thread_id,
    v_sender_user_id,
    v_message_type,
    v_deleted_at,
    v_existing_body
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF v_sender_user_id <> v_uid THEN
    RAISE EXCEPTION 'Only the sender can edit this message';
  END IF;

  IF v_message_type <> 'user' THEN
    RAISE EXCEPTION 'Only user messages can be edited';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Deleted messages cannot be edited';
  END IF;

  IF v_existing_body IS NULL THEN
    RAISE EXCEPTION 'Only text messages can be edited';
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NULL THEN
    RAISE EXCEPTION 'Message body cannot be empty';
  END IF;

  IF char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  IF public.is_objectionable_text(v_normalized_body) THEN
    RAISE EXCEPTION 'Message blocked by safety filter';
  END IF;

  IF v_normalized_body IS DISTINCT FROM v_existing_body THEN
    SELECT t.last_message_id = p_message_id
    INTO v_is_preview_source
    FROM public.threads t
    WHERE t.id = v_thread_id;

    UPDATE public.messages
    SET
      body = v_normalized_body,
      edited_at = now()
    WHERE messages.id = p_message_id;

    v_did_update := FOUND;
  END IF;

  IF v_did_update THEN
    PERFORM internal.append_thread_event(
      v_thread_id,
      'message_upserted',
      'message',
      p_message_id,
      internal.build_message_sync_payload_v2(p_message_id),
      v_uid
    );

    IF COALESCE(v_is_preview_source, false) THEN
      PERFORM internal.emit_thread_upserted_inbox_event_v2(tm.user_id, v_thread_id)
      FROM public.thread_memberships tm
      WHERE tm.thread_id = v_thread_id
        AND tm.status = 'active'
        AND internal.can_access_thread_as_user(v_thread_id, tm.user_id);
    END IF;
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(p_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.edit_message(uuid, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.edit_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;

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

  IF public.is_objectionable_text(v_body) THEN
    RAISE EXCEPTION 'Message blocked by safety filter';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;
