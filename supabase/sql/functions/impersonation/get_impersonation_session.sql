-- Function: get_impersonation_session
-- Description: Gets an active impersonation session by ID
-- Used by: supabase/functions/impersonation/index.ts (Edge Function)
-- Security: SECURITY DEFINER to allow Edge Functions to access internal schema

CREATE OR REPLACE FUNCTION public.get_impersonation_session(
  p_session_id uuid
)
RETURNS TABLE (
  id uuid,
  admin_user_id uuid,
  target_user_id uuid,
  admin_refresh_token_enc text,
  expires_at timestamptz,
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
    s.created_at
  FROM internal.impersonation_sessions s
  WHERE s.id = p_session_id
    AND s.ended_at IS NULL
    AND s.expires_at > now();
END;
$function$;

-- Grant execute to service_role (Edge Functions use service role)
GRANT EXECUTE ON FUNCTION public.get_impersonation_session TO service_role;

-- Revoke from public/anon for security
REVOKE EXECUTE ON FUNCTION public.get_impersonation_session FROM public;
REVOKE EXECUTE ON FUNCTION public.get_impersonation_session FROM anon;
