-- Function: can_access_thread
-- Description: Returns whether the authenticated user has active membership in the target thread

CREATE OR REPLACE FUNCTION public.can_access_thread(p_thread_id uuid)
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
        WHEN dt.user_low_id = auth.uid() THEN dt.user_high_id
        WHEN dt.user_high_id = auth.uid() THEN dt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM public.thread_memberships tm
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = tm.thread_id
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
  )
  SELECT EXISTS (
    SELECT 1
    FROM current_membership cm
    WHERE cm.counterpart_user_id IS NULL
      OR NOT public.is_user_pair_abuse_blocked(cm.counterpart_user_id)
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_access_thread(uuid) TO authenticated;
