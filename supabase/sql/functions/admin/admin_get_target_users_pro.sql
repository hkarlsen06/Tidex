-- Function: admin_get_target_users_pro
-- Description: Returns user IDs of users with push devices who have active or trialing subscriptions
-- Used by: Admin broadcast targeting

CREATE OR REPLACE FUNCTION public.admin_get_target_users_pro()
 RETURNS TABLE(user_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT pd.user_id
  FROM push_devices pd
  INNER JOIN subscriptions s ON s.user_id = pd.user_id
  WHERE s.status IN ('active', 'trialing');
$function$;
