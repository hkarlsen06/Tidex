CREATE OR REPLACE FUNCTION public.get_impersonation_session_full(
  p_session_id uuid
)
RETURNS TABLE(
  id uuid,
  admin_user_id uuid,
  target_user_id uuid,
  reason text,
  admin_refresh_token_enc text,
  expires_at timestamptz,
  ended_at timestamptz,
  ended_by_admin_user_id uuid,
  admin_ip text,
  admin_user_agent text,
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
    s.reason,
    s.admin_refresh_token_enc,
    s.expires_at,
    s.ended_at,
    s.ended_by_admin_user_id,
    s.admin_ip,
    s.admin_user_agent,
    s.created_at
  FROM internal.impersonation_sessions s
  WHERE s.id = p_session_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_impersonation_session_full(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_impersonation_session_full(uuid)
  TO service_role;
