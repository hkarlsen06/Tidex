-- Function: delete_message
-- Description: Soft deletes a sender-owned user message and returns the refreshed canonical thread summary

CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
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
  v_sender_user_id uuid;
  v_message_type text;
  v_deleted_at timestamptz;
  v_latest_message_id uuid;
  v_latest_sender_user_id uuid;
  v_latest_created_at timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.deleted_at
  INTO
    v_thread_id,
    v_sender_user_id,
    v_message_type,
    v_deleted_at
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF v_sender_user_id <> v_uid THEN
    RAISE EXCEPTION 'Only the sender can delete this message';
  END IF;

  IF v_message_type <> 'user' THEN
    RAISE EXCEPTION 'Only user messages can be deleted';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Message is already deleted';
  END IF;

  UPDATE public.messages
  SET deleted_at = now()
  WHERE messages.id = p_message_id;

  SELECT
    m.id,
    m.sender_user_id,
    m.created_at
  INTO
    v_latest_message_id,
    v_latest_sender_user_id,
    v_latest_created_at
  FROM public.messages m
  WHERE m.thread_id = v_thread_id
    AND m.deleted_at IS NULL
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1;

  UPDATE public.threads t
  SET
    last_message_id = v_latest_message_id,
    last_message_sender_id = v_latest_sender_user_id,
    last_message_at = COALESCE(v_latest_created_at, t.created_at)
  WHERE t.id = v_thread_id;

  RETURN QUERY
  SELECT *
  FROM public.get_thread_summary(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.delete_message(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.delete_message(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;
