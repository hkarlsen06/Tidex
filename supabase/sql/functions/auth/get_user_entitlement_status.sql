-- Function: get_user_entitlement_status
-- Description: Returns the entitlement status for a user as JSONB
-- Used by: Subscription and entitlement checks

CREATE OR REPLACE FUNCTION public.get_user_entitlement_status(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'user_id', user_id,
    'is_entitled', is_entitled,
    'is_grandfathered', is_grandfathered,
    'has_active_subscription', has_active_subscription,
    'active_provider', active_provider,
    'active_product_id', active_product_id,
    'subscription_ends_at', subscription_ends_at
  )
  FROM public.user_entitlements
  WHERE user_id = p_user_id;
$function$;
