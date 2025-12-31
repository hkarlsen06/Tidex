-- Function: admin_get_target_users_active
-- Description: Returns user IDs of users with push devices who were active in the last 7 days
-- Used by: Admin broadcast targeting

CREATE OR REPLACE FUNCTION public.admin_get_target_users_active()
 RETURNS TABLE(user_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT pd.user_id
  FROM push_devices pd
  INNER JOIN user_settings us ON us.user_id = pd.user_id
  WHERE us.last_active >= NOW() - INTERVAL '7 days';
$function$;
