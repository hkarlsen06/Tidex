-- Function: end_impersonation_session
-- Description: Ends an impersonation session and creates audit log
-- Used by: supabase/functions/impersonation/index.ts (Edge Function)
-- Security: SECURITY DEFINER to allow Edge Functions to access internal schema

CREATE OR REPLACE FUNCTION public.end_impersonation_session(
  p_session_id uuid,
  p_admin_ip text DEFAULT NULL,
  p_admin_user_agent text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_session internal.impersonation_sessions%ROWTYPE;
BEGIN
  -- Get the session
  SELECT * INTO v_session
  FROM internal.impersonation_sessions
  WHERE id = p_session_id;

  IF v_session.id IS NULL THEN
    RETURN false;
  END IF;

  -- Mark session as ended (no is_active column, just set ended_at)
  UPDATE internal.impersonation_sessions
  SET ended_at = now()
  WHERE id = p_session_id
    AND ended_at IS NULL;

  -- Create audit log entry
  INSERT INTO internal.impersonation_audit_log (
    session_id,
    admin_user_id,
    target_user_id,
    action,
    admin_ip,
    admin_user_agent
  ) VALUES (
    p_session_id,
    v_session.admin_user_id,
    v_session.target_user_id,
    'stop',
    p_admin_ip,
    p_admin_user_agent
  );

  RETURN true;
END;
$function$;

-- Grant execute to service_role (Edge Functions use service role)
GRANT EXECUTE ON FUNCTION public.end_impersonation_session TO service_role;

-- Revoke from public/anon for security
REVOKE EXECUTE ON FUNCTION public.end_impersonation_session FROM public;
REVOKE EXECUTE ON FUNCTION public.end_impersonation_session FROM anon;
