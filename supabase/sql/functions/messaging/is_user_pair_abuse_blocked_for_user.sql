-- Function: is_user_pair_abuse_blocked_for_user
-- Description: Resolves whether an explicit user pair is abuse-blocked in either share direction

CREATE OR REPLACE FUNCTION internal.is_user_pair_abuse_blocked_for_user(
  p_user_id uuid,
  p_other_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN p_user_id IS NULL OR p_other_user_id IS NULL OR p_user_id = p_other_user_id THEN false
    ELSE EXISTS (
      SELECT 1
      FROM public.shift_shares ss
      WHERE (
        (ss.owner_id = p_user_id AND ss.viewer_id = p_other_user_id)
        OR
        (ss.owner_id = p_other_user_id AND ss.viewer_id = p_user_id)
      )
        AND ss.blocked_by_user_id IS NOT NULL
    )
  END;
$function$;

