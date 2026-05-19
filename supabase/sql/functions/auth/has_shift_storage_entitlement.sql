-- Function: has_shift_storage_entitlement
-- Description: Checks if a user has shift storage entitlement (Pro feature)
-- Used by: RLS policies for shift storage

CREATE OR REPLACE FUNCTION public.has_shift_storage_entitlement(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT COALESCE(
    (
      SELECT is_entitled
      FROM public.user_entitlements
      WHERE user_id = p_user_id
        AND (
          p_user_id = auth.uid()
          OR auth.role() = 'service_role'
          OR public.is_admin()
        )
    ),
    false
  );
$function$;
