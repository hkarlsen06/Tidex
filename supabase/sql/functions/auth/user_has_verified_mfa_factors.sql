-- Function: user_has_verified_mfa_factors
-- Description: Checks if current user has any verified MFA factors
-- Used by: check_mfa_aal function for RLS policies

CREATE OR REPLACE FUNCTION public.user_has_verified_mfa_factors()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM auth.mfa_factors
    WHERE user_id = auth.uid()
      AND status = 'verified'
  )
$function$;

REVOKE EXECUTE ON FUNCTION public.user_has_verified_mfa_factors() FROM authenticated;
