-- Function: mark_thread_read
-- Description: Moves the caller's read marker forward-only for a thread

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

REVOKE EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) TO authenticated;
