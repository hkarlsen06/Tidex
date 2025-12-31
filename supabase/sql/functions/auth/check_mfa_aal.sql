-- Function: check_mfa_aal
-- Description: Checks if user meets MFA AAL requirements (aal2 if they have verified MFA factors)
-- Used by: RLS policies for MFA enforcement

CREATE OR REPLACE FUNCTION public.check_mfa_aal()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT
    CASE
      WHEN public.user_has_verified_mfa_factors() THEN
        (auth.jwt()->>'aal') = 'aal2'
      ELSE
        true
    END
$function$;
