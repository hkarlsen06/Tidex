-- Function: block_user_pair
-- Description: Applies an abuse block to both share directions for a user pair.

CREATE OR REPLACE FUNCTION public.block_user_pair(p_other_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_other_user_id IS NULL THEN
    RAISE EXCEPTION 'Blocked user is required';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Cannot block yourself';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
       OR (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
  ) THEN
    RAISE EXCEPTION 'No sharing relationship exists for this user pair';
  END IF;

  PERFORM set_config('tidex.allow_shift_share_abuse_block_update', 'true', true);

  UPDATE public.shift_shares ss
  SET hidden = true,
      blocked_by_user_id = v_uid
  WHERE (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
     OR (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.block_user_pair(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.block_user_pair(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.block_user_pair(uuid) TO authenticated;
