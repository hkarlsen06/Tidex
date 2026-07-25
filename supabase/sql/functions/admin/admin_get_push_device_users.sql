-- Service-role helper used by notification administration.
CREATE OR REPLACE FUNCTION public.admin_get_push_device_users()
RETURNS TABLE(user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'internal'
AS $function$
  SELECT pd.user_id
  FROM internal.push_devices pd
  GROUP BY pd.user_id
  ORDER BY MAX(pd.last_seen_at) DESC;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_push_device_users()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_push_device_users()
  TO service_role;
