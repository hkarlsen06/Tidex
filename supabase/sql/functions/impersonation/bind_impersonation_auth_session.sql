-- Function: bind_impersonation_auth_session
-- Description: Stores the auth session minted for an impersonation and caps
--              its refresh lifetime at the impersonation expiry
-- Used by: supabase/functions/impersonation/index.ts (Edge Function)

CREATE OR REPLACE FUNCTION public.bind_impersonation_auth_session(
  p_session_id uuid,
  p_auth_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_target_user_id uuid;
  v_expires_at timestamptz;
BEGIN
  UPDATE internal.impersonation_sessions
  SET auth_session_id = p_auth_session_id
  WHERE id = p_session_id
    AND ended_at IS NULL
    AND auth_session_id IS NULL
  RETURNING target_user_id, expires_at
  INTO v_target_user_id, v_expires_at;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Impersonation session not found, ended, or already bound';
  END IF;

  UPDATE auth.sessions
  SET not_after = v_expires_at
  WHERE id = p_auth_session_id
    AND user_id = v_target_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Auth session does not belong to the impersonated user';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.bind_impersonation_auth_session(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_impersonation_auth_session(uuid, uuid)
  TO service_role;
