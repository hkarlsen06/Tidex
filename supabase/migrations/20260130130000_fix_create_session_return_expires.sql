-- Migration: Fix create_impersonation_session to return expires_at
-- This fixes a potential clock skew issue where the Edge Function was calculating
-- expiration locally instead of using the database-calculated value.

-- Drop existing function first (required when changing return type)
DROP FUNCTION IF EXISTS public.create_impersonation_session(uuid, uuid, text, text, text, text, text, text);

-- Recreate with composite return type that includes expires_at
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
RETURNS TABLE (
  session_id uuid,
  expires_at timestamptz
)
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

  -- Return both session ID and expires_at
  RETURN QUERY SELECT v_session_id, v_expires_at;
END;
$function$;

-- Grant execute to service_role (Edge Functions use service role)
GRANT EXECUTE ON FUNCTION public.create_impersonation_session TO service_role;

-- Revoke from public/anon for security
REVOKE EXECUTE ON FUNCTION public.create_impersonation_session FROM public;
REVOKE EXECUTE ON FUNCTION public.create_impersonation_session FROM anon;

COMMENT ON FUNCTION public.create_impersonation_session IS
  'Creates an impersonation session with audit logging. Returns session_id and expires_at. Used by Edge Function.';
