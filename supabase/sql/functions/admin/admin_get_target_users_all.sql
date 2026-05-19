-- Function: admin_get_target_users_all
-- Description: Returns all user IDs with push devices, optionally excluding a specific user
-- Used by: Admin broadcast targeting

CREATE OR REPLACE FUNCTION public.admin_get_target_users_all(exclude_user_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(user_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT DISTINCT pd.user_id
  FROM internal.push_devices pd
  WHERE (exclude_user_id IS NULL OR pd.user_id != exclude_user_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_get_target_users_all(uuid) FROM authenticated;
