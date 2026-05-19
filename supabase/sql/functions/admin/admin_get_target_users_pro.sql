-- Function: admin_get_target_users_pro
-- Description: Returns user IDs of users with push devices who have active or trialing subscriptions
-- Used by: Admin broadcast targeting

CREATE OR REPLACE FUNCTION public.admin_get_target_users_pro()
 RETURNS TABLE(user_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT DISTINCT pd.user_id
  FROM internal.push_devices pd
  INNER JOIN public.subscriptions s ON s.user_id = pd.user_id
  WHERE s.status IN ('active', 'trialing');
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_get_target_users_pro() FROM authenticated;
