-- Function: can_post_to_thread
-- Description: Returns whether the authenticated user may post into the target thread

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
