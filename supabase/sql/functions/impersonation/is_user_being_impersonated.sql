CREATE OR REPLACE FUNCTION public.is_user_being_impersonated(
  p_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM internal.impersonation_sessions
    WHERE target_user_id = p_user_id
      AND ended_at IS NULL
      AND expires_at > now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.is_user_being_impersonated(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_user_being_impersonated(uuid)
  TO service_role;
