-- Function: record_impersonation_attempt
-- Description: Records an impersonation attempt for rate limiting purposes
-- Used by: lib/auth/impersonation.ts when admin impersonates a user
-- References: internal.impersonation_rate_limits
-- Note: Also cleans up old records (>24 hours) to prevent table bloat

CREATE OR REPLACE FUNCTION public.record_impersonation_attempt(p_admin_user_id uuid, p_success boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  INSERT INTO internal.impersonation_rate_limits (admin_user_id, success)
  VALUES (p_admin_user_id, p_success);

  -- Clean up old records (older than 24 hours) to prevent table bloat
  DELETE FROM internal.impersonation_rate_limits
  WHERE attempted_at < (now() - interval '24 hours');
END;
$function$;
