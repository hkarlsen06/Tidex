-- Function: admin_count_target_users_pro
-- Description: Counts distinct users with push devices who have active or trialing subscriptions
-- Used by: Admin broadcast targeting

CREATE OR REPLACE FUNCTION public.admin_count_target_users_pro()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  INNER JOIN public.subscriptions s ON s.user_id = pd.user_id
  WHERE s.status IN ('active', 'trialing');
$function$;
