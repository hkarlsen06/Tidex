-- Migration: Add impersonation RPC functions
-- These SECURITY DEFINER functions allow Edge Functions to access the internal schema
-- using the new sb_secret_ API key format (which doesn't support direct schema access)

-- ==============================================================================
-- PHASE 0: Create helper functions
-- ==============================================================================

-- Check if a user is currently being impersonated
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

-- Get an admin's active impersonation session
CREATE OR REPLACE FUNCTION public.get_active_impersonation_for_admin(
  p_admin_user_id uuid
)
RETURNS TABLE (
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

-- Get full session data by ID
CREATE OR REPLACE FUNCTION public.get_impersonation_session_full(
  p_session_id uuid
)
RETURNS TABLE (
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

-- End a session (mark as ended) - returns success boolean
CREATE OR REPLACE FUNCTION public.mark_impersonation_session_ended(
  p_session_id uuid,
  p_ended_by_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_row_count integer;
BEGIN
  UPDATE internal.impersonation_sessions
  SET
    ended_at = now(),
    ended_by_admin_user_id = p_ended_by_user_id
  WHERE id = p_session_id
    AND ended_at IS NULL;

  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  RETURN v_row_count > 0;
END;
$function$;

-- Insert audit log entry
CREATE OR REPLACE FUNCTION public.insert_impersonation_audit_log(
  p_session_id uuid,
  p_admin_user_id uuid,
  p_target_user_id uuid,
  p_action text,
  p_reason text DEFAULT NULL,
  p_admin_ip text DEFAULT NULL,
  p_admin_user_agent text DEFAULT NULL,
  p_metadata jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_log_id uuid;
BEGIN
  INSERT INTO internal.impersonation_audit_log (
    session_id,
    admin_user_id,
    target_user_id,
    action,
    reason,
    admin_ip,
    admin_user_agent,
    metadata
  ) VALUES (
    p_session_id,
    p_admin_user_id,
    p_target_user_id,
    p_action,
    p_reason,
    p_admin_ip,
    p_admin_user_agent,
    p_metadata
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$function$;

-- ==============================================================================
-- PHASE 1: Create the session creation function
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_impersonation_session(
  p_admin_user_id uuid,
  p_target_user_id uuid,
  p_admin_refresh_token_enc text DEFAULT '',
  p_reason text DEFAULT NULL,
  p_admin_ip text DEFAULT NULL,
  p_admin_user_agent text DEFAULT NULL,
  p_admin_email text DEFAULT NULL,
  p_target_email text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_session_id uuid;
  v_expires_at timestamptz;
BEGIN
  -- Calculate expiration (1 hour from now)
  v_expires_at := now() + interval '1 hour';

  -- Create the session (no is_active column - use ended_at IS NULL to check active)
  INSERT INTO internal.impersonation_sessions (
    admin_user_id,
    target_user_id,
    reason,
    admin_refresh_token_enc,
    expires_at,
    admin_ip,
    admin_user_agent,
    enc_kid,
    enc_alg,
    enc_format_ver
  ) VALUES (
    p_admin_user_id,
    p_target_user_id,
    COALESCE(p_reason, 'Admin impersonation'),
    COALESCE(p_admin_refresh_token_enc, ''),
    v_expires_at,
    p_admin_ip,
    p_admin_user_agent,
    'v1',
    'aes-256-gcm',
    1
  )
  RETURNING id INTO v_session_id;

  -- Create audit log entry
  INSERT INTO internal.impersonation_audit_log (
    session_id,
    admin_user_id,
    target_user_id,
    action,
    reason,
    admin_ip,
    admin_user_agent,
    metadata
  ) VALUES (
    v_session_id,
    p_admin_user_id,
    p_target_user_id,
    'start',
    p_reason,
    p_admin_ip,
    p_admin_user_agent,
    jsonb_build_object(
      'admin_email', p_admin_email,
      'target_email', p_target_email
    )
  );

  -- Record rate limit attempt
  INSERT INTO internal.impersonation_rate_limits (admin_user_id)
  VALUES (p_admin_user_id);

  RETURN v_session_id;
END;
$function$;

-- ==============================================================================
-- PHASE 2: Create the session retrieval function
-- ==============================================================================

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

-- ==============================================================================
-- PHASE 3: Create the session end function
-- ==============================================================================

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

-- ==============================================================================
-- PHASE 4: Grant permissions
-- ==============================================================================

-- Grant execute to service_role (Edge Functions use service role)
GRANT EXECUTE ON FUNCTION public.is_user_being_impersonated TO service_role;
GRANT EXECUTE ON FUNCTION public.get_active_impersonation_for_admin TO service_role;
GRANT EXECUTE ON FUNCTION public.get_impersonation_session_full TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_impersonation_session_ended TO service_role;
GRANT EXECUTE ON FUNCTION public.insert_impersonation_audit_log TO service_role;
GRANT EXECUTE ON FUNCTION public.create_impersonation_session TO service_role;
GRANT EXECUTE ON FUNCTION public.get_impersonation_session TO service_role;
GRANT EXECUTE ON FUNCTION public.end_impersonation_session TO service_role;

-- Revoke from public/anon for security
REVOKE EXECUTE ON FUNCTION public.is_user_being_impersonated FROM public;
REVOKE EXECUTE ON FUNCTION public.is_user_being_impersonated FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_active_impersonation_for_admin FROM public;
REVOKE EXECUTE ON FUNCTION public.get_active_impersonation_for_admin FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_impersonation_session_full FROM public;
REVOKE EXECUTE ON FUNCTION public.get_impersonation_session_full FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_impersonation_session_ended FROM public;
REVOKE EXECUTE ON FUNCTION public.mark_impersonation_session_ended FROM anon;
REVOKE EXECUTE ON FUNCTION public.insert_impersonation_audit_log FROM public;
REVOKE EXECUTE ON FUNCTION public.insert_impersonation_audit_log FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_impersonation_session FROM public;
REVOKE EXECUTE ON FUNCTION public.create_impersonation_session FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_impersonation_session FROM public;
REVOKE EXECUTE ON FUNCTION public.get_impersonation_session FROM anon;
REVOKE EXECUTE ON FUNCTION public.end_impersonation_session FROM public;
REVOKE EXECUTE ON FUNCTION public.end_impersonation_session FROM anon;

-- ==============================================================================
-- PHASE 5: Add comments
-- ==============================================================================

COMMENT ON FUNCTION public.create_impersonation_session IS
  'Creates an impersonation session with audit logging. Used by Edge Function.';

COMMENT ON FUNCTION public.get_impersonation_session IS
  'Gets an active impersonation session by ID. Used by Edge Function.';

COMMENT ON FUNCTION public.end_impersonation_session IS
  'Ends an impersonation session with audit logging. Used by Edge Function.';
