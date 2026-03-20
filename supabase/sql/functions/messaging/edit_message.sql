-- Function: edit_message
-- Description: Updates the text body of a sender-owned user message and returns the canonical payload

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
