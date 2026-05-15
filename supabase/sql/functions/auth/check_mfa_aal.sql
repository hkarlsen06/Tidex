-- Function: check_mfa_aal
-- Description: Checks if user meets MFA AAL requirements (aal2 if they have verified MFA factors)
-- Also allows active impersonation sessions to bypass AAL2 requirement
-- Used by: RLS policies for MFA enforcement

CREATE OR REPLACE FUNCTION public.check_mfa_aal()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT
    CASE
      -- If user is being impersonated, allow access (admin has already verified MFA)
      WHEN public.is_impersonation_session() THEN
        true
      -- If user has MFA factors, require AAL2
      WHEN public.user_has_verified_mfa_factors() THEN
        (auth.jwt()->>'aal') = 'aal2'
      -- Otherwise, allow access
      ELSE
        true
    END
$function$;

REVOKE EXECUTE ON FUNCTION public.check_mfa_aal() FROM anon;
GRANT EXECUTE ON FUNCTION public.check_mfa_aal() TO authenticated;
