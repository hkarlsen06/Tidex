-- Function: admin_count_target_users_all
-- Description: Counts all distinct users with push devices, optionally excluding a specific user
-- Used by: Admin broadcast targeting

CREATE OR REPLACE FUNCTION public.admin_count_target_users_all(exclude_user_id uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  WHERE (exclude_user_id IS NULL OR pd.user_id != exclude_user_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_count_target_users_all(uuid) FROM authenticated;
