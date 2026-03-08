-- Function: get_or_create_direct_thread
-- Description: Returns the canonical direct thread for a user pair, creating it if needed

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
