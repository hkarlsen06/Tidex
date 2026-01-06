-- Migration: add_admin_get_push_device_users
-- Description: Adds function to get users with push devices for admin targeting

CREATE OR REPLACE FUNCTION public.admin_get_push_device_users()
 RETURNS TABLE(user_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'internal'
AS $function$
  SELECT pd.user_id
  FROM internal.push_devices pd
  GROUP BY pd.user_id
  ORDER BY MAX(pd.last_seen_at) DESC;
$function$;
