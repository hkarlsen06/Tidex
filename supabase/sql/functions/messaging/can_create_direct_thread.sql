-- Function: can_create_direct_thread
-- Description: Checks whether the authenticated user may create a new direct thread with another user

CREATE OR REPLACE FUNCTION public.can_create_direct_thread(p_other_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_other_user_id IS NULL OR v_uid = p_other_user_id THEN
    RETURN false;
  END IF;

  IF public.is_user_pair_abuse_blocked(p_other_user_id) THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND ss.blocked_by_user_id IS NULL
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM authenticated;
