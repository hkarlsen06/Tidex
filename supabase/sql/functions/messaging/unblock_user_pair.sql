-- Function: unblock_user_pair
-- Description: Clears an abuse block for a user pair created by the authenticated user.

CREATE OR REPLACE FUNCTION public.unblock_user_pair(p_other_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_visible_before_low boolean := false;
  v_visible_before_high boolean := false;
  v_visible_after_low boolean := false;
  v_visible_after_high boolean := false;
  v_user_low_id uuid;
  v_user_high_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_other_user_id IS NULL THEN
    RAISE EXCEPTION 'Blocked user is required';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Cannot unblock yourself';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND ss.blocked_by_user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'No active block exists for this user pair';
  END IF;

  v_user_low_id := LEAST(v_uid, p_other_user_id);
  v_user_high_id := GREATEST(v_uid, p_other_user_id);

  SELECT dt.thread_id
  INTO v_thread_id
  FROM public.direct_threads dt
  WHERE dt.user_low_id = v_user_low_id
    AND dt.user_high_id = v_user_high_id
  LIMIT 1;

  IF v_thread_id IS NOT NULL THEN
    v_visible_before_low := internal.can_access_thread_as_user(v_thread_id, v_user_low_id);
    v_visible_before_high := internal.can_access_thread_as_user(v_thread_id, v_user_high_id);
  END IF;

  PERFORM set_config('tidex.allow_shift_share_abuse_block_update', 'true', true);

  UPDATE public.shift_shares ss
  SET hidden = false,
      blocked_by_user_id = NULL
  WHERE (
    (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
    OR
    (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
  )
    AND ss.blocked_by_user_id = v_uid;

  IF v_thread_id IS NOT NULL THEN
    v_visible_after_low := internal.can_access_thread_as_user(v_thread_id, v_user_low_id);
    v_visible_after_high := internal.can_access_thread_as_user(v_thread_id, v_user_high_id);

    IF NOT v_visible_before_low AND v_visible_after_low THEN
      PERFORM internal.emit_thread_upserted_inbox_event_v2(v_user_low_id, v_thread_id);
    END IF;

    IF NOT v_visible_before_high AND v_visible_after_high THEN
      PERFORM internal.emit_thread_upserted_inbox_event_v2(v_user_high_id, v_thread_id);
    END IF;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.unblock_user_pair(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.unblock_user_pair(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.unblock_user_pair(uuid) TO authenticated;
