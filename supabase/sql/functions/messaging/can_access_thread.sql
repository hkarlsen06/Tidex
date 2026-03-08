-- Function: can_access_thread
-- Description: Returns whether the authenticated user has active membership in the target thread

CREATE OR REPLACE FUNCTION public.can_access_thread(p_thread_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.thread_memberships tm
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_access_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_access_thread(uuid) TO authenticated;
