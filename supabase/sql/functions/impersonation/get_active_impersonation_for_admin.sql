CREATE OR REPLACE FUNCTION public.get_active_impersonation_for_admin(
  p_admin_user_id uuid
)
RETURNS TABLE(
  id uuid,
  admin_user_id uuid,
  target_user_id uuid,
  admin_refresh_token_enc text,
  expires_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.admin_user_id,
    s.target_user_id,
    s.admin_refresh_token_enc,
    s.expires_at,
    s.ended_at,
    s.created_at
  FROM internal.impersonation_sessions s
  WHERE s.admin_user_id = p_admin_user_id
    AND s.ended_at IS NULL
  ORDER BY s.created_at DESC
  LIMIT 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_active_impersonation_for_admin(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_active_impersonation_for_admin(uuid)
  TO service_role;
