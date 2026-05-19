-- Function: admin_count_target_users_active
-- Description: Counts distinct users with push devices who were active in the last 7 days
-- Used by: Admin broadcast targeting

CREATE OR REPLACE FUNCTION public.admin_count_target_users_active()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  INNER JOIN public.user_settings us ON us.user_id = pd.user_id
  WHERE us.last_active >= NOW() - INTERVAL '7 days';
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_count_target_users_active() FROM authenticated;
