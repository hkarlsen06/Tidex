-- Function: get_unread_direct_message_count
-- Description: Returns the total unread direct-message count for a user.

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
