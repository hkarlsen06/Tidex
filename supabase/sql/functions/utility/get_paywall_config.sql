-- Function: get_paywall_config
-- Description: Returns backend-controlled paywall offer metadata for clients.

CREATE OR REPLACE FUNCTION public.get_paywall_config()
RETURNS TABLE (
  free_trial_enabled boolean,
  free_trial_duration_days integer,
  free_trial_reminder_days_before_end integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    pc.free_trial_enabled,
    pc.free_trial_duration_days,
    pc.free_trial_reminder_days_before_end
  FROM internal.paywall_config pc
  WHERE pc.singleton = true
  LIMIT 1;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_paywall_config() FROM public;
GRANT EXECUTE ON FUNCTION public.get_paywall_config() TO anon;
GRANT EXECUTE ON FUNCTION public.get_paywall_config() TO authenticated;
