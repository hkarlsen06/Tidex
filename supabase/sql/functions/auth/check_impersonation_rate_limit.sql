-- Function: check_impersonation_rate_limit
-- Description: Checks if an admin has exceeded the impersonation rate limit (10 per hour)
-- Used by: lib/auth/impersonation.ts before allowing impersonation
-- References: internal.impersonation_rate_limits

CREATE OR REPLACE FUNCTION public.check_impersonation_rate_limit(p_admin_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  attempt_count int;
BEGIN
  -- Count attempts in the last hour
  SELECT COUNT(*) INTO attempt_count
  FROM internal.impersonation_rate_limits
  WHERE admin_user_id = p_admin_user_id
    AND attempted_at > (now() - interval '1 hour');

  -- Return true if under limit (10 per hour)
  RETURN attempt_count < 10;
END;
$function$;
