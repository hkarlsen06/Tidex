-- Function: can_access_thread_as_user
-- Description: Returns whether a specific user has active visible membership in the target thread

CREATE OR REPLACE FUNCTION internal.can_access_thread_as_user(
  p_thread_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH current_membership AS (
    SELECT
      tm.thread_id,
      CASE
        WHEN dt.user_low_id = p_user_id THEN dt.user_high_id
        WHEN dt.user_high_id = p_user_id THEN dt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM public.thread_memberships tm
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = tm.thread_id
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = p_user_id
      AND tm.status = 'active'
  )
  SELECT EXISTS (
    SELECT 1
    FROM current_membership cm
    WHERE cm.counterpart_user_id IS NULL
      OR NOT internal.is_user_pair_abuse_blocked_for_user(p_user_id, cm.counterpart_user_id)
  );
$function$;

