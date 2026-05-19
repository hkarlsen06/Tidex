-- Function: toggle_message_reaction
-- Description: Toggles the authenticated user's reaction for a message and returns the updated canonical payload

CREATE OR REPLACE FUNCTION public.toggle_message_reaction(
  p_message_id uuid,
  p_emoji text,
  p_attachment_id uuid DEFAULT NULL
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
  v_emoji text := btrim(COALESCE(p_emoji, ''));
  v_attachment_thread_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF v_emoji = '' OR char_length(v_emoji) > 16 THEN
    RAISE EXCEPTION 'Reaction emoji is invalid';
  END IF;

  SELECT m.thread_id
  INTO v_thread_id
  FROM public.messages m
  WHERE m.id = p_message_id
    AND m.deleted_at IS NULL
  LIMIT 1;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF NOT public.can_post_to_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread is read only';
  END IF;

  IF p_attachment_id IS NOT NULL THEN
    SELECT m.thread_id
    INTO v_attachment_thread_id
    FROM public.message_attachments ma
    INNER JOIN public.messages m
      ON m.id = ma.message_id
    WHERE ma.id = p_attachment_id
      AND ma.message_id = p_message_id
      AND m.deleted_at IS NULL
    LIMIT 1;

    IF v_attachment_thread_id IS NULL OR v_attachment_thread_id <> v_thread_id THEN
      RAISE EXCEPTION 'Attachment not found';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji
      AND mr.attachment_id IS NOT DISTINCT FROM p_attachment_id
  ) THEN
    PERFORM set_config('tidex.messaging_v2_emit_message_reaction', 'true', true);

    DELETE FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji
      AND mr.attachment_id IS NOT DISTINCT FROM p_attachment_id;
  ELSE
    PERFORM set_config('tidex.messaging_v2_emit_message_reaction', 'true', true);

    INSERT INTO public.message_reactions (
      thread_id,
      message_id,
      attachment_id,
      user_id,
      emoji
    )
    VALUES (
      v_thread_id,
      p_message_id,
      p_attachment_id,
      v_uid,
      v_emoji
    );
  END IF;

  RETURN QUERY
  SELECT payload.*
  FROM public.get_message_payload(p_message_id) AS payload;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text, uuid) TO authenticated;
